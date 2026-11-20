# Access modes, reclaim policies, and storage troubleshooting: Demo commands

Every command from this module's demos, in the order they run in the videos. Copy them one at a time and check the result before moving on: some steps fail on purpose, and some need a few seconds before the next command shows the expected state.

The first demo starts in the `02-storage-classes` folder, where the previous module ended, and changes to this `03-access-modes` folder. Run the rest from here, in the same terminal session, because one demo saves a value in a shell variable and uses it several steps later.

- [Demo: Proving access modes are per-node](#demo-proving-access-modes-are-per-node)
- [Demo: Comparing Delete and Retain, and reclaiming a released volume](#demo-comparing-delete-and-retain-and-reclaiming-a-released-volume)
- [Demo: StatefulSet storage identity and the troubleshooting ladder](#demo-statefulset-storage-identity-and-the-troubleshooting-ladder)

## Demo: Proving access modes are per-node

### Setup

```bash
cd ../03-access-modes
```

```bash
kubectl config set-context --current --namespace=globo-storage
```

```bash
kubectl get nodes
```

All three nodes are `Ready`.

```bash
kubectl get pvc
```

Only `globo-catalog-pvc`.

### Step 1: Create the claim and the first pod

```bash
kubectl apply -f globo-shared-pvc.yaml
```

```bash
kubectl apply -f globo-writer-pod.yaml
```

```bash
kubectl get pod globo-writer -o wide
```

`Running` on one of the two workers. Note which one.

```bash
kubectl get pvc globo-shared-pvc
```

`Bound`.

```bash
kubectl exec globo-writer -- sh -c 'echo "session-a from writer" > /shared/sessions.log'
```

```bash
kubectl exec globo-writer -- cat /shared/sessions.log
```

Prints `session-a from writer`.

### Step 2: Add a second pod on the same node

```bash
kubectl apply -f globo-reader-pod.yaml
```

```bash
kubectl get pods -o wide
```

Both pods `Running` on the same node, sharing one `ReadWriteOnce` claim.

```bash
kubectl exec globo-reader -- cat /shared/sessions.log
```

Prints `session-a from writer`.

```bash
kubectl exec globo-reader -- sh -c 'echo "session-b from reader" >> /shared/sessions.log'
```

```bash
kubectl exec globo-writer -- cat /shared/sessions.log
```

Prints both lines: two pods read and write a `ReadWriteOnce` volume on one node.

### Step 3: Force a third pod onto a different node

```bash
kubectl apply -f globo-cross-node-pod.yaml
```

```bash
kubectl get pod globo-cross-node
```

`Pending`, and it stays there.

```bash
kubectl describe pod globo-cross-node
```

`0/3 nodes are available: 1 node(s) didn't match PersistentVolume's node affinity, 1 node(s) didn't match pod anti-affinity rules, 1 node(s) had untolerated taint(s)`.

```bash
kubectl get pvc globo-shared-pvc
```

Still `Bound`: the failure shows on the pod, not the claim.

### Step 4: Clean up

```bash
kubectl delete pod globo-cross-node globo-reader globo-writer
```

```bash
kubectl delete pvc globo-shared-pvc
```

The volume goes too, because the `standard` class uses `Delete`.

## Demo: Comparing Delete and Retain, and reclaiming a released volume

This demo starts where the previous one ended, in this folder.

### Setup

```bash
kubectl get sc
```

`standard (default)` with `Delete`, and `fast-local` with `Retain`.

### Step 1: Provision through the Delete class and write data

```bash
kubectl apply -f globo-delete-pvc.yaml
```

```bash
kubectl apply -f globo-cache-pod.yaml
```

```bash
kubectl get pvc,pv
```

`globo-delete-pvc` is `Bound` to a new `pvc-<uid>` volume with reclaim policy `Delete`.

```bash
kubectl exec globo-cache -- sh -c 'echo "cached at 09:14" > /cache/entries.log'
```

```bash
kubectl exec globo-cache -- cat /cache/entries.log
```

Prints `cached at 09:14`.

### Step 2: Delete the claim and watch the volume go with it

```bash
kubectl delete pod globo-cache
```

```bash
kubectl delete pvc globo-delete-pvc
```

```bash
kubectl get pv
```

The volume is gone, along with its data.

### Step 3: Repeat against the Retain class

```bash
kubectl apply -f globo-retain-pvc.yaml
```

```bash
kubectl apply -f globo-audit-pod.yaml
```

```bash
kubectl get pvc,pv
```

`globo-retain-pvc` is `Bound` to a new `pvc-<uid>` volume with class `fast-local`.

```bash
kubectl exec globo-audit -- sh -c 'echo "audit entry 8841: order refunded" > /audit/trail.log'
```

```bash
kubectl exec globo-audit -- cat /audit/trail.log
```

Prints `audit entry 8841: order refunded`.

Save the volume's name in a variable. Steps 5 to 7 use it:

```bash
RETAINED_PV=$(kubectl get pvc globo-retain-pvc -o jsonpath='{.spec.volumeName}')
```

```bash
echo "$RETAINED_PV"
```

Prints the volume's `pvc-<uid>` name.

```bash
kubectl get pv
```

The volume named in `$RETAINED_PV` shows class `fast-local`, policy `Retain`, status `Bound`. The other `fast-local` row is the `Released` volume from the previous module.

### Step 4: Delete the claim and find the volume still there

```bash
kubectl delete pod globo-audit
```

```bash
kubectl delete pvc globo-retain-pvc
```

```bash
kubectl get pv
```

The volume survives as `Released`, and its `CLAIM` column still shows `globo-storage/globo-retain-pvc`.

### Step 5: Read the stale claim reference

```bash
kubectl get pv "$RETAINED_PV" -o jsonpath='{.spec.claimRef.name}'
```

Prints `globo-retain-pvc`.

### Step 6: Reclaim it

```bash
kubectl patch pv "$RETAINED_PV" -p '{"spec":{"claimRef": null}}'
```

```bash
kubectl get pv
```

The volume is `Available`, with an empty `CLAIM` column and its data untouched.

### Step 7: Bind a new claim to the reclaimed volume by name

Open `globo-reclaimed-pvc.yaml`, replace the `REPLACE_WITH_RETAINED_PV_NAME` placeholder in `volumeName` with the value of `$RETAINED_PV`, and save the file. Then apply it:

```bash
kubectl apply -f globo-reclaimed-pvc.yaml
```

```bash
kubectl get pvc,pv
```

`globo-reclaimed-pvc` is `Bound` to the retained volume.

```bash
kubectl apply -f globo-reclaimed-pod.yaml
```

Wait until the pod is `Running`, then:

```bash
kubectl exec globo-reclaimed -- cat /audit/trail.log
```

Prints `audit entry 8841: order refunded`: the data outlived its claim.

### Step 8: Clean up

```bash
kubectl delete pod globo-reclaimed
```

```bash
kubectl delete pvc --all
```

```bash
kubectl get pv
```

Three `Released` volumes with `Retain`: `globo-catalog-pv` and two `fast-local` volumes. They stay until the cluster teardown at the end of the next demo.

## Demo: StatefulSet storage identity and the troubleshooting ladder

This demo starts where the previous one ended, in this folder.

### Setup

```bash
kubectl get pvc,pv
```

No claims, and three `Released` volumes with `Retain`.

```bash
kubectl get sc
```

`standard (default)` and `fast-local`.

### Step 1: Deploy the StatefulSet

```bash
kubectl apply -f globo-redis-statefulset.yaml
```

`service/globo-redis created` and `statefulset.apps/globo-redis created`.

```bash
kubectl get statefulset globo-redis
```

READY `3/3` once all replicas have started.

```bash
kubectl get pods -l app=globo-redis -o wide
```

`globo-redis-0`, `globo-redis-1`, and `globo-redis-2`, started in that order.

### Step 2: Look at the storage it generated

```bash
kubectl get pvc
```

`data-globo-redis-0`, `data-globo-redis-1`, and `data-globo-redis-2`, each `Bound` at 1Gi.

```bash
kubectl get pv
```

Three new `pvc-<uid>` volumes, one per claim.

### Step 3: Write distinct data into each replica

```bash
kubectl exec globo-redis-0 -- redis-cli set shard "zero"
```

```bash
kubectl exec globo-redis-1 -- redis-cli set shard "one"
```

```bash
kubectl exec globo-redis-2 -- redis-cli set shard "two"
```

Each replies `OK`.

```bash
kubectl exec globo-redis-1 -- redis-cli get shard
```

Prints `one`.

### Step 4: Delete a pod and confirm it reattaches

```bash
kubectl delete pod globo-redis-1
```

```bash
kubectl get pods -l app=globo-redis -w
```

The replacement is named `globo-redis-1` again. Press `Ctrl+C` once it's `Running`.

```bash
kubectl get pvc
```

The same three claims, all `Bound`.

```bash
kubectl exec globo-redis-1 -- redis-cli get shard
```

Prints `one`: the new pod mounted the same volume.

### Step 5: Scale down and back up

```bash
kubectl scale statefulset globo-redis --replicas=1
```

```bash
kubectl get pods -l app=globo-redis
```

Once termination finishes, only `globo-redis-0` remains.

```bash
kubectl get pvc
```

All three claims remain.

```bash
kubectl scale statefulset globo-redis --replicas=3
```

```bash
kubectl get pods -l app=globo-redis
```

`globo-redis-1` and `globo-redis-2` return, in order.

Once `globo-redis-2` is `Running`:

```bash
kubectl exec globo-redis-2 -- redis-cli get shard
```

Prints `two`.

### Step 6: Delete the StatefulSet and find the storage still there

```bash
kubectl delete statefulset globo-redis
```

```bash
kubectl get pods -l app=globo-redis
```

Once termination finishes: `No resources found`.

```bash
kubectl get pvc
```

All three claims are still `Bound`.

The StatefulSet controller labels each claim with its selector, so you can delete them by label:

```bash
kubectl delete pvc -l app=globo-redis
```

```bash
kubectl get pvc,pv
```

No claims, and the three Redis volumes are gone, because the `standard` class uses `Delete`.

### Step 7: The storage troubleshooting ladder

The video covers this step on slides. Run the five rungs in order when a workload's storage doesn't work:

1. Is the claim bound? `Bound` means go to rung 3, and `Pending` means go to rung 2.

   ```bash
   kubectl get pvc
   ```

2. Why is the claim pending? Read the event text.

   ```bash
   kubectl describe pvc <claim-name>
   ```

3. What do the pod's events say? Use this when the claim is `Bound` but the pod won't run.

   ```bash
   kubectl describe pod <pod-name>
   ```

4. What do the cluster events show?

   ```bash
   kubectl get events --sort-by=.lastTimestamp | tail -20
   ```

5. What do the provisioner logs say?

   ```bash
   kubectl -n local-path-storage logs deployment/local-path-provisioner --tail=10
   ```

### Step 8: Tear down the cluster

```bash
kubectl get pv,pvc --all-namespaces
```

Only the three `Released` volumes with `Retain` remain.

```bash
kubectl delete pv --all
```

```bash
kind delete cluster --name globo
```

kind prints `Deleting cluster "globo" ...` and lists the three deleted nodes.
