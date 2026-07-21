# Exercise 18: Node Labels, Taints, and Scheduling

**Module:** Scheduling & Resources

**Prerequisite:** [Exercise 17 — Resource Requests and Limits](17-resource-requests-and-limits.md)

---

## Introduction

Exercise 17 covered *how much* of a node's resources the scheduler
requires before it'll place a Pod there. This exercise covers *which*
node — or whether a node is even eligible at all. Kubernetes gives you
several distinct mechanisms for influencing that decision: `nodeSelector`
and node **affinity** work from the Pod's side ("I want to run somewhere
matching this label," expressed either as a hard requirement or a soft
preference); **taints** and **tolerations** work from the node's side ("I
actively refuse Pods unless they explicitly say they can tolerate me").
Affinity attracts; taints repel — and this exercise covers both
directions.

With only one node, nothing in this exercise actually changes *where*
anything runs — there's nowhere else for it to go. What it does teach is
the mechanism itself: how the scheduler decides whether a given node is
even a candidate at all, using labels the node carries and rules the Pod
specifies. That mechanism is identical on a 1-node or a 1,000-node
cluster; only the outcome differs.

> **Before you start:** this exercise adds a taint to your only node in
> Step 4. A `NoSchedule` taint doesn't evict anything already running, but
> it **will** block any *new* Pod without a matching toleration — in this
> lab, that's every exercise after this one. Make sure you complete Step
> 7 (removing the taint) before moving on, even if you stop partway
> through.

---

## What you'll do

- Add labels to the node.
- Schedule a workload onto it with `nodeSelector`, and watch it fail
  cleanly when the label doesn't match.
- Use node affinity instead, and see the difference between a hard
  requirement and a soft preference.
- Taint the node, and watch an untolerated Pod get stuck `Pending`.
- Add a toleration and confirm the same Pod schedules despite the taint.
- Remove the taint and confirm normal scheduling returns.

---

## Step 1: Add labels to the node

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE_NAME" disktype=ssd environment=lab
kubectl get node "$NODE_NAME" --show-labels
```

These join the built-in labels you already reviewed back in Exercise 1.

---

## Step 2: Schedule with `nodeSelector`

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodeselector-demo
  namespace: lab-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nodeselector-demo
  template:
    metadata:
      labels:
        app: nodeselector-demo
    spec:
      nodeSelector:
        disktype: ssd
      containers:
        - name: nginx
          image: nginx:1.27
EOF
```

```bash
kubectl get pods -n lab-apps -l app=nodeselector-demo -o wide
```

`STATUS` should be `Running` — the only node available happens to satisfy
`disktype: ssd`. Now break it deliberately:

```bash
kubectl patch deployment nodeselector-demo -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/nodeSelector/disktype","value":"hdd"}]'
```

```bash
kubectl get pods -n lab-apps -l app=nodeselector-demo
```

The old Pod keeps running (changing the template doesn't touch existing
Pods until they're replaced), but any **new** one can't schedule. Force
one:

```bash
kubectl delete pod -n lab-apps -l app=nodeselector-demo
kubectl get pods -n lab-apps -l app=nodeselector-demo
```

The replacement sticks at `Pending`.

```bash
kubectl describe pod -n lab-apps -l app=nodeselector-demo
```

Events: `0/1 nodes are available: 1 node(s) didn't match Pod's node
affinity/selector.` — `nodeSelector` is a hard requirement; there's no
partial credit for a close-but-not-exact label match.

Fix it and clean up:

```bash
kubectl delete deployment nodeselector-demo -n lab-apps
```

---

## Step 3: Node affinity — a hard requirement, and a soft preference

Affinity is a more expressive version of the same idea, and it can be
either **required** (identical behavior to `nodeSelector`, just more
verbose) or **preferred** (a hint the scheduler tries to honor, but will
ignore rather than leave a Pod unschedulable).

Required, matching your `environment=lab` label from Step 1:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: affinity-required-demo
  namespace: lab-apps
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: environment
                operator: In
                values: ["lab"]
  containers:
    - name: nginx
      image: nginx:1.27
EOF
```

```bash
kubectl get pod affinity-required-demo -n lab-apps
```

`Running` — the label matches. Now a **preferred** affinity, deliberately
pointed at a label value that doesn't exist anywhere:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: affinity-preferred-demo
  namespace: lab-apps
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 1
          preference:
            matchExpressions:
              - key: environment
                operator: In
                values: ["does-not-exist"]
  containers:
    - name: nginx
      image: nginx:1.27
EOF
```

```bash
kubectl get pod affinity-preferred-demo -n lab-apps
```

Also `Running` — despite matching nothing. This is the entire point of
"preferred": it's a scheduling *hint*, not a requirement. With no node
that satisfies it, the scheduler simply falls back to placing it anywhere
valid, exactly the opposite behavior from the hard failure in Step 2.

Clean up:

```bash
kubectl delete pod affinity-required-demo affinity-preferred-demo -n lab-apps
```

---

## Step 4: Taint the node

```bash
kubectl taint node "$NODE_NAME" dedicated=lab-only:NoSchedule
kubectl describe node "$NODE_NAME" | grep Taints
```

Try scheduling an ordinary Pod, with nothing telling it about this taint:

```bash
kubectl run taint-test --image=nginx:1.27 -n lab-apps
kubectl get pod taint-test -n lab-apps
```

`Pending`.

```bash
kubectl describe pod taint-test -n lab-apps
```

Events: `0/1 nodes are available: 1 node(s) had untolerated taint
{dedicated: lab-only}.` A taint is the inverse of a `nodeSelector` — instead
of a Pod opting in to a node, the node itself is actively repelling every
Pod that doesn't explicitly say it's willing to tolerate this specific
taint.

```bash
kubectl delete pod taint-test -n lab-apps
```

---

## Step 5: Add a matching toleration

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: toleration-demo
  namespace: lab-apps
spec:
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "lab-only"
      effect: "NoSchedule"
  containers:
    - name: nginx
      image: nginx:1.27
EOF
```

```bash
kubectl get pod toleration-demo -n lab-apps
```

`Running` — same taint still in place from Step 4, but this Pod
explicitly declared it can tolerate it. Note what a toleration does
**not** do: it doesn't attract this Pod to the tainted node preferentially
(that would be affinity's job) — it only removes the taint as a
disqualifying reason. On a multi-node cluster, this Pod could still land
on any other, untainted node just as easily.

```bash
kubectl delete pod toleration-demo -n lab-apps
```

---

## Step 6: Remove the taint

```bash
kubectl taint node "$NODE_NAME" dedicated=lab-only:NoSchedule-
```

The trailing `-` removes a taint rather than adding one. Confirm:

```bash
kubectl describe node "$NODE_NAME" | grep Taints
```

Should read `Taints: <none>` again. Confirm scheduling is back to normal
with one more ordinary Pod:

```bash
kubectl run taint-test --image=nginx:1.27 -n lab-apps --restart=Never
kubectl get pod taint-test -n lab-apps
kubectl delete pod taint-test -n lab-apps
```

`Running`, with no toleration needed.

---

## Recap

In this exercise, you:

- Labeled the node, and used `nodeSelector` to require a matching label —
  and watched scheduling fail cleanly, with a clear event, the moment the
  label no longer matched.

- Used node affinity to express the same hard requirement more expressively,
  and then used a **preferred** affinity to see the opposite behavior: a
  mismatch that doesn't block scheduling at all, just gets ignored.

- Tainted the node and watched an ordinary Pod get stuck `Pending`, with
  an event explicitly naming the untolerated taint.

- Added a toleration and confirmed the exact same taint no longer blocked
  scheduling — and understand that a toleration permits, but doesn't
  attract.

- Removed the taint and confirmed normal scheduling returned to the
  cluster before moving on.

---

**Previous:** [Exercise 17 — Resource Requests and Limits](17-resource-requests-and-limits.md)

**Next:** [Exercise 19 — Single-Node Maintenance](19-single-node-maintenance.md)
