# Exercise 3: Deployments and ReplicaSets

**Module:** Foundations

**Prerequisite:** [Exercise 2 — Pods and Basic Workloads](02-pods-and-basic-workloads.md)

---

## Theme

A standalone Pod, as you saw in Exercise 2, has no one watching over it —
delete it and it's gone.

A **Deployment** fixes that by describing a *desired state* ("I want 3
copies of this Pod running, always") and handing it to a controller that
continuously reconciles reality toward that state. The Deployment itself
doesn't manage Pods directly — it manages a **ReplicaSet**, which manages
the Pods. Understanding that chain (Deployment -> ReplicaSet -> Pods) is
one of the most useful mental models in all of Kubernetes.

The `nginx-deployment` you create in this exercise stays running at the end
— later exercises (starting with Services in Exercise 4) build directly on
top of it.

---

## What you'll do

- Create an NGINX Deployment and inspect the Deployment/ReplicaSet/Pod
  chain it creates.
- Scale it up and down, and watch Pods appear and disappear.
- Delete an individual Pod and watch it get replaced automatically.
- Roll out a new image version and watch a rolling update happen live.
- Inspect rollout status and history, then roll back.
- Force a restart without changing the image.
- Compare the `RollingUpdate` and `Recreate` deployment strategies directly.

---

## Step 1: Create a Deployment

```bash
kubectl create deployment nginx-deployment --image=nginx:1.26 --replicas=3
```

This is deliberately starting one version behind — you'll upgrade to
`nginx:1.27` yourself in Step 6, so you can watch the transition happen
rather than starting already on the latest version.

---

## Step 2: Inspect the Deployment, ReplicaSet, and Pods

```bash
kubectl get deployment nginx-deployment
```

`READY 3/3` means 3 of the desired 3 replicas are up. `UP-TO-DATE` and
`AVAILABLE` will make more sense once you do a rolling update in Step 6 —
right now everything should be a clean `3`.

```bash
kubectl get rs -l app=nginx-deployment
```

`kubectl create deployment` automatically applies the label
`app=nginx-deployment` to everything it creates, which is what makes this
selector work. You should see exactly one ReplicaSet.

```bash
kubectl get pods -l app=nginx-deployment -o wide
```

Three Pods, each with a name like `nginx-deployment-<replicaset-hash>-<pod-suffix>`
— the first part of that name is literally the ReplicaSet's name.

Now look at the ownership chain directly:

```bash
kubectl describe deployment nginx-deployment
```

Note the `NewReplicaSet` field near the bottom — that's the Deployment
telling you which ReplicaSet it currently owns.

```bash
kubectl get pods -l app=nginx-deployment -o jsonpath='{.items[0].metadata.ownerReferences[0].name}'
echo
```

That prints the name of the ReplicaSet that owns one specific Pod — proof
that Pods are owned by the ReplicaSet, not directly by the Deployment. The
Deployment owns the ReplicaSet, which owns the Pods. Three layers, each one
only aware of the layer directly below it.

---

## Step 3: Scale up and down

```bash
kubectl scale deployment nginx-deployment --replicas=5
kubectl get pods -l app=nginx-deployment -o wide
```

Two new Pods should appear within a few seconds.

```bash
kubectl scale deployment nginx-deployment --replicas=2
kubectl get pods -l app=nginx-deployment -o wide
```

Three Pods terminate, leaving 2. To watch this happen live instead of
checking after the fact, run a scale command in one terminal and this in
another:

```bash
kubectl get pods -l app=nginx-deployment -o wide --watch
```

(`--watch` streams changes instead of exiting — press `Ctrl+C` when you're
done watching.)

Set it back to a clean 3 before moving on:

```bash
kubectl scale deployment nginx-deployment --replicas=3
```

---

## Step 4: Confirm multiple replicas run on the same node

```bash
kubectl get pods -l app=nginx-deployment -o wide
```

Look at the `NODE` column — every Pod shows the same node, because there's
only one. On a real multi-node cluster, the scheduler *prefers* (but by
default doesn't strictly require) spreading replicas of the same Deployment
across different nodes, so that losing one node doesn't take down every
replica at once. That resilience mechanism simply has nothing to work with
here — worth remembering as a limitation of single-node testing, not a
Kubernetes limitation.

---

## Step 5: Delete a Pod and watch it get replaced

```bash
kubectl get pods -l app=nginx-deployment
```

Pick one Pod name from the output, then:

```bash
kubectl delete pod <pod-name>
kubectl get pods -l app=nginx-deployment
```

A replacement Pod appears almost immediately, with a new name and `AGE` of
a few seconds. This is the direct contrast to Exercise 2, Step 6, where
deleting a standalone Pod left nothing behind: here, the ReplicaSet
controller noticed the actual replica count (2) no longer matched the
desired count (3), and created a new Pod to close the gap. Nothing about
the Deployment spec changed — the controller is just continuously
reconciling.

---

## Step 6: Update the image and watch a rolling update

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.27
```

Immediately start watching the rollout:

```bash
kubectl rollout status deployment/nginx-deployment
```

This blocks and prints progress until the rollout finishes. In another
terminal, while it's in progress, run:

```bash
kubectl get rs -l app=nginx-deployment
```

You'll briefly see **two** ReplicaSets: the old one scaling down and a new
one (for `nginx:1.27`) scaling up. This is what `RollingUpdate` — the
default strategy — actually does: it doesn't replace Pods in place, it
creates a new ReplicaSet and gradually shifts replica count from the old
one to the new one, so there's always some capacity serving traffic.

Once the rollout finishes:

```bash
kubectl get rs -l app=nginx-deployment
```

The old ReplicaSet is still there, scaled to `0`. Deployments keep a
configurable number of old ReplicaSets around (10 by default) specifically
so a rollback doesn't have to recreate one from scratch — it's already
there, just idle.

---

## Step 7: Inspect rollout status and history

```bash
kubectl rollout history deployment/nginx-deployment
```

You'll see a list of revisions, but the `CHANGE-CAUSE` column is empty —
Kubernetes doesn't automatically record *why* a change happened, only
*that* one did. You can add that context yourself:

```bash
kubectl annotate deployment/nginx-deployment kubernetes.io/change-cause="upgrade to nginx:1.27"
kubectl rollout history deployment/nginx-deployment
```

Note this annotation itself creates a new revision — annotating the
Deployment's pod template is a spec change, same as the image update was.

---

## Step 8: Roll back

```bash
kubectl rollout undo deployment/nginx-deployment
kubectl rollout status deployment/nginx-deployment
```

Confirm the image actually reverted:

```bash
kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

You should see `nginx:1.26` again. `kubectl rollout undo` works by
pointing the Deployment back at a previous ReplicaSet's Pod template — it's
the exact same rolling-update mechanism from Step 6, just moving in the
opposite direction.

You can also target a specific revision instead of just "the previous one":

```bash
kubectl rollout history deployment/nginx-deployment
kubectl rollout undo deployment/nginx-deployment --to-revision=<number>
```

---

## Step 9: Force a restart without changing the spec

```bash
kubectl rollout restart deployment/nginx-deployment
kubectl rollout status deployment/nginx-deployment
```

This recreates every Pod (new names, new start times) using the exact same
image and spec — no version change at all. This matters in practice for
things a Pod only reads once at startup: a mounted Secret's contents
changed, a certificate rotated, or an application needs a clean process
restart to clear in-memory state. You'll use this exact command again in
the ConfigMaps and Secrets exercises later.

---

## Step 10: Compare `RollingUpdate` and `Recreate` strategies

Check the current strategy:

```bash
kubectl get deployment nginx-deployment -o jsonpath='{.spec.strategy}'
echo
```

You should see `RollingUpdate` with `maxUnavailable`/`maxSurge` both
defaulting to `25%` — meaning during a rollout, at most 25% of replicas can
be unavailable, and up to 25% extra can be created temporarily, to keep the
app serving traffic throughout.

Switch to `Recreate`:

```bash
kubectl patch deployment nginx-deployment -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
```

Now trigger another version change and immediately check Pod status:

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.27
kubectl get pods -l app=nginx-deployment -o wide
```

Run that `get pods` a few times in a row, quickly. Unlike Step 6, you
should catch a moment where **all** Pods are `Terminating` or gone before
any new ones reach `Running` — `Recreate` tears down every old Pod first,
then creates new ones, with a real (if brief) gap where the Deployment
serves nothing at all. This is only ever appropriate when running two
versions simultaneously would actively break something — e.g. a
schema-incompatible database migration — since the tradeoff is guaranteed
downtime during every rollout.

Switch back to `RollingUpdate` to leave the Deployment in its normal state:

```bash
kubectl patch deployment nginx-deployment -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":"25%","maxSurge":"25%"}}}}'
kubectl rollout status deployment/nginx-deployment
```

---

## Leave this running

Don't delete `nginx-deployment` — Exercise 4 exposes it with a Service.
Confirm it's healthy and at 3 replicas before moving on:

```bash
kubectl get deployment nginx-deployment
```

---

## Recap

In this exercise, you:

- Created a Deployment and traced the full ownership chain it manages:
  Deployment -> ReplicaSet -> Pods.

- Scaled a Deployment up and down, and watched the ReplicaSet controller
  create and terminate Pods to match.

- Deleted an individual Pod managed by a Deployment and watched it get
  replaced automatically — the direct opposite of what happened to the
  standalone Pod in Exercise 2.

- Triggered a rolling update, watched two ReplicaSets coexist briefly
  during the transition, and inspected rollout status and history.

- Rolled back to a previous revision, and forced a restart with no spec
  change at all.

- Compared `RollingUpdate` (brief overlap, no downtime) against `Recreate`
  (full teardown before recreation, guaranteed downtime) by triggering the
  same version change under both strategies.

---

**Previous:** [Exercise 2 — Pods and Basic Workloads](02-pods-and-basic-workloads.md)

**Next:** [Exercise 4 — Services and Port Access](04-services-and-port-access.md)
