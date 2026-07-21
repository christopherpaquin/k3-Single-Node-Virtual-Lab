# Exercise 19: Single-Node Maintenance

**Module:** Scheduling & Resources

**Prerequisite:** [Exercise 18 — Node Labels, Taints, and Scheduling](18-node-labels-taints-and-scheduling.md)

---

## Introduction

**Cordoning** a node marks it unschedulable — the scheduler stops placing
*new* Pods there, but anything already running is left untouched.
**Draining** goes further: it cordons the node, then actively evicts every
existing Pod from it, trusting their controllers (Deployments,
StatefulSets, etc.) to reschedule them elsewhere. Together, `cordon` and
`drain` are routine, low-drama maintenance operations on a
real multi-node cluster — you take one node out of rotation, its
workloads shift to the others, you patch/reboot/replace it, and put it
back. On a single-node cluster, there's nowhere for anything to shift to,
which turns `drain` specifically into a full, if temporary, cluster
outage. That's worth experiencing directly, once, in a controlled way,
rather than discovering it by surprise.

> **Before you start:** Step 4 (`kubectl drain`) briefly disrupts **every**
> workload in the cluster — not just your own lab resources, but Traefik,
> CoreDNS, Headlamp, and everything else in `kube-system` too. It fully
> recovers once you `uncordon`, but don't start this exercise if you're
> not prepared for a few minutes of total cluster downtime.

---

## What you'll do

- Cordon the node and confirm new Pods can't schedule, while existing
  ones keep running untouched.
- Uncordon it and confirm scheduling returns to normal.
- Drain the node with a temporary workload in place, and see exactly how
  disruptive that is with nowhere else for anything to go.
- Uncordon and confirm the entire cluster recovers on its own.
- Run a quick post-maintenance health check — the same idea as Exercise
  15, applied here as a habit rather than a deep investigation.

---

## Step 1: Cordon the node

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl cordon "$NODE_NAME"
kubectl get nodes
```

`STATUS` now reads `Ready,SchedulingDisabled` — a status mentioned back in
Exercise 1 without you having seen it yet. Cordoning only blocks **new**
scheduling; it does nothing to what's already running:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Still `Running`, untouched.

---

## Step 2: Confirm new workloads can't schedule

```bash
kubectl run cordon-test --image=nginx:1.27 -n lab-apps --restart=Never
kubectl get pod cordon-test -n lab-apps
```

`Pending`.

```bash
kubectl describe pod cordon-test -n lab-apps
```

Events: `0/1 nodes are available: 1 node(s) were unschedulable.` — a
different, more specific message than the "insufficient resources" or
"untolerated taint" events from earlier exercises, even though the
practical effect (stuck `Pending`) looks the same from `kubectl get pods`
alone.

```bash
kubectl delete pod cordon-test -n lab-apps
```

---

## Step 3: Uncordon and confirm recovery

```bash
kubectl uncordon "$NODE_NAME"
kubectl get nodes
```

`STATUS` back to plain `Ready`. Confirm scheduling actually works again:

```bash
kubectl run cordon-test --image=nginx:1.27 -n lab-apps --restart=Never
kubectl get pod cordon-test -n lab-apps
kubectl delete pod cordon-test -n lab-apps
```

`Running` this time.

---

## Step 4: Drain the node, with a temporary workload in place

Create something disposable to watch get disrupted, rather than using
`nginx-deployment`:

```bash
kubectl create deployment drain-demo --image=nginx:1.27 --replicas=2 -n lab-apps
kubectl rollout status deployment/drain-demo -n lab-apps
```

Now drain the node:

```bash
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data
```

- `--ignore-daemonsets` is required on almost every real cluster too — a
  DaemonSet (like the `svclb-traefik` Pod from Exercise 5) is designed to
  run on every node permanently, so `drain` refuses to touch it unless
  told explicitly not to worry about it.
- `--delete-emptydir-data` is required if anything is using a temporary
  `emptyDir` volume, whose data can't be preserved anywhere else.

`drain` cordons the node (Step 1's behavior) and then actively **evicts**
every evictable Pod on it — including, on this single-node cluster,
essentially everything: `drain-demo`, `nginx-deployment`, and every
Deployment-managed Pod in `kube-system` (Traefik, CoreDNS, Headlamp,
metrics-server) as well.

```bash
kubectl get pods -A -o wide
```

You'll see a large number of Pods stuck `Pending` — their controllers
immediately tried to replace the evicted ones, exactly like Exercise 3
and Exercise 15, except this time there is nowhere for any replacement to
go, because the only node in the cluster is both cordoned and just had
everything evicted from it. This is the entire lesson: `drain` isn't
disruptive by design — rescheduling elsewhere is normally instant and
invisible. It's only disruptive **here**, specifically because "elsewhere"
doesn't exist.

---

## Step 5: Uncordon and confirm the cluster recovers on its own

```bash
kubectl uncordon "$NODE_NAME"
```

Give it a minute, then check broadly:

```bash
kubectl get nodes
kubectl get pods -A | grep -v Running
```

That second command should return little to nothing (a `Completed`
Helm-install Job or two is normal and fine — those are one-shot Jobs, not
something that's supposed to stay `Running`). Everything else should have
rescheduled back onto the node automatically, the same self-healing
behavior from Exercise 15 — nothing here required you to manually recreate
a single Pod.

Clean up the temporary Deployment:

```bash
kubectl delete deployment drain-demo -n lab-apps
```

---

## Step 6: A post-maintenance health check habit

Exercise 15 already covered *why* K3s restarts and host reboots recover
the way they do, in depth. The practical habit worth carrying forward from
both that exercise and this one is a quick, consistent check after
**any** maintenance operation — cordon, drain, a service restart, a
reboot — rather than assuming it went cleanly:

```bash
sudo systemctl restart k3s
```

Then, once it responds again:

```bash
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get deployments -A
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip
```

Node `Ready`, nothing unexpected outside `Running`/`Completed`, every
Deployment at full desired replica count, and the application itself
actually answering a real request — that combination is a genuinely
reliable signal the cluster came back cleanly, worth running as a matter
of habit after any of the operations in this exercise or Exercise 15.

---

## Recap

In this exercise, you:

- Cordoned the node and confirmed it blocks new scheduling without
  touching already-running Pods.

- Confirmed the exact scheduler event a cordoned node produces, and how
  it differs in wording from insufficient-resources or untolerated-taint
  failures.

- Drained the node with a temporary workload running, and watched
  essentially the entire cluster — not just your own resources — get
  evicted with nowhere to reschedule to.

- Uncordoned the node and confirmed the whole cluster recovered on its
  own, with no manual recreation needed.

- Built a short, repeatable post-maintenance health check you can reapply
  after any disruptive operation, in this exercise or Exercise 15.

---

**Previous:** [Exercise 18 — Node Labels, Taints, and Scheduling](18-node-labels-taints-and-scheduling.md)

**Next:** [Exercise 20 — Jobs and CronJobs](20-jobs-and-cronjobs.md)
