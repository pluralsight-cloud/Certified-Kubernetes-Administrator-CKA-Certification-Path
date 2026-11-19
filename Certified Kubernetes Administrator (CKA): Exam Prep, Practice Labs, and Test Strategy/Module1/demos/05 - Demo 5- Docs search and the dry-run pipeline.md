# Demo: Docs search and the dry-run pipeline

Clip: 5

Lets start with the docs, since you will use them in almost every task. I open the search box on kubernetes.io and search for the object, `NetworkPolicy`, not for the problem I want to solve.

The result I want is the Network Policies concept page. I skip the API reference here, because it lists every field but has no example I could copy.

On the page, I press Ctrl+F and type `podSelector`, and Firefox jumps straight to the `test-network-policy` example. The copy button is right there on the code block.

I don't need the example right now, I just want to show you how quickly you get to it when you know what to search for.

But some things you dont need to get from the docs, there is a faster way directly in the terminal. So next lets build a Pod with resource requests and a ConfigMap mount. That's quite a few fields, and I don't want to type all of them from memory, so I let kubectl generate the skeleton.

`k run demo-pod --image=nginx --dry-run=client -o yaml > demo-pod.yaml`

`--dry-run=client` doesn't create anything on the cluster. It only renders the YAML, and the redirect writes it into a file. If we look at the file, there is `resources: {}` under the container. kubectl leaves this empty, so filling it is our job.

Before I edit anything, I look up the two fields in the docs. I search for `configmap` and open Configure a Pod to Use a ConfigMap. Ctrl+F on `volumeMounts` takes me to the example that mounts a ConfigMap as a volume.

Then I search for resource requests and open Resource Management for Pods and Containers, where Ctrl+F on `requests:` shows me the format for `cpu` and `memory`.

Now I can edit the file with the docs open right next to it. In the exam environment you should use the VSCode IDE because it will help you fix intendeds etc easier. Of course if you are a pro in vim or nano, go ahead and use those. It comes down to personal preference.

`vim demo-pod.yaml`

I replace the empty resources with requests of `100m` CPU and `128Mi` memory. Under the container I add `volumeMounts` with a volume called `config` at `/etc/config`. And under the Pod spec I add `volumes`, which points at our `demo-config` ConfigMap.

Be careful with the indentation here — `volumeMounts` belongs to the container, but `volumes` belongs to the Pod spec. If you mix them up, the apply fails with an unknown field error, and you lose time hunting for it.

Let me apply it.

`k apply -f demo-pod.yaml`

`k get pod demo-pod` shows it Running. But the task asked for a mount and for requests, so those are the things I check.

`k exec demo-pod -- cat /etc/config/mode`

It returns `exam` — the value from our ConfigMap — so the mount works. A quick jsonpath query on the container resources shows `100m` and `128Mi`, which is exactly what we asked for.
If you do not want to type a jsonpath, you can also just use the describe command. It is faster to type but takes a bit longer to identify the correct section.

These checks only take a few seconds, and I do them on every task, because a Pod can be Running and still miss a field the task asked for.

Finally I clean up with `k delete pod demo-pod --now` and `k delete configmap demo-config`, so the cluster is back where we started.

I hope this demo gave you an idea how fast the docs can be when you search for the object and let kubectl write the skeleton. Practice this a few times before your exam, until the searches feel natural.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo5-docs-and-dry-run/reset_commands.txt for you. By hand:
cd m01-exam-strategy/demo5-docs-and-dry-run   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m1-demo5 && vagrant ssh control1

# stage m1-demo5 asserts: ConfigMap demo-config (mode=exam), no demo-pod, clean ~ on control1, reference in ~/solutions/
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Generate the skeleton ─────────────────────────────────
# Before you start typing: Firefox -> search "NetworkPolicy" -> "Network Policies" -> Ctrl+F "podSelector"
k run demo-pod --image=nginx --dry-run=client -o yaml > demo-pod.yaml
cat demo-pod.yaml #confirm

# ── Phase 2: Look up the fields, edit and apply ────────────────────
# During the confirm above: Firefox -> "configmap" -> Ctrl+F "volumeMounts", then "resource requests" -> Ctrl+F "requests:"
vim demo-pod.yaml #keys edits/demo-pod.keys
cat demo-pod.yaml #wait 10
k apply -f demo-pod.yaml

# ── Phase 3: Verify the fields the task asked for ──────────────────
k get pod demo-pod
k exec demo-pod -- cat /etc/config/mode
k get pod demo-pod -o jsonpath='{.spec.containers[0].resources}{"\n"}'

# ── Phase 4: Clean up ──────────────────────────────────────────────
k delete pod demo-pod --now
k delete configmap demo-config #wait 4
```

## Deviations & Questions

- **Word count ~525.** The module plan has this demo at ~4:00 including the objective slide, so expect ~4:30 real. The jsonpath check is the easiest cut.
- **Browser parts happen inside type.py pauses.** The NetworkPolicy search happens before you press Enter to start typing. Both field lookups happen during `cat demo-pod.yaml #confirm`, which replaces the usual `#wait 10` for that reason. The `# Firefox:` lines are notes in the plan only.
- **`vim ... #confirm`.** The edit is live on purpose. Fallback for a bad take: `cp ~/solutions/demo-pod.yaml demo-pod.yaml`.
- **Paste method decided:** no pasting here. The `cat > file.yaml` + Ctrl+D trick appears in Module 2, Scenario 2.
- **[VERIFY: Pod Running at Phase 3]** — `k get pod demo-pod` runs ~14s after the apply. With `nginx` pre-pulled by `./lab.sh images` that should be enough, but a slow first start would show `ContainerCreating` while the narration says Running.
