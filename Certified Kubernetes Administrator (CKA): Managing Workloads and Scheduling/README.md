# CKA: Managing Workloads and Scheduling

Manifests for the demos in the Pluralsight course *Certified Kubernetes Administrator (CKA): Managing Workloads and Scheduling*.

Every file here is applied in a demo. Clone the repo, create the cluster once, then work through the folders in order.

---

## Prerequisites


| Tool                                                                 | Notes                                                |
| -------------------------------------------------------------------- | ---------------------------------------------------- |
| [Docker](https://docs.docker.com/get-docker/)                        | Give it at least 4 CPUs and 8 GB of memory.          |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Creates the local cluster.                           |
| [kubectl](https://kubernetes.io/docs/tasks/tools/)                   | Match your cluster's minor version where you can.    |
| [Helm](https://helm.sh/docs/intro/install/)                          | Only needed for the metrics-server demo in Module 3. |


---



## One-time setup

```bash
cd 01-deployments
kind create cluster --config globo-kind-cluster.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=120s
kubectl get nodes
```

You should see three nodes: `globo-control-plane`, `globo-worker`, `globo-worker2`.

Create the namespace and make it your default so you can drop `-n globomantics` from every command:

```bash
kubectl create namespace globomantics
kubectl config set-context --current --namespace=globomantics
```

Every manifest here already carries `namespace: globomantics`.

### Tear down

```bash
kind delete cluster --name globo
```

---



## What runs where

The demos are cumulative: each one assumes the objects the previous ones created, so work through them in this order.

### `01-deployments/` — Module 1


| File                         | Used in                                |
| ---------------------------- | -------------------------------------- |
| `globo-kind-cluster.yaml`    | One-time cluster setup                 |
| `globo-frontend.yaml`        | Clip 3 — Performing a rolling update   |
| *(no new file)*              | Clip 4 — Revision history and rollback |
| `globo-frontend-probes.yaml` | Clip 6 — Gating rollouts with probes   |
| `globo-catalog-sidecar.yaml` | Clip 6 — Native sidecar container      |




### `02-config/` — Module 2


| File                                                               | Used in                                                            |
| ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| `globo-catalog-env-pod.yaml`                                       | Clip 3 — Creating ConfigMaps and Secrets                           |
| `globo-catalog-config.yaml`, `globo-catalog-secret.yaml`           | Clip 3 — declarative alternatives to the `kubectl create` commands |
| `app.properties`, `globo-catalog-volume-pod.yaml`                  | Clip 5 — Mounting a ConfigMap as a volume                          |
| `globo-catalog-deployment.yaml`                                    | Clip 5 — `rollout restart` to refresh env vars                     |
| `globo-catalog-broken-pod.yaml`, `globo-catalog-optional-pod.yaml` | Clip 6 — Diagnosing configuration failures                         |
| `globo-catalog-config-v2.yaml`                                     | Clip 6 — Versioned immutable ConfigMap                             |




### `03-scheduling/` — Module 3


| File                                                                                                                                     | Used in                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `globo-catalog-sized.yaml`, `globo-catalog-oversized.yaml`, `globo-memory-hog.yaml`, `globo-limitrange.yaml`, `globo-resourcequota.yaml` | Clip 2 — Requests, limits, LimitRange, ResourceQuota |
| `payment-toleration-pod.yaml`, `payment-toleration-affinity-pod.yaml`, `node-affinity-pod.yaml`                                          | Clip 4 — Taints, tolerations, node affinity          |
| `globo-catalog-cpu.yaml`                                                                                                                 | Clip 6 — metrics-server and HPA                      |


