# Exercise 16: Health Checks

**Module:** Observability & Troubleshooting

**Prerequisite:** [Exercise 15 — Pod Restart and Recovery](15-pod-restart-and-recovery.md)

---

## Introduction

So far, Kubernetes has only known whether a container's process is
running at all — which is a much weaker signal than "is this application
actually working." A container can be running and still be deadlocked,
stuck waiting on a dependency, or serving errors for every request. A
**probe** is a periodic check (typically an HTTP request, a TCP
connection attempt, or a command execution) that lets Kubernetes ask that
better question directly, and there are three kinds, each controlling a
different consequence:

- **Readiness** — controls whether a Pod receives Service traffic.
  Failure never restarts anything; it just pulls the Pod out of rotation.
- **Liveness** — controls whether the container gets restarted. Failure
  kills and recreates the container in place.
- **Startup** — delays the other two probes until a slow-starting
  container is actually ready to be checked at all.

Mixing these up is one of the most common real Kubernetes misconfigurations
— this exercise deliberately breaks readiness and liveness **separately**,
so the very different consequences of each are unmistakable.

---

## What you'll do

- Add all three probe types to `nginx-deployment`.
- Break readiness only, and confirm the Pod stays `Running` with zero
  restarts, while silently dropping out of the Service.
- Fix it, then break liveness only, and watch the container actually get
  restarted this time.
- Read the different Event messages each failure produces.
- Compare all three probe types directly.

---

## Step 0: Scale down to one replica for a clearer signal

```bash
kubectl scale deployment nginx-deployment -n lab-apps --replicas=1
kubectl rollout status deployment/nginx-deployment -n lab-apps
```

One Pod makes the effects in this exercise unambiguous — you'll scale back
to 2 at the end.

---

## Step 1: Add all three probes, healthy

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: lab-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-deployment
  template:
    metadata:
      labels:
        app: nginx-deployment
    spec:
      containers:
        - name: nginx
          image: nginx:1.26
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
          startupProbe:
            httpGet:
              path: /
              port: 80
            failureThreshold: 10
            periodSeconds: 3
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
      volumes:
        - name: html
          configMap:
            name: nginx-html
EOF
```

```bash
kubectl rollout status deployment/nginx-deployment -n lab-apps
kubectl get pods -n lab-apps -l app=nginx-deployment
```

`READY` should read `1/1`. Look at the probe configuration Kubernetes now
enforces:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment -o name | xargs -I{} kubectl describe -n lab-apps {}
```

In the container section, you'll see `Liveness:`, `Readiness:`, and
`Startup:` lines summarizing each probe's target and timing.

---

## Step 2: Break readiness only

```bash
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/nope"}]'
```

Wait a few seconds, then:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

`STATUS` still shows `Running` — but `READY` drops to `0/1`. Check the
Service:

```bash
kubectl get endpoints nginx-clusterip -n lab-apps
```

Empty. A perfectly healthy, running container just silently disappeared
from the Service the moment its readiness check started failing — no
crash, no restart, nothing that would show up if you were only watching
`STATUS`.

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Check the `RESTARTS` column specifically — it should still read `0`.
Confirm why in the events:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment -o name | xargs -I{} kubectl describe -n lab-apps {}
```

Look for repeating `Readiness probe failed: HTTP probe failed with
statuscode: 404` events — no mention of killing or restarting the
container anywhere.

Fix it:

```bash
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl get endpoints nginx-clusterip -n lab-apps
```

`READY` returns to `1/1`, and the endpoint reappears — automatically, with
no restart having ever happened.

---

## Step 3: Break liveness only

```bash
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/nope"}]'
```

This time, wait about 30–45 seconds (liveness needs a few consecutive
failures before it acts), then:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

`RESTARTS` should now be climbing — check again a bit later and it should
be higher still. This is a completely different consequence from Step 2:
Kubernetes isn't just pulling this Pod out of the Service, it's actively
killing and recreating the container, repeatedly, because it believes the
process itself is unhealthy.

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment -o name | xargs -I{} kubectl describe -n lab-apps {}
```

Look for `Liveness probe failed: HTTP probe failed with statuscode: 404`
immediately followed by `Killing container with id ...` and `Container
nginx failed liveness probe, will be restarted` — exactly the restart
behavior that was completely absent in Step 2.

Fix it:

```bash
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"}]'
kubectl get pods -n lab-apps -l app=nginx-deployment
```

`READY` should settle back to `1/1`, and `RESTARTS` should stop
increasing — though it won't go back down. `RESTARTS` is a cumulative
counter for the Pod's whole lifetime, not a live health indicator; `READY`
and `STATUS` are what actually reflect current health.

---

## Step 4: Compare all three probe types

| Probe | Checked when | On failure | On success |
|---|---|---|---|
| **Startup** | Only at container start, until it first succeeds | Container is killed and restarted (treated like a slow/failed start) | Readiness and liveness probes begin running |
| **Readiness** | Continuously, once startup succeeds | Pod is pulled out of every Service's endpoints — traffic stops, container keeps running | Pod is added back to Service endpoints |
| **Liveness** | Continuously, once startup succeeds | Container is killed and restarted in place — `RESTARTS` increments | Nothing changes — this is the expected steady state |

The `startupProbe` you configured in Step 1 (`failureThreshold: 10`,
`periodSeconds: 3` — up to 30 seconds) exists specifically to stop a slow-
starting application from being killed by an impatient liveness probe
before it's even finished booting — without it, you'd have to loosen the
liveness probe's own timing for every container, slow-starting or not.

---

## Scale back up

```bash
kubectl scale deployment nginx-deployment -n lab-apps --replicas=2
kubectl rollout status deployment/nginx-deployment -n lab-apps
```

Leave the probes in place — they're healthy now, and keeping them is
normal, good practice, not something to revert.

---

## Recap

In this exercise, you:

- Added startup, readiness, and liveness probes to `nginx-deployment`.

- Broke readiness in isolation, and confirmed the Pod stayed `Running`
  with zero restarts while disappearing entirely from the Service's
  endpoints.

- Broke liveness in isolation, and watched the container actually get
  killed and restarted repeatedly — a fundamentally different consequence
  from the same general idea of "a probe failing."

- Read the different Kubernetes Events each failure type produces, and
  can now tell which kind of probe failure you're looking at from the
  event text alone.

- Understand what a startup probe protects against, and why it matters
  specifically for slow-starting applications.

---

**Previous:** [Exercise 15 — Pod Restart and Recovery](15-pod-restart-and-recovery.md)

**Next:** [Exercise 17 — Resource Requests and Limits](17-resource-requests-and-limits.md)
