# Exercise 11: Declarative YAML

**Module:** Configuration & Organization

**Prerequisite:** [Exercise 10 — Labels, Selectors, and Annotations](10-labels-selectors-and-annotations.md)

---

## Theme

Every resource so far came from an imperative `kubectl` command —
`run`, `create deployment`, `expose`, `scale` — or, a few times, a YAML
manifest piped straight into `apply`. This exercise steps back and looks
at the declarative YAML workflow directly: how to generate a manifest
instead of writing one from scratch, and the real differences between
`create`, `apply`, `replace`, `patch`, and `edit` — four ways to change a
resource that are easy to treat as interchangeable and aren't.

This exercise uses its own throwaway app, `yaml-demo`, so you're free to
create, break, and delete it without touching `nginx-deployment`.

---

## What you'll do

- Generate a starting manifest with `--dry-run=client -o yaml` instead of
  writing one by hand.
- Create a resource from a file, then watch `create` refuse to run again.
- Update it with `apply`, and preview a change with `diff` before running
  it.
- Compare `create`, `apply`, `replace`, and `patch` directly against each
  other.
- Edit a live resource in place with `kubectl edit`.
- Delete resources by manifest file.
- Apply an entire directory of manifests in one command.
- Inspect the fields Kubernetes generates itself that you never wrote.

---

## Step 1: Generate a starter manifest instead of writing one by hand

```bash
kubectl create deployment yaml-demo --image=nginx:1.26 --replicas=2 -n lab-apps --dry-run=client -o yaml > yaml-demo-deployment.yaml
```

`--dry-run=client` means nothing is sent to the API server at all — this
only renders what *would* be created. `-o yaml` prints it instead of
creating it. This is a fast, reliable way to get a correct, complete
manifest to start editing, instead of recalling the exact YAML structure
from memory.

```bash
cat yaml-demo-deployment.yaml
```

Open it in an editor if you'd like to look around — it's the same shape
of object you've been reading with `kubectl get -o yaml` all along.

---

## Step 2: Create it, then watch `create` refuse to run twice

```bash
kubectl create -f yaml-demo-deployment.yaml
```

Run the exact same command again:

```bash
kubectl create -f yaml-demo-deployment.yaml
```

This fails with `AlreadyExists`. `create` is deliberately strict — it only
ever creates, and errors out rather than silently doing something else if
the object is already there.

---

## Step 3: Update it with `apply`

Edit the replica count in your local file:

```bash
sed -i 's/replicas: 2/replicas: 4/' yaml-demo-deployment.yaml
```

```bash
kubectl apply -f yaml-demo-deployment.yaml
kubectl get deployment yaml-demo -n lab-apps
```

Unlike `create`, `apply` is safe to run against something that already
exists — it computes the difference and updates only what changed. You've
actually been using `apply` since Exercise 4, piped from a heredoc instead
of a file — same command, same behavior.

---

## Step 4: Preview a change before applying it

```bash
sed -i 's/replicas: 4/replicas: 3/' yaml-demo-deployment.yaml
kubectl diff -f yaml-demo-deployment.yaml
```

`kubectl diff` shows you exactly what `apply` *would* change, without
changing anything yet — the same idea as `terraform plan` or a dry-run in
any other declarative tool. Once you're happy with it:

```bash
kubectl apply -f yaml-demo-deployment.yaml
```

---

## Step 5: Compare `create`, `apply`, `replace`, and `patch`

You've now used `create` (Step 2) and `apply` (Steps 3–4). Two more:

**`replace`** — sends a complete replacement object, and requires the
resource to already exist:

```bash
sed -i 's/replicas: 3/replicas: 2/' yaml-demo-deployment.yaml
kubectl replace -f yaml-demo-deployment.yaml
```

The practical difference from `apply`: `replace` doesn't do `apply`'s
three-way merge against the previously-applied config — it's closer to
"here's the whole object, use this" — and it will fail outright on fields
the API considers immutable, the same way you saw in Exercise 9. Confirm
that:

```bash
sed -i 's/namespace: lab-apps/namespace: default/' yaml-demo-deployment.yaml
kubectl replace -f yaml-demo-deployment.yaml
```

This fails, same as the namespace patch attempt in Exercise 9 did — no
verb can change an immutable field in place. Revert the file before
continuing:

```bash
sed -i 's/namespace: default/namespace: lab-apps/' yaml-demo-deployment.yaml
```

**`patch`** — changes only the specific field(s) you name, with no file
needed at all. You've actually already used this several times: the
deployment strategy change in Exercise 3, and the Service selector fix in
Exercise 4 both used `kubectl patch`. One more example:

```bash
kubectl patch deployment yaml-demo -n lab-apps --type=merge -p '{"spec":{"replicas":3}}'
kubectl get deployment yaml-demo -n lab-apps
```

| Verb | Needs a file? | If it already exists | Typical use |
|---|---|---|---|
| `create` | Optional | Fails | First-time creation only |
| `apply` | Optional | Updates (3-way merge) | Normal day-to-day workflow |
| `replace` | Yes | Updates (full replace) | Rare — mostly superseded by `apply` |
| `patch` | No | Updates (targeted field) | Small, surgical one-off changes |

---

## Step 6: Edit a live resource directly

```bash
kubectl edit deployment yaml-demo -n lab-apps
```

This opens the **live** object from the cluster in your default terminal
editor — not your local file. Change `replicas:` to `4`, save, and quit;
the change applies the moment you save. `kubectl get deployment yaml-demo
-n lab-apps` should confirm it.

This is convenient for a quick, one-off tweak, but notice what's missing
compared to everything else in this exercise: no file, no diff, no record
of what changed or why, anywhere outside the cluster itself. That's
exactly why teams that manage infrastructure seriously tend to prefer
`apply`-from-version-controlled-files as the normal path, and treat
`kubectl edit` as an exception for genuine one-offs, not a routine tool.

---

## Step 7: Delete by manifest file

```bash
kubectl delete -f yaml-demo-deployment.yaml
kubectl get deployment yaml-demo -n lab-apps
```

`delete -f` deletes whatever resource(s) the file describes, identified by
kind/name — it doesn't matter that the live object has drifted since
(different replica count, etc.) from what's in the file at this point.

---

## Step 8: Apply an entire directory at once

Real projects rarely have just one manifest. Build a small directory with
two related files and apply them together:

```bash
mkdir -p yaml-demo-manifests

cat <<'EOF' > yaml-demo-manifests/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: yaml-demo
  namespace: lab-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: yaml-demo
  template:
    metadata:
      labels:
        app: yaml-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.26
EOF

cat <<'EOF' > yaml-demo-manifests/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: yaml-demo
  namespace: lab-apps
spec:
  selector:
    app: yaml-demo
  ports:
    - port: 80
EOF
```

```bash
kubectl apply -f yaml-demo-manifests/
```

Both objects are created in one command. This is exactly how real
GitOps-style pipelines apply a whole folder of manifests as a single
operation — add `-R` if you ever need it to recurse into subdirectories
too.

```bash
kubectl get deployment,service yaml-demo -n lab-apps
```

---

## Step 9: Inspect fields Kubernetes generated itself

```bash
kubectl get deployment yaml-demo -n lab-apps -o yaml
```

None of what follows was in either manifest file you wrote:

- `metadata.uid` — a permanent unique identifier for this exact object
  instance. Delete this Deployment and create a new one with the identical
  name, and it gets a **different** UID — proof that, as far as
  Kubernetes is concerned, it's a genuinely new object, not a continuation
  of the old one.

- `metadata.resourceVersion` — changes on every single write. It's how
  Kubernetes implements optimistic concurrency: if you try to `replace` an
  object using a stale `resourceVersion` (because something else changed
  it since you last read it), the write is rejected rather than silently
  overwriting someone else's change.

- `metadata.creationTimestamp`, `metadata.generation`, and the whole
  `status:` block (`observedGeneration`, `replicas`, `conditions`, …) —
  all continuously maintained by controllers, not by you.

- `metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]`
  — added automatically the first time you ran `apply` against this
  object. This is literally the mechanism `apply` uses to compute future
  three-way merges and `diff` output — it's not just informational, it's
  load-bearing.

---

## Clean up

`yaml-demo` was only for this exercise:

```bash
kubectl delete -f yaml-demo-manifests/
rm -rf yaml-demo-manifests yaml-demo-deployment.yaml
```

---

## Recap

In this exercise, you:

- Generated a starting manifest with `--dry-run=client -o yaml` instead of
  writing one from memory.

- Created a resource from a file with `create`, and confirmed it refuses
  to run against something that already exists.

- Updated the same resource with `apply`, and previewed a pending change
  with `kubectl diff` before applying it.

- Compared `create`, `apply`, `replace`, and `patch` directly, and know
  when each is the right tool.

- Confirmed `replace` still can't touch immutable fields, the same
  limitation from Exercise 9.

- Edited a live resource with `kubectl edit`, and understand why that's a
  reasonable exception rather than a routine workflow.

- Deleted resources by manifest file, and applied a whole directory of
  manifests in one command.

- Identified server-generated fields (`uid`, `resourceVersion`, `status`,
  the `last-applied-configuration` annotation) that you never wrote
  yourself.

---

**Previous:** [Exercise 10 — Labels, Selectors, and Annotations](10-labels-selectors-and-annotations.md)

**Next:** [Exercise 12 — ConfigMaps](12-configmaps.md)
