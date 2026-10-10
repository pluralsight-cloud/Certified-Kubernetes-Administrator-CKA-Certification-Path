#!/usr/bin/env bash
#================================================================
# cka-lab.sh -- macOS lab controls for the CKA skill path.
#
# The Windows/Hyper-V lab is driven by the Verb-Noun PowerShell scripts beside
# this file (Start-CkaLab.ps1, Save-CkaSnapshot.ps1, ...). Those need Hyper-V
# and an elevated PowerShell, so on macOS this script is the equivalent: one
# entry point, subcommands, bare invocation does the sensible thing.
#
#   ./cka-lab.sh              up + bootstrap + kubeconfig + status
#   ./cka-lab.sh check        preflight only -- is the toolchain ready?
#   ./cka-lab.sh up           vagrant up, then bootstrap + kubeconfig (see below)
#   ./cka-lab.sh bootstrap    kubeadm init on control1, join both workers
#   ./cka-lab.sh kubeconfig   copy admin.conf to the Mac
#   ./cka-lab.sh status       vagrant status + kubectl get nodes -o wide
#   ./cka-lab.sh snap NAME    snapshot all three VMs
#   ./cka-lab.sh restore NAME restore all three VMs, then heal Calico
#   ./cka-lab.sh snapshots    list save points (they nest -- see snapshot_path)
#   ./cka-lab.sh dns          strip the DHCP 'localdomain' from Pod DNS (see below)
#   ./cka-lab.sh heal         fix Calico after a restore (see below)
#   ./cka-lab.sh halt         shut the VMs down (frees host port 2222)
#   ./cka-lab.sh destroy      delete the VMs (asks first)
#
# Every subcommand is re-runnable. bootstrap skips `kubeadm init` if the
# control plane is already up and skips a join if the node is already
# registered, so it is safe to re-run after a partial failure.
#
# Walkthrough and prerequisites: TUTORIAL-MACOS.md
#================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL="control1"
WORKERS=(worker1 worker2)
ALL_NODES=("$CONTROL" "${WORKERS[@]}")
CP_IP="192.168.50.10"
KUBECONFIG_OUT="${CKA_KUBECONFIG:-$HOME/.kube/cka-config}"
SSH_CFG="$HERE/.vagrant/cka-ssh-config"

# On macOS the only provider this lab supports is VMware. Setting it here means
# nobody has to remember `--provider`, and `vagrant up` cannot silently pick
# VirtualBox (which has no arm64 Ubuntu box and would fail much later).
export VAGRANT_DEFAULT_PROVIDER="${VAGRANT_DEFAULT_PROVIDER:-vmware_desktop}"

# Only one mutating run at a time. Two concurrent `bootstrap` runs both pass the
# "is the control plane already up?" check, both run `kubeadm init`, and the
# loser dies partway through installing Calico -- which is exactly what happened
# the first time this script was exercised end to end. A double-Enter during a
# recording would do the same thing.
LOCK_DIR="$HERE/.vagrant/cka-lab.lock"
acquire_lock() {
  mkdir -p "$HERE/.vagrant"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local owner
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    # A lock whose owner is gone is stale (killed run, reboot). Reclaim it
    # rather than making the next person delete a directory by hand.
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      die "Another cka-lab.sh run is in progress (pid $owner). Wait for it to finish."
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || die "Could not take the lock at $LOCK_DIR"
  fi
  echo "$$" > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
}

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

#---------------------------------------------------------------
# preflight
#---------------------------------------------------------------
cmd_check() {
  local ok=0
  say "Preflight"

  if command -v vagrant >/dev/null 2>&1; then
    info "vagrant       $(vagrant --version 2>/dev/null)"
  else
    info "vagrant       MISSING  -- brew install --cask vagrant"; ok=1
  fi

  # The VMware provider is two pieces: the Vagrant plugin AND the VMware
  # Vagrant Utility (a privileged helper that creates the host-only vmnet).
  # A missing utility does not show up until `vagrant up` fails, so check both.
  if command -v vagrant >/dev/null 2>&1 && vagrant plugin list 2>/dev/null | grep -q vagrant-vmware-desktop; then
    info "vmware plugin installed"
  else
    info "vmware plugin MISSING  -- vagrant plugin install vagrant-vmware-desktop"; ok=1
  fi

  if [ -x /opt/vagrant-vmware-desktop/bin/vagrant-vmware-utility ] \
     || pgrep -qf vagrant-vmware-utility 2>/dev/null; then
    info "vmware utility present"
  else
    info "vmware utility NOT FOUND -- brew install --cask vagrant-vmware-utility (needs your password)"; ok=1
  fi

  if [ -d "/Applications/VMware Fusion.app" ]; then
    info "VMware Fusion installed"
  else
    info "VMware Fusion MISSING  -- free download, see TUTORIAL-MACOS.md"; ok=1
  fi

  if command -v kubectl >/dev/null 2>&1; then
    info "kubectl       $(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"\([^"]*\)".*/\1/p' | head -1)"
  else
    info "kubectl       MISSING  -- brew install kubectl"; ok=1
  fi

  if [ -f "$KUBECONFIG_OUT" ] && command -v kubectl >/dev/null 2>&1; then
    if local_network_blocked; then
      info "local network BLOCKED -- macOS is denying kubectl access to the lab subnet."
      info "              System Settings > Privacy & Security > Local Network -> enable"
      info "              your terminal app, then quit it completely (Cmd-Q) and reopen."
      info "              Still blocked? tccutil reset LocalNetwork <bundle-id>, reopen, allow."
      ok=1
    else
      info "local network reachable"
    fi
  fi

  if command -v helm >/dev/null 2>&1; then
    info "helm          $(helm version --short 2>/dev/null)"
  else
    info "helm          MISSING  -- brew install helm (Course 7 installs Traefik with it)"; ok=1
  fi

  if [ "$ok" -eq 0 ]; then
    say "Preflight OK"
  else
    say "Preflight incomplete -- fix the MISSING lines above"
  fi
  return "$ok"
}

need_vagrant() { command -v vagrant >/dev/null 2>&1 || die "vagrant not installed. Run: ./cka-lab.sh check"; }

# Refresh the ssh config Vagrant generates, then talk to the VMs with plain
# ssh/scp. `vagrant ssh -c` allocates a TTY and mangles piped stdin, which is
# exactly what copying scripts and kubeconfigs needs to work.
ssh_config() {
  need_vagrant
  mkdir -p "$(dirname "$SSH_CFG")"
  vagrant ssh-config > "$SSH_CFG" 2>/dev/null \
    || die "Could not read ssh config -- are the VMs up? Try: ./cka-lab.sh up"
  [ -s "$SSH_CFG" ] || die "vagrant ssh-config returned nothing -- the VMs are probably not running."
}

on() { local node="$1"; shift; ssh -F "$SSH_CFG" "$node" "$@"; }

# The VMware utility holds Vagrant's automatic guest-22 -> host-2222 SSH
# forward open even after `vagrant halt` -- it restores the forward from
# /opt/vagrant-vmware-desktop/settings/portforwarding.json on every start, so
# restarting the daemon does not free the port. Anything else that wants 2222
# (CRC / OpenShift Local, most visibly) then fails to start. So the daemon
# lives and dies with the lab: bootstrapped on `up`, booted out on
# `halt`/`destroy`. Both need sudo; both are no-ops if already in that state.
VMWARE_UTILITY_PLIST="/Library/LaunchDaemons/com.vagrant.vagrant-vmware-utility.plist"
VMWARE_UTILITY_LABEL="com.vagrant.vagrant-vmware-utility"
VMWARE_UTILITY_PORT=9922   # the utility's API port, the one vagrant talks to

vmware_utility() {
  [ -f "$VMWARE_UTILITY_PLIST" ] || return 0
  # `launchctl list` cannot see a system daemon without root, so ask the
  # process table instead -- that works as your own user.
  local loaded=no
  pgrep -qf "/opt/vagrant-vmware-desktop/bin/vagrant-vmware-utility" && loaded=yes
  case "$1" in
    on)
      [ "$loaded" = yes ] && return 0
      say "Starting the VMware utility (sudo)"
      sudo launchctl bootstrap system "$VMWARE_UTILITY_PLIST" \
        || die "Could not start the VMware utility -- vagrant will not be able to reach the VMs"
      # launchctl returns as soon as it has forked the daemon, but vagrant talks
      # to its API on 9922 and fails hard ("Connection refused") if it gets
      # there first. Wait for the socket, not for the process.
      local i
      for i in $(seq 1 40); do
        nc -z 127.0.0.1 "$VMWARE_UTILITY_PORT" 2>/dev/null && break
        sleep 0.5
      done
      nc -z 127.0.0.1 "$VMWARE_UTILITY_PORT" 2>/dev/null \
        || die "VMware utility did not start listening on port $VMWARE_UTILITY_PORT within 20s"
      ;;
    off)
      [ "$loaded" = no ] && return 0
      say "Stopping the VMware utility to release host port 2222 (sudo)"
      sudo launchctl bootout "system/$VMWARE_UTILITY_LABEL" \
        || info "[WARN] Could not stop the VMware utility -- port 2222 may stay busy"
      ;;
  esac
}

#---------------------------------------------------------------
# subcommands
#---------------------------------------------------------------
cmd_up() {
  need_vagrant
  vmware_utility on
  say "Bringing up three VMs with the $VAGRANT_DEFAULT_PROVIDER provider"
  info "First run downloads the box and asks for your password once, so the"
  info "VMware utility can create the 192.168.50.0/24 host-only network."
  ( cd "$HERE" && vagrant up )
  ssh_config
  for n in "${ALL_NODES[@]}"; do
    on "$n" "hostname -I" >/dev/null || die "$n is up but not reachable over ssh"
    info "[OK] $n reachable"
  done

  # Chain straight into bootstrap + kubeconfig -- both are idempotent (bootstrap
  # skips kubeadm init/join steps that are already done; kubeconfig just
  # re-copies admin.conf), so `up` alone now leaves you with a working
  # kubeconfig on disk instead of stopping halfway and expecting a manual
  # follow-up command.
  cmd_bootstrap
  cmd_kubeconfig
  kubeconfig_hint
}

cmd_bootstrap() {
  ssh_config

  if on "$CONTROL" "sudo test -f /etc/kubernetes/admin.conf"; then
    say "Control plane already initialized on $CONTROL -- skipping kubeadm init"
  else
    say "kubeadm init on $CONTROL (bootstrap_cp.sh; Calico v3.29.1 follows)"
    scp -q -F "$SSH_CFG" "$HERE/bootstrap_cp.sh" "$CONTROL:/tmp/bootstrap_cp.sh"
    # Run via `bash <file>` rather than ./file: a copied script lands 0644 and
    # would fail with "permission denied" on camera.
    on "$CONTROL" "bash /tmp/bootstrap_cp.sh"
  fi

  # Fetch the join command from the control plane HERE, on the host, and hand it
  # to each worker. join_worker.sh does the same thing from inside a worker, but
  # that needs guest-to-guest SSH, which Vagrant does not set up.
  say "Joining workers"
  local join
  join="$(on "$CONTROL" "sudo kubeadm token create --print-join-command")"
  [ -n "$join" ] || die "Empty join command from $CONTROL"

  for w in "${WORKERS[@]}"; do
    if on "$CONTROL" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get node $w" >/dev/null 2>&1; then
      info "[skip] $w already registered"
      continue
    fi
    info "joining $w ..."
    on "$w" "sudo $join"
    info "[OK] $w joined"
  done

  say "Waiting for all three nodes to report Ready"
  on "$CONTROL" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf wait --for=condition=Ready node --all --timeout=300s"
}

cmd_kubeconfig() {
  ssh_config
  mkdir -p "$(dirname "$KUBECONFIG_OUT")"
  say "Copying admin.conf to $KUBECONFIG_OUT"
  on "$CONTROL" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG_OUT"
  [ -s "$KUBECONFIG_OUT" ] || die "admin.conf came back empty"
  # Defensive: admin.conf already points at the advertise address, but a
  # rebuilt cluster that picked a different one would silently break kubectl.
  sed -i '' -E "s#server: https://[0-9.]+:6443#server: https://${CP_IP}:6443#" "$KUBECONFIG_OUT"
  chmod 600 "$KUBECONFIG_OUT"
  grep -q "https://${CP_IP}:6443" "$KUBECONFIG_OUT" || die "kubeconfig does not point at ${CP_IP}"
  info "[OK] use it with:  export KUBECONFIG=$KUBECONFIG_OUT"
}

k() { KUBECONFIG="$KUBECONFIG_OUT" kubectl "$@"; }

# macOS gates LAN access per app ("Local Network" in Privacy & Security). When
# the grant is missing the kernel answers EHOSTUNREACH, so kubectl reports
# "no route to host" for the API server while ping, ssh, scp and curl keep
# working -- those are Apple platform binaries and are exempt. That pair is the
# fingerprint: kubectl fails, curl to the same host:port succeeds. Nothing in
# the lab is broken then, and no amount of re-running fixes it, so say so.
local_network_blocked() {
  [ "$(uname -s)" = "Darwin" ] || return 1
  KUBECONFIG="$KUBECONFIG_OUT" kubectl --request-timeout=5s get --raw /healthz \
    >/dev/null 2>&1 && return 1
  # curl cannot reach it either -> the API really is down, which is a different
  # problem and the caller's own error handling should report it.
  curl -sk -m 5 -o /dev/null "https://$CP_IP:6443/healthz" 2>/dev/null || return 1
  return 0
}

need_local_network() {
  local_network_blocked || return 0
  die "kubectl cannot reach $CP_IP:6443, but curl can -- macOS is blocking Local Network access for kubectl.

    Fix: System Settings > Privacy & Security > Local Network -> enable the
    terminal app you are running this from, then QUIT IT COMPLETELY (Cmd-Q)
    and reopen -- the permission is only read when the app launches.

    Still blocked afterwards? Reset the grant so macOS asks again:
      tccutil reset LocalNetwork <bundle-id>   # e.g. com.googlecode.iterm2
    then reopen the terminal, re-run, and click Allow on the prompt.

    The VMs and the cluster are fine -- this is a permission on your Mac."
}


cmd_status() {
  need_vagrant
  say "VMs"
  ( cd "$HERE" && vagrant status )
  if [ -s "$KUBECONFIG_OUT" ]; then
    say "Cluster"
    k get nodes -o wide || {
    info "API server not reachable -- VMs may still be booting"
    local_network_blocked && info "...actually: macOS is blocking Local Network access for kubectl -- run ./cka-lab.sh check"
    true
  }
  else
    info "No kubeconfig yet -- run: ./cka-lab.sh kubeconfig"
  fi
}

cmd_dns() {
  # VMware's NAT DHCP hands every VM `domain localdomain`, systemd-resolved puts
  # it in the node's search list, and kubelet copies the node's search list into
  # EVERY Pod. So a Pod ends up with:
  #
  #   search default.svc.cluster.local svc.cluster.local cluster.local localdomain
  #   options ndots:5
  #
  # `globo-shop.default.svc.cluster.local` has FOUR dots, which is fewer than
  # ndots, so the resolver treats it as RELATIVE and walks the search list first.
  # The three cluster suffixes NXDOMAIN instantly. The fourth --
  # `...cluster.local.localdomain` -- is not a cluster name, so CoreDNS forwards
  # it upstream to VMware's NAT DNS proxy at the gateway, which never answers.
  # The lookup burns the full resolver timeout before falling through to the
  # absolute name.
  #
  # Visible symptom: `curl <svc>.<ns>.svc.cluster.local` from a Pod hangs for
  # five seconds and returns nothing, while the SHORT name answers in one
  # millisecond. The FQDN is exactly what Course 7 Module 1 teaches, so this is
  # a recording-stopper, and nothing in `kubectl get`/`describe` hints at it.
  #
  # Fix at the root, not per-Pod: hand kubelet its own resolv.conf carrying the
  # upstream nameservers and NO search domains. Every Pod created afterwards --
  # including ad-hoc `kubectl run` Pods, which cannot easily set dnsConfig --
  # gets a clean three-entry cluster search list. The node's own resolution is
  # untouched, so ssh, apt, and image pulls behave exactly as before.
  #
  # Hyper-V does not hand out `localdomain`, which is why the Windows lab and the
  # recorded Courses 1-4 never hit this.
  ssh_config
  say "Removing the DHCP 'localdomain' search entry from Pod DNS"
  for n in "${ALL_NODES[@]}"; do
    on "$n" 'set -e
      # Take the upstream servers from what systemd-resolved actually resolved
      # to, rather than hardcoding a gateway address that changes per host.
      up=$(awk "/^nameserver/{print \$2}" /run/systemd/resolve/resolv.conf | head -3)
      [ -n "$up" ] || { echo "no upstream nameserver found" >&2; exit 1; }
      { for s in $up; do echo "nameserver $s"; done; echo "options edns0 trust-ad"; }         | sudo tee /etc/kubernetes/resolv.conf >/dev/null
      sudo sed -i "s#^resolvConf:.*#resolvConf: /etc/kubernetes/resolv.conf#" /var/lib/kubelet/config.yaml
      grep -q "^resolvConf: /etc/kubernetes/resolv.conf$" /var/lib/kubelet/config.yaml         || { echo "kubelet config.yaml not updated" >&2; exit 1; }
      sudo systemctl restart kubelet'
    info "[OK] $n"
  done

  # Assert the end state rather than assuming it. A throwaway Pod is the only
  # thing that proves what kubelet is actually writing into a Pod now.
  need_local_network
  k wait --for=condition=Ready node --all --timeout=180s >/dev/null \
    || die "a node did not come back Ready after the kubelet restart"
  k delete pod cka-dnscheck --ignore-not-found --force --grace-period=0 --timeout=60s >/dev/null 2>&1 || true
  k run cka-dnscheck --image=curlimages/curl --restart=Never -- sleep 120 >/dev/null
  k wait --for=condition=Ready pod/cka-dnscheck --timeout=120s >/dev/null \
    || die "cka-dnscheck pod never became Ready"
  local search
  search="$(k exec cka-dnscheck -- sh -c 'grep ^search /etc/resolv.conf')"
  k delete pod cka-dnscheck --force --grace-period=0 >/dev/null 2>&1 || true
  case "$search" in
    *localdomain*) die "Pod DNS still carries 'localdomain': $search" ;;
    *) info "[OK] Pod search list is now: ${search#search }" ;;
  esac
}

cmd_heal() {
  # Known gotcha, same on Hyper-V: restoring a snapshot invalidates Calico's
  # CNI token and the nodes sit NotReady until calico-node restarts.
  [ -s "$KUBECONFIG_OUT" ] || die "No kubeconfig at $KUBECONFIG_OUT -- run: ./cka-lab.sh kubeconfig"
  # Clear pods stuck Terminating BEFORE touching the rollout.
  #
  # A snapshot restore rolls a node's disk back to a moment when kubelet still
  # owned a pod that the API server has since marked for deletion. kubelet's
  # in-memory state and etcd then disagree forever: the container is gone from
  # the runtime (`crictl ps` shows nothing) while kubelet loops on
  # "Readiness probe already exists for container" and never finalizes.
  #
  # The DaemonSet uses maxUnavailable: 1, so ONE such pod wedges the entire
  # rollout -- `kubectl rollout status` then hangs at "0 out of 3 new pods have
  # been updated" with nothing anywhere explaining why, because the DaemonSet's
  # own status still cheerfully reports numberReady: 3.
  local stuck
  need_local_network
  stuck="$(k -n calico-system get pods \
            -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null || true)"
  if [ -n "$stuck" ]; then
    say "Clearing pods stuck Terminating (snapshot-restore artifact)"
    while IFS= read -r pod; do
      [ -n "$pod" ] || continue
      info "force-deleting $pod"
      k -n calico-system delete pod "$pod" --grace-period=0 --force --timeout=60s >/dev/null 2>&1 || true
    done <<< "$stuck"
  fi

  say "Restarting calico-node (post-restore CNI token fix)"
  k -n calico-system rollout restart ds/calico-node
  # 180s was too short and produced a red "timed out waiting for the condition"
  # on a cluster that then converged fine seconds later. The DaemonSet rolls one
  # node at a time and each calico-node takes a while to pass its probes, so
  # budget for the whole serial pass -- three nodes, cold image cache, 2 vCPU.
  k -n calico-system rollout status ds/calico-node --timeout=600s
  k wait --for=condition=Ready node --all --timeout=300s
  info "[OK] all nodes Ready, calico-node rolled out"
}

# VMware snapshots form a TREE, not a flat list: a snapshot taken after a
# restore becomes a CHILD of the one you restored, and `vagrant snapshot list`
# prints full paths --
#
#   post-bootstrap
#   post-bootstrap/take-1
#   post-bootstrap/take-1/post-c7
#
# `vagrant snapshot restore post-c7` then fails with "was not found" AND EXITS
# 0, so a naive wrapper reports success having restored nothing. Resolve the
# leaf name to its full path, and never trust the exit code alone.
snapshot_path() {
  local want="$1" matches
  matches="$(cd "$HERE" && vagrant snapshot list control1 2>/dev/null \
             | awk 'NF && $0 !~ /^==>/ {print $1}' \
             | awk -F/ -v w="$want" '$NF == w || $0 == w {print $0}')"
  local n
  n="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    die "No snapshot named '$want'. Existing snapshots:
$(cmd_snapshots)"
  elif [ "$n" -gt 1 ]; then
    die "'$want' is ambiguous -- it matches more than one snapshot. Pass the full path:
$matches"
  fi
  printf '%s' "$matches"
}

cmd_snapshots() {
  need_vagrant
  ( cd "$HERE" && vagrant snapshot list control1 2>/dev/null \
    | awk 'NF && $0 !~ /^==>/ {print "    " $1}' ) || true
}

cmd_snap() {
  need_vagrant
  local name="${1:-}"; [ -n "$name" ] || die "Usage: ./cka-lab.sh snap <name>"

  # Reject a duplicate leaf name up front: two snapshots ending in the same
  # name make `restore <name>` ambiguous, and you find that out later, under
  # pressure, when you are trying to get back to a known state.
  if (cd "$HERE" && vagrant snapshot list control1 2>/dev/null) \
       | awk 'NF && $0 !~ /^==>/ {print $1}' | awk -F/ '{print $NF}' | grep -qx "$name"; then
    die "A snapshot named '$name' already exists. Pick another name, or restore it first."
  fi

  say "Snapshotting all three VMs as '$name'"
  ( cd "$HERE" && vagrant snapshot save "$name" )
  snapshot_path "$name" >/dev/null   # assert it really landed
  info "[OK] saved as $(snapshot_path "$name")"
}

cmd_restore() {
  need_vagrant
  local name="${1:-}"; [ -n "$name" ] || die "Usage: ./cka-lab.sh restore <name>"
  local path out
  path="$(snapshot_path "$name")"
  say "Restoring all three VMs to '$path'"

  # Capture the output: vagrant exits 0 even when the snapshot does not exist,
  # so the message is the only signal there is.
  out="$( cd "$HERE" && vagrant snapshot restore --no-provision "$path" 2>&1 )" || true
  printf '%s\n' "$out"
  if printf '%s' "$out" | grep -qi "was not found\|not created\|error"; then
    die "Restore did not complete -- see the output above. The lab is in an unknown state."
  fi
  for n in "${ALL_NODES[@]}"; do
    (cd "$HERE" && vagrant status "$n" 2>/dev/null) | grep -q "running" \
      || die "$n is not running after the restore"
  done
  cmd_heal
}

cmd_halt()    { need_vagrant; ( cd "$HERE" && vagrant halt ); vmware_utility off; }

cmd_destroy() {
  need_vagrant
  say "This deletes control1, worker1 and worker2 and everything on them."
  read -r -p "    Type 'destroy' to confirm: " reply
  [ "$reply" = "destroy" ] || die "Aborted -- nothing was deleted"
  ( cd "$HERE" && vagrant destroy -f )
  vmware_utility off
}

# The kubeconfig lands in a non-default path, so a plain `kubectl`/`k` in your
# shell talks to localhost:8080 and reports "connection refused". Say so at the
# end of a full run, where it is the last thing on screen, unless the shell
# already points at the lab.
kubeconfig_hint() {
  [ "${KUBECONFIG:-}" = "$KUBECONFIG_OUT" ] && return 0
  say "Point your shell at the lab before using kubectl"
  info "export KUBECONFIG=$KUBECONFIG_OUT"
  info "(without it kubectl falls back to localhost:8080 and refuses to connect)"
}

# cmd_up already chains bootstrap + kubeconfig; no need to repeat them here.
cmd_all() { cmd_up; cmd_dns; cmd_status; kubeconfig_hint; }

# Read-only subcommands (check, status) deliberately skip the lock so you can
# look at the lab while a build is running.
case "${1:-all}" in
  all|"")     acquire_lock; cmd_all ;;
  check)      cmd_check ;;
  up)         acquire_lock; cmd_up ;;
  bootstrap)  acquire_lock; cmd_bootstrap ;;
  kubeconfig) acquire_lock; cmd_kubeconfig ;;
  status)     cmd_status ;;
  dns)        acquire_lock; cmd_dns ;;
  heal)       acquire_lock; cmd_heal ;;
  snapshots)  cmd_snapshots ;;
  snap)       acquire_lock; shift; cmd_snap "$@" ;;
  restore)    acquire_lock; shift; cmd_restore "$@" ;;
  halt)       acquire_lock; cmd_halt ;;
  destroy)    acquire_lock; cmd_destroy ;;
  -h|--help|help) sed -n '2,30p' "${BASH_SOURCE[0]}" ;;
  *)          die "Unknown subcommand '$1'. Try: ./cka-lab.sh help" ;;
esac
