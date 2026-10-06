# Course 7, M01 -- Service Types, Endpoints, and Traffic Routing

[Course 7 overview](../README.md)

**CKA domain:** Services & Networking (20%)  

**Exam objectives:** ClusterIP, NodePort, LoadBalancer, and ExternalName; Service DNS records; how Services map to EndpointSlices; diagnosing a Service with no endpoints.

---

## What's in this folder

Three demo folders, one per demo in the module. Each is self-contained: apply its `setup/` (where present), run `demo_commands.txt` top to bottom, then `reset_commands.txt` to get back to the top for another take.

| Folder | Demo | What it shows |
| --- | --- | --- |
| [`demo3-clusterip-and-dns/`](demo3-clusterip-and-dns/) | Demo 3 | Deploy the parts shop, `kubectl expose` it as a ClusterIP, reach it by short name / FQDN / raw ClusterIP, read the EndpointSlice, scale and watch the list follow. |
| [`demo5-nodeport-loadbalancer/`](demo5-nodeport-loadbalancer/) | Demo 5 | Patch the Service to NodePort, prove the port is open on **every** node, patch to LoadBalancer and watch `EXTERNAL-IP` sit at `<pending>`, then come back down to ClusterIP. |
| [`demo6-no-endpoints/`](demo6-no-endpoints/) | Demo 6 | Break the selector by one character, walk the diagnostic ladder to `Endpoints: <none>`, and fix it without restarting anything. |

Each folder holds:

| File | What it is |
| --- | --- |
| `demo_commands.txt` | The demo path in beat order, with `#wait` / `#confirm` automation hints. Byte-identical to the `## Commands` block of the matching teleprompter script. |
| `reset_commands.txt` | Between-takes cleanup. Idempotent. |
| `setup/` | The prerequisite state, for shooting that demo standalone. Demo 3 needs none -- it builds everything on camera. Demo 6 also ships `setup/curlpod.yaml`, written to match `kubectl run` field-for-field so it applies cleanly whether or not Demo 3 already created one. |
| `globo-shop-deployment.yaml` | Demo 3 only: the manifest applied live on camera. |

Everything here is built for a standard cluster (1 control-plane + 2 workers) at Kubernetes **v1.35**, the exam topology.

---

## Before you record: get the image onto the nodes

Every demo in this module runs `ghcr.io/timothywarner-org/globo-shop:v1`. The page it serves names the Pod and the node that answered, which is the only thing that makes "traffic is spreading across three Pods" visible instead of merely asserted.

```bash
shared/apps/globo-shop/load-image.sh
```

That script pulls the image if the nodes can, and otherwise builds it locally and side-loads it into each node's containerd. **On an Apple Silicon Mac you need the build path**: the published package is amd64-only, and on arm64 nodes it pulls successfully and then every Pod dies with `exec /entrypoint.sh: exec format error` -- CrashLoopBackOff with no mention of architecture anywhere in `kubectl describe pod`. The script checks the architecture rather than trusting the pull's exit code.

---

## Spin up a lab

Practice every demo on your own cluster. The lab environment lives in [`cka-lab/`](../../cka-lab/):

- **Windows -- Hyper-V + Vagrant:** three real Ubuntu VMs (`control1`, `worker1`, `worker2`) running kubeadm-built Kubernetes v1.35 with Calico. Bring it up with `Start-CkaLab.ps1`, check it with `Get-CkaLabStatus.ps1`, snapshot before risky steps with `Save-CkaSnapshot.ps1`. Walkthrough: [`TUTORIAL-HYPERV.md`](../../cka-lab/TUTORIAL-HYPERV.md).
- **macOS -- VMware Fusion + Vagrant:** the same three VMs, same IPs, same cluster. Bring it up with `./cka-lab.sh`, snapshot with `./cka-lab.sh snap <name>`. Walkthrough: [`TUTORIAL-MACOS.md`](../../cka-lab/TUTORIAL-MACOS.md).

Real VMs matter here: Demo 5 curls `192.168.50.10-12` **from your workstation**, outside the cluster, which is exactly how a NodePort is meant to be tested.

On macOS, run `./cka-lab.sh dns` once after the cluster is up (the bare `./cka-lab.sh` does it for you). VMware's DHCP hands the VMs a `localdomain` search domain that kubelet copies into every Pod, and with `ndots:5` that turns `globo-shop.default.svc.cluster.local` -- the exact FQDN this module teaches -- into a five-second hang. See the comment above `cmd_dns` in [`cka-lab.sh`](../../cka-lab/cka-lab.sh) for the full trace.

---

## Module 2 and 3 stack on top of this

The Ingress and Gateway API modules route to Services, so bring up the shared course stack (Gateway API CRDs, Traefik, the Globomantics backends) with [`lab.sh`](../lab.sh) in the course folder when you get there:

```bash
cd course-07-services-ingress-gateway
./lab.sh
```
