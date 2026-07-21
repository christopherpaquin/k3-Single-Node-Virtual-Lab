# Exercise 31: Failure Scenarios

**Module:** Resilience & Capstone

**Prerequisite:** [Exercise 30 — CLI Efficiency](30-cli-efficiency.md)

---

## Introduction

Every failure mode in this exercise was already taught, once, in depth,
somewhere earlier in this lab. This one is different on purpose: it's a
fast, back-to-back drill through nearly all of them, so you can practice
*recognizing* a failure quickly, rather than reasoning through it from
scratch every time. Each scenario gives you a minimal repro, the
diagnostic command to run, and a pointer back to the exercise with the
full explanation — except one (an unbound PVC) that's genuinely new.

For each scenario: create it, diagnose it yourself with the command shown
before reading the answer beneath it, then fix it and move on.

---

## Scenario 1: Invalid image tag

```bash
kubectl run fail1 --image=nginx:this-tag-does-not-exist -n lab-apps
kubectl get pod fail1 -n lab-apps
```

**Diagnose:** `STATUS` cycles through `ErrImagePull` -> `ImagePullBackOff`.
`kubectl describe pod fail1 -n lab-apps` names the exact tag that couldn't
be found. Full explanation: Exercise 2, Step 7c.

```bash
kubectl delete pod fail1 -n lab-apps
```

---

## Scenario 2: Incorrect container command

```bash
kubectl run fail2 --image=busybox:1.36 --restart=Always -n lab-apps -- sh -c "exit 1"
kubectl get pod fail2 -n lab-apps
```

**Diagnose:** `RESTARTS` climbing, `STATUS` reaches `CrashLoopBackOff`.
`kubectl logs fail2 -n lab-apps --previous` shows what the container
printed before it died. Full explanation: Exercise 2, Step 7b, and
Exercise 14, Step 2.

```bash
kubectl delete pod fail2 -n lab-apps
```

---

## Scenario 3: Service with the wrong selector

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: fail3-svc
  namespace: lab-apps
spec:
  selector:
    app: nothing-has-this-label
  ports:
    - port: 80
EOF
kubectl get endpoints fail3-svc -n lab-apps
```

**Diagnose:** `ENDPOINTS` shows `<none>` despite the Service itself
looking completely normal. Full explanation: Exercise 4, Step 10.

```bash
kubectl delete service fail3-svc -n lab-apps
```

---

## Scenario 4: Ingress pointing at the wrong backend port

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fail4-ingress
  namespace: lab-apps
spec:
  ingressClassName: traefik
  rules:
    - host: fail4.k3s.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-clusterip
                port:
                  number: 9999
EOF
curl -H "Host: fail4.k3s.local" http://<node-ip>/
```

**Diagnose:** An error response, with nothing obviously wrong in
`kubectl describe ingress`. The real signal is in Traefik's own logs:
`kubectl logs -n kube-system deployment/traefik --tail=20`. Full
explanation: Exercise 6, Step 7.

```bash
kubectl delete ingress fail4-ingress -n lab-apps
```

---

## Scenario 5: A missing ConfigMap

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: fail5
  namespace: lab-apps
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: cfg
          mountPath: /etc/demo
  volumes:
    - name: cfg
      configMap:
        name: does-not-exist
EOF
kubectl get pod fail5 -n lab-apps
```

**Diagnose:** Stuck `ContainerCreating` forever, never anything more
specific in `STATUS`. `kubectl describe pod fail5 -n lab-apps` names the
missing ConfigMap directly in Events. Full explanation: Exercise 2, Step
7d, and Exercise 12, Step 8 (which also covers the related-but-different
case of an existing ConfigMap with a missing *key*).

```bash
kubectl delete pod fail5 -n lab-apps
```

---

## Scenario 6: A failing readiness probe

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/broken"}]'
kubectl get pods -n lab-apps -l app=nginx-deployment
```

**Diagnose:** `STATUS` still `Running`, `READY` drops to `0/1`,
`RESTARTS` stays flat. `kubectl get endpoints nginx-clusterip -n lab-apps`
shows the affected Pod silently missing. Full explanation: Exercise 16,
Step 2.

```bash
kubectl patch deployment nginx-deployment -n lab-apps --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
```

---

## Scenario 7: An oversized resource request

```bash
kubectl run fail7 --image=nginx:1.27 -n lab-apps --requests='memory=500Gi'
kubectl get pod fail7 -n lab-apps
```

**Diagnose:** `Pending`, forever — never even attempted to start a
container. `kubectl describe pod fail7 -n lab-apps` names the exact
resource the scheduler couldn't satisfy. Full explanation: Exercise 17,
Step 4.

```bash
kubectl delete pod fail7 -n lab-apps
```

---

## Scenario 8: An unbound PersistentVolumeClaim (new)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fail8-pvc
  namespace: lab-apps
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: does-not-exist
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc fail8-pvc -n lab-apps
```

**Diagnose:** `STATUS` stuck at `Pending`, indefinitely — this is the
storage-layer equivalent of Scenario 7's compute-layer `Pending`: a
request the cluster fundamentally cannot satisfy, rather than a request
that just needs more time.

```bash
kubectl describe pvc fail8-pvc -n lab-apps
```

Events describe waiting for a volume with no provisioner able to satisfy
it — no `StorageClass` named `does-not-exist` exists, so nothing will
ever claim this PVC, no matter how long you wait.

`storageClassName` is immutable once set (the same immutability rule from
Exercise 9 and Exercise 11) — a `kubectl patch` to change it would simply
be rejected. The real fix is deleting and recreating the PVC with the
correct class:

```bash
kubectl delete pvc fail8-pvc -n lab-apps
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fail8-pvc
  namespace: lab-apps
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc fail8-pvc -n lab-apps
```

`Bound` this time.

```bash
kubectl delete pvc fail8-pvc -n lab-apps
```

---

## Scenario 9: A host-port conflict

```bash
kubectl expose deployment nginx-deployment --port=80 --name=fail9-lb -n lab-apps --type=LoadBalancer
kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=fail9-lb
```

**Diagnose:** The `svclb-fail9-lb-` Pod is `Pending`, colliding with
Traefik's existing bind on host port `80`. Full explanation: Exercise 5,
Steps 2–3.

```bash
kubectl delete service fail9-lb -n lab-apps
```

---

## Scenario 10: Roll back a failed Deployment

```bash
kubectl create deployment fail10 --image=nginx:1.26 --replicas=2 -n lab-apps
kubectl rollout status deployment/fail10 -n lab-apps
kubectl set image deployment/fail10 nginx=nginx:this-tag-does-not-exist -n lab-apps
kubectl rollout status deployment/fail10 -n lab-apps --timeout=20s
```

**Diagnose:** The rollout stalls — `kubectl get pods -n lab-apps -l
app=fail10` shows a mix of old, healthy Pods and new Pods stuck in
`ImagePullBackOff` (Scenario 1's failure, now happening mid-rollout). The
`RollingUpdate` strategy from Exercise 3 is doing exactly what it's
designed to do here: refusing to scale down the last known-good Pods
until enough new ones report healthy — which, with a broken image, will
never happen.

**Fix — roll back, the same command from Exercise 3:**

```bash
kubectl rollout undo deployment/fail10 -n lab-apps
kubectl rollout status deployment/fail10 -n lab-apps
```

```bash
kubectl delete deployment fail10 -n lab-apps
```

---

## Recap

In this exercise, you drilled through nine previously-taught failure
modes back to back — invalid image tags, bad commands, broken Service
selectors, broken Ingress backends, missing ConfigMaps, failing readiness
probes, oversized resource requests, host-port conflicts, and a stalled
rollout recovered with `rollout undo` — plus one new one: an unbound PVC
referencing a `StorageClass` that doesn't exist, the storage-layer
counterpart to an oversized resource request's compute-layer `Pending`.

The goal wasn't new material — it was speed: recognizing each symptom
(`ImagePullBackOff`, `CrashLoopBackOff`, empty `Endpoints`, stuck
`ContainerCreating`, `READY 0/1` with zero restarts, `Pending`, a stalled
rollout) and jumping straight to the right diagnostic command, without
re-deriving the reasoning from scratch each time.

---

**Previous:** [Exercise 30 — CLI Efficiency](30-cli-efficiency.md)

**Next:** [Exercise 32 — Backup and Recovery](32-backup-and-recovery.md)
