# Exercise 1: Cluster Orientation

**Module:** Foundations

**Prerequisite:** K3s installed and `kubectl` working from your own user
([K3s/Headlamp Install §1](../K3S-HEADLAMP-INSTALL.md#1-installing-k3s)).

---

## Introduction

**Kubernetes** is a system for running containerized applications across
one or more machines (**nodes**) and keeping them running the way you've
declared they should run, even as individual processes crash or machines
reboot. A Kubernetes **cluster** is one control plane (the "brain" —
scheduling decisions, API, cluster state) plus every node it manages. In a
typical production cluster, the control plane runs on its own dedicated
node(s), separate from the nodes that actually run application workloads.

**K3s** is a single, small binary that bundles a fully conformant
Kubernetes distribution — control plane, kubelet, container runtime, and
a few batteries-included extras (a CNI, an ingress controller, a
lightweight load balancer) — with far lower resource and operational
overhead than a full "vanilla" Kubernetes install. This lab runs it on
exactly **one** node, meaning that single machine plays both roles at
once: control plane and workload host. Almost everything you'll learn
generalizes directly to a bigger, multi-node cluster; the exercises are
explicit whenever single-node status changes the picture (as with
DaemonSets and node maintenance, later in this lab).

Before touching any workloads, get comfortable looking at the cluster
itself.

Every exercise after this one assumes you can quickly answer three
questions on your own: *is the cluster healthy, what does it look like right
now, and where would I look if something were wrong.*

This exercise is entirely read-only — you won't create or change anything.
The goal is just to build the habit of checking, not to memorize output.

---

## What you'll do

- Confirm the K3s service itself is healthy at the systemd level.
- Confirm the Kubernetes node is healthy at the cluster level.
- Read a node's full description and understand what each section means.
- Check version information for both Kubernetes and K3s.
- Understand why this single node is also the control plane.
- Look at what namespaces exist out of the box, and why.
- See the limits of `kubectl get all -A` as a "show me everything" command.

---

## Step 1: Check the K3s service

K3s runs as a systemd service on the host. Before you ever ask Kubernetes
whether something is wrong, it's worth confirming the underlying service is
even up.

```bash
sudo systemctl status k3s --no-pager
```

Look for:

- `Active: active (running)` — the service is up.
- The `Main PID` and recent log lines below it — if K3s were crash-looping
  at the systemd level, you'd see repeated restarts here, before Kubernetes
  itself ever gets a chance to report anything.

If this command shows anything other than `active (running)`, everything
below it will fail or hang — so it's always the first thing to check, not
`kubectl`.

---

## Step 2: Confirm the node is Ready

```bash
kubectl get nodes
```

Expected output looks like:

```
NAME   STATUS   ROLES                  AGE   VERSION
k3     Ready    control-plane,master   45m   v1.36.2+k3s1
```

The column to focus on is `STATUS`. `Ready` means the kubelet on this node
has told the control plane it's healthy and able to accept workloads.

Other values you might see later in the lab (not now): `NotReady`,
`SchedulingDisabled` (after a `cordon`), or the node missing entirely (if
K3s itself is down).

---

## Step 3: Describe the node in full

```bash
kubectl describe node
```

(With only one node, you can omit the node name — `kubectl describe node`
will use it by default. On a multi-node cluster you'd need
`kubectl describe node <name>`.)

This is a long output. Read it in sections rather than top to bottom:

**Labels** — near the top. These are how the scheduler identifies and
selects nodes. You'll use these directly in the Scheduling exercise later.

**Taints** — also near the top, often `<none>`. Taints repel pods unless
they have a matching toleration. Notice K3s does **not** taint its
control-plane node the way a full `kubeadm` cluster normally would — that's
why regular workloads can run here at all, despite this node also being the
control plane.

**Conditions** — near the middle. Look for `Ready: True`, and confirm
`MemoryPressure`, `DiskPressure`, and `PIDPressure` are all `False`. These
flip when the node is under real resource strain — worth remembering for
later when you intentionally exhaust memory in the Resource Requests and
Limits exercise.

**Capacity / Allocatable** — how much CPU and memory the node has in total
(`Capacity`), versus how much Kubernetes can actually hand out to pods
(`Allocatable`, slightly lower — some is reserved for the OS and Kubernetes'
own components).

**Non-terminated Pods** — a table near the bottom showing every pod
currently on this node and what it has requested/limited. On a single-node
cluster, this is literally every pod in the cluster.

---

## Step 4: Check versions

```bash
kubectl version
```

This prints both the **Client Version** (the `kubectl` binary you're
running) and the **Server Version** (the Kubernetes version the K3s API
server is running). They can differ slightly — that's normal and supported
within a version skew window; it's only a problem if they're far apart.

```bash
k3s --version
```

This shows the K3s-specific version string, plus the version of the bundled
Go runtime it was built with. K3s wraps a specific upstream Kubernetes
release — the `+k3s1` suffix on the version string identifies K3s's own
patch level on top of that upstream release.

---

## Step 5: Inspect CPU, memory, and role labels directly

Rather than reading the whole `describe` output again, pull specific fields
directly — this is a preview of the CLI-efficiency techniques you'll use
constantly later in the lab.

```bash
kubectl get node -o jsonpath='{.items[0].status.capacity}'
echo

kubectl get node -o jsonpath='{.items[0].status.allocatable}'
echo

kubectl get node --show-labels
```

In `--show-labels`, look specifically for:

- `node-role.kubernetes.io/control-plane=true`
- `node-role.kubernetes.io/master=true` (an older, still-present alias)

Both are just labels — nothing magical distinguishes a "control-plane node"
under the hood beyond these labels plus the control-plane pods (API server,
scheduler, controller-manager) actually running on it. On this single-node
lab, everything happens to run in one place.

---

## Step 6: Review the namespaces K3s creates by default

```bash
kubectl get namespaces
```

You should see:

- `default` — where resources land if you don't specify a namespace.
- `kube-system` — where K3s's own components live (CoreDNS, Traefik,
  metrics-server, the local-path provisioner, and — if you completed the
  [K3s/Headlamp Install guide](../K3S-HEADLAMP-INSTALL.md) §2 — Headlamp).
- `kube-public` — readable by all users (including unauthenticated ones);
  used for cluster-wide public information. Normally empty in practice.
- `kube-node-lease` — holds a lightweight "lease" object per node, used for
  node heartbeats. Faster and cheaper than the old heartbeat mechanism of
  updating the full Node object on every check-in.

You'll create your own namespace for lab workloads in the Namespaces
exercise later.

---

## Step 7: List resources across all namespaces

```bash
kubectl get all -A
```

Right now this should show mostly `kube-system` pods, services, and
deployments — plus your own `my-headlamp` resources if you installed
Headlamp.

**Important caveat, worth internalizing now:** despite the name, `get all`
does **not** mean literally everything in the cluster. It only covers a
fixed, curated set of common resource types (Pods, Services, Deployments,
ReplicaSets, StatefulSets, DaemonSets, Jobs, CronJobs, and a few others).

It does **not** include ConfigMaps, Secrets, PersistentVolumeClaims,
Ingresses, ServiceAccounts, or Roles — all of which you'll work with
directly in later exercises. If you ever go looking for a resource with
`get all -A` and don't find it, that's very likely why — not because it
doesn't exist.

---

## Recap

In this exercise, you:

- Confirmed K3s is healthy at the systemd level, before ever touching
  `kubectl`.

- Confirmed the node is `Ready` at the Kubernetes level, and know what that
  status actually represents.

- Read a full `kubectl describe node`, and know what each section (Labels,
  Taints, Conditions, Capacity/Allocatable, Non-terminated Pods) tells you.

- Checked both the Kubernetes client/server version and the K3s-specific
  version.

- Confirmed this single node carries the control-plane role via labels, and
  understood why K3s leaves it schedulable rather than tainting it.

- Reviewed the four namespaces K3s creates automatically, and what each one
  is for.

- Learned that `kubectl get all -A` is a curated shortcut, not a literal
  "everything" command — and which common resource types it leaves out.

---

**Next:** [Exercise 2 — Pods and Basic Workloads](02-pods-and-basic-workloads.md)
