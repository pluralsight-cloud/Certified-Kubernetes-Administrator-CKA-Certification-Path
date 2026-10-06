# Course 7, M02 -- Ingress

[Course 7 overview](../README.md)  |  [Skill path home](../../../README.md)

**CKA domain:** Services & Networking (20%)  

**Exam objectives:** Ingress resources, ingress controllers, and host/path routing rules.

---

## What's in this folder

Three demo folders, one per demo in the module. Each is self-contained: apply its `setup/` (where present), run `demo_commands.txt` top to bottom, then `reset_commands.txt` to get back to the top for another take.

| Folder | Demo | What it shows |
| --- | --- | --- |
| [`demo2-traefik-helm/`](demo2-traefik-helm/) | Demo 2 | Install Traefik with Helm pinned to chart 41.4.0, exposed as a NodePort because the lab has no cloud provider. Read the CHART / APP version columns, confirm the `traefik` IngressClass, stand up the three Globomantics backends, and knock on the front door for a controller-issued 404. |
| [`demo4-host-and-path-routing/`](demo4-host-and-path-routing/) | Demo 4 | Host routing across `catalog` / `portal` / `api` on one address, the same request through real DNS, then path routing under one host -- including the 404 that comes from the **backend** rather than the controller, and the vendor-specific Traefik `Middleware` that strips the prefix. |
| [`demo6-tls-and-broken-backend/`](demo6-tls-and-broken-backend/) | Demo 6 | A self-signed cert with a SAN, a `kubernetes.io/tls` Secret, TLS termination proved with `curl --resolve`, then a deliberate 503: walk Ingress to Service to EndpointSlice until the cause names itself. Closes with `spec.defaultBackend`. |

Each folder holds:

| File | What it is |
| --- | --- |
| `demo_commands.txt` | The demo path in beat order, with `#wait` / `#confirm` automation hints. Byte-identical to the `## Commands` block of the matching teleprompter script. |
| `reset_commands.txt` | Between-takes cleanup. Idempotent. |
| `setup/` | The prerequisite state, for shooting that demo standalone. Only Demo 6 ships one -- `setup/globo-hosts.yaml` is the plain-HTTP Ingress the demo starts from, so the TLS apply on camera is a real change. |
| `*.yaml` in the demo root | The manifests applied live on camera: Demo 2's `globo-apps.yaml`, Demo 4's `globo-hosts.yaml` / `globo-paths.yaml` / `strip-prefix.yaml`, Demo 6's `globo-hosts-tls.yaml` / `catch-all.yaml`. |

Demo 6 also writes `tls.crt` and `tls.key` into its folder when you run it. Both are gitignored -- they are regenerated on every take, and a private key does not belong in a public repo.

Everything here is built for a standard cluster (1 control-plane + 2 workers) at Kubernetes **v1.35**, the exam topology. All three demos have been **run end to end on the lab cluster**; what that found and fixed is in [`_test_run_report.md`](_test_run_report.md).

---

## The demos build on each other

Demo 2 installs the controller and the backends. Demo 4 routes to them. Demo 6 puts TLS in front of them and then breaks one. Run in order and nothing extra is needed.

To shoot **Demo 4 or Demo 6 standalone**, build the starting state by running Phases 3-5 of [`demo2-traefik-helm/demo_commands.txt`](demo2-traefik-helm/demo_commands.txt) -- the Helm install and the three backends -- then that demo's `reset_commands.txt` once.

Use Demo 2's own commands, **not** the course-level [`lab.sh`](../lab.sh). `lab.sh` builds the stack Module 3 needs and it differs from this module in three ways that break these demos: it deploys `nginx:1.27-alpine` with a static page into the `default` namespace (so every `grep 'f-pod'` here comes back empty), and its Helm install sets `ports.web.port=80` for Gateway API listener matching while omitting `providers.kubernetesIngress.ingressEndpoint.ip` (so the ADDRESS column stays blank and Demo 4's "the controller claimed it" beat has nothing to point at).

---

## Two prerequisites that are not in the cluster

**The image on the nodes.** Same as Module 1 -- every backend here runs `ghcr.io/timothywarner-org/globo-shop:v1`, and the page it serves names the Pod that answered, which is what makes routing visible rather than asserted. That self-identification comes from four Downward API `fieldRef` env vars, which is why `globo-apps.yaml` is a manifest and not `kubectl create deployment` -- there is no imperative flag that sets a `fieldRef`, and without them every `grep 'f-pod'` beat in Demos 4 and 6 prints `not-in-kubernetes`:

```bash
exercise-files/shared/apps/globo-shop/load-image.sh
```

On an Apple Silicon Mac you need that script's build path: the published package is amd64-only and arm64 nodes pull it happily and then CrashLoopBackOff with `exec format error`.

**DNS records, for one beat in Demo 4.** Phase 3b runs `dig +short catalog.globo.com` and then curls without a `Host:` header, so the record has to live on the recording network's **resolver** -- Pi-hole, UniFi, pfSense, dnsmasq, whatever answers for the recording host. An `/etc/hosts` entry will not do: `dig` bypasses it and the beat proves nothing.

```text
catalog.globo.com.   A   192.168.50.11
portal.globo.com.    A   192.168.50.11
api.globo.com.       A   192.168.50.11
shop.globo.com.      A   192.168.50.11
```

A wildcard `*.globo.com A 192.168.50.11` works too. Only `catalog.globo.com` is used on camera; the rest are there so re-ordering beats does not break anything. Every other beat in the module uses `-H "Host:"` or `curl --resolve`, so the demos survive a resolver that is not yours.

---

## Spin up a lab

Practice every demo on your own cluster. The lab environment lives in [`src/cka-lab/`](../../../src/cka-lab/) with the exam-shaped lab:

- **Windows -- Hyper-V + Vagrant:** three real Ubuntu VMs (`control1`, `worker1`, `worker2`) running kubeadm-built Kubernetes v1.35 with Calico, for node-level break/fix drills. Bring it up with `Start-CkaLab.ps1`, check it with `Get-CkaLabStatus.ps1`, and snapshot before risky steps with `Save-CkaSnapshot.ps1`. Walkthrough: [`TUTORIAL-HYPERV.md`](../../../src/cka-lab/TUTORIAL-HYPERV.md).
- **macOS -- VMware Fusion + Vagrant:** the same three VMs, same IPs, same cluster. Bring it up with `./cka-lab.sh`, snapshot with `./cka-lab.sh snap <name>`. Walkthrough: [`TUTORIAL-MACOS.md`](../../../src/cka-lab/TUTORIAL-MACOS.md).

Real VMs matter here: every curl in this module goes to `192.168.50.11:30080` **from your workstation**, outside the cluster, which is exactly how an ingress controller is meant to be tested.
