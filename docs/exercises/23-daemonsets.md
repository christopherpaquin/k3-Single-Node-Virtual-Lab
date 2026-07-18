# Exercise 23: DaemonSets

**Module:** Workload Types

**Prerequisite:** [Exercise 22 — StatefulSets](22-statefulsets.md)

---

## Theme

A Deployment answers "run N copies of this, spread across the cluster." A
**DaemonSet** answers a completely different question: "run exactly one
copy of this on every node that qualifies — no more, no fewer, and
automatically on any new node that joins later." You've already been
running one, without creating it yourself — the `svclb-traefik` Pod from
Exercise 5.

This lab's biggest limitation for this particular topic is unavoidable: a
DaemonSet's real value only shows up on a cluster with more than one node.
This exercise demonstrates the mechanics honestly, on the one node
available, and is explicit about what it can't show.

---

## What you'll do

- Inspect the DaemonSets already running in your cluster.
- Deploy your own, and confirm it creates exactly one Pod — with no
  `replicas` field involved at all.
- Add a node selector that matches, then change it so it doesn't — and
  see how differently a DaemonSet responds compared to a Deployment.
- Review real-world DaemonSet use cases.
- Understand exactly what a single-node lab can't demonstrate about them.

---

## Step 1: Inspect existing DaemonSets

```bash
kubectl get daemonset -A
```

You should see `svclb-traefik-*` in `kube-system` — the same Pod you
inspected directly back in Exercise 5. K3s's CNI (Flannel) runs bundled
inside the K3s binary itself here, rather than as a separate DaemonSet the
way it would on a typical `kubeadm`-built cluster — so this is likely the
only one present out of the box.

---

## Step 2: Deploy your own DaemonSet

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent-demo
  namespace: lab-apps
spec:
  selector:
    matchLabels:
      app: node-agent-demo
  template:
    metadata:
      labels:
        app: node-agent-demo
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "while true; do echo agent running on $(hostname); sleep 30; done"]
EOF
```

Notice what's **absent** from this spec compared to every Deployment
you've written in this lab: no `replicas` field anywhere. A DaemonSet
doesn't have one — its Pod count is entirely a function of how many nodes
match its scheduling constraints, not a number you configure directly.

```bash
kubectl get daemonset node-agent-demo -n lab-apps
```

`DESIRED`, `CURRENT`, and `READY` should all read `1` — because there's
exactly one qualifying node, not because you asked for one.

```bash
kubectl get pods -n lab-apps -l app=node-agent-demo -o wide
```

---

## Step 3: Add a node selector that matches

Reuse the `disktype=ssd` label you added to the node back in Exercise 18:

```bash
kubectl patch daemonset node-agent-demo -n lab-apps --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"disktype":"ssd"}}]'
```

```bash
kubectl get pods -n lab-apps -l app=node-agent-demo
```

Still one Pod, still `Running` — the label matches.

---

## Step 4: Change the selector so it no longer matches

```bash
kubectl patch daemonset node-agent-demo -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/nodeSelector/disktype","value":"hdd"}]'
```

```bash
kubectl get pods -n lab-apps -l app=node-agent-demo
```

No output at all — not a stuck `Pending` Pod. This is a real, worthwhile
distinction from every other workload type in this lab: a DaemonSet
controller checks each node's eligibility **before** deciding whether to
create a Pod there in the first place, rather than creating one and
letting the scheduler discover the mismatch afterward (which is exactly
what happened with the Deployment `nodeSelector` in Exercise 18, and
produced a visible `Pending` Pod there). No matching node means no Pod
object is created for it at all.

Fix it:

```bash
kubectl patch daemonset node-agent-demo -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/nodeSelector/disktype","value":"ssd"}]'
kubectl get pods -n lab-apps -l app=node-agent-demo
```

Back to one Pod.

---

## Step 5: Where DaemonSets are actually used

All of the following share the same underlying shape: "exactly one
instance, on every node, tied to that node's own resources" — a pattern
a Deployment has no good way to express at all:

- **Monitoring agents** — a metrics exporter (like `node-exporter`) that
  needs to read *that specific node's* CPU, memory, and disk stats.
- **Log collectors** — something like Fluentd or Fluent Bit, reading log
  files that physically live on that node's own disk.
- **Networking agents** — CNI plugins (Flannel, Calico, Cilium), normally
  deployed exactly this way on non-K3s clusters.
- **Storage agents** — CSI node plugins for systems like Ceph or Longhorn,
  which need a local process on every node to handle mounts.
- **Security agents** — runtime security tools (e.g. Falco) that inspect
  syscalls or container activity happening directly on that node.

---

## What a single-node lab can't show you

Everything above ran with `DESIRED`/`CURRENT`/`READY` permanently stuck at
`1`. The actual payoff of a DaemonSet — a brand-new node joining the
cluster and automatically, with zero manual action, getting its own copy
of every DaemonSet-managed Pod (and a node being removed cleanly taking
its copy with it) — has no way to happen here, because there is only ever
one node for it to run on. Worth knowing honestly as a limitation of this
lab, not something to assume you've fully verified.

---

## Clean up

```bash
kubectl delete daemonset node-agent-demo -n lab-apps
```

---

## Recap

In this exercise, you:

- Found the DaemonSet already running in your cluster from Exercise 5,
  and confirmed K3s runs its own CNI differently from a typical
  DaemonSet-based one.

- Deployed your own DaemonSet, and noticed it has no `replicas` field at
  all — its count is derived entirely from node eligibility.

- Added a matching node selector, then changed it to a non-matching one,
  and saw a DaemonSet respond by simply not creating a Pod at all —
  rather than creating one and leaving it `Pending`, the way a Deployment
  did in Exercise 18.

- Reviewed real-world DaemonSet use cases, all sharing the same
  "one-per-node, tied to that node's own resources" shape.

- Understand exactly which part of DaemonSet behavior this lab's
  single-node limitation prevents you from actually observing.

---

**Previous:** [Exercise 22 — StatefulSets](22-statefulsets.md)

**Next:** [Exercise 24 — Multi-Container Pods](24-multi-container-pods.md)
