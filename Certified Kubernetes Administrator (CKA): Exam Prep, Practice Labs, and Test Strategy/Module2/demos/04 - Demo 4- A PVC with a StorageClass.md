# Demo: A PVC with a StorageClass

Clip: 4

This task wants a PVC called `data-pvc` with `1Gi` from the available StorageClass. It also wants a Deployment called `writer` that mounts the claim at `/data` and writes `hello` into `/data/test.txt`. Lets start by looking at the storage this cluster offers.

`k get storageclass`

There is only 1 class, called `local-path`, and 2 of its columns are important for what happens next. The reclaim policy is `Delete`, and the binding mode is `WaitForFirstConsumer`.

There is no imperative command for a PVC, so I take it from the docs. I search for persistent volumes, open the Persistent Volumes page and press Ctrl+F on `kind: PersistentVolumeClaim` to find the shortest example. I paste it with `cat > data-pvc.yaml` and Ctrl+D.

Then I change only 4 fields: the name, `storageClassName` set to `local-path`, `accessModes` set to `ReadWriteOnce`, and the size set to `1Gi`. Everything else from the example can go.

`ReadWriteOnce` means only 1 node can mount the volume at a time. local-path keeps the data on the disk of a single node, so that's the only mode it supports anyway.

Let me apply it and check the claim.

`k apply -f data-pvc.yaml`

`k get pvc data-pvc`

It says Pending — and that's fine here. `WaitForFirstConsumer` means the provisioner waits until a Pod actually uses the claim, so it can create the volume on the node where the Pod lands.

This is why I check the binding mode first, otherwise a Pending claim looks like an error.

Next is the Deployment, and here kubectl can even set the container command for us. Everything after the double dash becomes the command, so I don't have to write a `command:` block by hand.

`k create deployment writer --image=busybox --dry-run=client -o yaml -- sh -c 'echo hello > /data/test.txt && sleep 3600' > writer.yaml`

`vim writer.yaml`

kubectl can't generate volumes, so I add them myself. Under the container I add a `volumeMounts` entry called `data` at `/data`. Under the Pod spec I add a `volumes` entry with `claimName: data-pvc`.

Its the same pattern as a ConfigMap mount, only the volume type is different.

`k apply -f writer.yaml`

`k rollout status deployment/writer`

Now lets verify the result, and I check 3 things. `k get pvc data-pvc` shows Bound this time, because a Pod finally uses the claim. `k get pv` shows the volume the provisioner created for us. It has a generated name, and it inherited the reclaim policy `Delete` from the StorageClass. So if you delete the claim later, the data is gone too.

The capacity column shows `1Gi`, but local-path doesn't actually enforce that size — the volume is just a directory on the node. The field still has to be correct, since that's what the task asked for.

And finally I check the data itself.

`k exec deploy/writer -- cat /data/test.txt`

It returns `hello`, so the file is on the volume. Because it lives on the PV and not in the container, it survives when the Pod gets replaced.

I stop the timer here. We completed the task successfully.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo4-pvc-storageclass/reset_commands.txt for you. By hand:
cd m02-timed-scenarios/demo4-pvc-storageclass   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m2-demo4 && vagrant ssh control1

# stage m2-demo4 asserts: StorageClass local-path (WaitForFirstConsumer, Delete) is the only class, no data-pvc/writer, fallbacks in ~/solutions/
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Find the StorageClass ─────────────────────────────────
k get storageclass

# ── Phase 2: PVC from the docs ─────────────────────────────────────
# Firefox -> search "persistent volumes" -> "Persistent Volumes" -> Ctrl+F "kind: PersistentVolumeClaim" -> copy
cat > data-pvc.yaml #paste solutions/data-pvc-docs.yaml
vim data-pvc.yaml #keys edits/data-pvc.keys
cat data-pvc.yaml #wait 10
k apply -f data-pvc.yaml

# ── Phase 3: Pending is expected here ──────────────────────────────
k get pvc data-pvc

# ── Phase 4: Deployment that writes the file ───────────────────────
k create deployment writer --image=busybox --dry-run=client -o yaml -- sh -c 'echo hello > /data/test.txt && sleep 3600' > writer.yaml
vim writer.yaml #keys edits/writer.keys
cat writer.yaml #wait 10
k apply -f writer.yaml

# ── Phase 5: Wait for the rollout ──────────────────────────────────
k rollout status deployment/writer #wait 12

# ── Phase 6: Verify claim, volume and data ─────────────────────────
k get pvc data-pvc
k get pv #wait 6
k exec deploy/writer -- cat /data/test.txt #wait 4
```

## Deviations & Questions

- **`&&` restored in the container command.** I had swapped it for `;` because I assumed type.py splits on `&&`. It doesn't inside quotes, but it DOES split on `;` inside quotes, typing a `quote>` continuation. So `&&` is the safer choice and matches the original script.
- **PVC pasted, then trimmed in vim.** Fallback: `cp ~/solutions/data-pvc-docs.yaml data-pvc.yaml`, reference result in `~/solutions/data-pvc.yaml`. The docs example carries a `selector`, which has to go: a claim with a selector is never dynamically provisioned.
- **local-path-provisioner pinned to `v0.0.37`** (current stable, post-CVE-2025-62878). `./lab.sh storage` asserts `WaitForFirstConsumer` and `Delete`.
- **`stage m2-demo4` warns if more than one StorageClass exists**, since the narration says "there is only 1 class".
- **[VERIFY: generated command]** — kubectl's reference confirms `kubectl create deployment NAME --image=image -- [COMMAND] [args...]`. Check the dry-run output against `~/solutions/writer.yaml` once on the lab.
