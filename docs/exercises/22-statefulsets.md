# Exercise 22: StatefulSets

**Module:** Workload Types

**Prerequisite:** [Exercise 21 — Local Storage](21-local-storage.md)

---

## Introduction

Exercise 3 introduced Deployments as the right tool for **stateless**
workloads — every replica interchangeable, none holding unique data, any
one freely replaceable by a new one with a random name. A **StatefulSet**
is the Kubernetes workload controller built for the opposite case:
**stateful** applications — clustered databases (PostgreSQL, MySQL,
Cassandra), message queues (Kafka, RabbitMQ), or anything else where each
replica is *not* interchangeable, because each one owns its own distinct
data and, often, needs to know its own identity relative to its peers
(e.g. "I am replica 0, the primary" versus "I am replica 1, a follower").

A StatefulSet provides exactly the three guarantees that kind of
application needs, none of which a Deployment gives you:

- **Stable, predictable Pod names** (`web-0`, `web-1`, `web-2` — not a
  random hash suffix), so other systems can address one specific replica
  by name and have that name mean the same thing after a restart.
- **A dedicated PersistentVolumeClaim per replica**, automatically
  recreated and reattached to the *same* replica if its Pod is deleted and
  replaced — not a volume shared across every replica.
- **Ordered, sequential startup and shutdown** (always low-to-high
  ordinal on scale-up, high-to-low on scale-down), which matters for
  applications where replica 0 must exist before replica 1 can safely join
  a cluster, for example.

This exercise uses plain NGINX (not a real database) specifically to keep
the focus on the *mechanics* StatefulSets provide, not on operating any
particular stateful application.

---

## What you'll do

- Deploy a StatefulSet behind a headless Service.
- Compare its Pod naming directly against a Deployment's.
- Scale it up and down, and observe the order Pods are created and
  removed in — not arbitrary, unlike a Deployment.
- Confirm each replica gets its own dedicated PVC, not a shared one.
- Delete a specific replica and confirm its replacement reconnects to
  that exact same PVC.
- Review why PVCs deliberately outlive the StatefulSet itself.

---

## Step 1: Deploy a StatefulSet

StatefulSets require a headless Service (`clusterIP: None`) to provide
each Pod's stable network identity:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: lab-apps
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - port: 80
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
  namespace: lab-apps
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 500Mi
EOF
```

```bash
kubectl rollout status statefulset/web -n lab-apps
```

---

## Step 2: Compare StatefulSet Pod names against a Deployment's

```bash
kubectl get pods -n lab-apps -l app=web
```

`web-0`, `web-1`, `web-2` — predictable, ordinal-indexed names. Compare
against your Deployment:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Random hash suffixes, with no meaningful order — completely interchangeable
by design. A StatefulSet's names are a **feature**, not an implementation
detail: delete `web-1` specifically, and its replacement will also be
named `web-1` — you'll prove that directly in Step 5.

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | Random suffix, interchangeable | Stable, ordinal (`-0`, `-1`, `-2`, …) |
| Storage | Shared or none | One dedicated PVC per replica |
| Creation/deletion order | Unordered, parallel | Strictly ordered |
| Typical use | Stateless web apps, APIs | Databases, queues, anything needing stable identity |

---

## Step 3: Scale up and down, and watch the order

```bash
kubectl scale statefulset web -n lab-apps --replicas=5
kubectl get pods -n lab-apps -l app=web -w
```

You should see `web-3` reach `Running` before `web-4` even starts being
created — unlike a Deployment's ReplicaSet, which creates every new
replica in parallel. `Ctrl+C` once both are `Running`.

Now scale down:

```bash
kubectl scale statefulset web -n lab-apps --replicas=2
kubectl get pods -n lab-apps -l app=web -w
```

`web-4` terminates first, then `web-3` — **highest ordinal first**,
leaving `web-0` and `web-1` behind. `Ctrl+C` once it settles. The rule is
symmetric and consistent: StatefulSets always create low-to-high, and
always remove high-to-low. Nothing about a Deployment gives you any such
guarantee about which specific replica gets removed on a scale-down.

Scale back to 3:

```bash
kubectl scale statefulset web -n lab-apps --replicas=3
kubectl rollout status statefulset/web -n lab-apps
```

---

## Step 4: Each replica gets its own PVC

```bash
kubectl get pvc -n lab-apps
```

Look for `data-web-0`, `data-web-1`, `data-web-2` — the naming pattern is
`<volumeClaimTemplate-name>-<pod-name>`. Each is a completely separate PVC,
not one shared volume — this is the piece a Deployment has no equivalent
for at all.

Write distinct data to each replica:

```bash
kubectl exec web-0 -n lab-apps -- sh -c "echo 'I am web-0' > /usr/share/nginx/html/index.html"
kubectl exec web-1 -n lab-apps -- sh -c "echo 'I am web-1' > /usr/share/nginx/html/index.html"
kubectl exec web-2 -n lab-apps -- sh -c "echo 'I am web-2' > /usr/share/nginx/html/index.html"
```

```bash
kubectl exec web-0 -n lab-apps -- cat /usr/share/nginx/html/index.html
kubectl exec web-1 -n lab-apps -- cat /usr/share/nginx/html/index.html
kubectl exec web-2 -n lab-apps -- cat /usr/share/nginx/html/index.html
```

Three distinct answers, from three replicas of the exact same image and
spec — proof each has its own independent storage.

---

## Step 5: Delete a specific replica and confirm it reconnects to its storage

```bash
kubectl delete pod web-1 -n lab-apps
kubectl get pods -n lab-apps -l app=web -w
```

`Ctrl+C` once the replacement reaches `Running`. Note its name: **still**
`web-1` — not a new random name the way a Deployment's replacement would
get. Confirm it reconnected to the same PVC, with the same data:

```bash
kubectl exec web-1 -n lab-apps -- cat /usr/share/nginx/html/index.html
```

Still `I am web-1` — the new Pod, despite being a completely fresh
container, was reattached to `data-web-1` automatically, purely because it
carries the same stable identity as the Pod it replaced.

---

## Step 6: PVCs deliberately outlive the StatefulSet

```bash
kubectl delete statefulset web -n lab-apps
kubectl get pods -n lab-apps -l app=web
kubectl get pvc -n lab-apps
```

Every Pod is gone — but `data-web-0`, `data-web-1`, and `data-web-2` are
all still there. This is deliberate, not an oversight: deleting a
StatefulSet is a common, low-stakes operation (recreating it brings the
exact same Pods back, reattached to the exact same storage), while
deleting the underlying data is a much bigger, harder-to-reverse decision
that Kubernetes refuses to make on your behalf implicitly.

Clean up fully, including storage this time:

```bash
kubectl delete pvc data-web-0 data-web-1 data-web-2 -n lab-apps
kubectl delete service web-headless -n lab-apps
```

---

## Recap

In this exercise, you:

- Deployed a StatefulSet behind a headless Service, and compared its
  stable, ordinal Pod names against a Deployment's random ones.

- Scaled up and down, and confirmed StatefulSets always create low-to-high
  and remove high-to-low — a strict, predictable order a Deployment
  doesn't provide.

- Confirmed each replica gets its own dedicated PVC, and wrote distinct
  data to each to prove it.

- Deleted a specific replica and confirmed its replacement kept the same
  name and reconnected to the exact same storage automatically.

- Deleted the StatefulSet itself and confirmed its PVCs survived — a
  deliberate safety boundary between removing the workload and removing
  its data.

---

**Previous:** [Exercise 21 — Local Storage](21-local-storage.md)

**Next:** [Exercise 23 — DaemonSets](23-daemonsets.md)
