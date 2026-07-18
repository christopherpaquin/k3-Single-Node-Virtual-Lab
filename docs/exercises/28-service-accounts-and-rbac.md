# Exercise 28: Service Accounts and RBAC

**Module:** Security

**Prerequisite:** [Exercise 27 — Security Contexts](27-security-contexts.md)

---

## Theme

Exercise 13 ended with a pointed but unanswered question: anyone who can
`get` a Secret can decode it — so who actually can? This exercise answers
it. Every Pod authenticates to the Kubernetes API as a **ServiceAccount**
— every Pod you've created in this entire lab has been using one, whether
you noticed or not — and **RBAC** (Role-Based Access Control) governs
exactly what that identity is allowed to do.

You've also already used this exact system without necessarily
recognizing it: the `cluster-admin`-bound ServiceAccount token you created
for Headlamp back in README §3.3 is the same mechanism this exercise
builds a properly *narrow* version of.

---

## What you'll do

- Inspect the default ServiceAccount every Pod in this lab has used
  implicitly.
- Create a dedicated ServiceAccount, a read-only Role, and bind them
  together.
- Test permissions with `kubectl auth can-i` before creating anything
  that depends on them.
- Run real `kubectl` commands **from inside a Pod**, using that Pod's own
  identity — not your own.
- Watch a real request get denied, fix the missing permission, and watch
  it succeed.
- Compare `Role` against `ClusterRole` with a permission only the latter
  can grant.
- Find the actual token file Kubernetes mounts into every Pod
  automatically.

---

## Step 1: The default ServiceAccount you've already been using

```bash
kubectl get serviceaccount -n lab-apps
```

`default` exists automatically in every namespace — you never created it.
Confirm your own workloads have been using it:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl get pod <nginx-pod-name> -n lab-apps -o jsonpath='{.spec.serviceAccountName}'
echo
```

`default` — every Pod you've created in this lab, unless told otherwise,
authenticates to the API as this same identity.

```bash
kubectl auth can-i --list --as=system:serviceaccount:lab-apps:default
```

The `default` ServiceAccount typically has little to no API access
configured out of the box — worth confirming directly rather than
assuming.

---

## Step 2: Create a dedicated ServiceAccount, Role, and binding

```bash
kubectl create serviceaccount pod-reader-sa -n lab-apps
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: lab-apps
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
EOF

kubectl create rolebinding pod-reader-binding -n lab-apps \
  --role=pod-reader --serviceaccount=lab-apps:pod-reader-sa
```

A `Role` alone does nothing — it's just a named list of permissions. A
`RoleBinding` is what actually grants it to someone.

---

## Step 3: Test permissions before building anything on top of them

```bash
kubectl auth can-i list pods -n lab-apps --as=system:serviceaccount:lab-apps:pod-reader-sa
kubectl auth can-i delete pods -n lab-apps --as=system:serviceaccount:lab-apps:pod-reader-sa
kubectl auth can-i get secrets -n lab-apps --as=system:serviceaccount:lab-apps:pod-reader-sa
```

`yes`, `no`, `no` — exactly matching the Role you wrote: list/get/watch on
Pods only. That last check directly answers Exercise 13's question: this
identity specifically **cannot** read `db-credentials`, because nothing
ever granted it permission to `get secrets` at all.

---

## Step 4: Run real `kubectl` commands from inside a Pod

`kubectl auth can-i --as=...` simulates a permission check from your own
session. To see RBAC enforced for real, run commands as this identity
actually would — from a Pod using it:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rbac-test-pod
  namespace: lab-apps
spec:
  serviceAccountName: pod-reader-sa
  containers:
    - name: kubectl
      image: bitnami/kubectl:latest
      command: ["sh", "-c", "sleep 3600"]
EOF
```

This Pod has `kubectl` installed inside it, and — because it's running
with `serviceAccountName: pod-reader-sa` — its own `kubectl` commands
authenticate as `pod-reader-sa` automatically, with no config needed:

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get pods -n lab-apps
```

Succeeds — this matches what the Role grants.

---

## Step 5: Watch a real denial happen

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get secret db-credentials -n lab-apps
```

```
Error from server (Forbidden): secrets "db-credentials" is forbidden: User "system:serviceaccount:lab-apps:pod-reader-sa" cannot get resource "secrets" in API group "" in the namespace "lab-apps"
```

A real, live-enforced denial — not a simulation this time, and the exact
mechanism that answers Exercise 13's open question about who can actually
decode a Secret: only identities explicitly granted permission to `get`
it, which this one deliberately is not.

Try something the Role also doesn't cover:

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get deployments -n lab-apps
```

Also `Forbidden` — the Role only ever granted access to `pods`, nothing
else.

---

## Step 6: Add the missing permission and retest

```bash
kubectl patch role pod-reader -n lab-apps --type=json -p \
  '[{"op":"add","path":"/rules/-","value":{"apiGroups":["apps"],"resources":["deployments"],"verbs":["get","list"]}}]'
```

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get deployments -n lab-apps
```

Succeeds immediately — RBAC changes take effect right away, with no
restart or propagation delay needed for either the Role or the Pod using
it.

---

## Step 7: `Role` versus `ClusterRole`

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get nodes
```

`Forbidden` — but notice this isn't just a missing permission in the same
sense as Step 5. **Nodes are cluster-scoped**, not namespaced at all — a
plain `Role`, which is always tied to one specific namespace, cannot grant
access to a cluster-scoped resource under any circumstances, no matter
what you put in its rules. Only a `ClusterRole` can:

```bash
kubectl create clusterrole node-reader --verb=get,list --resource=nodes
kubectl create clusterrolebinding node-reader-binding \
  --clusterrole=node-reader --serviceaccount=lab-apps:pod-reader-sa
```

```bash
kubectl exec rbac-test-pod -n lab-apps -- kubectl get nodes
```

Succeeds now. This is the real, structural difference between the two —
not just "broader by convention," but the only mechanism capable of
granting access to anything that doesn't belong to a namespace at all
(Nodes, PersistentVolumes, Namespaces themselves, and other
cluster-scoped resources).

---

## Step 8: Find the token Kubernetes actually mounted

Everything `rbac-test-pod` did above worked with zero manual
configuration — no kubeconfig file, no token you copied in yourself.
Find out where that came from:

```bash
kubectl get pod rbac-test-pod -n lab-apps -o jsonpath='{.spec.volumes}' | python3 -m json.tool 2>/dev/null || kubectl get pod rbac-test-pod -n lab-apps -o jsonpath='{.spec.volumes}'
```

Look for a volume named something like `kube-api-access-xxxxx`, of type
`projected` — combining a `serviceAccountToken` (time-bound, unlike the
old-style static tokens), the cluster's CA certificate, and the Pod's own
namespace, all mounted together automatically by an admission controller,
with no action required from you. This is the exact same underlying
mechanism as `kubectl create token` from README §3.3 — there, you ran it
manually to get a token for a **human** to paste into Headlamp; here,
Kubernetes runs the equivalent automatically so a **Pod's own processes**
can authenticate as themselves.

```bash
kubectl exec rbac-test-pod -n lab-apps -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

`token`, `ca.crt`, and `namespace` — the three files that, together, are
the entire reason `kubectl` worked inside this Pod without any
configuration at all.

---

## Clean up

```bash
kubectl delete pod rbac-test-pod -n lab-apps
kubectl delete role pod-reader -n lab-apps
kubectl delete rolebinding pod-reader-binding -n lab-apps
kubectl delete serviceaccount pod-reader-sa -n lab-apps
kubectl delete clusterrole node-reader
kubectl delete clusterrolebinding node-reader-binding
```

---

## Recap

In this exercise, you:

- Confirmed every Pod in this lab has been authenticating as the
  `default` ServiceAccount, whether you specified one or not.

- Created a dedicated ServiceAccount, a narrowly-scoped Role, and bound
  them together, then verified the exact permissions with
  `kubectl auth can-i` before building anything on top of it.

- Ran real `kubectl` commands from inside a Pod using that Pod's own
  identity, and watched a real, live-enforced `Forbidden` error — finally
  answering Exercise 13's question about who can actually read a Secret.

- Fixed a missing permission and confirmed RBAC changes apply instantly,
  with no restart required.

- Proved structurally why a namespaced `Role` can never grant access to a
  cluster-scoped resource like Nodes, and that only a `ClusterRole` can.

- Found the actual token, CA certificate, and namespace file Kubernetes
  mounts into every Pod automatically — the same mechanism behind
  `kubectl create token`, applied automatically instead of manually.

---

**Previous:** [Exercise 27 — Security Contexts](27-security-contexts.md)

**Next:** [Exercise 29 — Helm](29-helm.md)
