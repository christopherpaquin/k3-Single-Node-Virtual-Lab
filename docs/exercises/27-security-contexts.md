# Exercise 27: Security Contexts

**Module:** Security

**Prerequisite:** [Exercise 26 — k3s Service and Host-Level Investigation](26-k3s-service-and-host-level-investigation.md)

---

## Introduction

Containers are not full virtual machines — by default, a containerized
process shares the host's kernel, isolated mainly through Linux
namespaces and cgroups rather than hardware-level separation. That makes
*how much* a container is allowed to do a genuinely important security
boundary, not just a formality. A `securityContext` (settable at the Pod
or individual container level) is Kubernetes' interface to the underlying
Linux security controls — user ID, filesystem permissions, and
capabilities — that govern exactly that. By default, a container runs as
`root` inside its own namespace, with a writable filesystem and most
default Linux capabilities intact. None of that is required for most
applications — a `securityContext` lets you strip away exactly what isn't
needed, following the general security principle of **least privilege**,
so that if a container is ever compromised, there's meaningfully less it
can do.

This exercise makes each restriction concrete: not just configuring a
setting, but showing the specific thing it actually blocks.

---

## What you'll do

- Run a container as a non-root user, and compare it against the default.
- Watch a real operation fail specifically *because* it needed root.
- Prevent privilege escalation.
- Make a container's root filesystem read-only, and prove it.
- Drop Linux capabilities, and watch a specific operation stop working.
- Compare a privileged container's view of the host against a normal
  one's.
- Review the real risk behind `hostPath`, host networking, host PID, and
  host IPC.

---

## Step 1: Run as non-root, and compare against the default

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nonroot-demo
  namespace: lab-apps
spec:
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
EOF
```

```bash
kubectl exec nonroot-demo -n lab-apps -- id
```

`uid=1000`. Compare against a container with no `securityContext` at all:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl exec <nginx-pod-name> -n lab-apps -- id
```

`uid=0(root)` — the container image's default, unless you explicitly
override it. Most images, including official NGINX, run as root by
default.

---

## Step 2: Watch an operation actually fail because it needed root

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nonroot-nginx-demo
  namespace: lab-apps
spec:
  securityContext:
    runAsUser: 1000
  containers:
    - name: nginx
      image: nginx:1.27
EOF
```

```bash
kubectl get pod nonroot-nginx-demo -n lab-apps
```

Likely `CrashLoopBackOff`.

```bash
kubectl logs nonroot-nginx-demo -n lab-apps
```

Look for `bind() to 0.0.0.0:80 failed (13: Permission denied)`. Ports
below `1024` are privileged on Linux — binding one has historically
required root. This is a real, common gotcha, not a contrived failure:
plenty of off-the-shelf images assume they're allowed to bind a low port
and simply break under `runAsNonRoot` without also being reconfigured to
listen on a higher port.

```bash
kubectl delete pod nonroot-nginx-demo -n lab-apps
```

---

## Step 3: Prevent privilege escalation

```bash
kubectl patch pod nonroot-demo -n lab-apps --type=json \
  -p '[{"op":"add","path":"/spec/containers/0/securityContext","value":{"allowPrivilegeEscalation":false}}]' 2>/dev/null || true
```

(Pods are mostly immutable after creation — in practice you'd set this in
the original manifest, the way the rest of this exercise's Pods do it
directly.) The setting itself:

```yaml
securityContext:
  allowPrivilegeEscalation: false
```

This blocks a process from gaining **more** privileges than it started
with — for example, via a `setuid` binary — regardless of whether the
container starts as root or not. It's one of the settings required by
Kubernetes' own "restricted" Pod Security Standard, and there's rarely a
legitimate reason to need it enabled.

---

## Step 4: Read-only root filesystem, proven

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: readonly-demo
  namespace: lab-apps
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        readOnlyRootFilesystem: true
EOF
```

```bash
kubectl exec readonly-demo -n lab-apps -- sh -c "echo test > /somefile.txt"
```

`Read-only file system` — a real write attempt, really blocked. An
application that genuinely needs to write somewhere (temp files, a cache)
would get an explicit writable `emptyDir` volume mounted at just that one
path, layered on top of an otherwise fully read-only container — narrowly
targeted, instead of leaving the whole filesystem writable by default.

```bash
kubectl delete pod readonly-demo -n lab-apps
```

---

## Step 5: Drop capabilities, and watch a specific one disappear

Linux capabilities break "root's powers" into individually grantable
pieces — `CAP_NET_RAW` (raw sockets, needed for tools like `ping`) is a
good one to test directly, since containers have it by default:

```bash
kubectl exec nonroot-demo -n lab-apps -- ping -c1 8.8.8.8
```

This should succeed (assuming your VM has outbound internet access) —
`CAP_NET_RAW` is present by default. Now try it with every capability
dropped:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cap-drop-demo
  namespace: lab-apps
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        capabilities:
          drop: ["ALL"]
EOF
```

```bash
kubectl exec cap-drop-demo -n lab-apps -- ping -c1 8.8.8.8
```

`Operation not permitted` — the exact same command, failing for a very
specific, provable reason: without `CAP_NET_RAW`, the process can't open
the raw socket `ping` needs, no matter what user it's running as.

```bash
kubectl delete pod cap-drop-demo -n lab-apps
```

---

## Step 6: Privileged versus normal — a container's view of `/dev`

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-demo
  namespace: lab-apps
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        privileged: true
EOF
```

```bash
kubectl exec privileged-demo -n lab-apps -- ls /dev
```

Compare against a normal container:

```bash
kubectl exec nonroot-demo -n lab-apps -- ls /dev
```

The privileged Pod sees the **host's** real device nodes — potentially
including block devices like the LVM volume from Exercise 21 — while the
normal Pod sees only a small, isolated, virtual set (`null`, `zero`,
`random`, `urandom`, and a few others). `privileged: true` doesn't just
relax one restriction; it removes nearly all container isolation for that
container, giving it access close to root on the host itself. Treat this
setting as something to avoid entirely outside of genuine
infrastructure-level tooling that specifically requires it.

```bash
kubectl delete pod privileged-demo -n lab-apps
```

---

## Step 7: Other host-sharing risks worth knowing, even without a live demo

The following weren't demonstrated live in this exercise — each carries
its own real risk, and is worth recognizing on sight in a manifest:

- **`hostPath` volumes** — mount a directory from the **node's own
  filesystem** directly into a container. Depending on the path chosen,
  this can range from mildly risky to a direct container-escape vector
  (e.g. mounting `/` or `/var/run/docker.sock`-equivalent paths).

- **`hostNetwork: true`** — the container shares the node's network
  namespace entirely, rather than getting its own Pod IP. It can bind any
  host port directly and observe host network traffic — this is exactly
  the mechanism K3s's own ServiceLB Pods use (Exercise 5), which is
  legitimate for a purpose-built system component, but rarely appropriate
  for an application workload.

- **`hostPID: true`** — the container can see (and potentially signal)
  every process on the **host**, not just its own — including processes
  belonging to completely unrelated Pods.

- **`hostIPC: true`** — shares the host's inter-process communication
  namespace (shared memory, semaphores), which can allow interference
  with unrelated processes' IPC.

All four share a common shape with `privileged: true`: each one removes a
specific, normally-guaranteed isolation boundary between a container and
the host it's running on. None of them are wrong to use in principle — a
DaemonSet-based monitoring or CNI agent may genuinely need one — but each
should be treated as a deliberate, reviewed exception, not a convenience
default.

---

## Recap

In this exercise, you:

- Ran a container as a non-root user, and compared it against a default
  container running as root.

- Watched NGINX itself fail to start under `runAsNonRoot`, with a log
  line naming exactly why — a real, common real-world gotcha.

- Reviewed `allowPrivilegeEscalation: false` and what it specifically
  blocks.

- Proved a read-only root filesystem with a real, rejected write attempt.

- Dropped all Linux capabilities and watched `ping` specifically fail
  once `CAP_NET_RAW` was gone — the same command, working under default
  capabilities and failing under none.

- Compared a privileged container's view of `/dev` against a normal
  container's, and saw concretely how much isolation `privileged: true`
  removes.

- Reviewed `hostPath`, `hostNetwork`, `hostPID`, and `hostIPC` as a
  family of settings that all remove a specific host/container isolation
  boundary, each deserving deliberate review rather than casual use.

---

**Previous:** [Exercise 26 — k3s Service and Host-Level Investigation](26-k3s-service-and-host-level-investigation.md)

**Next:** [Exercise 28 — Service Accounts and RBAC](28-service-accounts-and-rbac.md)
