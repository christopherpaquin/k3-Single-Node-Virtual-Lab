# Exercise 10: Labels, Selectors, and Annotations

**Module:** Configuration & Organization

**Prerequisite:** [Exercise 9 — Namespaces](09-namespaces.md), with the
`lab-apps` namespace and its `nginx-deployment` (2 replicas) still running.

---

## Theme

You've been relying on labels since Exercise 4 without examining them
directly — a Service's `selector` is nothing more than a label query, and
`kubectl create deployment` has been quietly attaching `app=nginx-deployment`
to everything it creates since Exercise 3.

This exercise looks at labels, selectors, and annotations head-on — and
deliberately breaks the relationship between a Pod and the Service in
front of it, by editing nothing but a label.

---

## What you'll do

- Add labels directly to running Pods, and separately to a Deployment
  object itself — and see why those are not the same thing.
- Query resources by one label, multiple labels, and a set-based
  selector.
- Relabel a single Pod out of a Service's selector, and watch what
  actually happens to it.
- Add annotations, and understand how they differ from labels.
- Apply Kubernetes' own recommended label schema.

---

## Step 1: Label running Pods directly

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl label pods -n lab-apps -l app=nginx-deployment tier=frontend environment=learning --overwrite
kubectl get pods -n lab-apps -l app=nginx-deployment --show-labels
```

Both existing Pods now carry `tier=frontend` and `environment=learning`,
in addition to `app=nginx-deployment`. Note this only affected the two
Pods that existed *right now* — it says nothing about what labels a future
replacement Pod will have.

---

## Step 2: Label the Deployment object itself — and see it doesn't cascade

```bash
kubectl label deployment nginx-deployment -n lab-apps team=platform --overwrite
kubectl get deployment nginx-deployment -n lab-apps --show-labels
```

The Deployment object now carries `team=platform`. Check whether its Pods
picked it up too:

```bash
kubectl get pods -n lab-apps -l team=platform
```

No results. A label on the Deployment object's own `metadata.labels` is
completely separate from the Pod template's labels
(`spec.template.metadata.labels`) — only the latter ever ends up on the
Pods it creates. This is a common source of confusion: labeling "the
Deployment" doesn't mean labeling "everything the Deployment manages."

---

## Step 3: Query by label

By one label:

```bash
kubectl get pods -n lab-apps -l tier=frontend
```

By multiple labels at once (comma-separated is AND, not OR):

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment,tier=frontend
```

Set-based selector — matches if the label's value is any of a list:

```bash
kubectl get pods -n lab-apps -l 'environment in (learning,staging,production)'
```

All three of these are the same underlying selector language a Service's
`spec.selector` uses — you're just running it manually with `-l` instead
of Kubernetes running it continuously on your behalf.

---

## Step 4: Relabel one Pod, and watch what actually happens

`nginx-clusterip`'s selector is `app=nginx-deployment` — exactly the label
the ReplicaSet also uses to know which Pods are "its" Pods. Change that
one label on a single Pod and both relationships break at once, in
different ways.

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Pick one Pod name from the output, then:

```bash
kubectl label pod <pod-name> -n lab-apps app=nginx-detached --overwrite
```

Check the Service first:

```bash
kubectl get endpoints nginx-clusterip -n lab-apps
```

Only one IP now, instead of two — the relabeled Pod is still perfectly
healthy and `Running`, but it no longer matches the Service's selector, so
it silently dropped out of rotation. Nothing was deleted; nothing
crashed — this Pod simply became invisible to the Service.

Now check the ReplicaSet's side of things:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

You should see **two** Pods again — a brand new one, plus whichever
original Pod you didn't relabel. The ReplicaSet uses this same
`app=nginx-deployment` label to count "its" Pods too, and as far as it's
concerned, it just lost one — so it created a replacement to get back to
the desired count of 2.

Confirm your relabeled Pod is still out there, on its own:

```bash
kubectl get pod <pod-name> -n lab-apps
```

Still `Running` — but now effectively orphaned. It still has an
`ownerReference` pointing back at the ReplicaSet (that's a separate,
fixed-at-creation-time field, not affected by this), but the ReplicaSet
stopped actively managing it the moment it stopped matching the label
selector. Nothing will restart it if it crashes now, and nothing will
clean it up automatically — it'll just sit there consuming resources.
Clean it up yourself:

```bash
kubectl delete pod <pod-name> -n lab-apps
```

The lesson here has a real-world edge: a single mistyped or accidentally
overwritten label on one Pod can simultaneously pull it out of a Service
*and* trigger an unwanted extra replacement Pod — and neither symptom, on
its own, looks like a labeling problem unless you know to check labels
first.

---

## Step 5: Add annotations

Labels are for anything you need to *select on*. Annotations are for
metadata you just want attached and readable — build info, contact
details, tooling hints — without it being queryable the way a label is.
You've actually already used one: the `kubernetes.io/change-cause`
annotation from Exercise 3.

```bash
kubectl annotate deployment nginx-deployment -n lab-apps \
  lab.example.com/purpose="learning exercise" \
  lab.example.com/contact="you@example.com" \
  --overwrite
```

```bash
kubectl describe deployment nginx-deployment -n lab-apps
```

Look for the `Annotations:` section. Now try the thing that doesn't work:

```bash
kubectl get deployments -n lab-apps -l lab.example.com/purpose=learning
```

No results, and no error either — `-l`/selectors only ever consider
labels. Annotations are metadata for humans and tooling to read, not for
Kubernetes to filter on.

---

## Step 6: Apply Kubernetes' own recommended label schema

Kubernetes documents a standard set of `app.kubernetes.io/*` label keys
specifically so tooling (and other engineers) can rely on a consistent
naming scheme across totally unrelated applications:

```bash
kubectl label deployment nginx-deployment -n lab-apps \
  app.kubernetes.io/name=nginx \
  app.kubernetes.io/instance=nginx-lab-apps \
  app.kubernetes.io/version=1.26 \
  app.kubernetes.io/component=web \
  app.kubernetes.io/part-of=k3s-lab \
  app.kubernetes.io/managed-by=kubectl \
  --overwrite
```

```bash
kubectl get deployment nginx-deployment -n lab-apps --show-labels
```

You've actually already seen this exact convention in this lab without it
being pointed out — Helm applies it automatically to everything it
installs:

```bash
kubectl get deployment my-headlamp -n kube-system --show-labels
```

Look for the same `app.kubernetes.io/*` keys on Headlamp's Deployment,
applied by the chart itself back in the
[K3s/Headlamp Install guide](../K3S-HEADLAMP-INSTALL.md) — this is precisely why
those labels exist: so that a UI, a script, or another engineer can
reliably answer "what is this, what's it part of, and what's managing it"
for *any* resource in the cluster, not just the ones you set up yourself.

---

## Recap

In this exercise, you:

- Labeled running Pods directly, and separately labeled a Deployment
  object — and confirmed the two are not the same thing.

- Queried resources with an equality selector, a multi-label AND
  selector, and a set-based selector.

- Relabeled a single Pod out of a Service's selector and watched it both
  drop silently out of `nginx-clusterip`'s endpoints *and* get replaced by
  the ReplicaSet — two separate consequences of one small change.

- Cleaned up an orphaned Pod that a controller was no longer managing.

- Added annotations, and confirmed they're not selectable the way labels
  are.

- Applied the standard `app.kubernetes.io/*` label schema, and recognized
  it already in use on Headlamp, applied automatically by Helm.

---

**Previous:** [Exercise 9 — Namespaces](09-namespaces.md)

**Next:** [Exercise 11 — Declarative YAML](11-declarative-yaml.md)
