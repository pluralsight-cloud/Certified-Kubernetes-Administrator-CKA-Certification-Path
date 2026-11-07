# Demo: A crashing sidecar

Clip: 5

Lets start with the symptom, because the task card doesn't give us much. It only says that the Pods of Deployment `web` are not ready, and that we should find the cause and fix it.

`k get pods`

The Pod shows `1/2` ready, the status flips between `Error` and `CrashLoopBackOff`, and the restart count keeps going up. The `1/2` already tells us a lot, because it means one container is fine and the other one isn't, and `describe` tells us which one. I select the Pod by its label, so I don't have to copy the generated name.

`k describe pod -l app=web`

Under Containers, `nginx` is running fine. The `log-shipper` container is the problem, its state is Terminated with exit code `127`, and in Linux `127` means command not found.

I always look at the exit code first. `137` for example would mean the container was killed, often because it ran out of memory, and `1` is a general application error.

For the details we need the logs, and `-c` picks the container. The crashed attempt is still the latest one, so the plain logs show exactly why it died. `--previous` is the flag for the other case — when the container has already restarted and is running again, and you want the attempt before.

`k logs deploy/web -c log-shipper`

It says `sh: line 0: tial: not found`. Someone miss-typed the command `tail`.

Before I fix it, I want to show you a second way to get the same answer. Lets assume the API server is down and kubectl doesn't work, its likely that at least on task in the exam throws this at you.

The container runtime on the node still knows all its containers, and `crictl` talks to it directly. For that we need to know the node first.

`k get pod -l app=web -o wide`

The Pod runs on `worker1`, so I go there and check the prompt.

`ssh worker1`

`sudo crictl ps -a --name log-shipper`

The `-a` is important here — without it, crictl only lists running containers, and we would not see our crashed sidecar at all.

With `-a` we see the exited `log-shipper` container. The kubelet only keeps the most recent dead one, and the `ATTEMPT` column counts the restarts. I take its ID and read the log.

`sudo crictl logs`

It shows the same `tial: not found` line as kubectl. Now I `exit` and check that the prompt says `control1` again before I change anything.

The fix belongs on the Deployment — not on the Pod. If I fixed the Pod, the ReplicaSet would replace it with a new copy of the old, broken template, so I edit the Deployment instead.

`k edit deployment web`

I change `tial` to `tail` in the `log-shipper` command and save, which starts a new rollout.

`k rollout status deployment/web`

`k get pods`

The new Pod shows `2/2` Running with 0 restarts, and the old one is gone. 

I hope this scenario showed you how kubectl and crictl give you the same information from 2 different levels. Start with describe and the logs, and go to the node with crictl when kubectl can't help you.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo5-crashing-sidecar/reset_commands.txt for you. By hand:
cd m02-timed-scenarios/demo5-crashing-sidecar   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m2-demo5 && vagrant ssh control1

# stage m2-demo5 asserts: Deployment web on worker1 with log-shipper crash-looping (CrashLoopBackOff or Error, >= 2 restarts), earlier scenarios' Deployments removed
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: The symptom ───────────────────────────────────────────
k get pods #allow-error
k describe pod -l app=web #confirm #allow-error

# ── Phase 2: Read the last crash ───────────────────────────────────
k logs deploy/web -c log-shipper

# ── Phase 3: Same answer from the node with crictl ─────────────────
k get pod -l app=web -o wide
ssh worker1
sudo crictl ps -a --name log-shipper #wait 6
sudo crictl logs $(sudo crictl ps -a --name log-shipper --latest -q) #wait 6
exit
hostname

# ── Phase 4: Fix the Deployment and confirm ────────────────────────
k edit deployment web #keys edits/web-fix.keys
k rollout status deployment/web #wait 12
k get pods #wait 6
```

## Deviations & Questions

- **Pod pinned to `worker1`.** A `nodeSelector` keeps "the Pod runs on `worker1`" true. Learners see it during `k edit`. `stage m2-demo5` asserts the node.
- **`--previous` dropped (found in the live test).** On this v1.35 lab the crashed container stays `Terminated` for most of the backoff, and in that window `k logs --previous` fails with `unable to retrieve container logs`. The kubelet only keeps one dead container, and the earlier attempt is already gone. It only worked in the few seconds the state showed `Waiting/CrashLoopBackOff`. Plain `k logs -c log-shipper` returned the crash line in every sample. Sampled every 8s for two minutes.
- **No generated names on screen.** `k describe pod -l app=web`, `k logs deploy/web` and `k get pod -l app=web -o wide` replace the `$POD` variable. These are exam-transferable and match the narration. On the node, `crictl logs $(crictl ps -a --name log-shipper --latest -q)` picks the newest container.
- **`k edit deployment web #confirm`.** type.py only auto-confirms `oc edit`, not `kubectl`/`k`. Without the tag it would type the next command into vim.
- **CrashLoopBackOff lines tagged `#allow-error`**, so the run summary stays clean.
- **Native-sidecar key point cut**, and the module-final close added (2 sentences).
