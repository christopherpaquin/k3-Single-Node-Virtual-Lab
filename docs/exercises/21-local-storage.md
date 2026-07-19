# Exercise 21: Local Storage

**Module:** Workload Types

**Prerequisite:** [Exercise 20 — Jobs and CronJobs](20-jobs-and-cronjobs.md).
Track A below also needs the secondary disk from
[README §1](../../README.md#1-virtual-machine-requirements), attached but
still unformatted.

---

## Theme

Every workload so far has been stateless — delete a Pod, and nothing of
value is lost. A **PersistentVolumeClaim (PVC)** is how a Pod asks for
durable storage that survives a Pod being deleted and recreated, backed by
a **PersistentVolume (PV)** that a **StorageClass** knows how to
provision.

This exercise covers both storage paths this lab is built around: K3s's
built-in **Local Path Provisioner** (Track A — using a dedicated disk, the
way a real deployment would rather than sharing the OS disk), and,
optionally, network storage over **NFS** (Track B) for anyone with a
hypervisor or NAS available to export a share from. Both answer the same
question — where does the data actually live — in very different ways.

---

## What you'll do

- Inspect K3s's default `local-path` StorageClass.
- Create a PVC, mount it, write data, delete and recreate the Pod, and
  confirm the data survived.
- Inspect the PV/PVC relationship and find the data on the host's
  filesystem directly.
- Review reclaim policies, and understand why local-path storage is tied
  to one specific node.
- **Track A:** build a dedicated LVM volume, reconfigure the Local Path
  Provisioner to use it, and run PostgreSQL on top of it.
- **Track B (optional):** point this lab at an NFS export for
  network-backed storage instead.

---

## Step 1: Inspect the default `local-path` StorageClass

```bash
kubectl get storageclass
```

`local-path` should be marked `(default)` — any PVC that doesn't specify a
`storageClassName` uses this one automatically.

```bash
kubectl describe storageclass local-path
```

`PROVISIONER` reads `rancher.io/local-path` — this is a K3s-bundled
controller, not a generic Kubernetes feature; it's what turns a PVC
request into real space on the node's local disk.

---

## Step 2: Create a PVC and mount it

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-demo-pvc
  namespace: lab-apps
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

```bash
kubectl get pvc local-demo-pvc -n lab-apps
```

`STATUS` should reach `Bound` — a real `PersistentVolume` was created and
matched to this claim automatically.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: local-demo-pod
  namespace: lab-apps
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: local-demo-pvc
EOF
```

---

## Step 3: Write data, delete the Pod, and confirm it survives

```bash
kubectl exec local-demo-pod -n lab-apps -- sh -c "echo 'persisted data' > /data/test.txt"
kubectl exec local-demo-pod -n lab-apps -- cat /data/test.txt
```

Now delete the Pod entirely — not just restart it:

```bash
kubectl delete pod local-demo-pod -n lab-apps
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: local-demo-pod
  namespace: lab-apps
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: local-demo-pvc
EOF
```

```bash
kubectl exec local-demo-pod -n lab-apps -- cat /data/test.txt
```

`persisted data` is still there — this is a brand-new Pod (check
`kubectl get pod local-demo-pod -n lab-apps` and note the fresh `AGE`),
but the same underlying volume was reattached to it. This is the entire
point of a PVC: the data's lifecycle is independent of any one Pod's.

---

## Step 4: Inspect the PV/PVC relationship, and find the data on disk

```bash
kubectl get pvc local-demo-pvc -n lab-apps
kubectl get pv
```

Find the `PersistentVolume` whose `CLAIM` column references
`lab-apps/local-demo-pvc` — this is the actual provisioned volume, a
separate cluster-scoped object your PVC is bound to.

```bash
kubectl describe pv <pv-name>
```

Look at `Source.Path` — an actual directory path on the node's own
filesystem. Confirm it directly, on the VM itself:

```bash
sudo ls -la <path-from-above>
sudo cat <path-from-above>/test.txt
```

The "volume" is, under the hood, just a directory on the node's local
disk that the Local Path Provisioner created and manages for you.

---

## Step 5: Reclaim policies

```bash
kubectl get pv <pv-name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
echo
```

`local-path`'s default is `Delete` — when the PVC is deleted, the
PersistentVolume **and the underlying directory on disk** are deleted
with it, not just unlinked from Kubernetes. Confirm it:

```bash
kubectl delete pod local-demo-pod -n lab-apps
kubectl delete pvc local-demo-pvc -n lab-apps
kubectl get pv <pv-name>
```

The PV is gone. If you still have the directory path from Step 4 handy,
check it on the host too — it should be gone as well. The alternative
policy, `Retain`, would leave both the PV object and the on-disk data
behind after the PVC is deleted, specifically so the data can be
recovered or migrated manually — appropriate for anything you can't
afford to lose to an accidental `kubectl delete pvc`.

---

## Step 6: Why local-path storage is tied to one node

Nothing about this was visible in the exercise above, because there was
never a second node for it to matter. On a real multi-node cluster,
though, a `local-path` volume physically exists on whichever node created
it — if the Pod using it gets rescheduled onto a **different** node later
(after a drain, a node failure, or just normal rebalancing), it cannot
reach that data at all; Kubernetes has to keep re-scheduling that Pod back
onto the original node specifically, which local-path handles through a
node affinity it adds to the PV automatically. This lab never surfaces
that constraint, precisely because there's only ever one place for
anything to go — worth remembering as a real limitation before reaching
for `local-path` in a production, multi-node context.

---

## Track A: A dedicated LVM volume for local-path

Using the OS disk for application data works for a lab, but ties your
application storage's capacity and I/O directly to the same disk running
the OS itself. This track builds a separate, dedicated volume instead —
matching this lab's advertised "dual-track" storage design — and points
the Local Path Provisioner at it.

### A1. Confirm the secondary disk

```bash
lsblk
```

Identify the secondary disk from README §1 — unformatted, no partitions,
no mount point. The device name is VM-specific (commonly `/dev/sdb`, but
confirm rather than assume).

### A2. Build the LVM volume group and logical volume

```bash
sudo pvcreate /dev/sdb
sudo vgcreate vg_lab_storage /dev/sdb
sudo lvcreate -l 100%FREE -n lv_local_path vg_lab_storage
sudo mkfs.xfs /dev/vg_lab_storage/lv_local_path
```

Replace `/dev/sdb` with your actual secondary disk device if different.

### A3. Mount it and point the Local Path Provisioner at it

```bash
sudo mkdir -p /mnt/lv_local_path
sudo mount /dev/vg_lab_storage/lv_local_path /mnt/lv_local_path
```

Make it persistent across reboots:

```bash
echo "/dev/vg_lab_storage/lv_local_path /mnt/lv_local_path xfs defaults 0 0" | sudo tee -a /etc/fstab
```

Now reconfigure the provisioner itself:

```bash
kubectl get configmap local-path-config -n kube-system -o jsonpath='{.data.config\.json}'
```

```bash
kubectl patch configmap local-path-config -n kube-system --type=merge -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/mnt/lv_local_path\"]}]}"}}'
```

```bash
kubectl rollout restart deployment local-path-provisioner -n kube-system
kubectl rollout status deployment local-path-provisioner -n kube-system
```

Any PVC created from this point on provisions its storage under
`/mnt/lv_local_path` — your dedicated LVM volume — instead of the OS
disk.

### A4. Run PostgreSQL on the new storage

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: lab-apps
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: lab-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16
          env:
            - name: POSTGRES_PASSWORD
              value: labpassword
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-pvc
EOF
```

```bash
kubectl rollout status deployment/postgres -n lab-apps
```

Write and verify test data, then prove it survives a Pod cycle, the same
way you did in Steps 2–3:

```bash
kubectl exec deploy/postgres -n lab-apps -- psql -U postgres -c "CREATE TABLE lab_test (id serial, note text);"
kubectl exec deploy/postgres -n lab-apps -- psql -U postgres -c "INSERT INTO lab_test (note) VALUES ('surviving a pod restart');"

kubectl delete pod -n lab-apps -l app=postgres

kubectl rollout status deployment/postgres -n lab-apps
kubectl exec deploy/postgres -n lab-apps -- psql -U postgres -c "SELECT * FROM lab_test;"
```

The row is still there — and this time, confirm exactly where on the host
it actually lives:

```bash
sudo ls /mnt/lv_local_path
```

You should see a directory corresponding to `postgres-pvc`'s
provisioned volume, physically on the dedicated LVM logical volume, not
the OS disk.

---

## Track B (optional): NFS-backed network storage

Everything above is local to this one node — appropriate for K3s's Local
Path Provisioner by definition. If you have a hypervisor, NAS, or separate
Linux host that can export an NFS share, you can add genuine
network-attached, `ReadWriteMany`-capable storage instead. This track is
environment-specific (it depends on infrastructure outside this VM), so
treat it as optional.

1. **Export a share from your hypervisor/NAS** (outside this VM) — e.g.
   `/srv/nfs/k3s-lab`, exported to this VM's IP or subnet.

2. **Install NFS client tooling on this VM**, if you didn't already back
   in [K3s/Headlamp Install §1.1](../K3S-HEADLAMP-INSTALL.md#11-update-the-os-and-install-prerequisites):

   ```bash
   sudo apt install -y nfs-common   # Ubuntu
   sudo dnf install -y nfs-utils    # Fedora
   ```

3. **Confirm the export is reachable:**

   ```bash
   showmount -e <nfs-server-ip>
   ```

4. **Install the `nfs-subdir-external-provisioner`** via Helm, pointed at
   your export:

   ```bash
   helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
   helm repo update
   kubectl create namespace nfs-provisioning
   helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
     --namespace nfs-provisioning \
     --set nfs.server=<nfs-server-ip> \
     --set nfs.path=<nfs-export-path> \
     --set storageClass.name=nfs-client
   ```

5. **Confirm the new StorageClass, and use it explicitly** (unlike
   `local-path`, this one won't be the default):

   ```bash
   kubectl get storageclass nfs-client
   ```

   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: nfs-demo-pvc
     namespace: lab-apps
   spec:
     accessModes:
       - ReadWriteMany
     storageClassName: nfs-client
     resources:
       requests:
         storage: 1Gi
   EOF
   ```

   `ReadWriteMany` is the headline difference from Tracks A above and
   Steps 1–6: multiple Pods, even on different nodes on a real cluster,
   can mount this same volume simultaneously — something `local-path`
   fundamentally cannot do.

---

## Recap

In this exercise, you:

- Inspected the default `local-path` StorageClass and its provisioner.

- Created a PVC, wrote data to it, deleted and recreated the Pod using
  it, and confirmed the data survived — proof a PVC's lifecycle is
  independent of any one Pod's.

- Traced the PV/PVC relationship and found the provisioned data directly
  on the node's filesystem.

- Reviewed reclaim policies, and confirmed `local-path`'s default
  (`Delete`) removes the on-disk data along with the PVC.

- Understand why `local-path` storage is fundamentally tied to a single
  node, even though this lab never surfaces that constraint directly.

- **(Track A)** Built a dedicated LVM logical volume, reconfigured the
  Local Path Provisioner to use it instead of the OS disk, and ran
  PostgreSQL on top of it — confirming data survives a Pod cycle on
  dedicated storage.

- **(Track B, optional)** Reviewed how to add NFS-backed, `ReadWriteMany`
  network storage for anyone with infrastructure to export a share from.

---

**Previous:** [Exercise 20 — Jobs and CronJobs](20-jobs-and-cronjobs.md)

**Next:** [Exercise 22 — StatefulSets](22-statefulsets.md)
