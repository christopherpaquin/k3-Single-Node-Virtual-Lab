# Exercise 5: k3s ServiceLB

**Module:** Networking

**Prerequisite:** [Exercise 4 — Services and Port Access](04-services-and-port-access.md)

---

## Theme

Exercise 4 ended by pointing out that `LoadBalancer` Services don't mean
much without a cloud provider to hand out a real external IP.

K3s doesn't leave `LoadBalancer` broken on bare metal, though — it ships
its own lightweight controller, **ServiceLB** (internally built on a
project called Klipper), which fulfills `LoadBalancer` Services by running
a small proxy Pod on every node that binds directly to the Service's port
on the host itself. It's not a "real" external load balancer in the cloud
sense — it's a clever, single-node-friendly stand-in, and it's already
running in your cluster right now, in front of Traefik.

This exercise deliberately walks into a real port conflict with it, so the
failure mode is something you recognize later rather than something you
hit for the first time in the middle of a different exercise.

---

## What you'll do

- Find the ServiceLB Pod already running in front of Traefik.
- Create your own `LoadBalancer` Service — and collide with Traefik's port
  on purpose.
- Diagnose the resulting scheduling failure.
- Fix it by choosing a free port.
- Reach the working Service from outside the cluster.
- Compare ServiceLB directly against `NodePort`.

---

## Step 1: Inspect the ServiceLB already running for Traefik

Traefik — bundled with K3s since Exercise 2.2 — is itself exposed as a
`LoadBalancer` Service:

```bash
kubectl get service traefik -n kube-system
```

Look at `EXTERNAL-IP`: it's already populated, with your node's own IP
address — not `<pending>`, the way it would be on a cluster with no
load-balancer support at all. That's ServiceLB at work.

Find the Pod actually doing that work:

```bash
kubectl get daemonset -n kube-system -l svccontroller.k3s.cattle.io/svcname=traefik
kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=traefik -o wide
```

The Pod name starts with `svclb-traefik-`. It's managed as a DaemonSet
(one copy per node — you'll cover DaemonSets properly later in this lab)
specifically so that, on a multi-node cluster, every node would be able to
receive external traffic for this Service, not just one.

```bash
kubectl describe pod -n kube-system -l svccontroller.k3s.cattle.io/svcname=traefik
```

Look for `Host Port` in the container spec — this Pod binds directly to
port `80` and `443` on the node itself, then forwards whatever it receives
to Traefik's real `ClusterIP`. That direct host-port bind is both the
entire trick behind ServiceLB, and exactly what you're about to collide
with in Step 2.

---

## Step 2: Create your own `LoadBalancer` Service — on the same port

```bash
kubectl expose deployment nginx-deployment --port=80 --name=nginx-loadbalancer --type=LoadBalancer
```

```bash
kubectl get service nginx-loadbalancer
```

`EXTERNAL-IP` will likely sit at `<pending>` instead of resolving the way
Traefik's did.

---

## Step 3: Diagnose why

```bash
kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=nginx-loadbalancer
```

The `svclb-nginx-loadbalancer-` Pod is stuck `Pending`.

```bash
kubectl describe pod -n kube-system -l svccontroller.k3s.cattle.io/svcname=nginx-loadbalancer
```

In **Events**, look for something like:

```
0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports.
```

This is the exact port conflict called out in the theme above: your node
only has one port `80`, and Traefik's `svclb` Pod already has it bound.
There's no queueing or sharing — the second Pod simply can't be scheduled
at all while the first one holds the port.

---

## Step 4: Fix it with a free port

Delete and recreate on a port nothing else is using:

```bash
kubectl delete service nginx-loadbalancer
kubectl expose deployment nginx-deployment --port=8081 --target-port=80 --name=nginx-loadbalancer --type=LoadBalancer
```

`--port=8081` is the external/host port this time; `--target-port=80` is
still the container's actual listening port inside the Pod — the Service
translates between the two.

```bash
kubectl get service nginx-loadbalancer
```

`EXTERNAL-IP` should now resolve to the node's IP within a few seconds.

```bash
kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=nginx-loadbalancer
```

The `svclb-nginx-loadbalancer-` Pod should now be `Running`.

---

## Step 5: Reach it from outside the cluster

```bash
curl http://<node-ip>:8081
```

No `port-forward`, no NodePort range — this is bound directly to the port
you asked for, on the node's real IP, exactly like Traefik is on `80`.

---

## Step 6: Compare ServiceLB with `NodePort`

Both ultimately make a Service reachable from outside the cluster via the
node's IP, but the mechanism and the tradeoffs differ:

| | `NodePort` | `LoadBalancer` (via k3s ServiceLB) |
|---|---|---|
| Port choice | Kubernetes-assigned range, `30000`–`32767` (or a value you pin inside that range) | Any port you ask for — including well-known ports like `80`/`443` |
| How it's implemented | `kube-proxy` rules on every node, no extra Pods | A dedicated `svclb-*` Pod per node, directly bound to the host port |
| Conflict behavior | Rare — the whole point of the high default range is to avoid collisions | Real and immediate — you just hit one, on a single-node cluster, using only two Services |
| Typical use | Simple, low-stakes external access | Standing in for a cloud load balancer; needed when you want a normal, memorable port like `80` |

The flexibility of choosing any port is exactly what makes ServiceLB more
prone to conflicts than `NodePort` — every `LoadBalancer` Service on this
node is competing for the same finite set of host ports, with no
Kubernetes-managed range keeping them apart automatically.

---

## Clean up

`nginx-loadbalancer` was only for this exercise — later exercises don't
depend on it:

```bash
kubectl delete service nginx-loadbalancer
```

---

## Recap

In this exercise, you:

- Found the `svclb-traefik-` Pod already running in your cluster, and
  confirmed it's what makes Traefik's `LoadBalancer` Service work at all
  on bare metal.

- Created a `LoadBalancer` Service that intentionally collided with
  Traefik's host port, and watched its `svclb` Pod get stuck `Pending`.

- Diagnosed that failure with `kubectl describe pod`, and recognized the
  "didn't have free ports" scheduling event.

- Fixed the conflict by choosing an unused port, and confirmed the
  `EXTERNAL-IP` resolved and the `svclb` Pod reached `Running`.

- Reached the Service from outside the cluster via the node's IP.

- Compared `NodePort` and ServiceLB-backed `LoadBalancer` directly, and
  know why the latter is more conflict-prone despite being more flexible.

---

**Previous:** [Exercise 4 — Services and Port Access](04-services-and-port-access.md)

**Next:** [Exercise 6 — Traefik Ingress](06-traefik-ingress.md)
