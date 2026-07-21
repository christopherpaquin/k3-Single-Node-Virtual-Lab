# Exercise 24: Multi-Container Pods

**Module:** Workload Types

**Prerequisite:** [Exercise 23 — DaemonSets](23-daemonsets.md)

---

## Introduction

Exercise 2 introduced the Pod as potentially holding more than one
container; every exercise since has used exactly one. This exercise
returns to that multi-container capability directly. A Pod can hold
several containers, sharing the same network namespace and, optionally,
storage — the foundation of two distinct, common patterns: the
**sidecar** pattern (a helper container running alongside the main one,
for the Pod's *entire* lifetime — e.g. a log shipper, a proxy, a
certificate refresher) and **init containers** (helpers that run once, in
a defined order, *before* the main containers ever start, and must all
succeed first — e.g. waiting for a dependency, running a one-time setup
step). The difference is lifetime and timing: a sidecar runs continuously
alongside the app; an init container runs once and is done before the app
begins.

---

## What you'll do

- Create a Pod with two containers sharing an `emptyDir` volume.
- View logs from, and exec into, one specific container at a time.
- Confirm the shared volume is genuinely live-shared, not just
  configured.
- Use an init container to prepare content before the main container
  starts.
- Watch the distinct Pod states an init container introduces.
- Deliberately fail an init container, and confirm the main container
  never starts at all.

---

## Step 1: A Pod with two containers sharing storage

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
  namespace: lab-apps
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      volumeMounts:
        - name: shared
          mountPath: /usr/share/nginx/html
    - name: content-writer
      image: busybox:1.36
      command: ["sh", "-c", "while true; do echo \"Updated at $(date)\" > /data/index.html; echo wrote update; sleep 10; done"]
      volumeMounts:
        - name: shared
          mountPath: /data
  volumes:
    - name: shared
      emptyDir: {}
EOF
```

Two containers, one shared `emptyDir` volume mounted at two different
paths — `content-writer` continuously updates a file, and `nginx` serves
whatever's currently there.

---

## Step 2: Logs and exec, one container at a time

```bash
kubectl logs sidecar-demo -n lab-apps -c content-writer
```

You should see `wrote update` lines appearing every 10 seconds.

```bash
kubectl logs sidecar-demo -n lab-apps -c nginx
```

Empty (or close to it) — `nginx` hasn't been asked to serve anything yet.
Exec into a specific container the same way — `-c` isn't just for logs:

```bash
kubectl exec -it sidecar-demo -n lab-apps -c nginx -- sh -c "cat /usr/share/nginx/html/index.html"
```

---

## Step 3: Confirm the shared volume is genuinely live

```bash
kubectl get pod sidecar-demo -n lab-apps -o jsonpath='{.status.podIP}'
echo
```

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s <pod-ip>
```

Wait at least 10 seconds, then run that `curl-test` command again. The
timestamp in the response should have changed — `nginx` is serving
content it never wrote itself, produced entirely by the other container,
through nothing but a shared directory both happen to have mounted. This
is the sidecar pattern in its simplest possible form.

Clean up:

```bash
kubectl delete pod sidecar-demo -n lab-apps
```

---

## Step 4: An init container that prepares content once

An init container runs to completion **before** any regular container in
the Pod starts — useful for one-time setup, as opposed to a sidecar's
continuous, whole-lifetime presence:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
  namespace: lab-apps
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo 'Prepared by init container' > /data/index.html"]
      volumeMounts:
        - name: shared
          mountPath: /data
  containers:
    - name: nginx
      image: nginx:1.27
      volumeMounts:
        - name: shared
          mountPath: /usr/share/nginx/html
  volumes:
    - name: shared
      emptyDir: {}
EOF
```

Watch it come up:

```bash
kubectl get pod init-demo -n lab-apps -w
```

You should briefly catch `Init:0/1` and then `PodInitializing` before it
settles on `Running` — states you haven't seen anywhere else in this lab,
specific to the init-container phase. `Ctrl+C` once it's `Running`.

The init container already exited, but its logs are still retrievable,
the same way a completed Job's Pod logs still were in Exercise 20:

```bash
kubectl logs init-demo -n lab-apps -c setup
```

Confirm `nginx` is serving what it prepared:

```bash
kubectl exec init-demo -n lab-apps -c nginx -- cat /usr/share/nginx/html/index.html
```

Clean up:

```bash
kubectl delete pod init-demo -n lab-apps
```

---

## Step 5: A failing init container blocks everything

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: init-fail-demo
  namespace: lab-apps
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo 'failing on purpose'; exit 1"]
  containers:
    - name: nginx
      image: nginx:1.27
EOF
```

```bash
kubectl get pod init-fail-demo -n lab-apps
```

`STATUS` shows something like `Init:Error` or, after a few automatic
retries, `Init:CrashLoopBackOff` — the same backoff behavior from
Exercise 2's `CrashLoopBackOff`, just applied to the init phase instead
of a regular container.

```bash
kubectl logs init-fail-demo -n lab-apps -c setup
```

`failing on purpose` — the init container's own output, same as any other
container's logs.

```bash
kubectl describe pod init-fail-demo -n lab-apps
```

Look at the `nginx` container's state specifically — it should show
`Waiting: PodInitializing`, indefinitely. This is the core rule: init
containers run **in order**, and every single one must succeed before any
regular container is even started — not "started but unhealthy," not
"started and retried," genuinely never started at all, for as long as the
init container keeps failing.

Clean up:

```bash
kubectl delete pod init-fail-demo -n lab-apps
```

---

## Recap

In this exercise, you:

- Created a Pod with two containers sharing an `emptyDir` volume, and
  viewed logs from, and executed commands in, each one individually with
  `-c`.

- Confirmed the shared volume was genuinely live by watching content
  produced by one container get served by the other, over real HTTP
  requests, as it changed.

- Used an init container to prepare content once before the main
  container ever started, and watched the `Init:`/`PodInitializing`
  states unique to that phase.

- Deliberately failed an init container, and confirmed the main container
  never started at all — a stricter, more absolute failure mode than
  anything else covered in this lab.

---

**Previous:** [Exercise 23 — DaemonSets](23-daemonsets.md)

**Next:** [Exercise 25 — System-Level k3s Components](25-system-level-k3s-components.md)
