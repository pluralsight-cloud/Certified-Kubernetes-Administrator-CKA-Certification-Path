# Volumes, PersistentVolumes, and PersistentVolumeClaims: Demo commands

Every command from this module's demos, in the order they run in the videos. Copy them one at a time and check the result before moving on: some steps fail on purpose, and some need a few seconds before the next command shows the expected state.

Run them from this `01-pv-pvc` folder, except the first command of the first demo, which you run from the repo root.

- [Demo: Watching emptyDir lose data](#demo-watching-emptydir-lose-data)
- [Demo: Creating a PV, binding a PVC, and surviving pod deletion](#demo-creating-a-pv-binding-a-pvc-and-surviving-pod-deletion)
- [Demo: Diagnosing a PVC that will not bind](#demo-diagnosing-a-pvc-that-will-not-bind)

## Demo: Watching emptyDir lose data

### Setup

If you still have a `globo` cluster from an earlier course in the path, delete it first with `kind delete cluster --name globo`.

From the repo root, change to this folder:

```bash
cd 01-pv-pvc
```

Create the three-node cluster:

```bash
kind create cluster --config globo-kind-cluster.yaml
```

kind finishes by setting the kubectl context to `kind-globo`.

```bash
kubectl wait --for=condition=Ready nodes --all --timeout=120s
```

`condition met` for `globo-control-plane`, `globo-worker`, and `globo-worker2`.

```bash
kubectl get nodes
```

All three nodes are `Ready`.

```bash
kubectl create namespace globo-storage
```

```bash
kubectl config set-context --current --namespace=globo-storage
```

### Step 1: Deploy a pod with an emptyDir volume

```bash
kubectl apply -f globo-scratch-pod.yaml
```

```bash
kubectl get pod globo-scratch
```

READY `1/1`, STATUS `Running`, RESTARTS `0`.

### Step 2: Write data into the mount

```bash
kubectl exec globo-scratch -- sh -c 'echo "catalog record 1" > /data/catalog.txt'
```

```bash
kubectl exec globo-scratch -- cat /data/catalog.txt
```

Prints `catalog record 1`.

### Step 3: Restart the container and show the data survives

```bash
kubectl exec globo-scratch -- ps -o pid,comm
```

`sh` is PID 1, and `tail` runs as its child.

```bash
kubectl exec globo-scratch -- pkill tail
```

The container exits and the kubelet restarts it.

```bash
kubectl get pod globo-scratch
```

`Running` again, with RESTARTS `1`.

```bash
kubectl exec globo-scratch -- cat /data/catalog.txt
```

Still prints `catalog record 1`: the data survived the container restart.

### Step 4: Delete the pod and show the data is gone

```bash
kubectl delete pod globo-scratch
```

```bash
kubectl apply -f globo-scratch-pod.yaml
```

Wait until the new pod is `Running`, then:

```bash
kubectl exec globo-scratch -- ls /data
```

The output is empty: the volume was deleted with the pod.

### Step 5: Clean up

```bash
kubectl delete pod globo-scratch
```

## Demo: Creating a PV, binding a PVC, and surviving pod deletion

### Step 1: Create the PersistentVolume

```bash
kubectl apply -f globo-catalog-pv.yaml
```

```bash
kubectl get pv
```

`globo-catalog-pv` is `Available`, with an empty `CLAIM` column and reclaim policy `Retain`.

### Step 2: Create the claim and watch both objects bind

```bash
kubectl apply -f globo-catalog-pvc.yaml
```

```bash
kubectl get pv,pvc
```

Both are `Bound` to each other within a second or two.

```bash
kubectl describe pvc globo-catalog-pvc
```

`Capacity` 1Gi and access mode `RWO`.

### Step 3: Mount the claim in a PostgreSQL pod

```bash
kubectl apply -f globo-postgres-pod.yaml
```

```bash
kubectl get pod globo-postgres -o wide
```

Once the init container completes: READY `1/1`, STATUS `Running`, on node `globo-worker`.

### Step 4: Write data the database actually owns

```bash
kubectl exec -it globo-postgres -c postgres -- psql -U postgres -d catalog
```

At the `catalog=#` prompt, create a table, insert two rows, read them back, and exit:

```sql
CREATE TABLE products (id serial PRIMARY KEY, name text, price numeric);
INSERT INTO products (name, price) VALUES ('Globomantics Widget', 24.99);
INSERT INTO products (name, price) VALUES ('Globomantics Gadget', 49.50);
SELECT * FROM products;
\q
```

### Step 5: Delete the pod and prove the data survived

```bash
kubectl delete pod globo-postgres
```

```bash
kubectl get pv,pvc
```

Both storage objects are still `Bound`.

```bash
kubectl apply -f globo-postgres-pod.yaml
```

Wait until the pod is `Running`, then:

```bash
kubectl exec -it globo-postgres -c postgres -- psql -U postgres -d catalog -c 'SELECT * FROM products;'
```

Both rows come back.

## Demo: Diagnosing a PVC that will not bind

This demo starts where the previous one ended: `globo-catalog-pvc` bound and `globo-postgres` running.

### Setup

```bash
kubectl get pv,pvc
```

Only `globo-catalog-pv` and `globo-catalog-pvc`, both `Bound`.

### Step 1: Request more than any volume offers

```bash
kubectl apply -f globo-oversized-pvc.yaml
```

```bash
kubectl get pvc
```

`globo-oversized-pvc` is `Pending`, and it stays there.

### Step 2: Diagnose it

```bash
kubectl describe pvc globo-oversized-pvc
```

A `FailedBinding` event of type `Normal`, not `Warning`.

```bash
kubectl get events --field-selector involvedObject.name=globo-oversized-pvc
```

`no persistent volumes available for this claim and no storage class is set`.

### Step 3: Satisfy the claim without touching it

```bash
kubectl apply -f globo-reports-pv.yaml
```

```bash
kubectl get pv,pvc
```

`globo-oversized-pvc` is now `Bound` to `globo-reports-pv`. This can take up to about fifteen seconds, so if it still shows `Pending`, run the command again.

### Step 4: Reproduce the access mode mismatch

```bash
kubectl get pv globo-reports-pv
```

`ACCESS MODES` reads `RWO`.

```bash
kubectl apply -f globo-shared-reports-pvc.yaml
```

```bash
kubectl get pvc globo-shared-reports-pvc
```

`Pending`: a `ReadWriteMany` claim can't bind a `ReadWriteOnce` volume.

### Step 5: The omitted storageClassName trap

```bash
kubectl apply -f globo-noclass-pvc.yaml
```

```bash
kubectl get pvc globo-noclass-pvc
```

`Pending`, with `standard` in the `STORAGECLASS` column, a value the manifest never set.

```bash
kubectl describe pvc globo-noclass-pvc
```

`waiting for first consumer to be created before binding`.

```bash
kubectl apply -f globo-noclass-pod.yaml
```

```bash
kubectl get pvc globo-noclass-pvc
```

Now `Bound`.

```bash
kubectl get pv
```

A new `pvc-<uid>` volume with class `standard` and reclaim policy `Delete`.

### Step 6: Clean up

```bash
kubectl delete pod globo-noclass globo-postgres
```

```bash
kubectl delete pvc globo-shared-reports-pvc globo-noclass-pvc globo-oversized-pvc
```

```bash
kubectl delete pv globo-reports-pv
```

```bash
kubectl get pv,pvc
```

Only `globo-catalog-pv` and `globo-catalog-pvc` remain, still `Bound`. Keep them: the next module uses them.
