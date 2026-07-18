# Exercise 25: System-Level k3s Components

**Module:** Platform Internals

**Prerequisite:** [Exercise 24 — Multi-Container Pods](24-multi-container-pods.md)

---

## Theme

You've now met every major piece of `kube-system` individually, spread
across earlier exercises: CoreDNS (Exercise 7), Traefik (Exercise 6),
ServiceLB (Exercise 5), Metrics Server (Exercise 17), and Helm-installed
components (Exercise 6, for Headlamp back in README §3). This exercise
treats `kube-system` as one connected system, fills in the one piece you
haven't looked at directly yet (the Local Path Provisioner, used
constantly since Exercise 21), and adds one new general-purpose skill:
tracing any Pod back to whatever actually controls it.

---

## What you'll do

- Survey everything running in `kube-system` in one pass.
- Visit each core component and recall — or discover — what it's for.
- Describe a system Pod and inspect its events.
- Review logs from a couple of critical system Pods.
- Delete a managed system Pod and confirm it gets recreated, same as any
  other controller-managed Pod.
- Trace the ownership chain from Pod up to its controller — and see that
  chain isn't always the same length.

---

## Step 1: Survey `kube-system`

```bash
kubectl get all -n kube-system
```

This is a lot busier than it was back in Exercise 1 — everything K3s
bundles by default, plus Headlamp if you installed it from README §3.

---

## Step 2: Visit each core component

**CoreDNS** — cluster DNS, covered in depth in Exercise 7:

```bash
kubectl get deployment coredns -n kube-system
```

**Traefik** — the Ingress controller, covered in Exercise 6:

```bash
kubectl get deployment traefik -n kube-system
```

**Metrics Server** — powers `kubectl top`, covered in Exercise 17:

```bash
kubectl get deployment metrics-server -n kube-system
```

**Local Path Provisioner** — you've relied on this since Exercise 21
without inspecting it directly. It's what actually turns a PVC request
into a real directory on the node's disk:

```bash
kubectl get deployment local-path-provisioner -n kube-system
kubectl logs -n kube-system deployment/local-path-provisioner --tail=20
```

If you still have any PVCs around from Exercise 21 or 22, you'll likely
see log lines referencing the actual provisioning work it did for them.

**ServiceLB** — unlike the others, there's no single Deployment for this
one. Its controller runs embedded inside the K3s process itself (the same
way Flannel does, as you saw in Exercise 23) — the only thing visible as
a normal Kubernetes object is what it *creates*, the `svclb-*` DaemonSets
per `LoadBalancer` Service, which you already inspected directly in
Exercise 5:

```bash
kubectl get daemonset -n kube-system
```

**Helm install Jobs** — the one-shot Jobs that bootstrapped Traefik at
cluster install time, using the `HelmChart` mechanism from Exercise 6:

```bash
kubectl get jobs -n kube-system
```

These are the exact same resource type (`Job`) you worked with directly in
Exercise 20 — `COMPLETIONS` should read `1/1`, and they're not doing
anything anymore; they're historical record of a one-time setup task that
already succeeded.

---

## Step 3: Describe a system Pod and inspect its events

```bash
kubectl describe pod -n kube-system -l k8s-app=kube-dns
```

Depending on how long your cluster has been running, the **Events**
section may already be empty — recall from Exercise 14 that Kubernetes
garbage-collects events after about an hour. If CoreDNS started more than
an hour ago and hasn't had anything noteworthy happen since, there's
simply nothing left to show — itself a live example of that lesson.

---

## Step 4: Logs from critical system Pods

```bash
kubectl logs -n kube-system deployment/coredns --tail=20
kubectl logs -n kube-system deployment/traefik --tail=20
```

Nothing new here mechanically — same `kubectl logs` you've used
throughout this lab, just pointed at the platform's own components
instead of your own workloads.

---

## Step 5: Delete a managed system Pod and watch it recover

```bash
kubectl get pods -n kube-system -l app=local-path-provisioner
```

```bash
kubectl delete pod -n kube-system -l app=local-path-provisioner
kubectl get pods -n kube-system -l app=local-path-provisioner -w
```

`Ctrl+C` once a replacement reaches `Running`. Exactly the same
self-healing behavior from Exercise 3 — `kube-system` components are
ordinary Deployments, managed the identical way anything you've built in
this lab has been.

---

## Step 6: Trace the ownership chain — it isn't always the same length

You traced Deployment -> ReplicaSet -> Pod back in Exercise 3. Confirm it
again here, and then find a case where the chain is shorter.

CoreDNS (a Deployment):

```bash
kubectl get pod -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}'
echo
```

That should print a `ReplicaSet` name. Follow it one more hop:

```bash
kubectl get replicaset <replicaset-name-from-above> -n kube-system -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
echo
```

`Deployment/coredns` — two hops, same as Exercise 3.

Now check the `svclb-traefik` Pod instead:

```bash
kubectl get pod -n kube-system -l svccontroller.k3s.cattle.io/svcname=traefik -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}'
echo
```

`DaemonSet`, directly — **one** hop, not two. DaemonSets (like Jobs)
manage their Pods directly, with no intermediate ReplicaSet-equivalent
layer the way Deployments have. Nothing about `kubectl describe pod` tells
you this difference exists — you have to actually walk the
`ownerReferences` chain to see it, which is exactly what this step just
did.

This technique — follow `ownerReferences` upward until you reach
something with none — works for tracing *any* Pod back to its real
controller, anywhere in the cluster, not just here in `kube-system`.

---

## Recap

In this exercise, you:

- Surveyed every resource in `kube-system` in one pass, and revisited
  CoreDNS, Traefik, Metrics Server, and ServiceLB with the context of the
  exercises where you first met each one.

- Inspected the Local Path Provisioner directly for the first time,
  despite having relied on it since Exercise 21.

- Confirmed the Helm-install Jobs from Traefik's bootstrap are the same
  `Job` resource type from Exercise 20, now sitting `Completed`.

- Read a system Pod's events, and possibly watched Exercise 14's
  event-TTL lesson play out live if there was nothing left to show.

- Deleted a managed system Pod and confirmed it self-heals exactly like
  any Deployment-managed workload you've built yourself.

- Traced ownership chains for two different Pods, and found they aren't
  the same length — Deployments go through an intermediate ReplicaSet;
  DaemonSets (and Jobs) own their Pods directly.

---

**Previous:** [Exercise 24 — Multi-Container Pods](24-multi-container-pods.md)

**Next:** [Exercise 26 — k3s Service and Host-Level Investigation](26-k3s-service-and-host-level-investigation.md)
