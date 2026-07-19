# Exercise 4: Services and Port Access

**Module:** Networking

**Prerequisite:** [Exercise 3 — Deployments and ReplicaSets](03-deployments-and-replicasets.md),
with `nginx-deployment` still running at 3 replicas.

---

## Theme

In Exercise 2, you reached a Pod directly by its IP address — and it was
called out at the time as fragile. Here's why: Pod IPs change every time a
Pod is recreated (you saw this yourself when a Deployment replaced a
deleted Pod in Exercise 3). Nothing else in the cluster can reliably depend
on a Pod IP staying the same for more than a few minutes.

A **Service** solves this by giving a stable virtual IP and DNS name to a
*set* of Pods, selected by label — not to any one Pod. As Pods come and go
behind it, the Service's address never changes.

---

## What you'll do

- Expose `nginx-deployment` with a ClusterIP Service.
- Inspect its virtual IP, selector, Endpoints, and EndpointSlices.
- Reach it by name from another Pod.
- Expose the same Deployment again with a NodePort Service, both
  auto-assigned and pinned to a specific port.
- Reach it from outside the cluster via the node's IP.
- Use `port-forward` against both a Pod and a Service directly.
- Compare `ClusterIP`, `NodePort`, and `LoadBalancer` conceptually.
- Break a Service on purpose with a bad selector, and diagnose it the same
  way you would a real one.

---

## Step 1: Create a ClusterIP Service

```bash
kubectl expose deployment nginx-deployment --port=80 --name=nginx-clusterip
```

`kubectl expose` reads the Deployment's Pod template labels
(`app=nginx-deployment`, set automatically back in Exercise 3) and uses
them to build the Service's selector — you didn't have to specify it. Type
`ClusterIP` is the default if you don't pass `--type`.

---

## Step 2: Inspect the Service's IP, selector, endpoints, and EndpointSlices

```bash
kubectl get service nginx-clusterip
```

The `CLUSTER-IP` column is a virtual IP — it doesn't belong to any real
network interface. Traffic sent to it is transparently redirected by
`kube-proxy` to one of the backing Pods.

```bash
kubectl describe service nginx-clusterip
```

Look at two fields specifically:

- `Selector` — the label expression this Service uses to find backend
  Pods (`app=nginx-deployment`).
- `Endpoints` — the actual list of Pod IPs currently matching that
  selector, each with `:80` appended.

That `Endpoints` list is not something you configured — it's continuously
recomputed by a controller watching for Pods matching the selector. See it
as its own object:

```bash
kubectl get endpoints nginx-clusterip
```

Modern Kubernetes actually tracks this through a newer, more scalable API
called EndpointSlices (the older `Endpoints` object above is kept mainly
for backward compatibility):

```bash
kubectl get endpointslices -l kubernetes.io/service-name=nginx-clusterip
kubectl describe endpointslice -l kubernetes.io/service-name=nginx-clusterip
```

Same information — the IPs of the 3 `nginx-deployment` Pods — represented
in the newer API that the rest of the cluster actually uses under the
hood.

---

## Step 3: Reach the Service from another Pod

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- curl -s nginx-clusterip
```

Notice you used the **name** `nginx-clusterip`, not an IP address — cluster
DNS resolves Service names automatically for any Pod in the same
namespace. You'll go a level deeper into exactly how that resolution works
in the CoreDNS exercise later in this module.

---

## Step 4: Expose the Deployment with an auto-assigned NodePort

```bash
kubectl expose deployment nginx-deployment --port=80 --name=nginx-nodeport --type=NodePort
kubectl get service nginx-nodeport
```

Look at the `PORT(S)` column — it now shows two ports, like `80:31842/TCP`.
`80` is still the internal Service port; the second number is a NodePort
Kubernetes picked randomly from its default range (`30000`–`32767`) and
opened on **every** node in the cluster.

---

## Step 5: Reach it from outside the cluster

```bash
kubectl get service nginx-nodeport -o jsonpath='{.spec.ports[0].nodePort}'
echo
```

Then, from any machine that can reach the node (not from inside a Pod this
time):

```bash
curl http://<node-ip>:<node-port>
```

This is the fundamental difference from `ClusterIP`: a NodePort Service is
reachable from **outside** the cluster, on every node's own IP, with no
`port-forward` and nothing that needs to keep running in a terminal.

---

## Step 6: Assign a specific NodePort instead of a random one

A random port is inconvenient to document or bookmark. Recreate the
Service with a fixed one:

```bash
kubectl delete service nginx-nodeport
kubectl expose deployment nginx-deployment --port=80 --name=nginx-nodeport --type=NodePort --node-port=30080
kubectl get service nginx-nodeport
```

`PORT(S)` should now read exactly `80:30080/TCP`, and
`curl http://<node-ip>:30080` should work the same way as Step 5.

---

## Step 7: `port-forward` to a Pod directly

```bash
kubectl get pods -l app=nginx-deployment
```

Pick one Pod name, then:

```bash
kubectl port-forward pod/<pod-name> 8080:80
```

In another terminal (or another tab): `curl http://localhost:8080`. This
tunnels straight to one specific Pod — bypassing the Service, the
selector, and load balancing entirely. `Ctrl+C` to stop it when you're
done.

If you're connecting to this VM remotely rather than working from its own
desktop, plain `localhost` won't be reachable from your workstation — the
same caveat covered in [K3s/Headlamp Install
§2.4](../K3S-HEADLAMP-INSTALL.md#24-access-headlamp) for Headlamp applies
here too (use `--address 0.0.0.0` and the node's IP, or an SSH tunnel).

---

## Step 8: `port-forward` to a Service instead

```bash
kubectl port-forward service/nginx-clusterip 8080:80
```

Functionally similar to Step 7 from the outside, but this time Kubernetes
picks one of the Service's backing Pods for you on each connection, the
same way real traffic to the Service would be routed. `Ctrl+C` when done.

---

## Step 9: Compare `ClusterIP`, `NodePort`, and `LoadBalancer`

| Type | Reachable from | Typical use |
|---|---|---|
| `ClusterIP` (default) | Inside the cluster only | Pod-to-Pod / internal service-to-service traffic |
| `NodePort` | Outside the cluster, via any node's IP on a fixed port | Simple external access without an ingress controller |
| `LoadBalancer` | Outside the cluster, via a dedicated external IP | Production external access — normally provisions a real cloud load balancer |

A `NodePort` Service is actually a superset of `ClusterIP` — it gets a
`ClusterIP` too, plus the NodePort on top, which is why the Service you
created in Step 4 was still reachable from inside the cluster the whole
time.

`LoadBalancer` doesn't mean much on a bare-metal single-node lab like this
one — there's no cloud provider to hand out a real external IP. K3s ships
its own lightweight controller (**ServiceLB**) that fulfills `LoadBalancer`
Services anyway, in a way that's worth understanding on its own — that's
the entirety of the next exercise.

---

## Step 10: Break a Service on purpose, then diagnose it

Create a Service with a selector that doesn't match anything:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-broken
spec:
  selector:
    app: nginx-typo
  ports:
    - port: 80
      targetPort: 80
EOF
```

```bash
kubectl get service nginx-broken
```

The Service exists and has a perfectly normal `ClusterIP` — nothing here
looks wrong yet. This is exactly why this is such a common real-world bug:
the failure is silent at the Service level.

```bash
kubectl get endpoints nginx-broken
```

`ENDPOINTS` shows `<none>`. No Pod in the cluster carries the label
`app=nginx-typo`, so there is nothing behind this Service at all — any
request to it will hang or fail, with no error message pointing at the
real cause.

```bash
kubectl describe service nginx-broken
```

Confirms the same thing directly: `Endpoints: <none>`, next to a
`Selector` you can now compare, by eye, against the label your actual Pods
carry:

```bash
kubectl get pods --show-labels -l app=nginx-deployment
```

Fix it:

```bash
kubectl patch service nginx-broken -p '{"spec":{"selector":{"app":"nginx-deployment"}}}'
kubectl get endpoints nginx-broken
```

`ENDPOINTS` should now list the 3 `nginx-deployment` Pod IPs. Whenever a
Service seems unreachable in the future, this is the very first thing
worth checking — `kubectl get endpoints <service-name>`, before assuming
the problem is with the application itself.

Clean up — this Service was only ever for this demonstration:

```bash
kubectl delete service nginx-broken
```

---

## Leave this running

Keep `nginx-clusterip` and `nginx-nodeport` — later exercises (Ingress,
CoreDNS) reference them directly.

---

## Recap

In this exercise, you:

- Exposed a Deployment with a `ClusterIP` Service and confirmed it gets a
  stable virtual IP, independent of any individual Pod's IP.

- Inspected a Service's selector, its `Endpoints` object, and the newer
  `EndpointSlice` API that backs it.

- Reached a Service by DNS name from another Pod, instead of a raw Pod IP.

- Exposed the same Deployment as `NodePort`, both with a random port and a
  pinned one, and reached it from outside the cluster.

- Used `port-forward` against a Pod directly and against a Service, and
  know the difference between them.

- Compared `ClusterIP`, `NodePort`, and `LoadBalancer` and know when each
  is appropriate.

- Diagnosed a Service with zero endpoints — the single most common
  "why can't I reach my app" failure — using `kubectl get endpoints`.

---

**Previous:** [Exercise 3 — Deployments and ReplicaSets](03-deployments-and-replicasets.md)

**Next:** [Exercise 5 — k3s ServiceLB](05-k3s-servicelb.md)
