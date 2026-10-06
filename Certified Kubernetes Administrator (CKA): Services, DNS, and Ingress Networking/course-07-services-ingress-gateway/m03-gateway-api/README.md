# Course 7, M03 -- Gateway API

[Course 7 overview](../README.md)  |  [Skill path home](../../../README.md)

**CKA domain:** Services & Networking (20%)  

**Exam objectives:** GatewayClass, Gateway, and HTTPRoute (new in Feb 2025; the successor to Ingress).

---

## What's in this folder

There are three demo folders, one per demo in the module. Run each folder's `demo_commands.txt` from top to bottom, then its `reset_commands.txt` to get back to the start for another take.

| Folder | Demo | What it shows |
| --- | --- | --- |
| [`demo3-crds-and-gateway/`](demo3-crds-and-gateway/) | Demo 3 | Starts on a cluster with no Gateway API. Installs the v1.6.1 standard-channel CRDs, turns on Traefik's Gateway provider with the chart's own GatewayClass and Gateway suppressed, and applies a `traefik` GatewayClass. Then a Gateway on port 80 that the controller refuses (`PortUnavailable`: Traefik matches listeners to its entry points, 8000/8443), and the corrected Gateway with an HTTPS listener that terminates `catalog-tls`. |
| [`demo4-first-httproute/`](demo4-first-httproute/) | Demo 4 | `catalog-route` pinned to the `web` listener with `sectionName`, and a `URLRewrite` filter where Module 2 needed a vendor Middleware. Shows the handshake from both sides (route conditions, then the listener's attached-route count), then breaks it on purpose: `NoMatchingListenerHostname`, a 404, and the restore. |
| [`demo5-header-and-weighted-split/`](demo5-header-and-weighted-split/) | Demo 5 | A `catalog-v2` backend, an `X-Version: v2` header match, a misspelled `weight` that the CRD schema rejects at apply time, and an 80/20 weighted split counted by Deployment over 20 requests. |

Each folder holds:

| File | What it is |
| --- | --- |
| `demo_commands.txt` | The demo path in beat order, with `#wait` / `#confirm` / `#allow-error` automation hints. Byte-identical to the `## Commands` block of the matching teleprompter script. |
| `reset_commands.txt` | Between-takes reset to the demo's starting state. Idempotent. |
| `setup/` | Only Demo 5 ships one. `setup/catalog-route.yaml` is Demo 4's single-rule route, which the reset puts back so the header apply on camera is a real change. |
| `*.yaml` in the demo root | The manifests applied live on camera. |

Everything here is built for a standard cluster (1 control-plane + 2 workers) at Kubernetes **v1.35**, the exam topology. All three demos have been **run end to end on the lab cluster** (Traefik chart 41.4.0 / v3.7.12), with each reset run twice to prove it is idempotent.

---

## The demos build on each other, and on Module 2

Module 3 starts from the state Module 2 leaves behind: Traefik in `traefik` on NodePort 30080/30443, the `catalog` / `portal` / `api` backends in `globomantics`, and the `catalog-tls` Secret from Module 2 Demo 6. Demo 3 installs the Gateway API and the Gateway, Demo 4 attaches a route to it, and Demo 5 reworks that route.

To shoot one demo standalone, run the earlier demos' `demo_commands.txt` in order first, then that demo's `reset_commands.txt` once. Demo 4's reset also deletes Module 2's `globo-paths` and `catch-all` Ingresses: they run on the same Traefik and would answer the Gateway curls themselves.

> **Build the Module 2 state from its demos, not from `../lab.sh`.** `lab.sh` moves Traefik's entry points to 80/443. That makes Demo 3's deliberate port-80 failure succeed and its "corrected" port-8000 Gateway fail. It also deploys the backends into `default` rather than `globomantics`.

---

## Spin up a lab

Practice every demo on your own cluster. The lab environment lives in [`src/cka-lab/`](../../../src/cka-lab/) with the exam-shaped lab:

- **Windows -- Hyper-V + Vagrant:** three real Ubuntu VMs (`control1`, `worker1`, `worker2`) running kubeadm-built Kubernetes v1.35 with Calico, for node-level break/fix drills. Bring it up with `Start-CkaLab.ps1`, check it with `Get-CkaLabStatus.ps1`, and snapshot before risky steps with `Save-CkaSnapshot.ps1`. Walkthrough: [`TUTORIAL-HYPERV.md`](../../../src/cka-lab/TUTORIAL-HYPERV.md).
- **macOS -- VMware Fusion + Vagrant:** the same three VMs, same IPs, same cluster. Bring it up with `./cka-lab.sh`, snapshot with `./cka-lab.sh snap <name>`. Walkthrough: [`TUTORIAL-MACOS.md`](../../../src/cka-lab/TUTORIAL-MACOS.md).

Then install this course's traffic-routing stack -- Gateway API CRDs, Traefik via Helm, and the Globomantics backends -- with [`lab.sh`](../lab.sh) in the course folder:

```bash
cd exercise-files/course-07-services-ingress-gateway
./lab.sh
```

Real VMs matter here: NodePort and Ingress are browsable from your workstation at the nodes' own IPs (`192.168.50.10-12`), which is exactly how the demos test routing.
