# Demo: The designated-host workflow

Clip: 3

Lets start on the task host. On the exam, every task gives you the ssh command in its info box. Here in the Vagrant lab, `control1` plays that host, so I connect to it.

`vagrant ssh control1`

Before I type anything else, I look at the prompt. It says `vagrant@control1`, so I know exactly where my next command runs, and `hostname` confirms it.

`k get nodes`

We see 3 nodes, all Ready on `v1.35.0`. The `k` alias and the Bash completion are already set up, just like on the exam hosts.

Some tasks are about a node itself — for example the kubelet. For those you have to go to the machine where the kubelet runs, so I hop over to the first worker.

`ssh worker1`

The prompt changed to `vagrant@worker1`, and since the kubelet is a systemd service, I need root to look at it, which is what `sudo` is for.

`sudo systemctl status kubelet --no-pager`

It is `active (running)`, so this node is healthy. On the exam, this is where you would fix something and then verify it on the same host.

Now lets assume this task is done and the next one starts. I forget to `exit`, and since the next task is a cluster task, I go straight to kubectl.

`k get nodes`

And it fails, the last line says the connection to the server `localhost:8080` was refused. That means there is no kubeconfig on this machine for this user, so I am on the wrong host.

This error is actually the lucky case, because you notice it right away.

It gets worse when the command works but runs against a different cluster. Then your solution is correct, but it sits on a host the grader never checks, and you get 0 points for it.

The fix is a single `exit`, and then I read the prompt again before I type anything.

`exit`

We are back on `vagrant@control1`, and `hostname` agrees. There is one difference to the real exam though — I only hop from `control1` to `worker1` because our lab has no base machine.

On the exam, nested ssh is not supported, so you always `exit` back to base before you start the next task.

`k get nodes`

kubectl works again, all 3 nodes are Ready, and we are on the right host for whatever comes next.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo3-designated-host/reset_commands.txt for you. By hand:
cd m01-exam-strategy/demo3-designated-host   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m1-demo3

# stage m1-demo3 asserts: worker1 reachable from control1 without a password, no ~/.kube/config on worker1, k alias on every node
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Log into the task host ────────────────────────────────
vagrant ssh control1 #wait 8
hostname
k get nodes

# ── Phase 2: Hop to a worker and check the kubelet ─────────────────
ssh worker1
sudo systemctl status kubelet --no-pager

# ── Phase 3: The wrong-host trap ───────────────────────────────────
k get nodes #allow-error

# ── Phase 4: Exit and confirm where you are ────────────────────────
exit
hostname
k get nodes #wait 6
```

## Deviations & Questions

- **Word count ~390, below the 550–650 CLI target.** Deliberate: the module plan gives this demo ~2:30 including the objective slide.
- **`vagrant ssh control1` sits in the Commands block.** It is the thing being taught. The recording window stays in this demo's folder; `reset_commands.txt` exports `VAGRANT_CWD` pointing at `src/cka-lab/`, so the first beat works as typed from here.
- **Guest-to-guest ssh is solved by `./lab.sh keys`**, and `stage m1-demo3` asserts it. `/etc/hosts` on every node already maps `worker1` (Vagrantfile provisioner).
- **`k` alias on every node:** `./lab.sh alias` (part of prep, and re-checked by every `stage`) writes `alias k=kubectl` plus bash completion into each node's `.bashrc` and proves it with `bash -ic 'type k'`. So the wrong-host trap on `worker1` fails with `localhost:8080`, not with `k: command not found`.
- **[VERIFY: wrong-host error text]** — recent kubectl prints a few `memcache.go` lines first, then `The connection to the server localhost:8080 was refused - did you specify the right host or port?`. The narration only quotes the last line. Tagged `#allow-error` so type.py doesn't count it as a failure.
