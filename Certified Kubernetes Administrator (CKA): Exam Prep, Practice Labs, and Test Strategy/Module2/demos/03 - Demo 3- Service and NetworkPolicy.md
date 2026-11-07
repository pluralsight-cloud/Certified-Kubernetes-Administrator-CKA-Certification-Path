# Demo: Service and NetworkPolicy

Clip: 3

This task wants a `backend` Deployment exposed with a Service, and only the `frontend` namespace should be able to reach it. Lets start with the imperative part, which is just 2 commands.

`k create deployment backend --image=nginx`

`k expose deployment backend --port=80 --target-port=80`

Before I move on, I check that the Service found its Pods. `k get endpointslices -l kubernetes.io/service-name=backend` shows 1 EndpointSlice with the Pod IP on port `80`, so the selector works.

Next is the NetworkPolicy, and since there is no `k create networkpolicy` command, so I take it from the docs. I search for `NetworkPolicy`, open the Network Policies page and copy the `test-network-policy` example.

In the terminal I type `cat > allow-frontend.yaml`, paste the example and press Ctrl+D to close the file. This trick saved me quite some time on my own exam. If you work in VSCode for editing instead of vim, its faster than vim for pasting, and vim's auto-indent can't mess up the YAML.

The example does a lot more than we need, so I trim it in vim.

`vim allow-frontend.yaml`

I rename it to `allow-frontend` in the `default` namespace, set the `podSelector` to `app: backend`, and keep only Ingress. I remove the egress rule, the `ipBlock` and the `podSelector` under `from`.

What's left is the `namespaceSelector`, where I change the label value to `frontend`, and port `80`.

Let me apply it and see how Kubernetes reads it.

`k apply -f allow-frontend.yaml`

`k describe networkpolicy allow-frontend`

The describe output is quite readable, it says the policy allows ingress traffic to port `80` from namespaces that match our selector. That looks right — but I only trust a policy once I have tested it with real traffic.

So I start a throwaway busybox Pod in `frontend` and call the backend by its Service DNS name.

`k run t1 -n frontend --rm -it --restart=Never --image=busybox -- wget -qO- -T2 backend.default`

And it times out — from the namespace that should be allowed. Hmm thats not good.

About half of the time budget is gone by now, and I don't see the cause right away. On the exam, this is the moment where I click Flag and move on to the next task. Leaving doesn't cost anything, because the task stays one click away.

But lets assume the other tasks are done and we come back to this one. A `namespaceSelector` matches labels, so the first question is which labels the namespace actually has.

`k get namespace frontend --show-labels`

That explains it. The namespace only has the label `kubernetes.io/metadata.name=frontend`, but I kept the key `project` from the docs example and only changed the value.

Kubernetes sets `kubernetes.io/metadata.name` on every namespace automatically, so its the reliable way to select a namespace by its name. I fix the key in vim and apply the file again.

Now I test both sides, because the task asks for both. From `frontend`, the same `wget` now returns the nginx welcome page. Then I run it from the `default` namespace, where plain `backend` is enough as the name.

`k run t2 --rm -it --restart=Never --image=busybox -- wget -qO- -T2 backend`

This one times out, and that's what we want, because I always test the blocked side as well. A policy that blocks everything would pass that test too, so you need both results to know the policy is right.

I stop the timer here and we are still well within our time budget, including the detour. Remember you dont need to be perfect, good is enough is the key to passing the exam. 

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo3-service-networkpolicy/reset_commands.txt for you. By hand:
cd m02-timed-scenarios/demo3-service-networkpolicy   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m2-demo3 && vagrant ssh control1

# stage m2-demo3 asserts: namespace frontend with ONLY kubernetes.io/metadata.name, no backend/allow-frontend, Calico present, fallbacks in ~/solutions/
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Workload and Service ──────────────────────────────────
k create deployment backend --image=nginx
k expose deployment backend --port=80 --target-port=80
k get endpointslices -l kubernetes.io/service-name=backend

# ── Phase 2: NetworkPolicy from the docs ───────────────────────────
# Firefox -> search "NetworkPolicy" -> "Network Policies" -> copy the test-network-policy example
cat > allow-frontend.yaml #paste solutions/allow-frontend-docs.yaml
vim allow-frontend.yaml #keys edits/allow-frontend-trim.keys
cat allow-frontend.yaml #wait 10
k apply -f allow-frontend.yaml

# ── Phase 3: Read the policy back ──────────────────────────────────
k describe networkpolicy allow-frontend #confirm

# ── Phase 4: Test the allowed side ─────────────────────────────────
k run t1 -n frontend --rm -it --restart=Never --image=busybox -- wget -qO- -T2 backend.default #wait 8 #allow-error

# ── Phase 5: Flag it, come back, find the cause ────────────────────
# Flag the task on the exam-style task card (overlay). Cut in the edit; the timer keeps running.
k get namespace frontend --show-labels #wait 6
vim allow-frontend.yaml #keys edits/allow-frontend-fix.keys
cat allow-frontend.yaml #wait 10
k apply -f allow-frontend.yaml

# ── Phase 6: Test both sides ───────────────────────────────────────
k run t1 -n frontend --rm -it --restart=Never --image=busybox -- wget -qO- -T2 backend.default #wait 8
k run t2 --rm -it --restart=Never --image=busybox -- wget -qO- -T2 backend #wait 8 #allow-error
```

## Deviations & Questions

- **Question: personal line.** "This trick saved me quite some time on my own exam" assumes the `cat > file` hint was one of the habits that saved you time (your hints slide says so). Cut it if that's not true for this trick.
- **Paste with `cat > file` + Ctrl+D.** In type.py, `cat > allow-frontend.yaml #confirm` waits for your keypress: paste, press Ctrl+D, then continue. Fallback: `cp ~/solutions/allow-frontend-docs.yaml allow-frontend.yaml`.
- **`describe` moved to its own section.** After a `cat` + `apply`, the next line must be a heading, or the output lands below the fold.
- **Second `t1` run summarized in prose.** It's still in the Commands block.
- **Both expected timeouts are tagged `#allow-error`.**
- **`stage m2-demo3` protects the failure:** it strips every label on `frontend` except `kubernetes.io/metadata.name`. A leftover `project=frontend` would make the broken policy work.
- **DNS on the Mac lab:** without `./cka-lab.sh dns`, VMware's `localdomain` search entry can make `backend.default` take ~5s to resolve, and the 2s `wget` timeout would fail on the side that should work. `stage` warns if the fix is missing.
