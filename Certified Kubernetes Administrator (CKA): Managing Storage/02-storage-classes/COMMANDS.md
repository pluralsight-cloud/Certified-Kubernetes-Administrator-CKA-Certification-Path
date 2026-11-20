# StorageClasses and dynamic provisioning: Demo commands

Every command from this module's demos, in the order they run in the videos. Copy them one at a time and check the result before moving on: some steps fail on purpose, and some need a few seconds before the next command shows the expected state.

The first demo starts in the `01-pv-pvc` folder, where the previous module ended, and changes to this `02-storage-classes` folder. Run the rest from here, in the same terminal session, because one step saves a value in a shell variable.

- [Demo: Dynamic provisioning end to end](#demo-dynamic-provisioning-end-to-end)
- [Demo: A custom StorageClass and the missing-default-class failure](#demo-a-custom-storageclass-and-the-missing-default-class-failure)

## Demo: Dynamic provisioning end to end

### Setup

```bash
cd ../02-storage-classes
```

A kind cluster comes with the Rancher local-path provisioner installed and marked as the default. If your cluster has no StorageClass at all, follow "Cluster with no StorageClass" in the [README](../README.md) first.

```bash
kubectl config set-context --current --namespace=globo-storage
```

```bash
kubectl get pv,pvc
```

The static `globo-catalog-pv` is still bound to `globo-catalog-pvc`.

### Step 1: Find the class and read it

```bash
kubectl get storageclass
```

One class, `standard (default)`: provisioner `rancher.io/local-path`, reclaim policy `Delete`, binding mode `WaitForFirstConsumer`.

```bash
kubectl describe storageclass standard
```

`IsDefaultClass: Yes`, from the `storageclass.kubernetes.io/is-default-class=true` annotation.

### Step 2: See the provisioner itself

```bash
kubectl -n local-path-storage get pods
```

One `local-path-provisioner` pod, `Running`.

```bash
kubectl -n local-path-storage logs deployment/local-path-provisioner --tail=20
```

### Step 3: Create a claim with no class named

```bash
kubectl apply -f globo-default-pvc.yaml
```

```bash
kubectl get pvc globo-default-pvc
```

`Pending`, with class `standard`. This is expected: nothing is provisioned until a pod uses the claim.

```bash
kubectl describe pvc globo-default-pvc
```

`waiting for first consumer to be created before binding`.

### Step 4: Create a claim naming the class explicitly

```bash
kubectl apply -f globo-explicit-pvc.yaml
```

```bash
kubectl get pvc
```

`globo-explicit-pvc` is `Pending` with class `standard`, exactly like `globo-default-pvc`.

### Step 5: Attach a pod and watch provisioning happen

```bash
kubectl apply -f globo-uploads-pod.yaml
```

```bash
kubectl get pvc,pv
```

`globo-explicit-pvc` is `Bound` to a new `pvc-<uid>` volume. `globo-default-pvc` stays `Pending`.

Save the provisioned volume's name in a variable:

```bash
PROVISIONED_PV=$(kubectl get pvc globo-explicit-pvc -o jsonpath='{.spec.volumeName}')
```

```bash
kubectl get pv "$PROVISIONED_PV" -o yaml
```

The volume source is a directory on a node, and `spec.nodeAffinity` names the node the pod landed on.

### Step 6: Write to it and confirm the backing directory

```bash
kubectl exec globo-uploads -- sh -c 'echo "invoice-4417.pdf" > /uploads/manifest.txt'
```

```bash
kubectl exec globo-uploads -- cat /uploads/manifest.txt
```

Prints `invoice-4417.pdf`.

```bash
kubectl exec globo-uploads -- ls -ld /uploads
```

`drwxrwxrwx`, owned by `root`: no ownership fix or init container needed.

## Demo: A custom StorageClass and the missing-default-class failure

This demo starts where the previous one ended, in this folder.

### Setup

```bash
kubectl get sc
```

Only `standard (default)`.

### Step 1: Create the class

```bash
kubectl apply -f globo-fast-local-sc.yaml
```

```bash
kubectl get sc
```

Two classes. Only `standard` is the default, and `fast-local` has reclaim policy `Retain`.

### Step 2: Claim against it and confirm the deliberate wait

```bash
kubectl apply -f globo-fast-local-pvc.yaml
```

```bash
kubectl get pvc globo-fast-local-pvc
```

`Pending`, with class `fast-local`.

```bash
kubectl describe pvc globo-fast-local-pvc
```

`waiting for first consumer to be created before binding`.

```bash
kubectl get pv
```

No `fast-local` volume yet.

### Step 3: Add a pod and watch both happen at once

```bash
kubectl apply -f globo-fast-local-pod.yaml
```

```bash
kubectl get pod globo-fast-local -o wide
```

`Running` on one of the two workers.

```bash
kubectl get pvc,pv
```

`globo-fast-local-pvc` is `Bound` to a new `pvc-<uid>` volume with class `fast-local`.

### Step 4: Confirm the volume inherited Retain

```bash
kubectl get pv
```

The `fast-local` volume shows `Retain`, and the `standard` volume shows `Delete`.

### Step 5: Remove the default annotation and strand a claim

The trailing hyphen removes the annotation:

```bash
kubectl annotate storageclass standard storageclass.kubernetes.io/is-default-class-
```

```bash
kubectl get sc
```

The `(default)` marker is gone.

`storageClassName` can't change once set, so delete the claim and create it again while no default exists:

```bash
kubectl delete pvc globo-default-pvc
```

```bash
kubectl apply -f globo-default-pvc.yaml
```

```bash
kubectl get pvc globo-default-pvc
```

`Pending`, with an empty `STORAGECLASS` column. The `<unset>` beside it belongs to `VOLUMEATTRIBUTESCLASS`.

```bash
kubectl describe pvc globo-default-pvc
```

`no persistent volumes available for this claim and no storage class is set`.

### Step 6: Restore the default and watch it resolve

```bash
kubectl patch storageclass standard \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

```bash
kubectl get sc
```

`(default)` is back on `standard`.

```bash
kubectl get pvc globo-default-pvc
```

The class may still be empty right after the patch. Wait about fifteen seconds and run the same command again:

```bash
kubectl get pvc globo-default-pvc
```

`STORAGECLASS` now reads `standard`, with no edit to the claim.

```bash
kubectl describe pvc globo-default-pvc
```

The latest event is `waiting for first consumer to be created before binding`: the healthy wait.

### Step 7: Clean up

```bash
kubectl delete pod globo-uploads globo-fast-local
```

```bash
kubectl delete pvc globo-explicit-pvc globo-fast-local-pvc globo-default-pvc
```

The `standard` volume is deleted with its claim. The `fast-local` volume stays as `Released`, because its policy is `Retain`. Keep it and the `fast-local` class: the next module uses them.
