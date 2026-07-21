# Exercise 12: ConfigMaps

**Module:** Configuration & Organization

**Prerequisite:** [Exercise 11 — Declarative YAML](11-declarative-yaml.md),
with `nginx-deployment` and `nginx-clusterip` still running in `lab-apps`.

---

## Introduction

A core Kubernetes design principle is separating an application's
**image** (the built, versioned artifact — code and runtime) from its
**configuration** (values that differ by environment or deployment: a
feature flag, a hostname, a log level). Baking configuration directly
into an image means rebuilding the image for every environment; a
**ConfigMap** holds configuration data as key/value pairs instead, kept
completely separate from the container image itself, and attached to a
Pod at deploy time. The same NGINX image can serve completely different
content, or behave differently, purely based on what ConfigMap (if any)
is attached to it — no rebuild required.

There are two fundamentally different ways to attach that data to a Pod —
as environment variables, or as mounted files — and they behave
differently in ways that matter, which this exercise deliberately exposes.

---

## What you'll do

- Create a ConfigMap from literal key/value pairs, and another from a
  file.
- Inject ConfigMap values as environment variables.
- Mount a ConfigMap as files instead.
- Use a ConfigMap to replace `nginx-deployment`'s default page.
- Update that ConfigMap and observe — and time — how the running
  application actually picks up the change.
- Force an immediate reload with `kubectl rollout restart`.
- Troubleshoot a Pod referencing a ConfigMap key that doesn't exist.

---

## Step 1: Create a ConfigMap from literal values

```bash
kubectl create configmap app-config -n lab-apps \
  --from-literal=GREETING="Hello from a ConfigMap" \
  --from-literal=ENVIRONMENT=learning
```

```bash
kubectl get configmap app-config -n lab-apps -o yaml
```

Under `data:`, both keys are stored as plain, un-encoded text — worth
remembering when you get to the Secrets exercise next, where that's
specifically *not* the case.

---

## Step 2: Create a ConfigMap from a file

```bash
cat <<'EOF' > motd.txt
Welcome to the K3s Single-Node Lab.
This message is being served from a ConfigMap.
EOF

kubectl create configmap motd-config -n lab-apps --from-file=motd.txt
```

```bash
kubectl get configmap motd-config -n lab-apps -o yaml
```

The key in `data:` is the filename itself (`motd.txt`) — you can override
that with `--from-file=customkey=motd.txt` if you want the key name to
differ from the file name.

---

## Step 3: Inject ConfigMap values as environment variables

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-env-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo GREETING=$GREETING; echo ENVIRONMENT=$ENVIRONMENT"]
      envFrom:
        - configMapRef:
            name: app-config
EOF
```

```bash
kubectl logs configmap-env-test -n lab-apps
```

Both keys from `app-config` show up as real environment variables inside
the container — `envFrom` pulls in every key from the ConfigMap at once,
without you having to list them individually.

Clean up:

```bash
kubectl delete pod configmap-env-test -n lab-apps
```

---

## Step 4: Mount a ConfigMap as files instead

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-file-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "cat /etc/motd/motd.txt"]
      volumeMounts:
        - name: motd-vol
          mountPath: /etc/motd
  volumes:
    - name: motd-vol
      configMap:
        name: motd-config
EOF
```

```bash
kubectl logs configmap-file-test -n lab-apps
```

The ConfigMap's `motd.txt` key shows up as an actual file at
`/etc/motd/motd.txt` inside the container — a different delivery mechanism
than Step 3 entirely, and the one you'll use next for something more
visual.

Clean up:

```bash
kubectl delete pod configmap-file-test -n lab-apps
```

---

## Step 5: Replace NGINX's default page with a ConfigMap

```bash
cat <<'EOF' > custom-index.html
<html><body><h1>Served from a ConfigMap</h1></body></html>
EOF

kubectl create configmap nginx-html -n lab-apps --from-file=index.html=custom-index.html
```

Now update `nginx-deployment` itself to mount this ConfigMap over NGINX's
default content directory:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: lab-apps
spec:
  replicas: 2
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
      volumes:
        - name: html
          configMap:
            name: nginx-html
EOF
```

This changes the Pod template, so — exactly like Exercise 3 — it triggers
a real rolling update:

```bash
kubectl rollout status deployment/nginx-deployment -n lab-apps
```

Confirm the new content is being served:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip
```

You should see `Served from a ConfigMap` instead of the default NGINX
welcome page.

---

## Step 6: Update the ConfigMap and time how long the change takes

Change the file and push the update using a common real-world idiom —
rendering the updated object as YAML and piping it straight into `apply`,
so you don't have to delete and recreate the ConfigMap:

```bash
cat <<'EOF' > custom-index.html
<html><body><h1>Updated content, same ConfigMap</h1></body></html>
EOF

kubectl create configmap nginx-html -n lab-apps --from-file=index.html=custom-index.html \
  --dry-run=client -o yaml | kubectl apply -f -
```

Check immediately:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip
```

You'll likely still see the **old** content. This is a real and
important behavior, not a bug: the kubelet syncs mounted ConfigMap volumes
on a periodic interval (by default roughly once a minute), not instantly.
Wait about a minute and try again:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip
```

This time you should see the updated content — the running Pods picked it
up on their own, with no restart.

This is the opposite of what you'd see with `envFrom` (Step 3): environment
variables are only ever read once, at container start. If `app-config`
changed right now, a running Pod using `envFrom` would keep the *old*
values indefinitely, with no eventual sync at all — only a full restart
reads them again.

---

## Step 7: Force an immediate reload

Waiting up to a minute is rarely acceptable in practice, and it does
nothing at all for env-var-based config. The reliable way to guarantee
new Pods — and therefore fresh config, however it's attached — is the
same command from Exercise 3:

```bash
kubectl rollout restart deployment/nginx-deployment -n lab-apps
kubectl rollout status deployment/nginx-deployment -n lab-apps
```

---

## Step 8: Troubleshoot a ConfigMap key that doesn't exist

You already saw one ConfigMap failure mode back in Exercise 2, Step 7d — a
Pod referencing a ConfigMap that doesn't exist **at all**, stuck forever
in `ContainerCreating`. This one is different: the ConfigMap exists, but
the specific *key* you asked for inside it doesn't.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-badkey-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo $GREETING"]
      env:
        - name: GREETING
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: GREETIN_TYPO
EOF
```

```bash
kubectl get pod configmap-badkey-test -n lab-apps
```

`STATUS` shows `CreateContainerConfigError` — a distinctly different
failure than the stuck `ContainerCreating` from Exercise 2, and worth
being able to tell apart on sight:

- **Missing ConfigMap entirely** -> stuck `ContainerCreating` (the kubelet
  can't even mount the volume).
- **ConfigMap exists, but the key doesn't** -> `CreateContainerConfigError`
  (the kubelet got far enough to know the reference itself is broken).

```bash
kubectl describe pod configmap-badkey-test -n lab-apps
```

Events will name the exact missing key:

```
couldn't find key GREETIN_TYPO in ConfigMap lab-apps/app-config
```

Fix it:

```bash
kubectl delete pod configmap-badkey-test -n lab-apps

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-badkey-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo $GREETING"]
      env:
        - name: GREETING
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: GREETING
EOF
```

```bash
kubectl logs configmap-badkey-test -n lab-apps
```

Should print `Hello from a ConfigMap` cleanly. Clean up:

```bash
kubectl delete pod configmap-badkey-test -n lab-apps
rm -f motd.txt custom-index.html
```

---

## Leave this running

Keep `nginx-deployment` (now serving from `nginx-html`), `app-config`,
`motd-config`, and `nginx-html` — nothing here needs to be undone before
moving on.

---

## Recap

In this exercise, you:

- Created ConfigMaps from literal values and from a file.

- Injected ConfigMap data as environment variables with `envFrom`, and
  mounted the same kind of data as real files with a `configMap` volume.

- Used a ConfigMap to replace `nginx-deployment`'s served content, and
  confirmed it with a live request.

- Updated a ConfigMap in place and watched a running Pod pick up the
  change on its own after the kubelet's periodic sync — and know that
  environment-variable-based config would **never** have updated the same
  way without a restart.

- Used `kubectl rollout restart` to force an immediate, guaranteed reload.

- Told apart two different ConfigMap failure modes by their status alone:
  a missing ConfigMap (`ContainerCreating`, from Exercise 2) versus a
  missing key inside an existing one (`CreateContainerConfigError`).

---

**Previous:** [Exercise 11 — Declarative YAML](11-declarative-yaml.md)

**Next:** [Exercise 13 — Secrets](13-secrets.md)
