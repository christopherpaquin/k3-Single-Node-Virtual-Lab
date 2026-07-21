# Exercise 6: Traefik Ingress

**Module:** Networking

**Prerequisite:** [Exercise 5 — k3s ServiceLB](05-k3s-servicelb.md)

---

## Introduction

`NodePort` and `LoadBalancer` both give you one Service per port. That
breaks down fast in the real world, where you might want dozens of
different applications all reachable on the same, ordinary port `80` —
routed to the right one by hostname or URL path instead.

That's what an **Ingress** is for: an API object that describes HTTP(S)
routing rules — "requests for host X, path Y go to Service Z" — layered
on top of Services rather than replacing them. An Ingress object by
itself does nothing; it needs an **Ingress controller** actually watching
for Ingress objects and configuring a real HTTP proxy to match. Kubernetes
ships no controller by default — you always have to install one
(Traefik, NGINX Ingress, and others are common choices). K3s happens to
bundle Traefik automatically, which is why this lab already has one
running with no separate install step.

You already met the mechanism Traefik uses to receive that traffic in the
first place — it's the same ServiceLB Pod from Exercise 5, bound to host
port `80`.

---

## What you'll do

- Confirm Traefik is installed and inspect its resources in `kube-system`.
- Create an Ingress routing a hostname to `nginx-clusterip`.
- Test it with `curl` and a custom `Host` header.
- Add a second application and route two different paths to two different
  Services.
- Watch Traefik's logs while sending requests.
- Break the Ingress with a wrong Service name and a wrong port, and
  diagnose both.
- Inspect the K3s-specific `HelmChart` resource that installed Traefik in
  the first place.

---

## Step 1: Confirm Traefik is installed

```bash
kubectl get deployment traefik -n kube-system
kubectl get ingressclass
```

The second command should list `traefik` as an available `IngressClass` —
this is what an Ingress object references to say *which* controller should
handle it (useful on clusters running more than one).

---

## Step 2: Inspect Traefik's resources in `kube-system`

```bash
kubectl get all -n kube-system -l app.kubernetes.io/name=traefik
```

You should see its Deployment, its `ClusterIP` Service (the internal
address Ingress rules ultimately point traffic at), and the `LoadBalancer`
Service you already inspected in Exercise 5.

---

## Step 3: Create an Ingress for `nginx-clusterip`

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: traefik
  rules:
    - host: lab.k3s.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-clusterip
                port:
                  number: 80
EOF
```

```bash
kubectl get ingress nginx-ingress
kubectl describe ingress nginx-ingress
```

`describe` shows the same rule you just wrote back to you, resolved
against real Service endpoints — a quick way to confirm Traefik picked the
Ingress up at all.

---

## Step 4: Test routing with a custom `Host` header

There's no real DNS entry for `lab.k3s.local`, so tell `curl` to send that
`Host` header manually while still connecting to the node's real IP:

```bash
curl -H "Host: lab.k3s.local" http://<node-ip>/
```

You should get the NGINX welcome page. Now try without the header:

```bash
curl http://<node-ip>/
```

Depending on what else is listening on port `80`, you'll either get a
`404` from Traefik or a different default backend — proof that it's
routing on the `Host` header itself, not just "anything hitting port 80."
This is exactly how one IP and one port can serve any number of different
hostnames at once.

---

## Step 5: Add a second app and route by path

Deploy a small app built specifically for demos like this — it responds
with its own Pod name and the request details it received, which makes it
obvious which backend actually served a given request:

```bash
kubectl create deployment whoami --image=traefik/whoami --replicas=1
kubectl expose deployment whoami --port=80 --name=whoami
```

Update the Ingress to route two paths under the same hostname to two
different Services:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: traefik
  rules:
    - host: lab.k3s.local
      http:
        paths:
          - path: /whoami
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-clusterip
                port:
                  number: 80
EOF
```

`/whoami` is listed first deliberately — Traefik matches path rules by
specificity, but keeping the more specific path above the catch-all `/`
avoids relying on that ordering behavior to make the point.

Test both:

```bash
curl -H "Host: lab.k3s.local" http://<node-ip>/
curl -H "Host: lab.k3s.local" http://<node-ip>/whoami
```

The first should still be the NGINX welcome page; the second should print
`whoami`'s own response — including the Pod name that handled it, and the
headers `curl` sent (including the `Host` header you set).

---

## Step 6: Watch Traefik's logs while sending requests

```bash
kubectl logs -n kube-system deployment/traefik -f
```

While that's running, send a few requests from another terminal (either
`curl` command from Step 5 works). You likely won't see a new line appear
per request — K3s's bundled Traefik ships with per-request access logging
turned **off** by default, so what you *will* see in this stream is
configuration/route-sync activity, not a request-by-request access log.
That's worth knowing on its own: "no access logs" is Traefik's default,
not a sign anything is broken. (You'll see exactly where that's configured
in Step 8.) `Ctrl+C` to stop following.

---

## Step 7: Break it — wrong Service name, then wrong port

**Wrong Service name:**

```bash
kubectl patch ingress nginx-ingress --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/1/backend/service/name","value":"nginx-typo"}]'
curl -H "Host: lab.k3s.local" http://<node-ip>/
```

You should get an error response (a `404` or `502`, depending on Traefik's
version) instead of the NGINX page. Unlike the broken-selector Service
from Exercise 4, `kubectl describe ingress nginx-ingress` here likely
**won't** clearly flag the problem — Traefik's ingress provider doesn't
always surface backend errors as Kubernetes Events the way you might
expect. Check Traefik's own logs instead:

```bash
kubectl logs -n kube-system deployment/traefik --tail=20
```

Look for a line referencing the Ingress and a Service it couldn't resolve
— this is the actual place the error surfaced, which is the point of this
step: not every failure shows up the same way, and knowing to check
controller logs (not just `kubectl describe`) is itself the skill.

Fix it:

```bash
kubectl patch ingress nginx-ingress --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/1/backend/service/name","value":"nginx-clusterip"}]'
curl -H "Host: lab.k3s.local" http://<node-ip>/
```

**Wrong backend port:**

```bash
kubectl patch ingress nginx-ingress --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/1/backend/service/port/number","value":81}]'
curl -H "Host: lab.k3s.local" http://<node-ip>/
```

Same category of failure — `nginx-clusterip` exists, but it isn't
listening on `81` (only `80`) — so this fails the same way a wrong name
did, for a different underlying reason. Same diagnostic path applies:
check `kubectl logs -n kube-system deployment/traefik --tail=20` for the
connection error.

Fix it and confirm recovery:

```bash
kubectl patch ingress nginx-ingress --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/1/backend/service/port/number","value":80}]'
curl -H "Host: lab.k3s.local" http://<node-ip>/
curl -H "Host: lab.k3s.local" http://<node-ip>/whoami
```

Both paths should be back to working.

---

## Step 8: Inspect the `HelmChart` resource that installed Traefik

Traefik wasn't installed with the Helm CLI the way Headlamp was back in
the [K3s/Headlamp Install guide](../K3S-HEADLAMP-INSTALL.md) §2 — K3s has
its own built-in mechanism for bootstrapping bundled components, using a
custom resource called `HelmChart`:

```bash
kubectl get helmchart -n kube-system traefik -o yaml
```

Look at `spec.chart`, `spec.version`, and `spec.valuesContent` — this is
the same information a `values.yaml` file would hold for a normal Helm
install, just expressed as a Kubernetes object instead of a CLI argument.
A controller inside K3s (`helm-controller`) watches for `HelmChart` objects
like this one and runs the equivalent of `helm install`/`helm upgrade` on
your behalf, tracked through a Job:

```bash
kubectl get jobs -n kube-system -l helmcharts.helm.cattle.io/chart=traefik
```

You'll work with the Helm CLI directly, the way Headlamp was installed, in
the dedicated Helm exercise later in this lab — this is the same
underlying tool, just triggered declaratively by K3s itself rather than
run by hand.

---

## Recap

In this exercise, you:

- Confirmed Traefik is installed and found its resources in `kube-system`,
  including the `IngressClass` it registers.

- Created an Ingress routing a hostname to a Service, and tested it with a
  manual `Host` header since no real DNS entry existed.

- Routed two different URL paths under the same hostname to two different
  Services.

- Watched Traefik's logs and learned that per-request access logging is
  off by default in K3s's configuration.

- Broke the Ingress two different ways (wrong Service name, wrong port),
  and learned that Traefik doesn't always surface these failures through
  `kubectl describe` the way a bad Service selector did — controller logs
  were the more reliable signal.

- Found the `HelmChart` custom resource K3s used to install Traefik in the
  first place, and the Job it triggers under the hood.

---

**Previous:** [Exercise 5 — k3s ServiceLB](05-k3s-servicelb.md)

**Next:** [Exercise 7 — CoreDNS and Service Discovery](07-coredns-and-service-discovery.md)
