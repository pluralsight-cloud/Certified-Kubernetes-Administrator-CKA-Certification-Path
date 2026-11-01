# Demo: Backing up and restoring etcd

Clip: 2

Its time for the etcd drill. The task says to back up etcd to `/tmp/etcd-backup.db` and then restore the cluster from that backup. 

I don't type any certificate paths from memory — they are all in the etcd manifest, so I grep for them. This is still a long command, so you can also do this by hand just looking at the manifest.

`sudo grep -E -- '--(listen-client-urls|cert-file|key-file|trusted-ca-file)=' /etc/kubernetes/manifests/etcd.yaml`

But for the demo this gives me 4 lines with everything the backup needs. The client URL contains `https://127.0.0.1:2379`, and the 3 files are the CA at `/etc/kubernetes/pki/etcd/ca.crt`, the server certificate and its key. I copy them straight from this output.

Now I can take the backup. I always go in the same order: endpoint, CA, cert, key, and then the file.

`sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /tmp/etcd-backup.db`

etcdctl reports that the snapshot was saved to `/tmp/etcd-backup.db`. Older tutorials often set the environment variable `ETCDCTL_API=3` first. You don't need that anymore, but it doesn't break anything if you type it out of habit.

Next I want a marker, so we can see later if the restore really worked, and for that I create a Deployment after the backup.

`k create deployment after-backup --image=nginx`

This Deployment is not in the snapshot, so if the restore works, it should be gone afterwards.

Now lets check the snapshot. Since etcd 3.6, `snapshot status` and `snapshot restore` no longer exist in `etcdctl`, they moved to `etcdutl`.

`etcdctl` talks to a running etcd over the network, that's why the backup needs the endpoint and the certificates. `etcdutl` works directly on the files. You still find the old `etcdctl` commands in a lot of guides, so double check which tool you type.

`sudo etcdutl snapshot status /tmp/etcd-backup.db -w table`

The table shows a hash, a revision, the total number of keys and the size, so the file is a real snapshot and not an empty one.

Now comes the restore, and I never restore over the live data directory, always into a new one. If you mess up in the exam its always best if you have the original files still present, to go back to later on.

`sudo etcdutl snapshot restore /tmp/etcd-backup.db --data-dir=/var/lib/etcd-restored`

etcd and the API server both run as static Pods, so the kubelet starts them from their manifest files. Before I touch etcd, I stop the API server by moving its manifest out of the manifests folder.

`sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/`

This step matters more than it looks. The docs say no API server should run while you restore etcd. If it keeps running, it keeps serving its cached view from before the restore — objects that no longer exist in etcd still show up in `k get pods`.

Now I point etcd at the restored data, and I edit its manifest directly on the node.

`sudo vim /etc/kubernetes/manifests/etcd.yaml`

I scroll down to the `etcd-data` volume and change its hostPath from `/var/lib/etcd` to `/var/lib/etcd-restored`. That's the only change, because the `--data-dir` flag and the `volumeMounts` both use the path inside the container, and that one stays the same.

As soon as I save, the kubelet notices the change and restarts etcd. kubectl doesn't work right now, because there is no API server, so I watch the containers with crictl instead.

`watch "sudo crictl ps --name 'etcd|kube-apiserver'"`

I wait until etcd shows a fresh uptime and the API server is gone from the list. Then I move the API server manifest back, and the kubelet starts it again with a fresh view of the data.

`sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/`

When both containers are running again, `k get nodes` shows all 3 nodes Ready, and `k get pods -A` shows the system Pods running. Now lets do the marker test.

`k get deployment after-backup`

It returns NotFound — so the cluster is back at the state of the backup.

On a real cluster I would also restart the kubelets afterwards. Everything that watches the API can still hold its view from before the restore, and the docs recommend that restart for exactly this reason.

There is one more thing I want to mention. A snapshot contains every Secret of your cluster, so please store it as carefully as the Secrets themselves.

This was a more complicated task, I suggest you leave this until the end when you finished all easier and faster tasks to ensure you got all the easy points before you sink time into complex tasks. 

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo2-etcd-backup-restore/reset_commands.txt for you. By hand:
cd m03-weak-area-drills/demo2-etcd-backup-restore   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m3-demo2 && vagrant ssh control1

# stage m3-demo2 asserts: etcd on /var/lib/etcd, no /var/lib/etcd-restored or /tmp/etcd-backup.db, no after-backup, etcdctl/etcdutl match the cluster's etcd
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Read the certificate paths ────────────────────────────
sudo grep -E -- '--(listen-client-urls|cert-file|key-file|trusted-ca-file)=' /etc/kubernetes/manifests/etcd.yaml

# ── Phase 2: Back up ───────────────────────────────────────────────
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /tmp/etcd-backup.db

# ── Phase 3: Marker after the backup ───────────────────────────────
k create deployment after-backup --image=nginx

# ── Phase 4: Check the snapshot ────────────────────────────────────
sudo etcdutl snapshot status /tmp/etcd-backup.db -w table

# ── Phase 5: Restore into a new directory ──────────────────────────
sudo etcdutl snapshot restore /tmp/etcd-backup.db --data-dir=/var/lib/etcd-restored

# ── Phase 6: Stop the API server, point etcd at the restored data ───
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/
sudo vim /etc/kubernetes/manifests/etcd.yaml #keys edits/etcd.keys
watch "sudo crictl ps --name 'etcd|kube-apiserver'" #confirm

# ── Phase 7: Start the API server again ────────────────────────────
sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/
watch "sudo crictl ps --name 'etcd|kube-apiserver'" #confirm

# ── Phase 8: Verify ────────────────────────────────────────────────
k get nodes
k get pods -A #wait 6
k get deployment after-backup #wait 4 #allow-error
```

## Deviations & Questions

- **The `watch` command is wrapped in double quotes (found on your first take).** `watch` glues its arguments together and hands them to `sh -c`, so the single quotes around `etcd|kube-apiserver` were stripped and the shell read `|` as a pipe: `sh: 1: kube-apiserver: not found`. My live test missed it because the harness swapped this beat for a polling loop. No narration change, the spoken line doesn't read the quotes out.
- **`watch sudo crictl ps` instead of a one-shot `crictl ps`.** The restart takes 30–90 seconds, and `watch` lets you talk over it and continue when etcd is up. Cut the wait in the edit.
- **grep made exact.** `--(cert-file|...)=` matches only the four client-side flags and skips the `--peer-*` ones.
- **"kubernetes.io page still shows the older tab" softened** to "older guides still show the `etcdctl` versions".
- **API server stopped during the restore (found in the live test).** The first version only edited `etcd.yaml`. After that restore, etcd no longer had the marker's Pod or ReplicaSet, but `k get pods -A` still listed both, served from the API server's watch cache (checked with `etcdctl get /registry/pods/default/ --prefix --keys-only`: no `after-backup` key). The Kubernetes docs say: *"If any API servers are running in your cluster, you should not attempt to restore instances of etcd. Instead […] stop all API server instances, restore state in all etcd instances, restart all API server instances."* The drill now parks `kube-apiserver.yaml` in `/etc/kubernetes/` before the edit and moves it back once etcd is up. The watch covers both containers, so you can see the API server is really gone before you move it back (the kubelet checks the manifest folder about every 20s).
- **No Vagrant snapshot needed between takes.** `stage m3-demo2` moves etcd's live data from `/var/lib/etcd-restored` back to `/var/lib/etcd` and repoints the manifest, so the revision keeps moving forward. A `./cka-lab.sh snap` before the first take is still cheap insurance.
- **etcd tools from `./lab.sh etcdtools`**, installed at the version of the cluster's etcd image (arm64 or amd64 picked automatically).
- **Restarting the other components: narrated, not typed (found in the live test).** The docs: *"The Kubernetes project also recommends restarting Kubernetes components (`kube-scheduler`, `kube-controller-manager`, `kubelet`) to ensure that they don't rely on some stale data. […] During the restoration, critical components will lose leader lock and restart themselves."* On the lab, kube-scheduler and kube-controller-manager did restart on their own (restart counters went up during the drill). kube-proxy did not: after the restores it kept REJECTing `10.96.0.1` on worker1, so new Pods there hung in ContainerCreating (`calico … dial tcp 10.96.0.1:443: connect: connection refused`). The marker test still passes, so the demo itself is unaffected. The repair is off camera: `stage m3-demo2` (and every other stage) notices that etcd ran from `/var/lib/etcd-restored`, moves it home and then runs `./lab.sh heal` (kubelets + the DaemonSets in kube-system and calico-system). One spoken sentence after the marker test covers it for learners.
