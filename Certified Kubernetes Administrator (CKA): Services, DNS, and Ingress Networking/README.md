# CKA: Services, DNS, and Ingress Networking

Manifests, scripts, and demo files for the Pluralsight course *Certified Kubernetes Administrator (CKA): Services, DNS, and Ingress Networking*.

Course 7 of the CKA v1.35 skill path. It covers the Services & Networking exam domain (20%): Service types, Ingress, and the Gateway API. The demos follow Globomantics, a fictional company whose workloads are finally being exposed to external traffic.

Every file here is used in a demo. Clone the repo, bring up the lab once, install the shared stack with `lab.sh`, then work through the modules in order.

---

## Prerequisites

| Tool | Notes |
| ---- | ----- |
| [Vagrant](https://developer.hashicorp.com/vagrant/install) 2.4+ | Drives the three-node lab. |
| Hyper-V (Windows 11) or VMware Fusion (macOS) | The VM provider for the lab in `cka-lab/`. |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Match the cluster's minor version (v1.35). |
| [Helm](https://helm.sh/docs/intro/install/) | Installs Traefik, which serves both Ingress and Gateway API. |
| curl | Used for every traffic check. |

16 GB of host RAM is recommended: three VMs at 2 GB each, plus host overhead.

---

## One-time setup

### 1. Bring up the lab cluster

The lab is three Ubuntu VMs (`control1`, `worker1`, `worker2`) running kubeadm-built Kubernetes v1.35 with Calico, on real private IPs (`192.168.50.10-12`). Real IPs matter because the NodePort and Ingress demos curl the nodes from your workstation.

- **Windows (Hyper-V):** see [`cka-lab/TUTORIAL-HYPERV.md`](cka-lab/TUTORIAL-HYPERV.md). Run from an elevated PowerShell.
- **macOS (VMware Fusion):** see [`cka-lab/TUTORIAL-MACOS.md`](cka-lab/TUTORIAL-MACOS.md).

```bash
cd cka-lab
./cka-lab.sh                          # macOS: up + bootstrap + kubeconfig + status
export KUBECONFIG=~/.kube/cka-config
kubectl get nodes                     # control1, worker1, worker2 all Ready
```

### 2. Put the demo app on the nodes

Every demo runs `globo-shop`, a small nginx page that reports which Pod and node served each request. That is what makes load balancing visible.

```bash
shared/apps/globo-shop/load-image.sh
```

On Apple Silicon this builds the image locally and side-loads it into each node, because the published image is amd64-only.

### 3. Install the shared stack

All three modules share one stack, so one script installs it.

```bash
cd course-07-services-ingress-gateway
./lab.sh            # Gateway API CRDs + Traefik (Helm) + the Globomantics backends, then verify
```

| Command | What it does |
| ------- | ------------ |
| `./lab.sh` | Everything below, then verify |
| `./lab.sh gatewayapi` | Gateway API CRDs (standard channel) |
| `./lab.sh traefik` | Traefik via Helm, as a NodePort on `30080` / `30443` |
| `./lab.sh apps` | The `catalog`, `portal`, and `api` backends, plus `catalog-v2` |
| `./lab.sh verify` | Asserts CRDs, controller, endpoints, and host reachability |
| `./lab.sh reset` | Removes everything the script created |

`type: LoadBalancer` Services stay `<pending>` on this lab. That is correct: there is no cloud provider, and Module 1 teaches exactly that.

---

## What runs where

Each demo folder holds `demo_commands.txt` (the demo in beat order), `reset_commands.txt` (back to the starting state, safe to re-run), the manifests applied on screen, and `setup/` where a demo needs prerequisite state. Folder numbers match the demo numbers in the video.

### `course-07-services-ingress-gateway/m01-service-types/` -- Module 1: Service Types, Endpoints, and Traffic Routing

| Folder | What it shows |
| ------ | ------------- |
| `demo3-clusterip-and-dns/` | Expose a Deployment as ClusterIP, reach it by short name, FQDN, and ClusterIP, read the EndpointSlice, scale and watch it follow. |
| `demo5-nodeport-loadbalancer/` | NodePort open on every node and reachable from the host; LoadBalancer stuck at `<pending>`. |
| `demo6-no-endpoints/` | A selector off by one character: walk get, describe, EndpointSlice to the cause, then fix it. |

### `course-07-services-ingress-gateway/m02-ingress/` -- Module 2: Ingress Controllers and Ingress Resources

| Folder | What it shows |
| ------ | ------------- |
| `demo2-traefik-helm/` | Install Traefik with Helm, deploy the three backends, verify the controller. |
| `demo4-host-and-path-routing/` | Path-based and host-based Ingress rules, plus prefix stripping. |
| `demo6-tls-and-broken-backend/` | TLS termination from a Secret, a broken backend Service, and a default backend. |

Demo 6 generates `tls.crt` and `tls.key` in its own folder when you run it. They are not committed.

### `course-07-services-ingress-gateway/m03-gateway-api/` -- Module 3: Gateway API for Traffic Management

| Folder | What it shows |
| ------ | ------------- |
| `demo3-crds-and-gateway/` | Gateway API CRDs, a GatewayClass, and a Gateway with HTTP and HTTPS listeners. |
| `demo4-first-httproute/` | A first HTTPRoute attached to the Gateway, read from both sides, then broken on purpose. |
| `demo5-header-and-weighted-split/` | `X-Version: v2` header matching and an 80/20 weighted split. |

---

## Everything else

| Path | What it is |
| ---- | ---------- |
| `course-07-services-ingress-gateway/lab.sh` | Installs and verifies the shared stack. |
| `shared/apps/globo-shop/` | The demo app, its image build, and `load-image.sh`. |
| `cka-lab/` | The three-VM Vagrant lab (Hyper-V and VMware Fusion). |

Everything targets a standard cluster (1 control plane + 2 workers) at Kubernetes **v1.35**.

---

## Tear down

```bash
cd course-07-services-ingress-gateway && ./lab.sh reset   # remove the shared stack
cd ../cka-lab && ./cka-lab.sh halt                        # macOS: shut the VMs down
```

On Windows, use `./Stop-CkaLab.ps1`.
