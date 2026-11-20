# Demo: Deployment, ConfigMap, and a rolling update

Clip: 2

Its time for the webapp task. The task card says `ssh cka-node1`, and in our lab `control1` plays that host. First I read the task to the end.

We need a Deployment called `webapp` with 3 replicas of `nginx`, requests of `100m` CPU and `128Mi` memory, and the ConfigMap `app-config` mounted at `/etc/config`. After that, we roll it to a new image version. The timer starts now.

That's too many fields for a single imperative command, so I let kubectl write the skeleton.

`k create deployment webapp --image=nginx --replicas=3 --dry-run=client -o yaml > webapp.yaml`

Then I open it in vim.

`vim webapp.yaml`

Under the container I replace the empty `resources` with the two requests, and I add a `volumeMounts` entry called `config` at `/etc/config`. One level up, in the Pod spec of the template, I add the `volumes` entry that points at `app-config`.

While I'm in the file, look at the container name. kubectl named it `nginx`, after the image — and we need exactly this name for the image update later.

Let me apply it.

`k apply -f webapp.yaml`

`k rollout status deployment/webapp`

I like to use rollout status instead of `get pods` here, because it waits until all 3 replicas are up and then tells me in one line that the rollout was successful. If you want to be extreme, you could do another task while waiting but I observed that things are very fast in the exam environment.

Next I check the mount, because that's the part of the task that's easy to miss.

`k exec deploy/webapp -- ls /etc/config`

It lists `APP_MODE`, because every key of the ConfigMap becomes a file in the mount, so the ConfigMap is exactly where the task wants it.

Now lets do the rolling update. `set image` takes the container name, an equals sign and the new image, and that's why the container name was important.

`k set image deployment/webapp nginx=nginx:1.27`

`k rollout status` follows the new Pods as they replace the old ones. By default a Deployment allows 25% extra Pods and 25% unavailable Pods during a rollout.

With 3 replicas, the extra Pods round up to 1 and the unavailable ones round down to 0.

So Kubernetes starts 1 new Pod at a time and only removes an old one when its replacement is ready. The app never drops below full capacity during the update.

`k rollout history deployment/webapp` now shows 2 revisions, the original and our update.

Lets say the new version has a bug, and the task wants us to go back.

`k rollout undo deployment/webapp`

Undo goes back to the previous revision, but I still check that it worked — I never just assume it. When the rollout is done, `k get deployment webapp -o wide` shows plain `nginx` in the `IMAGES` column again, with all 3 replicas ready.

If you look at the history again, revision 1 is gone and there is a revision 3 instead. A rollback in Kubernetes is just a new rollout of the old template, so it gets a new revision number.

There is one shortcut you should know for this kind of task.

If a task only asks for resource requests on an existing Deployment, `k set resources deployment webapp --requests=cpu=100m,memory=128Mi` does it in one line, without opening vim. I only used YAML here because we needed the volume and the mount anyway.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo2-deployment-rollout/reset_commands.txt for you. By hand:
cd m02-timed-scenarios/demo2-deployment-rollout   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m2-demo2 && vagrant ssh control1

# stage m2-demo2 asserts: ConfigMap app-config (APP_MODE=production), no webapp, reference in ~/solutions/webapp.yaml
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Generate the template ─────────────────────────────────
k create deployment webapp --image=nginx --replicas=3 --dry-run=client -o yaml > webapp.yaml

# ── Phase 2: Add requests, volume and mount ────────────────────────
vim webapp.yaml #keys edits/webapp.keys
cat webapp.yaml #wait 10
k apply -f webapp.yaml

# ── Phase 3: Verify the rollout and the mount ──────────────────────
k rollout status deployment/webapp #wait 12
k exec deploy/webapp -- ls /etc/config

# ── Phase 4: Rolling update ────────────────────────────────────────
k set image deployment/webapp nginx=nginx:1.27
k rollout status deployment/webapp #wait 12
k rollout history deployment/webapp

# ── Phase 5: Roll back and confirm ─────────────────────────────────
k rollout undo deployment/webapp
k rollout status deployment/webapp #wait 12
k get deployment webapp -o wide #wait 6
k rollout history deployment/webapp

# ── Phase 6: Compare with the reference solution ───────────────────
cat ~/solutions/webapp.yaml #wait 10
```

## Deviations & Questions

- **Revision renumbering added.** One sentence on revision `1` turning into `3` after the undo. It's what learners see on screen.
- **Elapsed time not scripted.** The narration says "compare the elapsed time with the 6-minute budget", so you read the real time off the overlay.
- **`vim ... #confirm`.** The edit is live. Fallback: `cp ~/solutions/webapp.yaml webapp.yaml`.
- **`rollout status` lines carry `#wait 12`.** They block until the rollout finishes. Without the wait, type.py starts typing the next command into the running output.
- **`webapp` is removed by `stage m2-demo5`**, so Scenario 4's bare `k get pods` only shows the broken Pod.
