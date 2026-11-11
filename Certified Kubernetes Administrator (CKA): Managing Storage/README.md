# CKA: Managing Storage

Manifests for the demos in the Pluralsight course *Certified Kubernetes Administrator (CKA): Managing Storage*.

## Prerequisites

| Tool | Version |
| --- | --- |
| [Docker](https://docs.docker.com/get-docker/) | Give it at least 4 CPUs and 8 GB of memory. |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | v0.31.0 or later |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.36 or later |
| Kubernetes | v1.35 or later; three nodes (one control plane, two workers) |

Create the cluster once, from the repo root:

```bash
cd 01-pv-pvc
kind create cluster --config globo-kind-cluster.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=120s
```

If you still have a `globo` cluster from an earlier course in the Certified Kubernetes Administrator (CKA) path, delete it first with `kind delete cluster --name globo`.

Then create this course's namespace and make it your default:

```bash
kubectl create namespace globo-storage
kubectl config set-context --current --namespace=globo-storage
```

Every namespaced manifest here carries `namespace: globo-storage`. PersistentVolumes and StorageClasses are cluster-scoped, so theirs do not.

### Cluster with no StorageClass

Needed only for the StorageClasses and dynamic provisioning module. A kind cluster ships with the Rancher local-path provisioner installed and marked default. A kubeadm cluster ships with none, and `kubectl get storageclass` returns nothing. Install one and mark it default:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
```

The `(default)` marker appears next to `local-path`.

## Folders

The demos are cumulative, so work through the folders in order. Each file is named after the object it creates.

| Folder | Module | What it holds |
| --- | --- | --- |
| `01-pv-pvc/` | Volumes, PersistentVolumes, and PersistentVolumeClaims | Cluster config, the emptyDir pod, static PVs and claims, the PostgreSQL pod |
| `02-storage-classes/` | StorageClasses and dynamic provisioning | Claims against the default class, the `fast-local` StorageClass, consumer pods |
| `03-access-modes/` | Access modes, reclaim policies, and storage troubleshooting | Shared-claim pods, Delete and Retain claims, the reclaim claim, and the Redis StatefulSet |

## Tear down

Deleting the cluster removes every object and the data on its nodes:

```bash
kind delete cluster --name globo
```
