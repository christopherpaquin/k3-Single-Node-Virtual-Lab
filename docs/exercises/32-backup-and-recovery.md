# Exercise 32: Backup and Recovery

**Module:** Resilience & Capstone

**Prerequisite:** [Exercise 31 — Failure Scenarios](31-failure-scenarios.md)

---

## Theme

This exercise ties together three earlier discoveries — Exercise 26 found
K3s's SQLite datastore file, Exercise 21 found exactly where a PVC's data
lives on the host disk, and Exercise 11 covered exporting live objects to
YAML — into an actual backup and recovery drill. It ends with a real test
of whether the backup works at all, not just whether the backup command
ran successfully.

> **Before you start:** this exercise stops K3s and directly manipulates
> its core datastore file. Every step keeps the original file around
> under a renamed path rather than deleting it, specifically so you have
> a way back if something goes wrong. Worst case on this lab VM, if
> something does go sideways, is reinstalling K3s from README §2 — not
> something you'd want on a real cluster, but a reasonable, known-safe
> fallback here.

---

## What you'll do

- Identify K3s's datastore and understand why it's a single SQLite file
  on this single-node cluster specifically.
- Stop K3s and take a consistent backup of the datastore, the node
  token, and K3s's own configuration.
- Export live application manifests to YAML.
- Back up actual application *data* — a completely different thing from
  backing up object definitions.
- Delete and restore an application from your manifest backup.
- Test-restore the data backup to confirm it's actually valid.
- Understand the real difference between cluster-state and
  application-data backups.
- Run a full, controlled recovery drill: intentionally replace the live
  datastore with your backup, and confirm the entire cluster's state
  comes back from it.

---

## Step 1: Identify the datastore

You already found this in Exercise 26:

```bash
sudo ls -la /var/lib/rancher/k3s/server/db/
```

`state.db` is a SQLite database — the default datastore for a
**single-node** K3s cluster. A K3s cluster running in HA mode across
multiple server nodes uses an embedded etcd datastore instead, with its
own separate snapshot mechanism (`k3s etcd-snapshot`) — not applicable
here, since this lab has exactly one node.

---

## Step 2: Stop K3s before backing it up

```bash
sudo systemctl stop k3s
```

SQLite is a single file, actively written to while K3s is running —
copying it live risks capturing a half-written, inconsistent state.
Stopping the service first guarantees the file you copy is exactly what
K3s itself considers consistent.

---

## Step 3: Back up the datastore, token, and configuration

```bash
mkdir -p ~/k3s-backup
sudo cp /var/lib/rancher/k3s/server/db/state.db ~/k3s-backup/
sudo cp /var/lib/rancher/k3s/server/token ~/k3s-backup/
sudo cp -r /etc/rancher/k3s ~/k3s-backup/rancher-k3s-config
sudo chown -R "$(id -u)":"$(id -g)" ~/k3s-backup
```

The `server/token` file is what a second node would need to join this
cluster (not directly exercised in this single-node lab, but essential to
capture in any real backup) — treat it with the same care as the Secrets
from Exercise 13, since it's just as sensitive.

Start K3s back up:

```bash
sudo systemctl start k3s
kubectl get nodes
```

Same post-restart health check habit from Exercise 15/19 — confirm
`Ready` before continuing.

---

## Step 4: Export application manifests to YAML

```bash
kubectl get deployment nginx-deployment -n lab-apps -o yaml > ~/k3s-backup/nginx-deployment.yaml
kubectl get service nginx-clusterip -n lab-apps -o yaml > ~/k3s-backup/nginx-clusterip.yaml
```

Recall from Exercise 11, Step 9: this export includes server-generated
fields (`resourceVersion`, `uid`, `status`, …) alongside the parts you
actually wrote. That's fine for a backup — reapplying this file later
simply ignores or regenerates those fields — but it's worth remembering
you're exporting *live state*, not the clean, hand-authored manifest you
originally started from.

---

## Step 5: Back up actual application data

This is a fundamentally different kind of backup from Step 4 — data
sitting in a PersistentVolume, not a Kubernetes object definition. Using
the PostgreSQL deployment from Exercise 21, Track A:

```bash
sudo ls /mnt/lv_local_path
```

Identify the directory corresponding to `postgres-pvc` (from Exercise
21), then:

```bash
sudo tar czf ~/k3s-backup/postgres-data.tar.gz -C /mnt/lv_local_path <postgres-pvc-directory-name>
sudo chown "$(id -u)":"$(id -g)" ~/k3s-backup/postgres-data.tar.gz
```

For a real production database, you'd normally use the database's own
consistent backup tool (`pg_dump`, for PostgreSQL) rather than a raw file
copy — this file-level approach is used here specifically because it
follows directly from what Exercise 21 already taught about where
`local-path` actually stores data on disk.

---

## Step 6: Delete and restore an application from your manifest backup

```bash
kubectl delete deployment nginx-deployment -n lab-apps
kubectl delete service nginx-clusterip -n lab-apps
kubectl get deployment,service -n lab-apps
```

Both gone. Restore from the backup you took in Step 4:

```bash
kubectl apply -f ~/k3s-backup/nginx-deployment.yaml
kubectl apply -f ~/k3s-backup/nginx-clusterip.yaml
kubectl rollout status deployment/nginx-deployment -n lab-apps
```

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip
```

Serving the same ConfigMap-backed content from Exercise 12 — the
`nginx-html` ConfigMap itself was never deleted, only the Deployment and
Service, so this confirms both the restore worked and that it correctly
reconnected to configuration that never went away.

---

## Step 7: Test-restore the data backup

A backup you've never test-restored isn't a verified backup — extract it
somewhere safe and confirm it's actually intact and readable:

```bash
mkdir -p ~/k3s-backup/restore-test
tar xzf ~/k3s-backup/postgres-data.tar.gz -C ~/k3s-backup/restore-test
ls ~/k3s-backup/restore-test/*/
```

You should see real PostgreSQL data files (`PG_VERSION`, a `base/`
directory, and others) — proof the tarball is genuinely valid, not just a
file that exists. A real disaster-recovery restore would go further: scale
the `postgres` Deployment to `0` (Exercise 15), replace the live PVC
directory's contents with this extracted backup, then scale back up —
deliberately not performed live here, since overwriting a running
database's actual data directory is a genuinely destructive operation
worth rehearsing conceptually before ever doing it against something that
matters.

---

## Step 8: Cluster-state backups versus application-data backups

Two completely independent risks, each needing its own backup strategy:

| | Cluster-state backup (`state.db`) | Application-data backup (PVC contents) |
|---|---|---|
| Captures | Every object definition — every Deployment, Service, ConfigMap, Secret, RBAC rule, everything you've built in this entire lab | The actual bytes an application wrote to its own storage |
| Losing it means | The cluster itself has no memory of anything you ever created | The cluster is perfectly healthy, but an application's records are gone |
| Restored via | Replacing K3s's datastore file | Restoring files into a PVC's actual storage location |
| Demonstrated in | Step 3 (backup), Step 9 below (restore) | Step 5 (backup), Step 7 (restore verification) |

A backup plan covering only one of these is an incomplete backup plan —
Step 9 tests the first; Step 7 already tested the second.

---

## Step 9: A controlled recovery drill

Simulate real datastore loss, and confirm your Step 3 backup actually
recovers the whole cluster's state — not just one resource, everything.

```bash
sudo systemctl stop k3s
sudo mv /var/lib/rancher/k3s/server/db/state.db /var/lib/rancher/k3s/server/db/state.db.corrupted
sudo cp ~/k3s-backup/state.db /var/lib/rancher/k3s/server/db/state.db
sudo chown --reference=/var/lib/rancher/k3s/server/db/state.db.corrupted /var/lib/rancher/k3s/server/db/state.db
sudo systemctl start k3s
```

```bash
kubectl get nodes
kubectl get deployments -A
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Everything should be exactly as it was at the moment of the Step 3
backup — including `nginx-deployment` and `nginx-clusterip`, which you
deliberately deleted and restored from a YAML file in Step 6, *before*
this datastore backup was taken. If that restore genuinely worked, this
recovery drill proves it a second time, from a completely independent
angle: not from the YAML file this time, but from the datastore itself
remembering it.

Once you've confirmed everything is healthy, clean up the renamed backup
file:

```bash
sudo rm /var/lib/rancher/k3s/server/db/state.db.corrupted
```

---

## Recap

In this exercise, you:

- Identified K3s's SQLite datastore and understand why single-node K3s
  uses SQLite specifically, rather than etcd.

- Took a consistent backup of the datastore, the node token, and K3s's
  configuration, after stopping the service first.

- Exported live application manifests to YAML, and backed up actual PVC
  data using the on-disk location Exercise 21 taught you to find.

- Deleted and restored an application entirely from a manifest backup.

- Test-restored the data backup and confirmed it was genuinely valid,
  not just present.

- Built a clear mental model of cluster-state versus application-data
  backups as two independent risks needing two independent strategies.

- Ran a full, controlled recovery drill — replacing the live datastore
  with your own backup — and confirmed the entire cluster's state,
  including a resource you'd already restored once by other means, came
  back correctly.

---

**Previous:** [Exercise 31 — Failure Scenarios](31-failure-scenarios.md)

**Next:** [Exercise 33 — Final Troubleshooting Challenge](33-final-troubleshooting-challenge.md)
