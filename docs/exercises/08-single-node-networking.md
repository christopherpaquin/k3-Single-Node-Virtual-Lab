# Exercise 8: Single-Node Networking

**Module:** Networking

**Prerequisite:** [Exercise 7 — CoreDNS and Service Discovery](07-coredns-and-service-discovery.md)

---

## Introduction

Every exercise in this module so far worked entirely through the
Kubernetes API — `kubectl get`, `describe`, DNS lookups from inside a Pod.
This one drops down a level, onto the VM's own network stack, to see what
all of that is actually built on top of: a **CNI (Container Network
Interface) plugin**. Kubernetes itself doesn't implement Pod networking —
it defines an interface that a pluggable component fulfills, responsible
for giving every Pod its own IP and making sure Pods can reach each other
across the cluster. K3s uses **Flannel** as its default CNI (other
clusters commonly use Calico, Cilium, or others) — you'll find its actual
network interface on the host directly in this exercise.

You'll also close the loop on two failure modes from earlier exercises —
ServiceLB's host-port conflict (Exercise 5) and how it compares to a
`NodePort` conflict, which behaves completely differently.

---

## What you'll do

- Compare node, Pod, and Service IP address ranges directly.
- Confirm two Pods on the same node can reach each other directly.
- Use a debug Pod to test raw TCP connectivity, not just HTTP.
- Delete a Pod and watch its IP change, side by side.
- Inspect the Flannel network interface and routes on the host itself.
- Confirm the cluster's Pod and Service CIDRs.
- Inspect real listening ports on the host with `ss`.
- Trigger a `NodePort` conflict and compare its failure mode against
  Exercise 5's ServiceLB conflict.

---

## Step 1: Compare node, Pod, and Service IP ranges

```bash
kubectl get nodes -o wide
```

Note the `INTERNAL-IP` column — this is the VM's real address on your
actual network (the same one you've been using in `<node-ip>` throughout
this lab).

```bash
kubectl get pods -A -o wide
```

Compare the `IP` column here against the node's `INTERNAL-IP` above —
they're in a completely different address range. Pod IPs come from a
separate, virtual network that Kubernetes manages itself (via Flannel, in
this lab), not from your VM's real network.

```bash
kubectl get services -A
```

`CLUSTER-IP` is a **third**, separate range again. Three distinct address
spaces — node, Pod, and Service — all active on the same single VM at
once.

---

## Step 2: Confirm Pods on the same node can reach each other directly

```bash
kubectl get pods -l app=nginx-deployment -o wide
```

Pick one Pod's IP, then reach it from a different, disposable Pod:

```bash
kubectl run net-test --rm -it --restart=Never --image=curlimages/curl -- curl -s <pod-ip>
```

This should succeed immediately — Pods on the same node communicate
directly over the Pod network, with no NAT and no extra routing hops
involved between them.

---

## Step 3: Test raw TCP connectivity, not just HTTP

`curl` confirms an HTTP response specifically. Sometimes you just need to
know whether *anything* is listening on a port at all — useful for
non-HTTP services, or narrowing down whether a failure is at the network
layer or the application layer:

```bash
kubectl run net-test --rm -it --restart=Never --image=busybox:1.36 -- nc -zv <pod-ip> 80
```

`nc -z` ("zero-I/O mode") just checks whether the port accepts a
connection and exits — you'll see `open` printed if it does. Try a port
nothing is listening on to see the failure mode:

```bash
kubectl run net-test --rm -it --restart=Never --image=busybox:1.36 -- nc -zv <pod-ip> 81
```

This should report the connection refused — a clean way to confirm
"nothing is even listening here" as distinct from "something's listening
but returning errors."

---

## Step 4: Delete a Pod and watch its IP change

```bash
kubectl get pods -l app=nginx-deployment -o wide
```

Note one Pod's name and IP, then:

```bash
kubectl delete pod <pod-name>
kubectl get pods -l app=nginx-deployment -o wide
```

The replacement Pod has a different IP. You already saw this happen back
in Exercise 3 — the point here is to look at it specifically as a
networking fact, not just a scheduling one: nothing about a Pod's IP is
guaranteed to survive even a routine, healthy replacement.

---

## Step 5: Why applications should use Services, not Pod IPs

You've now seen this from three separate angles across this module: a Pod
IP changes on every recreation (Exercise 3, and just now); a Service's
`ClusterIP` and DNS name stay fixed across any number of Pod replacements
behind it (Exercise 4); and DNS resolution of a Service name is automatic
for every Pod in the cluster (Exercise 7). Hardcoding a Pod IP anywhere in
a real application is effectively hardcoding a value that's guaranteed to
go stale.

---

## Step 6: Inspect Flannel on the host

These next few commands run **directly on the VM** — not through
`kubectl` — since they're inspecting the host's own network stack, not the
Kubernetes API.

```bash
ip addr show flannel.1
```

`flannel.1` is a VXLAN interface Flannel (K3s's default CNI) creates to
carry Pod-to-Pod traffic. On a multi-node cluster, this is the interface
that would tunnel Pod traffic between nodes; on this single-node lab it
still exists, even though every Pod happens to be local.

```bash
ip route show
```

Look for a route covering the Pod CIDR (by default, `10.42.0.0/16` on
K3s), pointed at `flannel.1` — this is the actual routing rule that makes
`kubectl run net-test ... curl <pod-ip>` in Step 2 work at the OS level.

```bash
sudo cat /run/flannel/subnet.env
```

Flannel's own runtime config for this node — `FLANNEL_NETWORK` (the whole
cluster's Pod CIDR), `FLANNEL_SUBNET` (the slice of it assigned to this
specific node), and `FLANNEL_MTU`.

---

## Step 7: Confirm the cluster's Pod and Service CIDRs

You've now seen enough real IPs in this lab to infer the ranges by eye —
confirm it authoritatively instead:

```bash
kubectl get service kubernetes -o jsonpath='{.spec.clusterIP}'
echo
```

The built-in `kubernetes` Service (in the `default` namespace, present on
every cluster) always gets the very first address in the Service CIDR —
by default `10.43.0.1` on K3s, confirming the Service range is
`10.43.0.0/16`.

```bash
sudo cat /run/flannel/subnet.env
```

`FLANNEL_NETWORK` here is the Pod CIDR for the whole cluster — by default
`10.42.0.0/16` on K3s. Two separate `/16` ranges, neither overlapping the
VM's own real network.

---

## Step 8: Inspect real listening ports on the host

```bash
sudo ss -tlnp
```

Look through the output for `traefik` (bound to `80`/`443` — this is the
literal socket behind the `svclb-traefik-` Pod from Exercise 5) and `k3s`
itself (bound to `6443`, the Kubernetes API server port).

Notice what's **not** here: `30080`, the `NodePort` you pinned on
`nginx-nodeport` back in Exercise 4. That's not an oversight — it's a real
and useful distinction, covered next.

---

## Step 9: `NodePort` conflicts behave differently than ServiceLB conflicts

Exercise 5 showed a `LoadBalancer` Service fail because its `svclb` Pod —
a real process, with a real bound socket — couldn't get the host port it
needed. `NodePort` doesn't work that way: `kube-proxy` implements it with
`iptables` rules that redirect traffic before it ever reaches a userspace
listener, which is exactly why `30080` didn't show up in `ss` above. See
the rule directly:

```bash
sudo iptables-save | grep 30080
```

You should see a `KUBE-NODEPORTS` rule referencing port `30080` — a real
mechanism, just not one that presents as a listening socket the way a
`hostPort` Pod does.

That difference in mechanism produces a real difference in *when* a
conflict gets caught. Try creating a second `NodePort` Service pinned to
the same port `nginx-nodeport` already uses:

```bash
kubectl expose deployment whoami --port=80 --name=whoami-nodeport --type=NodePort --node-port=30080
```

This should fail **immediately**, with an error straight from the API
server — something like `provided port is already allocated`. Compare that
against Exercise 5: the ServiceLB conflict wasn't rejected at creation
time at all; the Service was created successfully, and the conflict only
showed up later, as a stuck `Pending` Pod. `NodePort` allocation is
tracked centrally by the API server itself, so it can refuse the request
outright; ServiceLB's host-port binding is only enforced later, at Pod
scheduling time, by the kubelet.

Since the port is available, retry with a free one to confirm the command
itself was otherwise correct:

```bash
kubectl expose deployment whoami --port=80 --name=whoami-nodeport --type=NodePort --node-port=30081
kubectl get service whoami-nodeport
```

Clean up — this was only for the demonstration:

```bash
kubectl delete service whoami-nodeport
```

---

## Recap

In this exercise, you:

- Compared node, Pod, and Service IP ranges side by side, and confirmed
  they're three genuinely separate address spaces on the same VM.

- Confirmed direct Pod-to-Pod reachability on the same node, and tested
  raw TCP connectivity with `nc` independent of HTTP.

- Watched a Pod's IP change on deletion/recreation, reinforcing why
  Services (not Pod IPs) are the correct thing to depend on.

- Inspected Flannel's VXLAN interface, host routes, and its subnet config
  file directly on the VM.

- Confirmed the cluster's Pod CIDR (`10.42.0.0/16`) and Service CIDR
  (`10.43.0.0/16`) authoritatively, rather than just guessing from
  observed IPs.

- Found real listening sockets on the host with `ss`, and learned why
  `NodePort` — unlike ServiceLB — deliberately does **not** show up there.

- Triggered a `NodePort` conflict and compared its immediate,
  API-server-level rejection against Exercise 5's delayed,
  scheduling-level ServiceLB conflict.

---

**Previous:** [Exercise 7 — CoreDNS and Service Discovery](07-coredns-and-service-discovery.md)

**Next:** [Exercise 9 — Namespaces](09-namespaces.md)
