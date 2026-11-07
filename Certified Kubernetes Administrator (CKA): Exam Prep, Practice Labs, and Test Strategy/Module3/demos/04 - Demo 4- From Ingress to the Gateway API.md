# Demo: From Ingress to the Gateway API

Clip: 4

Lets start with the task. It says to replace the Ingress `web` with an HTTPRoute called `web`, attached to the Gateway `web-gateway`, and the route should handle the same traffic.

Before I change anything, I want to see that the Ingress works, because that's the behavior we have to rebuild.

`curl -s -H "Host: web.example.com" http://192.168.50.11:30080/ | grep title`

The title of the nginx welcome page comes back through Traefik, which serves both the Ingress and the Gateway on this cluster. Now lets look at what the Ingress actually does.

`k get ingress web -o yaml`

We need 5 things from it: the host `web.example.com`, the path `/`, the path type `Prefix`, the backend Service `web` and port `80`. I also check for a `tls` section, but there is none, so we stay on plain HTTP.

The route has to attach to a Gateway, so next I check which one exists.

`k get gatewayclass,gateway -A`

There is the `traefik` GatewayClass and our `web-gateway` in `default`. `PROGRAMMED` is True, so the Gateway is ready for routes.

The Gateway API docs are allowed on the CKA, so I open gateway-api.sigs.k8s.io and go to the HTTP routing guide. I copy the simple HTTPRoute example, paste it with `cat > web-route.yaml`, and then I fill in the Ingress values in vim. Again the in the exam I suggest you use VSCode to edit and then paste via cat but the choice is yours.

`vim web-route.yaml`

The name becomes `web`, and `parentRefs` points at `web-gateway`. `hostnames` gets `web.example.com`. In the rule I set a path match of type `PathPrefix` with the value `/`. And `backendRefs` points at Service `web` on port `80`.

The only mapping that isn't obvious is the path type. `Prefix` in the Ingress becomes `PathPrefix` in the route, and `Exact` stays `Exact`. Everything else is the same information — it just sits in different fields.

Let me apply it and check what the Gateway thinks of it.

`k apply -f web-route.yaml`

`k describe httproute web`

Under the parent status I look for 2 conditions. `Accepted` is True, so the Gateway took the route, and `ResolvedRefs` is True, so the backend Service exists. If one of them is False, the reason field tells you why, which is much faster than curling blindly.

The task says replace, not create, so the Ingress has to go. If it only said "create a route", I would leave the Ingress alone, and that's why I always read the task to the end.

`k delete ingress web`

The Ingress is gone now, so if the next request works, it has to come through the route.

`curl -s -H "Host: web.example.com" http://192.168.50.11:30080/ | grep title`

The nginx welcome page is back — this time through the HTTPRoute. `k get ingress,httproute` confirms that only the route is left.

There is one variant we didn't need today. If the Ingress has a `tls` section, the Gateway needs an HTTPS listener with `certificateRefs` that point at the same Secret. The HTTPRoute itself stays the same.

I hope this drill showed you how an Ingress maps onto the Gateway API. Once you know where each field goes, the conversion only takes a few minutes, even under exam pressure.

## Prerequisites

```bash
# ----- Once per lab build (workstation, in the course folder) -----
cd ~/PycharmProjects/ps-cka/exercise-files/course-11-exam-prep
./lab.sh                      # alias, keys, images, storage, gateway, etcdtools, then verify

# ----- Before every take -----
# type.py runs demo4-ingress-to-gateway/reset_commands.txt for you. By hand:
cd m03-weak-area-drills/demo4-ingress-to-gateway   # every demo runs from its own folder
export VAGRANT_CWD="$(cd ../../../../src/cka-lab && pwd)"   # lets vagrant find the lab from here
../../lab.sh stage m3-demo4 && vagrant ssh control1

# stage m3-demo4 asserts: GatewayClass traefik Accepted, Gateway web-gateway Programmed, fresh web Deployment/Service/Ingress answering 200, no HTTPRoute
# After a take: `exit` back to the workstation (you land in the demo folder again) before the next run.
```

## Commands

```bash
# ── Phase 1: Baseline through the Ingress ──────────────────────────
curl -s -H "Host: web.example.com" http://192.168.50.11:30080/ | grep title

# ── Phase 2: Read the Ingress ──────────────────────────────────────
k get ingress web -o yaml #confirm

# ── Phase 3: Find the Gateway ──────────────────────────────────────
k get gatewayclass,gateway -A

# ── Phase 4: Build the route from the docs ─────────────────────────
# Firefox -> gateway-api.sigs.k8s.io -> Guides -> HTTP routing -> copy an HTTPRoute example
cat > web-route.yaml #paste solutions/web-route-docs.yaml
vim web-route.yaml #keys edits/web-route.keys
cat web-route.yaml #wait 10
k apply -f web-route.yaml

# ── Phase 5: Check the route status ────────────────────────────────
k describe httproute web #confirm

# ── Phase 6: Replace the Ingress ───────────────────────────────────
k delete ingress web

# ── Phase 7: Test through the route ────────────────────────────────
curl -s -H "Host: web.example.com" http://192.168.50.11:30080/ | grep title
k get ingress,httproute #wait 6
```

## Deviations & Questions

- **Baseline curl added, and the Ingress is deleted before the final curl.** Traefik serves both for the same host, so a curl with both in place proves nothing. The delete and the final curl sit in different sections, so the 10s section pause gives Traefik time to drop the Ingress router before the request.
- **`curl ... | grep title`** prints one line (`<title>Welcome to nginx!</title>`) instead of the 25-line page.
- **Gateway comes from `./lab.sh gateway`, not the chart's default Gateway.** Course 7's Traefik install stays as it is: the CRDs and Traefik come from Course 7's `lab.sh` (Gateway API v1.6.1, chart 41.4.0). The listener port is read from Traefik's web entryPoint, because Traefik matches listeners to entryPoints by port and Course 7 has used both 80 and 8000. The port isn't narrated.
- **Node IP `192.168.50.11`**, the same address Course 7 gives Traefik as the Gateway status address, so the `ADDRESS` column and the curl match.
- **`ingress2gateway` cut.**
- **`k get gatewayclass,gateway -A` also lists Course 7's `globo-gateway`** if its Module 3 objects are still on the cluster. The narration only names ours, so clear them or accept the extra line.
