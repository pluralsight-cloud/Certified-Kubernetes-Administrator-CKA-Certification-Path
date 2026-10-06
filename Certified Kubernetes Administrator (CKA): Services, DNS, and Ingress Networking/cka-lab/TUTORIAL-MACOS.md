# TUTORIAL -- VMware Fusion + Vagrant CKA Lab (macOS)

> Same three VMs, same IPs, same kubeadm cluster as the Hyper-V lab.
> Different hypervisor, because macOS does not have Hyper-V.

---

## Read this first

The recorded courses (1-4) were built on Windows + Hyper-V, and
[`TUTORIAL-HYPERV.md`](TUTORIAL-HYPERV.md) is still the reference for that path.
This page is the macOS equivalent. Both build the **identical cluster**:

- `control1` / `worker1` / `worker2` at `192.168.50.10` / `.11` / `.12`
- Ubuntu 22.04, containerd, kubeadm-installed Kubernetes **v1.35**
- Calico **v3.29.1** via the Tigera operator, pod CIDR `192.168.0.0/16`

Same `Vagrantfile`, which branches on the host OS. Nothing about the Windows
path changed.

**Why real VMs and not a container-based cluster:** Course 7 demos curl a
NodePort at `192.168.50.11:<port>` from your Mac, and browse Ingress and Gateway
routes the same way. That works because these are real VMs on a host-routable
network. A Docker-based cluster hides node IPs behind a bridge the Mac cannot
reach, so half the course would need `kubectl port-forward` scaffolding that the
exam never uses.

---

## Prereqs

| Thing | Why |
|-------|-----|
| Apple Silicon or Intel Mac | Both work. On Apple Silicon the guests are arm64. |
| [VMware Fusion](https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion) | Free since November 2024, personal and commercial. Downloading it needs a (free) Broadcom account. |
| [Vagrant](https://developer.hashicorp.com/vagrant/install) 2.4+ | `brew install --cask vagrant` |
| `vagrant-vmware-desktop` plugin | Open-sourced under MPL -- no license key needed any more. |
| VMware Vagrant Utility | Privileged helper that creates the host-only network. Separate installer from the plugin. |
| `kubectl`, `helm` | `brew install kubectl helm` -- Course 7 installs Traefik with Helm. |
| ~10 GB disk, ~8 GB free RAM | Three VMs at 2 GB each, plus overhead. |

### First-time install

```bash
brew install --cask vagrant
brew install kubectl helm
vagrant plugin install vagrant-vmware-desktop

# These two run an Apple installer package, so they ask for your password.
brew install --cask vmware-fusion            # skip if Fusion is already installed
brew install --cask vagrant-vmware-utility
```

VMware Fusion is also available directly from the Broadcom download portal if
you would rather not use the cask. Either way, approve the system extension when
macOS prompts and reboot if it asks.

The first `vagrant up` asks for your password too, when the utility creates the
`192.168.50.0/24` host-only network. That is expected -- making a virtual
network interface is a privileged operation.

The utility is not optional. Without it the provider fails immediately with
`No such file or directory ... /opt/vagrant-vmware-desktop/certificates/vagrant-utility.client.crt`.

### Give VMware the lab network first

**Do this before the first `vagrant up`.** Vagrant tries to create a host-only
network for `192.168.50.0/24` on its own, and on Fusion 26 that fails:

```text
Vagrant failed to create a new VMware networking device.
  Failed to enable device
```

Vagrant writes the config (`VNET_2_*` lands in
`/Library/Preferences/VMware Fusion/networking`) but Fusion never instantiates
the device -- no `vmnet2` directory, no interface. Fusion's own networking is
fine; it is the *create a new one* path that is broken.

The fix is to hand an existing, working vmnet that subnet. Vagrant reuses any
vmnet whose subnet already matches and only tries to create one when nothing
does, so this sidesteps the broken path entirely. `vmnet1` is host-only and
unused by default:

```bash
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --stop
```

```bash
sudo cp "/Library/Preferences/VMware Fusion/networking" "/Library/Preferences/VMware Fusion/networking.pre-cka"
```

```bash
sudo sed -i '' -e 's/^answer VNET_1_HOSTONLY_SUBNET .*/answer VNET_1_HOSTONLY_SUBNET 192.168.50.0/' -e '/^answer VNET_2_/d' "/Library/Preferences/VMware Fusion/networking"
```

```bash
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --configure
```

```bash
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --start
```

Confirm before moving on -- you want `inet 192.168.50.1 netmask 0xffffff00`:

```bash
ifconfig | grep 192.168.50.1
```

GUI equivalent, if you prefer to see it: **Fusion → Settings → Network →
unlock → vmnet1 → subnet IP `192.168.50.0`, mask `255.255.255.0`**.

On Apple Silicon these networks show up as `bridge1xx` interfaces rather than
`vmnetX`, so do not go looking for a `vmnet1` in `ifconfig` -- match on the
address instead.

### Check the toolchain

Check the whole toolchain before you build anything:

```bash
cd src/cka-lab
./cka-lab.sh check
```

Every line should read installed. Fix any `MISSING` line before continuing.

---

## Build the cluster

```bash
cd src/cka-lab
./cka-lab.sh
```

That single command runs four steps, and you can run any of them on its own:

| Step | What happens | Roughly |
|------|--------------|---------|
| `up` | Downloads `bento/ubuntu-22.04` (arm64 is selected automatically), boots three VMs, installs containerd + kubeadm/kubelet/kubectl pinned to `1.35.0-1.1` | 10-15 min first time |
| `bootstrap` | `kubeadm init` on control1, Calico, then joins both workers | 4-6 min |
| `kubeconfig` | Copies `admin.conf` to `~/.kube/cka-config` and points it at `192.168.50.10` | seconds |
| `status` | `vagrant status` plus `kubectl get nodes -o wide` | seconds |

Then point your shell at the cluster:

```bash
export KUBECONFIG=~/.kube/cka-config
kubectl get nodes -o wide
```

**The output that matters:**

```text
NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP
control1   Ready    control-plane   3m    v1.35.0   192.168.50.10
worker1    Ready    <none>          2m    v1.35.0   192.168.50.11
worker2    Ready    <none>          2m    v1.35.0   192.168.50.12
```

Check the `INTERNAL-IP` column, not just `Ready`. If a node reports a `172.16.x`
address, kubelet picked the VMware NAT interface instead of the lab network and
NodePort access from your Mac will not work. See Troubleshooting.

---

## Prove NodePort reaches the VMs

This is the property Course 7 is built on, so verify it once, up front:

```bash
kubectl create deployment probe --image=nginx:1.27-alpine
kubectl expose deployment probe --type=NodePort --port=80
kubectl get svc probe          # note the 3xxxx port
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.50.11:<nodePort>
kubectl delete deployment,svc probe --ignore-not-found --timeout=60s
```

`200` means the whole path works: your Mac, the host-only network, the node, and
kube-proxy.

---

## The practice loop

Snapshot before anything risky, restore when you want to redrill or re-record:

```bash
./cka-lab.sh snap pre-cluster     # or: post-bootstrap, pre-take-3, ...
# ... break things, record a take, experiment ...
./cka-lab.sh restore pre-cluster
./cka-lab.sh snapshots            # what save points exist
```

`restore` rolls all three VMs back together and then runs `heal` for you.

**Snapshots nest.** VMware keeps them as a tree, not a flat list: a snapshot you
take after restoring another becomes its child, so after a few re-record cycles
`./cka-lab.sh snapshots` looks like this:

```text
post-bootstrap
post-bootstrap/take-1
post-bootstrap/take-1/post-c7
```

This matters because raw `vagrant snapshot restore post-c7` fails on the bare
name -- and **exits 0 while doing nothing**, so it looks like it worked until you
notice the cluster never changed. `./cka-lab.sh restore post-c7` resolves the
leaf name to its full path, refuses a name that would be ambiguous, and checks
the restore actually happened. Use the wrapper, not raw vagrant, for restores.

**Why `heal` exists:** restoring a snapshot invalidates Calico's CNI token, and
the nodes sit `NotReady` until `calico-node` restarts. This is the same gotcha
the Hyper-V lab has. `./cka-lab.sh heal` does the restart and waits for Ready --
run it by hand if a restore ever leaves you with NotReady nodes.

---

## Course 7 stack

Once the cluster is Ready, install the traffic-routing components the course
teaches against:

```bash
cd ../../exercise-files/course-07-services-ingress-gateway
./lab.sh
```

That installs the Gateway API CRDs, Traefik via Helm (serving both Ingress and
Gateway API), and the Globomantics `catalog` / `portal` / `api` backends, then
verifies the whole thing end to end. Traefik is exposed as a **NodePort** on
`30080` / `30443`, so `http://192.168.50.11:30080` reaches it from your Mac.

Note that `type: LoadBalancer` Services stay `<pending>` on this lab. That is
correct and deliberate -- there is no cloud provider to satisfy them, and
Module 1 teaches exactly that.

Two things `lab.sh` sets that are not obvious, both verified against this
cluster rather than assumed:

- **Gateway API CRDs are pinned to v1.6.1**, not the v1.2.0 the course outline
  names. Traefik 3.7 watches `TLSRoute` and `BackendTLSPolicy` at `v1`; the
  v1.2.0 standard channel ships neither, so Traefik's Gateway provider stalls
  and every Gateway sits `Pending` with nothing in `describe` to explain it.
  Ingress is unaffected, so only the Gateway API module breaks.
- **Traefik's entryPoints are moved to 80/443** (the chart defaults to
  `:8000`/`:8443`). Traefik matches a Gateway listener to an entryPoint by port,
  so a listener on port 80 -- the one everybody writes, and the one the exam
  shows -- is otherwise rejected with `no matching entryPoint for port 80`.

---

## How this differs from the Hyper-V lab

| | Hyper-V (Windows) | VMware Fusion (macOS) |
|---|---|---|
| Provider | `hyperv` | `vmware_desktop` |
| Box | `generic/ubuntu2204` | `bento/ubuntu-22.04` (arm64 on Apple Silicon) |
| Network | `CKA-NAT` external switch, static IP via netplan | VMware host-only vmnet, configured by Vagrant |
| NICs per VM | one | **two** -- VMware NAT plus the lab network |
| Snapshots | Hyper-V checkpoints, `Save-CkaSnapshot.ps1` | `vagrant snapshot`, `./cka-lab.sh snap` |
| Controls | `*.ps1`, elevated PowerShell | `./cka-lab.sh`, plain terminal |

The two-NIC difference is the one with teeth, and two things in this repo exist
because of it: the `kubelet-node-ip` provisioner in the `Vagrantfile` pins
kubelet's advertised address, and `bootstrap_cp.sh` selects the `192.168.50.x`
address for both the API server and Calico's node autodetection. Without those,
the cluster comes up looking healthy and is unreachable from the host.

The Windows-only assets stay Windows-only: the `Initialize-C04M0*Lab.ps1`
Course 4 harnesses, the `Invoke-M0*` on-rails demos, and the `notebooks/`
runbook tooling. Course 7 does not use them.

---

## Troubleshooting

**`vagrant up` fails with no usable provider.**
The plugin or the utility is missing. Run `./cka-lab.sh check`. The script
already exports `VAGRANT_DEFAULT_PROVIDER=vmware_desktop`, so you never need
`--provider`.

**`vagrant up` hangs at "Waiting for the machine to report its IP address".**
Usually the VMware Vagrant Utility is not running. Check with
`pgrep -fl vagrant-vmware-utility`, and reinstall it if nothing comes back.

**A node shows a `172.16.x` INTERNAL-IP.**
kubelet picked the NAT interface. Confirm the pin took, then restart kubelet:

```bash
vagrant ssh worker1 -c "cat /etc/default/kubelet"     # expect --node-ip=192.168.50.11
vagrant ssh worker1 -c "sudo systemctl restart kubelet"
```

**Nodes are `NotReady` after a snapshot restore.**
Calico's CNI token expired with the restore. Run `./cka-lab.sh heal`.

**A pod sits `Terminating` forever, and nothing will reschedule.**
Also a restore artifact, and a nastier one because the cluster looks healthy:
`kubectl get nodes` says Ready and the DaemonSet reports `numberReady: 3`, while
`kubectl -n calico-system rollout status ds/calico-node` hangs at
"0 out of 3 new pods have been updated" with no explanation anywhere.

What happened is that the restore rolled a node's disk back to a moment when
kubelet still owned a pod the API server had already marked for deletion. The
container is gone from the runtime, but kubelet loops on
`"Readiness probe already exists for container"` and never finalizes the pod.
Since `calico-node` uses `maxUnavailable: 1`, that single pod wedges the whole
rollout.

`./cka-lab.sh heal` force-deletes any such pod before restarting the rollout, so
running it is the fix. To confirm the diagnosis yourself:

```bash
kubectl -n calico-system get pods -o wide | grep Terminating
```

**`curl http://192.168.50.11:<nodePort>` times out.**
Check `ifconfig | grep 192.168.50.1` -- you should see the host end of the lab
network. If it is missing, go back to "Give VMware the lab network first".

**The box download fails or resolves to an amd64 image.**
`vagrant box add bento/ubuntu-22.04` and confirm it offers `vmware_desktop`.
Vagrant 2.4 picks the host architecture on its own; older Vagrant does not, which
is why 2.4+ is a hard prereq.

**Start over.**

```bash
./cka-lab.sh destroy      # asks for confirmation
./cka-lab.sh              # rebuild from scratch
```
