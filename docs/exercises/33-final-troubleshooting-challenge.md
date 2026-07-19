# Exercise 33: Final Troubleshooting Challenge

**Module:** Resilience & Capstone

**Prerequisite:** [Exercise 32 — Backup and Recovery](32-backup-and-recovery.md)

---

## Theme

No walkthrough this time. This exercise deploys one bundle of resources —
a small, fictional "capstone" application — with **eight** deliberate,
independent faults baked in, covering every failure category from
Exercise 31, distributed across several resources so they don't mask each
other. Your job is to find and fix all eight yourself, using nothing but
the techniques built up over the previous 32 exercises.

This is a personal exercise, not something to submit anywhere — the
"documentation" called for below just means keeping your own notes as you
go, the same habit worth having for any real incident.

---

## Deploy the broken application

```bash
kubectl create namespace capstone

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capstone-web
  namespace: capstone
spec:
  replicas: 2
  selector:
    matchLabels:
      app: capstone-web
  template:
    metadata:
      labels:
        app: capstone-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          readinessProbe:
            httpGet:
              path: /this-path-does-not-exist
              port: 80
            periodSeconds: 5
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capstone-worker
  namespace: capstone
spec:
  replicas: 1
  selector:
    matchLabels:
      app: capstone-worker
  template:
    metadata:
      labels:
        app: capstone-worker
    spec:
      containers:
        - name: worker
          image: busybox:9.9.9-does-not-exist
          command: ["sh", "-c", "sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capstone-cache
  namespace: capstone
spec:
  replicas: 1
  selector:
    matchLabels:
      app: capstone-cache
  template:
    metadata:
      labels:
        app: capstone-cache
    spec:
      containers:
        - name: cache
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
          volumeMounts:
            - name: cfg
              mountPath: /etc/capstone
      volumes:
        - name: cfg
          configMap:
            name: capstone-config
---
apiVersion: v1
kind: Service
metadata:
  name: capstone-web-svc
  namespace: capstone
spec:
  selector:
    app: capstone-wb
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: capstone-ingress
  namespace: capstone
spec:
  ingressClassName: traefik
  rules:
    - host: capstone.k3s.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: capstone-web-svc
                port:
                  number: 8080
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: capstone-data
  namespace: capstone
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: capstone-storage
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: capstone-batch
  namespace: capstone
spec:
  containers:
    - name: batch
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources:
        requests:
          memory: 200Gi
---
apiVersion: v1
kind: Service
metadata:
  name: capstone-lb
  namespace: capstone
spec:
  type: LoadBalancer
  selector:
    app: capstone-web
  ports:
    - port: 80
EOF
```

---

## Your task

Find and fix all eight faults. For each one, fill in a row like this
(keep notes however you like — a scratch file, a text editor, whatever's
convenient):

| # | Symptom | Command used to investigate | Root cause | Corrective action | Command used to validate |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |
| 6 | | | | | |
| 7 | | | | | |
| 8 | | | | | |

**Where to start:**

```bash
kubectl get all -n capstone
kubectl get pvc -n capstone
kubectl get ingress -n capstone
```

From there, the general toolkit is exactly what you've used throughout
this lab: `kubectl describe`, `kubectl logs` (including `--previous`
where relevant), `kubectl get endpoints`, and reading Events carefully.
Every fault here is a variant of something covered in Exercise 31 — the
challenge is finding each one without being told which resource it's
hiding in.

One deliberate wrinkle: fixing one fault will not necessarily reveal a
Service's traffic is flowing correctly — check whether more than one
issue is affecting the same resource before assuming a single fix solved
everything.

---

## Clean up

Once you've fixed everything (or once you're done attempting it and just
want to reset):

```bash
kubectl delete namespace capstone
```

Deleting the namespace removes every resource in this exercise at once —
the same behavior you proved deliberately back in Exercise 9, Step 7.

---

## Solutions

Try the challenge yourself first — these are here to check your work
against, not to read ahead.

<details>
<summary>Click to reveal the eight faults and fixes</summary>

1. **`capstone-web`'s readiness probe** points at `/this-path-does-not-exist`.
   Symptom: `READY 0/2`, `STATUS Running`, `RESTARTS 0`.
   Investigate: `kubectl get pods -n capstone` then `kubectl describe pod
   -n capstone -l app=capstone-web`.
   Fix: `kubectl patch deployment capstone-web -n capstone --type=json -p
   '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'`

2. **`capstone-worker`'s image tag** doesn't exist
   (`busybox:9.9.9-does-not-exist`).
   Symptom: `STATUS ImagePullBackOff`.
   Investigate: `kubectl describe pod -n capstone -l app=capstone-worker`.
   Fix: `kubectl set image deployment/capstone-worker worker=busybox:1.36 -n capstone`

3. **`capstone-cache`** mounts a ConfigMap, `capstone-config`, that was
   never created.
   Symptom: `STATUS ContainerCreating`, stuck indefinitely.
   Investigate: `kubectl describe pod -n capstone -l app=capstone-cache`.
   Fix: `kubectl create configmap capstone-config -n capstone --from-literal=placeholder=value`

4. **`capstone-web-svc`'s selector** is `app: capstone-wb` (missing the
   `e` in `web`) — doesn't match anything.
   Symptom: `kubectl get endpoints capstone-web-svc -n capstone` shows
   `<none>`.
   Investigate: compare the Service's `Selector` (`kubectl describe
   service capstone-web-svc -n capstone`) against the Deployment's Pod
   labels (`kubectl get pods -n capstone --show-labels`).
   Fix: `kubectl patch service capstone-web-svc -n capstone -p '{"spec":{"selector":{"app":"capstone-web"}}}'`

5. **`capstone-ingress`** points at port `8080` on `capstone-web-svc`,
   which only listens on `80`.
   Symptom: `curl -H "Host: capstone.k3s.local" http://<node-ip>/`
   fails/errors.
   Investigate: `kubectl logs -n kube-system deployment/traefik --tail=20`.
   Fix: `kubectl patch ingress capstone-ingress -n capstone --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":80}]'`

6. **`capstone-data`** references `storageClassName: capstone-storage`,
   which doesn't exist.
   Symptom: `kubectl get pvc -n capstone` shows `STATUS Pending`,
   indefinitely.
   Investigate: `kubectl describe pvc capstone-data -n capstone`.
   Fix: delete and recreate with `storageClassName: local-path` (recall
   from Exercise 31, Scenario 8: this field is immutable, so a patch
   won't work).

7. **`capstone-batch`** requests `200Gi` of memory — far beyond the
   node's capacity.
   Symptom: `kubectl get pod capstone-batch -n capstone` shows
   `STATUS Pending`, indefinitely.
   Investigate: `kubectl describe pod capstone-batch -n capstone` (look
   for `Insufficient memory`).
   Fix: `kubectl delete pod capstone-batch -n capstone` and recreate with
   a reasonable request, e.g. `128Mi`.

8. **`capstone-lb`** is a `LoadBalancer` Service on port `80`, colliding
   with Traefik's existing host-port binding from Exercise 5.
   Symptom: its `svclb-capstone-lb-` Pod in `kube-system` is stuck
   `Pending`.
   Investigate: `kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=capstone-lb`
   then `kubectl describe pod` on it (look for "didn't have free ports").
   Fix: `kubectl patch service capstone-lb -n capstone -p '{"spec":{"ports":[{"port":8081,"targetPort":80}]}}'`

</details>

---

## Recap

In this exercise, you:

- Diagnosed and fixed eight simultaneous, independent faults across
  Deployments, Services, an Ingress, a PVC, a plain Pod, and a
  `LoadBalancer` Service — every major failure category covered across
  this entire lab — without being told in advance which resource hid
  which problem.

- Practiced telling apart symptoms that look similar at a glance
  (`Pending` from an oversized request versus `Pending` from a bad
  `StorageClass`; `ContainerCreating` from a missing ConfigMap versus a
  Service with zero endpoints) using the specific diagnostic commands
  each one actually calls for.

- Confirmed that fixing one problem on a resource doesn't guarantee every
  problem on it is fixed — some of this lab's resources had exactly one
  fault, verified by checking thoroughly rather than assuming.

---

## You've completed the lab

That's all 33 exercises — from checking `systemctl status k3s` for the
first time in Exercise 1, through every core Kubernetes primitive, to
diagnosing a multi-fault outage blind, using nothing but `kubectl` and the
habits built up one exercise at a time. Head back to the
[exercise index](../../README.md#2-lab-exercises) any time you want to
revisit a topic.

**Previous:** [Exercise 32 — Backup and Recovery](32-backup-and-recovery.md)
