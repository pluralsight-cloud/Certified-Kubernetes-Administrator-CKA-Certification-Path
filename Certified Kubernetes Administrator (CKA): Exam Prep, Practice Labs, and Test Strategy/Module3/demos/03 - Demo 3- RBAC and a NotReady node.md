# Demo: RBAC and a NotReady node

Clip: 3

Lets start with the RBAC drill and be quick, lets plan 2 minutes for it. The task says the ServiceAccount `my-sa` in `default` needs permission to list and get Pods. So we need an account, a role and a binding.

All 3 have imperative commands, so I don't need any YAML.

`k create serviceaccount my-sa`

`k create role pod-reader --verb=list,get --resource=pods`

`k create rolebinding my-sa-binding --role=pod-reader --serviceaccount=default:my-sa`

In the last command, `--serviceaccount` takes the namespace and the name, separated by a colon. kubectl rejects the flag if the namespace is missing.

Also check the scope of the task, because a Role and a RoleBinding only work inside one namespace. If a task says "in all namespaces", you need a ClusterRole and a ClusterRoleBinding instead. The commands are the same, just with `cluster` in front.

Now lets verify it, and I test both directions. With `k auth can-i` I can ask the API server as if I were the ServiceAccount, but for that it needs the full user name, `system:serviceaccount:default:my-sa`.

`k auth can-i list pods --as=system:serviceaccount:default:my-sa`

It returns `yes`, which is what we granted. But a binding that grants way too much would also return yes here, so I also ask for something we did not grant.

`k auth can-i delete pods --as=system:serviceaccount:default:my-sa`

That returns `no`. With the yes and the no, we know the permission is exactly as wide as the task asked for, and we finished our first task.

The second drill says node `worker1` is NotReady, and we should fix it.

`k get nodes`

kubectl shows `worker1` as NotReady — but it can't tell us why. For that we have to go to the node, and I check the prompt when I get there.

`ssh worker1`

When a node is NotReady, the kubelet is usually the problem, so I start with its service.

`sudo systemctl status kubelet --no-pager`

It is `inactive (dead)` and also `disabled`, so it wouldn't even come back after a reboot. The journal shows how it got there.

`sudo journalctl -u kubelet -n 20 --no-pager`

The interesting part is at the very end. The last lines show a clean stop and no crash — somebody simply stopped the service. In harder tasks, this is where you find a wrong flag or a broken `/var/lib/kubelet/config.yaml`.

If the journal points at a flag, `systemctl cat kubelet` shows you where it comes from. On a kubeadm node that's the drop-in file `10-kubeadm.conf`, which pulls in the kubeconfig, the config file and any extra arguments.

The fix should cover the current state and the boot state at the same time.

`sudo systemctl enable --now kubelet`

`enable --now` enables the service and starts it with one command. Now I `exit`, check that the prompt says `control1` again, and watch the node. Here I type the full `kubectl`, because `watch` runs the command in its own shell and doesn't know the `k` alias.

`watch kubectl get nodes`

After a few seconds `worker1` turns Ready again, and we finished the second task. It’s good to practice these easy tasks too because loosing time here would be a pity.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo3-rbac-notready-node/reset_commands.txt for you. By hand:
cd m03-weak-area-drills/demo3-rbac-notready-node   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m3-demo3 && vagrant ssh control1

# stage m3-demo3 asserts: no my-sa/pod-reader/my-sa-binding, worker1 NotReady with the kubelet stopped AND disabled
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Drill A: Account, role, binding ────────────────────────────────
k create serviceaccount my-sa
k create role pod-reader --verb=list,get --resource=pods
k create rolebinding my-sa-binding --role=pod-reader --serviceaccount=default:my-sa

# ── Drill A: Verify both directions ────────────────────────────────
k auth can-i list pods --as=system:serviceaccount:default:my-sa
k auth can-i delete pods --as=system:serviceaccount:default:my-sa #allow-error

# ── Drill B: The symptom ───────────────────────────────────────────
k get nodes

# ── Drill B: Read the service on the node ──────────────────────────
ssh worker1
sudo systemctl status kubelet --no-pager #wait 6
sudo journalctl -u kubelet -n 20 --no-pager #confirm

# ── Drill B: Fix and come back ─────────────────────────────────────
sudo systemctl enable --now kubelet
exit
hostname
watch kubectl get nodes #confirm
```

## Deviations & Questions

- **Two teaching asides added to fill the 5-minute slot:** Role vs ClusterRole scope, and `systemctl cat kubelet` → `10-kubeadm.conf`. `systemctl cat` is narration only.
- **`watch kubectl get nodes` instead of `k get nodes -w`.** `watch` doesn't expand aliases, so it is the one place the demos type the full `kubectl`. The narration says so, which is a useful exam detail in its own right. `./lab.sh alias` sets up `k` as an alias (like the exam), not as a symlink, on purpose.
- **`journalctl -n 20 #confirm`.** Cut from 50 lines in the live test: on the lab the earlier lines are full of unrelated kubelet noise (stale sandboxes, a crash-looping Pod from another demo), which buries the stop at the end. `stage m3-demo3` now also deletes the other demos' Deployments first.
- **The fault is staged and asserted by `stage m3-demo3`:** kubelet stopped AND disabled, and the stage waits until the node actually reports NotReady (up to 180s). Every other `stage` re-enables the kubelet first, so a half-finished take can't leak into another demo.
