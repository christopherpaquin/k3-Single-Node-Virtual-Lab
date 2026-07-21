# Exercise 9: Namespaces

**Module:** Configuration & Organization

**Prerequisite:** [Exercise 8 — Single-Node Networking](08-single-node-networking.md)

---

## Introduction

Every resource you've created so far has landed in the `default`
namespace, mostly because you never specified one. A **namespace** is
Kubernetes' way of dividing a single cluster into separate logical
workspaces — separate enough that two objects can share the exact same
name, as long as they're in different namespaces. Most (but not all)
resource types are namespaced; a few, like Nodes and PersistentVolumes,
are cluster-scoped and exist outside any namespace at all — you'll see
that distinction matter directly in the RBAC exercise later in this lab.

From here on, this lab uses a dedicated namespace, `lab-apps`, for
application workloads — separating them from `default` and from K3s's own
`kube-system` components, the same separation you'd expect on a real
cluster shared by more than one team or environment.

---

## What you'll do

- Create a namespace for the rest of the lab.
- Deploy an application into it, with the same name as something already
  running in `default`.
- Prove namespaces are immutable — you can't "move" a resource into one.
- Set your `kubectl` context's default namespace.
- List resources across all namespaces.
- Reach a Service in a different namespace from inside one.
- Delete a namespace and watch everything inside it disappear with it.

---

## Step 1: Create a namespace

```bash
kubectl create namespace lab-apps
kubectl get namespaces
```

`lab-apps` should now sit alongside the four you reviewed back in Exercise
1 (`default`, `kube-system`, `kube-public`, `kube-node-lease`).

---

## Step 2: Deploy into it — using a name that's already in use elsewhere

```bash
kubectl create deployment nginx-deployment --image=nginx:1.26 --replicas=2 -n lab-apps
kubectl expose deployment nginx-deployment --port=80 --name=nginx-clusterip -n lab-apps
```

This is the exact same name — `nginx-deployment` — as the Deployment
you've been using since Exercise 3, which is still running in `default`.
Confirm both exist simultaneously:

```bash
kubectl get deployments -A | grep nginx-deployment
```

You should see two separate rows, one per namespace. A resource's name
only has to be unique **within its namespace** — this is the whole reason
namespaces work as an isolation boundary at all.

---

## Step 3: Namespaces are immutable — you can't move a resource into one

It might seem like you could just edit the `default` copy's namespace
field to relocate it. Try it:

```bash
kubectl patch deployment nginx-deployment -n default -p '{"metadata":{"namespace":"lab-apps"}}'
```

This fails — the API server rejects changes to `metadata.namespace` after
creation. The field is immutable, full stop. In practice, "moving" a
resource to a different namespace always really means: export it, delete
the original, and re-create it under the new namespace. There's no
in-place migration.

---

## Step 4: Set your context's default namespace

Typing `-n lab-apps` on every command gets old fast. Set it once instead:

```bash
kubectl config set-context --current --namespace=lab-apps
```

Confirm it took effect:

```bash
kubectl config view --minify -o jsonpath='{..namespace}'
echo
```

Now commands that omit `-n` target `lab-apps` automatically:

```bash
kubectl get deployments
```

This should list the `lab-apps` copy of `nginx-deployment` without you
specifying a namespace at all.

**A caveat worth being explicit about:** every command in the rest of this
lab still includes `-n <namespace>` explicitly anyway, specifically so
each exercise still works correctly if you jump to it directly from the
README index rather than following the exercises in order. Treat this
context default as a personal convenience for your own ad hoc exploring,
not something the lab's instructions rely on silently.

---

## Step 5: List resources across all namespaces

```bash
kubectl get all -A
```

Revisit this from Exercise 1 — it should look noticeably busier now,
with `lab-apps` resources alongside everything in `default` and
`kube-system`.

To see just one resource type across every namespace, add `-A` to a more
specific query instead:

```bash
kubectl get deployments -A
```

---

## Step 6: Reach a Service in a different namespace

With your context now defaulting to `lab-apps` (Step 4), create a
disposable debug Pod — it will land in `lab-apps` automatically:

```bash
kubectl run net-test --rm -it --restart=Never --image=curlimages/curl -- curl -s nginx-clusterip
```

The short name alone works — it resolves to `lab-apps`'s own
`nginx-clusterip`, in the same namespace as this debug Pod, exactly the
way Exercise 7 explained.

Now reach across into `default` instead, using the `service.namespace`
shorthand from Exercise 7:

```bash
kubectl run net-test --rm -it --restart=Never --image=curlimages/curl -- curl -s nginx-clusterip.default
```

Same command pattern, different namespace, different (but same-named)
backend — direct proof that namespace isolation applies to DNS resolution
too, not just to object names.

---

## Step 7: Delete a namespace and watch its contents disappear

Create a throwaway namespace with something running inside it:

```bash
kubectl create namespace scratch-ns
kubectl run test-pod --image=busybox:1.36 --restart=Never -n scratch-ns -- sleep 3600
kubectl get pod test-pod -n scratch-ns
```

Confirm it's `Running`, then delete the namespace itself — not the Pod:

```bash
kubectl delete namespace scratch-ns
```

If you check quickly enough, you can catch the namespace itself
mid-deletion:

```bash
kubectl get namespace scratch-ns
```

You may briefly see `STATUS: Terminating` — deleting a namespace doesn't
happen instantly; Kubernetes has to clean up everything inside it first
(the same `Terminating` concept from Exercise 2, just applied to an entire
namespace's worth of objects at once). A moment later:

```bash
kubectl get pod test-pod -n scratch-ns
```

Both the Pod and the namespace itself are gone — deleting a namespace
deletes everything it contains, with no separate confirmation step. This
is worth being genuinely careful about outside of a lab environment.

---

## Leave this running

Keep the `lab-apps` namespace, its `nginx-deployment`, and its
`nginx-clusterip` — several later exercises deploy directly into
`lab-apps`. Leave your context's default namespace set to `lab-apps` too,
for your own convenience going forward.

---

## Recap

In this exercise, you:

- Created a namespace and deployed a workload into it using a name that
  was already in use in `default`, and confirmed both coexist.

- Proved namespaces are immutable — there's no in-place way to move a
  resource between them.

- Set your `kubectl` context's default namespace, and know why this lab's
  own instructions still specify `-n` explicitly regardless.

- Listed resources across every namespace at once.

- Reached a Service in a different namespace using the
  `service.namespace` DNS shorthand from Exercise 7.

- Deleted a namespace and watched everything inside it — Pods included —
  disappear along with it.

---

**Previous:** [Exercise 8 — Single-Node Networking](08-single-node-networking.md)

**Next:** [Exercise 10 — Labels, Selectors, and Annotations](10-labels-selectors-and-annotations.md)
