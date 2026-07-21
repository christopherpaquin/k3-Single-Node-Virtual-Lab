# Exercise 7: CoreDNS and Service Discovery

**Module:** Networking

**Prerequisite:** [Exercise 6 — Traefik Ingress](06-traefik-ingress.md)

---

## Introduction

Back in Exercise 4, you reached `nginx-clusterip` from another Pod just by
name, with no explanation of how that actually worked. This exercise opens
that up.

**Service discovery** is the general problem of how one part of a system
finds the network address of another part, especially when that address
can change. Kubernetes solves it with DNS: every Kubernetes cluster runs a
cluster-internal DNS server — **CoreDNS** — that automatically creates a
DNS record for every Service the moment it's created, and every Pod is
automatically configured (via its `/etc/resolv.conf`) to use it. That
combination is what lets you write `nginx-clusterip` instead of
memorizing a ClusterIP, and it's the mechanism nearly every real
Kubernetes application relies on to talk to other services in the same
cluster.

---

## What you'll do

- Resolve a Service name from another Pod, then resolve its fully
  qualified name.
- Inspect a Pod's `/etc/resolv.conf` and understand why short names work
  at all.
- Test what happens resolving a Service in a *different* namespace.
- Query CoreDNS directly, instead of relying on automatic resolution.
- Inspect CoreDNS's own logs and configuration.
- Diagnose a Service name that doesn't exist at all — a different failure
  mode than the broken selector from Exercise 4.
- Compare Pod-IP access against Service DNS names directly.

---

## Step 1: Resolve a Service name from another Pod

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup nginx-clusterip
```

You should get back the Service's `ClusterIP` — the same address you saw
in `kubectl get service nginx-clusterip` back in Exercise 4.

---

## Step 2: Resolve the fully qualified name

Every Service actually has a full DNS name of the form
`<service>.<namespace>.svc.<cluster-domain>` — `cluster.local` by default.
`nginx-clusterip` is really shorthand for the whole thing:

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup nginx-clusterip.default.svc.cluster.local
```

Same result. Understanding this full name matters for two reasons: it's
what actually gets resolved under the hood, and it's the only form that
reliably works from **outside** a Pod's own namespace, as you'll see in
Step 4.

---

## Step 3: Inspect a Pod's `/etc/resolv.conf`

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- cat /etc/resolv.conf
```

You'll see something like:

```
nameserver 10.43.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

- `nameserver` — CoreDNS's own ClusterIP. Every Pod gets this injected
  automatically; nothing about it is specific to this lab.
- `search` — a list of suffixes the resolver tries, in order, whenever you
  look up a name that isn't already a complete FQDN. This is the entire
  reason `nginx-clusterip` alone was enough in Step 1 — the resolver
  quietly tried `nginx-clusterip.default.svc.cluster.local` on your
  behalf.
- `ndots:5` — controls when the resolver bothers trying the search list at
  all versus treating a name as already fully qualified. In practice: any
  name with fewer than 5 dots gets the search-list treatment first.

---

## Step 4: Test resolution across namespaces

Create a throwaway namespace with its own Service, to see what happens
reaching across namespace boundaries:

```bash
kubectl create namespace dns-demo
kubectl create deployment nginx --image=nginx:1.27 -n dns-demo
kubectl expose deployment nginx --port=80 -n dns-demo
```

From a Pod in the `default` namespace, try the short name first:

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup nginx
```

This should **fail** (`NXDOMAIN` / "can't find nginx") — the search list
tried `nginx.default.svc.cluster.local` first (there's no Service named
plainly `nginx` in `default`), and none of the other search suffixes
happen to land on the right answer either.

Now try the "service.namespace" shorthand:

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup nginx.dns-demo
```

This one **succeeds**. It looks like a coincidence, but it isn't: the
`svc.cluster.local` entry in the search list, appended to `nginx.dns-demo`,
produces exactly `nginx.dns-demo.svc.cluster.local` — a fully valid
Service FQDN. This `service.namespace` shorthand (without `.svc.cluster.local`
on the end) is extremely common in real manifests for exactly this reason.

Clean up the demo namespace:

```bash
kubectl delete namespace dns-demo
```

---

## Step 5: Query CoreDNS directly

Rather than relying on the `nameserver` line in `resolv.conf`, point a
query at CoreDNS's Service explicitly:

```bash
kubectl get service -n kube-system kube-dns
```

(CoreDNS's Service is named `kube-dns` for historical/compatibility
reasons, even though the Pods behind it run CoreDNS, not the older
`kube-dns` implementation it replaced years ago.)

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup nginx-clusterip.default.svc.cluster.local <kube-dns-cluster-ip>
```

Same result as Step 1 — proof that the automatic resolution you rely on
constantly is just this same server, queried automatically instead of by
hand.

---

## Step 6: Inspect CoreDNS's logs and configuration

```bash
kubectl get configmap -n kube-system coredns -o yaml
```

The `Corefile` key holds CoreDNS's actual configuration — a small
plugin-based DSL. Look for the `kubernetes` plugin block, which is what
makes CoreDNS aware of Services and Pods at all, and a `forward` block,
which sends anything **not** matching the cluster's internal domain out to
an upstream resolver (normally whatever DNS server the node itself uses).

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

Like Traefik's access logs in Exercise 6, don't expect a line per query
here by default — the `log` plugin (which would print every query) isn't
enabled in the default `Corefile`. What you will see is startup and health
information.

---

## Step 7: Diagnose a Service name that doesn't exist

```bash
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup nginx-typo
```

This fails at the DNS layer itself — `nslookup` reports it can't find the
name at all. Compare that against the broken-selector Service from
Exercise 4: there, the Service **did** resolve — DNS worked fine — but the
connection itself hung because there were no endpoints behind it. Here,
there's no Service object with that name in the first place, so DNS fails
immediately and explicitly instead. Two different bugs, two different
symptoms:

| Symptom | Likely cause | Where to look first |
|---|---|---|
| Name doesn't resolve at all | Service doesn't exist / wrong name or namespace | `kubectl get service <name>` |
| Name resolves, but connection hangs/fails | Service exists, but has no matching Pods | `kubectl get endpoints <name>` (Exercise 4) |

---

## Step 8: Compare Pod IP versus Service DNS name

A short recap, now that you've seen both in practice across this and
earlier exercises:

| | Pod IP | Service DNS name |
|---|---|---|
| Stability | Changes every time the Pod is recreated (Exercise 2/3) | Stable for the Service's entire lifetime |
| Portability | Different in every environment | Same name works the same way in any namespace/cluster following the same convention |
| What you used it for here | One-off debugging (`curl <pod-ip>` in Exercise 2) | Everything else — this is the normal way workloads talk to each other |

---

## Recap

In this exercise, you:

- Resolved a Service by its short name and its fully qualified name, and
  confirmed both point at the same `ClusterIP`.

- Read a Pod's `/etc/resolv.conf` and understand exactly why short names
  resolve: the `search` list and `ndots` setting injected into every Pod.

- Watched short-name resolution fail across a namespace boundary, and
  confirmed the `service.namespace` shorthand works for exactly the reason
  the search list is built the way it is.

- Queried CoreDNS directly by its `ClusterIP` instead of relying on
  automatic resolution.

- Found CoreDNS's `Corefile` configuration and know that, like Traefik,
  per-query logging isn't on by default.

- Diagnosed a nonexistent Service name as a DNS-level failure, and can now
  distinguish it from the endpoint-level failure from Exercise 4 by
  symptom alone.

---

**Previous:** [Exercise 6 — Traefik Ingress](06-traefik-ingress.md)

**Next:** [Exercise 8 — Single-Node Networking](08-single-node-networking.md)
