# Exercise 17: Resource Requests and Limits

**Module:** Scheduling & Resources

**Prerequisite:** [Exercise 16 — Health Checks](16-health-checks.md)

---

## Introduction

The Kubernetes **scheduler** is the control-plane component responsible
for deciding which node a new Pod runs on — evaluating every node's
available capacity and any placement rules against what the Pod actually
needs. Without any resource configuration, a container can use as much CPU and
memory as the node has, and the scheduler has no real information to
decide whether a node can actually fit a new Pod. **Requests** are what a
container is guaranteed and what the scheduler uses to place it; **limits**
are a hard ceiling enforced at runtime. Confusing the two — or setting
neither — is one of the most common causes of both scheduling failures and
mysteriously killed containers.

---

## What you'll do

- Add CPU and memory requests and limits to `nginx-deployment`.
- Inspect allocated resources on the node.
- Deliberately exceed a memory limit and watch a container get
  `OOMKilled`.
- Deliberately request more memory than the node has, and watch a Pod get
  stuck `Pending` instead.
- Use `kubectl top` to see real usage, and compare it against requests.
- Confirm what's actually powering `kubectl top`: the bundled Metrics
  Server.

---

## Step 1: Add requests and limits

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: lab-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-deployment
  template:
    metadata:
      labels:
        app: nginx-deployment
    spec:
      containers:
        - name: nginx
          image: nginx:1.26
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          startupProbe:
            httpGet:
              path: /
              port: 80
            failureThreshold: 10
            periodSeconds: 3
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
      volumes:
        - name: html
          configMap:
            name: nginx-html
EOF
```

```bash
kubectl rollout status deployment/nginx-deployment -n lab-apps
kubectl get pods -n lab-apps -l app=nginx-deployment
```

`50m` means 5% of one CPU core; `64Mi`/`128Mi` are mebibytes. Confirm it
landed:

```bash
kubectl describe pod -n lab-apps -l app=nginx-deployment | grep -A4 "Requests:"
```

---

## Step 2: Inspect allocated resources on the node

```bash
kubectl describe node
```

Scroll to **Allocated resources** near the bottom — this is the same node
description from Exercise 1, but now with real numbers in it. It shows
total CPU/memory *requested* and *limited* across every Pod on the node,
each as a percentage of the node's allocatable capacity. This — not
`kubectl top`'s live usage — is what the scheduler actually checks before
placing a new Pod, which matters directly in Step 4.

---

## Step 3: Exceed a memory limit and watch OOMKilled happen

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: oom-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: stress
      image: polinux/stress
      command: ["stress"]
      args: ["--vm", "1", "--vm-bytes", "200M", "--vm-hang", "0"]
      resources:
        requests:
          memory: "50Mi"
        limits:
          memory: "50Mi"
EOF
```

This container deliberately tries to allocate 200MB while capped at 50Mi.
Wait a few seconds, then:

```bash
kubectl get pod oom-test -n lab-apps
```

`STATUS` should show `OOMKilled`. Look closer:

```bash
kubectl describe pod oom-test -n lab-apps
```

Under the container's `Last State`, look for `Reason: OOMKilled` and
`Exit Code: 137`. `137` is `128 + 9` — signal 9 is `SIGKILL`. This isn't
the application deciding to exit (contrast with `CrashLoopBackOff` from
Exercise 2, where the process exited on its own) — the Linux kernel's
cgroup memory controller killed it outright the instant it crossed the
limit, with no opportunity for the process to clean up or even log
anything about why.

Clean up:

```bash
kubectl delete pod oom-test -n lab-apps
```

---

## Step 4: Request more memory than the node has

```bash
kubectl run too-big-mem --image=nginx:1.27 --requests='memory=500Gi' -n lab-apps
```

```bash
kubectl get pod too-big-mem -n lab-apps
```

`STATUS` sits at `Pending` — a different failure entirely from Step 3.
This container was never even started; the scheduler refused to place it
anywhere in the first place.

```bash
kubectl describe pod too-big-mem -n lab-apps
```

In **Events**, look for the scheduler explaining exactly why:

```
0/1 nodes are available: 1 Insufficient memory.
```

This is the same category of failure from Exercise 2's `too-big` Pod
(`Insufficient cpu`), just triggered by memory this time — and directly
explained by the **Allocated resources** figures you looked at in Step 2:
the scheduler compared this request against the node's real allocatable
memory and rejected it before ever attempting to start a container.

Clean up:

```bash
kubectl delete pod too-big-mem -n lab-apps
```

---

## Step 5: `kubectl top` — real usage, not configured requests

```bash
kubectl top nodes
```

```bash
kubectl top pods -n lab-apps
```

This is genuinely different information from anything in Steps 1–2:
requests and limits are what you *configured*; `kubectl top` shows what's
*actually being consumed*, right now. Compare the real memory usage of
your `nginx-deployment` Pods against the `64Mi` request you gave them in
Step 1 — idle NGINX typically uses a fraction of that. Requests aren't a
prediction of real usage; they're a reservation, and it's completely
normal (and common) for real usage to sit well below them.

---

## Step 6: What's actually powering `kubectl top`

`kubectl top` isn't a built-in kubelet feature by itself — it queries a
separate aggregated API that has to be installed and running:

```bash
kubectl get deployment metrics-server -n kube-system
```

K3s bundles this by default — it's one of the four core `kube-system`
components mentioned all the way back in Exercise 1. Confirm it's
registered and healthy as an API extension:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```

`AVAILABLE` should read `True`. If this Deployment were ever missing or
unhealthy, `kubectl top` would fail outright with an error rather than
just showing stale data — worth remembering the next time `kubectl top`
doesn't respond the way you expect.

---

## Recap

In this exercise, you:

- Added CPU and memory requests and limits to `nginx-deployment`, and
  confirmed them with `kubectl describe`.

- Read the node's **Allocated resources** section and understand it's
  what the scheduler actually checks before placing a Pod.

- Exceeded a memory limit and watched a container get `OOMKilled` (exit
  code `137`) — a kernel-level kill, distinct from an application-level
  crash.

- Requested more memory than the node has, and watched the Pod get stuck
  `Pending` with a clear scheduler event explaining why — before any
  container was ever started.

- Used `kubectl top` to see real, live resource usage, and understand why
  it can (and normally does) differ from configured requests.

- Confirmed `kubectl top` depends entirely on the bundled Metrics Server
  being installed and healthy.

---

**Previous:** [Exercise 16 — Health Checks](16-health-checks.md)

**Next:** [Exercise 18 — Node Labels, Taints, and Scheduling](18-node-labels-taints-and-scheduling.md)
