# Exercise 2: Pods and Basic Workloads

**Module:** Foundations

**Prerequisite:** [Exercise 1 — Cluster Orientation](01-cluster-orientation.md)

---

## Theme

A Pod is the smallest deployable unit in Kubernetes — one or more
containers that share a network namespace and storage.

In this exercise you'll create a standalone Pod directly (no Deployment
wrapping it), poke at it from the inside and the outside, delete it and
watch what happens, and then deliberately break several pods in different
ways so you can recognize the failure states on sight later, instead of
guessing.

---

## What you'll do

- Create a standalone NGINX Pod from the command line.
- Inspect its status, IP, image, and node.
- Read its events with `describe`.
- Exec into the running container and look around.
- Reach the NGINX page from inside the cluster.
- Delete the Pod and confirm nothing brings it back.
- Deliberately create five broken pods and diagnose each one:
  `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, a stuck
  `ContainerCreating`, and `Terminating`.

---

## Step 1: Create a standalone Pod

```bash
kubectl run nginx --image=nginx:1.27
```

`kubectl run` creates a single bare Pod — nothing else. There's no
Deployment or ReplicaSet behind it, which matters a lot in Step 6.

---

## Step 2: Inspect status, IP, image, and node

```bash
kubectl get pod nginx -o wide
```

The columns that matter here:

- `STATUS` — should reach `Running` within a few seconds.
- `IP` — the Pod's own cluster-internal IP address. You'll use this in
  Step 5.
- `NODE` — which node it landed on (only one option in this lab, but this
  column matters a great deal on a real multi-node cluster).

You can also pull just the image directly:

```bash
kubectl get pod nginx -o jsonpath='{.spec.containers[0].image}'
echo
```

---

## Step 3: Describe the Pod and read its events

```bash
kubectl describe pod nginx
```

Scroll to the **Events** section at the very bottom. For a healthy Pod
you'll see a short, boring sequence like:

```
Scheduled  ->  Pulling  ->  Pulled  ->  Created  ->  Started
```

Get used to reading this sequence now — later in this exercise, when you
create broken pods, this is exactly where the story of *what went wrong*
will show up.

---

## Step 4: Exec into the container

```bash
kubectl exec -it nginx -- /bin/bash
```

Once inside, poke around a little:

```bash
ps aux
cat /usr/share/nginx/html/index.html
nginx -v
exit
```

`kubectl exec` runs a command inside an already-running container — it does
not start a new container or a new Pod. Everything you just looked at is
happening inside the one container this Pod is already running.

---

## Step 5: Reach NGINX from inside the cluster

The official NGINX image is intentionally minimal — it doesn't include
`curl` or `wget`, so you can't test connectivity from inside the NGINX
container itself. Instead, spin up a disposable Pod whose only job is
making one request:

```bash
kubectl get pod nginx -o jsonpath='{.status.podIP}'
echo
```

Copy that IP, then:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- curl -s <pod-ip>
```

- `--rm` deletes this Pod automatically as soon as it exits.
- `--restart=Never` means "run once and stop" rather than being kept alive
  and restarted.
- You should see raw NGINX welcome-page HTML print to your terminal.

This is deliberately using a raw Pod IP, with no Service involved yet.
Remember this IP — in the Services exercise you'll see why depending on a
Pod IP directly is fragile, and why Services exist to solve that.

---

## Step 6: Delete the Pod and watch what happens

```bash
kubectl delete pod nginx
kubectl get pods
```

The Pod is gone, permanently — nothing recreates it. This is the
distinguishing feature of a standalone Pod versus a Deployment: no
controller is watching over it. In Exercise 3, you'll wrap NGINX in a
Deployment and delete a Pod the exact same way — and see a replacement
appear within seconds, because a ReplicaSet controller will be watching it.

---

## Step 7: Create and diagnose broken pods

Kubernetes has a small number of very common failure states. Below, you'll
deliberately trigger five of them, one at a time, so the symptom becomes
recognizable on sight.

For each one: create it, run the diagnostic commands, read what they say,
then clean up before moving to the next.

### 7a. `Pending`

Ask for far more CPU than the node actually has:

```bash
kubectl run too-big --image=nginx:1.27 --requests='cpu=100'
```

```bash
kubectl get pod too-big
```

`STATUS` will sit at `Pending` indefinitely — the scheduler is refusing to
place it anywhere, because no node (there's only one) can satisfy a request
for 100 full CPU cores.

```bash
kubectl describe pod too-big
```

In **Events**, look for a line from the `default-scheduler` like:

```
0/1 nodes are available: 1 Insufficient cpu.
```

That single line is the scheduler telling you exactly why — this is the
first place to look any time a Pod is stuck `Pending`.

Clean up:

```bash
kubectl delete pod too-big
```

---

### 7b. `CrashLoopBackOff`

Run a container whose command exits immediately:

```bash
kubectl run crash-demo --image=busybox --restart=Always -- sh -c "exit 1"
```

```bash
kubectl get pod crash-demo
```

It'll cycle through `Running` -> `Error`/`Completed` -> `CrashLoopBackOff`
over the first minute or so. `RESTARTS` climbing in `kubectl get pods` is
your first clue something is wrong, even before you read the status.

```bash
kubectl describe pod crash-demo
```

Look for `Back-off restarting failed container` in Events — Kubernetes is
deliberately slowing down how often it retries, backing off exponentially,
rather than restarting a failing container as fast as possible.

```bash
kubectl logs crash-demo
```

The exit code and any output the container produced before dying show up
here — this is usually where the *actual* root cause of a crash loop shows
up (an application error, a missing file, a bad config value), not in the
Pod status itself.

Clean up:

```bash
kubectl delete pod crash-demo
```

---

### 7c. `ImagePullBackOff`

Reference an image that doesn't exist:

```bash
kubectl run bad-image --image=nginx:this-tag-does-not-exist
```

```bash
kubectl get pod bad-image
```

You'll see `ErrImagePull` first, then `ImagePullBackOff` shortly after —
the same backoff behavior as 7b, but for failed pulls instead of failed
starts.

```bash
kubectl describe pod bad-image
```

Events will show something like:

```
Failed to pull image "nginx:this-tag-does-not-exist": ... manifest unknown
```

This is the single most common typo-driven failure in Kubernetes — a
misspelled tag, a private image pulled without credentials, or a registry
that's unreachable will all land you here.

Clean up:

```bash
kubectl delete pod bad-image
```

---

### 7d. Stuck `ContainerCreating`

Reference a ConfigMap volume that doesn't exist:

```bash
kubectl run stuck-mount --image=nginx:1.27 --dry-run=client -o yaml \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "stuck-mount",
      "image": "nginx:1.27",
      "volumeMounts": [{"name": "cfg", "mountPath": "/etc/demo"}]
    }],
    "volumes": [{"name": "cfg", "configMap": {"name": "does-not-exist"}}]
  }
}' > /tmp/stuck-mount.yaml

kubectl apply -f /tmp/stuck-mount.yaml
```

```bash
kubectl get pod stuck-mount
```

`STATUS` will sit at `ContainerCreating` and never progress — the kubelet
can't start the container because a volume it depends on can't be mounted.

```bash
kubectl describe pod stuck-mount
```

Events will repeat something like:

```
MountVolume.SetUp failed for volume "cfg" : configmap "does-not-exist" not found
```

This is a preview of the ConfigMaps exercise later: a Pod referencing a
ConfigMap that doesn't exist (yet, or due to a typo) doesn't fail fast — it
hangs here instead, which is exactly why checking `describe` events is more
useful than just watching the status column.

Clean up:

```bash
kubectl delete -f /tmp/stuck-mount.yaml
rm /tmp/stuck-mount.yaml
```

---

### 7e. `Terminating`

Run a container that ignores the normal shutdown signal:

```bash
kubectl run stubborn --image=busybox --restart=Never -- sh -c "trap '' TERM; sleep 3600"
```

Wait for it to reach `Running`, then delete it and immediately check its
status:

```bash
kubectl delete pod stubborn --wait=false
kubectl get pod stubborn
```

`STATUS` will show `Terminating` for up to 30 seconds (the default grace
period). Kubernetes sends `SIGTERM` first and waits; because this container
explicitly traps and ignores `SIGTERM`, it never exits gracefully, so
Kubernetes falls back to a hard `SIGKILL` once the grace period expires.

```bash
kubectl get pod stubborn
```

Run that once more after ~30 seconds — the Pod should be gone. If you ever
see a Pod stuck in `Terminating` far longer than that in a real cluster,
it's usually a sign of a stuck node, a finalizer waiting on something
external, or the kubelet itself being unresponsive — not a normal graceful
shutdown.

---

## Recap

In this exercise, you:

- Created a standalone Pod with `kubectl run` and confirmed it has no
  controller watching over it.

- Read a Pod's status, IP, and node placement with `get -o wide`, and
  pulled a single field directly with `-o jsonpath`.

- Read a Pod's event history with `describe`, and know the normal healthy
  sequence (`Scheduled -> Pulling -> Pulled -> Created -> Started`).

- Used `kubectl exec` to run commands inside a live container.

- Reached a Pod directly by its cluster-internal IP from a disposable
  debug Pod — and know why that's fragile.

- Deleted a standalone Pod and confirmed nothing recreates it.

- Recognized five common failure states on sight —
  `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, a stuck
  `ContainerCreating`, and `Terminating` — and know the first
  `kubectl describe`/`kubectl logs` line to check for each one.

---

**Previous:** [Exercise 1 — Cluster Orientation](01-cluster-orientation.md)

**Next:** [Exercise 3 — Deployments and ReplicaSets](03-deployments-and-replicasets.md)
