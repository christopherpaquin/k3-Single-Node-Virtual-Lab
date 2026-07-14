# Lab Checklist

This checklist tracks the full set of exercises for the K3s Single-Node Lab,
to be completed **after** following the install steps in the
[root README](../README.md). Work through the phases in order — later phases
(especially Phase 3) assume earlier resources already exist.

## Why exact names matter

Every resource you create below has a **fixed, required name** (and
namespace, where applicable). This is deliberate: a validation script can
only give you a reliable pass/fail if it knows exactly what to look for.
Checking "does *a* PVC exist?" can't tell a correctly-completed step apart
from an unrelated leftover object, and it can't catch typos in your own
manifests. Checking `kubectl get pvc postgres-pvc -n lab-apps` can.

Use the names exactly as written (including case) in your manifests, LVM
commands, and `kubectl` invocations. Each item's `validate:` tag shows the
exact check the future `scripts/validate.sh` (not yet implemented) will run.

## Naming Conventions Reference

| Resource | Name | Namespace |
|---|---|---|
| Namespace | `lab-apps` | — |
| Standalone Pod (Phase 1) | `nginx-standalone` | `default` |
| Deployment (Phase 1-2) | `nginx-deployment` | `lab-apps` |
| ClusterIP Service | `nginx-clusterip` | `lab-apps` |
| DNS test Pod | `dns-test` | `lab-apps` |
| NodePort Service | `nginx-nodeport` (port `30080`) | `lab-apps` |
| Ingress | `nginx-ingress` (host `lab.k3s.local`) | `lab-apps` |
| LVM Volume Group | `vg_lab_storage` | — (host-level) |
| LVM Logical Volume | `lv_local_path` | — (host-level) |
| Local Path mount point | `/mnt/lv_local_path` | — (host-level) |
| Postgres Deployment | `postgres` | `lab-apps` |
| Postgres PVC | `postgres-pvc` | `lab-apps` |
| NFS provisioner namespace | `nfs-provisioning` | `nfs-provisioning` |
| NFS provisioner Deployment | `nfs-subdir-external-provisioner` | `nfs-provisioning` |
| NFS StorageClass | `nfs-client` | — (cluster-scoped) |
| NFS-backed Deployment | `nginx-shared` | `lab-apps` |
| NFS-backed PVC | `nginx-shared-pvc` | `lab-apps` |
| ConfigMap | `app-config` | `lab-apps` |
| ConfigMap test Pod | `configmap-test` | `lab-apps` |
| Secret | `db-credentials` | `lab-apps` |
| Secret test Pod | `secret-test` | `lab-apps` |

---

## Phase 1: Workload Primitives

- [ ] Deploy a standalone Nginx Pod named **`nginx-standalone`** (no
      controller, namespace `default`) and observe its behavior when
      deleted — confirm it does **not** get recreated.
      `validate: pod/nginx-standalone -n default absent-after-delete`
- [ ] Wrap Nginx in a Deployment named **`nginx-deployment`**, scale to 3
      replicas, then manually delete one Pod and confirm the ReplicaSet
      self-heals back to 3.
      `validate: deployment/nginx-deployment replicas=3`
- [ ] Create namespace **`lab-apps`** and re-create/move `nginx-deployment`
      into it (same name, new namespace) for logical isolation.
      `validate: namespace/lab-apps + deployment/nginx-deployment -n lab-apps`

## Phase 2: Networking & Exposure

All resources below live in the `lab-apps` namespace and target
`nginx-deployment`.

- [ ] **ClusterIP:** Create a ClusterIP Service named **`nginx-clusterip`**
      and validate internal cluster DNS resolution from a temporary Pod
      named **`dns-test`** (`nslookup nginx-clusterip.lab-apps.svc.cluster.local`).
      `validate: service/nginx-clusterip type=ClusterIP + dns-resolves`
- [ ] **NodePort:** Create a NodePort Service named **`nginx-nodeport`**
      bound to node port **`30080`**, and reach it from outside the VM using
      the node's IP.
      `validate: service/nginx-nodeport type=NodePort nodePort=30080`
- [ ] **Ingress:** Create an Ingress named **`nginx-ingress`** mapping host
      **`lab.k3s.local`** to `nginx-clusterip`, and confirm routing works via
      `curl -H "Host: lab.k3s.local" http://<node-ip>/`.
      `validate: ingress/nginx-ingress host=lab.k3s.local`

## Phase 3: Persistent Storage (Dual Architecture)

### Track A — Local Block Storage (RWO)

- [ ] Confirm the secondary virtual disk attached to the VM is visible
      (`lsblk`) and unformatted. (Device name is VM-specific — check with
      `lsblk`, don't assume `/dev/sdb`.)
      `validate: block-device-present`
- [ ] Build an LVM Volume Group named **`vg_lab_storage`** and a Logical
      Volume named **`lv_local_path`** on the secondary disk, and format the
      Logical Volume with XFS.
      `validate: lvm vg=vg_lab_storage lv=lv_local_path fstype=xfs`
- [ ] Mount the Logical Volume at **`/mnt/lv_local_path`** and reconfigure
      K3s's Local Path Provisioner (`local-path-config` ConfigMap in
      `kube-system`) to use that path.
      `validate: mount /mnt/lv_local_path + local-path-config points there`
- [ ] Deploy PostgreSQL as a Deployment named **`postgres`** with a PVC
      named **`postgres-pvc`** (namespace `lab-apps`), write test data,
      delete and recreate the Pod, and confirm the data survives.
      `validate: pvc/postgres-pvc bound + deployment/postgres data-persists`

### Track B — NFS External Provisioning (RWX)

- [ ] Export an NFS share from the hypervisor (outside the VM). Path is
      environment-specific — document the export path you used, e.g.
      `/srv/nfs/k3s-lab`.
      `validate: storage-nfs-export-reachable`
- [ ] Install and validate NFS client tooling on the guest OS —
      `nfs-common` on Ubuntu, `nfs-utils` on Fedora — and confirm the share
      can be mounted manually (`mount -t nfs <host>:<path> /mnt/test`).
      `validate: storage-nfs-client-mount`
- [ ] Deploy `nfs-subdir-external-provisioner` into namespace
      **`nfs-provisioning`** (Deployment name
      **`nfs-subdir-external-provisioner`**), pointed at the exported share,
      registering StorageClass **`nfs-client`**.
      `validate: deployment/nfs-subdir-external-provisioner -n nfs-provisioning + storageclass/nfs-client`
- [ ] Deploy an Nginx Deployment named **`nginx-shared`** (namespace
      `lab-apps`, 3 replicas) sharing a single RWX PVC named
      **`nginx-shared-pvc`**, all serving the same `index.html` written to
      the shared volume.
      `validate: pvc/nginx-shared-pvc accessMode=RWX + deployment/nginx-shared replicas=3`

## Phase 4: Configuration Management

- [ ] Create a ConfigMap named **`app-config`** and mount it into a test Pod
      named **`configmap-test`** (namespace `lab-apps`); confirm the values
      are visible inside the container.
      `validate: configmap/app-config + pod/configmap-test mounts-it`
- [ ] Create a Secret named **`db-credentials`** with mock database
      credentials and inject it as environment variables into a test Pod
      named **`secret-test`** (namespace `lab-apps`); confirm the values
      resolve and are **not** stored in plaintext in the Pod spec.
      `validate: secret/db-credentials + pod/secret-test env-from-secret`

## Phase 5: Operational Troubleshooting

These steps reuse `nginx-deployment` from Phase 1/2 — no new named
resources, just command usage to confirm.

- [ ] Stream logs from a Pod in `nginx-deployment` with `kubectl logs -f`
      and observe live output.
      `validate: ops-logs-streamable`
- [ ] Open an interactive shell in a Pod in `nginx-deployment` with
      `kubectl exec -it -- /bin/sh` and inspect its filesystem/process state.
      `validate: ops-exec-shell`
- [ ] Establish a local tunnel to `nginx-clusterip` with
      `kubectl port-forward svc/nginx-clusterip 8080:80` and reach it on
      `localhost:8080`, bypassing NodePort/Ingress.
      `validate: ops-port-forward-tunnel`

---

## Architecture Reference

- **Distribution:** K3s (containerd runtime, embedded SQLite datastore)
- **Networking:** Flannel (CNI)
- **Ingress:** Traefik
- **Storage:**
  - RWO — K3s Local Path Provisioner backed by a dedicated LVM Logical Volume, XFS.
  - RWX — `nfs-subdir-external-provisioner` backed by a hypervisor-exported NFS share.

See [`project/K3s Single-Node Lab Project Goals.pdf`](../project/K3s%20Single-Node%20Lab%20Project%20Goals.pdf)
for the original project brief this checklist is derived from (written against
RHEL; this lab substitutes Ubuntu/Fedora throughout).
