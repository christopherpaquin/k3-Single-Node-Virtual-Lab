# Exercise 26: k3s Service and Host-Level Investigation

**Module:** Platform Internals

**Prerequisite:** [Exercise 25 — System-Level k3s Components](25-system-level-k3s-components.md)

---

## Theme

Every exercise so far has looked at the cluster through `kubectl` — which
means through the API server. This one drops below that entirely, onto
the VM itself, to look at what's actually running underneath: the K3s
process, its on-disk state, and the container runtime `kubectl` is
ultimately just a friendly abstraction over.

All commands in this exercise run **directly on the VM**, not through
`kubectl`.

---

## What you'll do

- Inspect the K3s systemd unit itself.
- Search K3s's own logs more deeply than Exercise 14's brief look.
- Find (or confirm the absence of) K3s's config file.
- Revisit `k3s.yaml` at its source, and understand one detail that
  matters if you ever use it remotely.
- Tour K3s's on-disk state under `/var/lib/rancher/k3s`.
- Use `crictl` to see containers and Pod sandboxes directly — a level of
  detail `kubectl` never shows you.
- Compare `kubectl` visibility against `crictl` visibility directly.
- Find the real host processes behind everything this lab has done.

---

## Step 1: Inspect the K3s systemd unit

```bash
sudo systemctl cat k3s
```

Look at the `ExecStart` line — it's just `/usr/local/bin/k3s server`. That
single command is the **entire** control plane (API server, scheduler,
controller-manager), the kubelet, and K3s's own supervisor for containerd,
all bundled into one process tree. A typical non-K3s cluster runs each of
these as separate systemd services; K3s's single-binary design is exactly
what makes it lightweight enough for a lab like this one.

---

## Step 2: Search K3s's logs more deeply

```bash
sudo journalctl -u k3s --since "1 hour ago" --no-pager | tail -50
```

Search for a specific component:

```bash
sudo journalctl -u k3s --no-pager | grep -i traefik
```

Filter by severity instead of searching text:

```bash
sudo journalctl -u k3s -p err --no-pager
```

`-p err` shows only error-priority-and-above entries — useful for
scanning a long-running cluster's history for anything that actually
mattered, without reading every routine startup/reconciliation line.

---

## Step 3: Find K3s's config file

```bash
ls -la /etc/rancher/k3s/
cat /etc/rancher/k3s/config.yaml 2>/dev/null || echo "no config.yaml present"
```

Unlike `k3s.yaml` (the kubeconfig), a `config.yaml` here is entirely
optional — K3s runs fine without one. This lab's cluster was configured
entirely through install-time behavior and defaults (README §2.2), which
is a completely normal and common way to run K3s; `config.yaml` only
becomes necessary once you want persistent, file-based server flags
instead of a one-off install command.

---

## Step 4: Revisit `k3s.yaml` at its source

You copied this file back in README §2.4 — look at the original directly
this time:

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

Look at the `server:` field — by default it reads
`https://127.0.0.1:6443`, the loopback address, because this file is
written assuming it'll be used **on the node itself**. If you ever copy
this file to a different machine to manage the cluster remotely, that
loopback address needs to be edited to the node's real IP first — copying
it as-is would try to reach `127.0.0.1` on the *remote* machine, not this
VM.

---

## Step 5: Tour K3s's on-disk state

```bash
sudo ls -la /var/lib/rancher/k3s/
```

Three directories matter most:

- **`server/`** — the control plane's own state, including
  `server/db/state.db`, the SQLite datastore mentioned as far back as
  Exercise 13 (where you learned it doesn't encrypt Secrets by default).
  This is the literal file that stores every object you've created in
  this entire lab.

- **`agent/`** — kubelet-side state, including
  `agent/containerd`, where containerd itself stores image and container
  data.

- **`data/`** — versioned, extracted K3s runtime binaries. This is where
  the `containerd-shim-runc-v2` paths you may have noticed back in
  Exercise 1's `systemctl status k3s` output actually live on disk.

```bash
sudo du -sh /var/lib/rancher/k3s/server/db/state.db
```

A quick, concrete sense of how much cluster state this single file
currently holds.

---

## Step 6: `crictl` — container runtime activity directly

K3s bundles its own `crictl` the same way it bundles `kubectl` — as
another symlink to the same binary (recall README §2.2):

```bash
sudo k3s crictl ps
```

This lists running **containers**, not Pods — a more granular view than
`kubectl get pods` gives you. A multi-container Pod (like the sidecar Pod
from Exercise 24) shows up here as multiple separate entries, one per
container, not one combined row.

---

## Step 7: List all containers and Pod sandboxes

```bash
sudo k3s crictl ps -a
```

`-a` includes exited containers too — useful for finding evidence of a
crash after the fact, similar in spirit to `kubectl logs --previous` from
Exercise 14, but at the runtime level instead.

```bash
sudo k3s crictl pods
```

This shows Pod **sandboxes** — a detail `kubectl` never surfaces at all.
Every single Pod, under the hood, is backed by a hidden "pause" container
that does nothing but hold that Pod's network namespace open, so its real
containers can share it. `kubectl` treats a Pod as one clean concept;
`crictl` shows you the actual plumbing underneath that concept.

---

## Step 8: Container logs through the runtime

```bash
sudo k3s crictl ps | grep nginx
```

Copy a container ID, then:

```bash
sudo k3s crictl logs <container-id>
```

Compare this against `kubectl logs` for the same Pod — same underlying
log data, reached by an entirely different path. This matters
specifically when `kubectl logs` isn't an option at all: `crictl` talks
directly to containerd on the local machine, with no dependency on the
API server being reachable — extending the escalation ladder from
Exercise 14 one level further down (`kubectl logs` -> `journalctl -u
k3s` for the K3s service itself -> `crictl`, for the container runtime
directly, independent of whether K3s's control plane is healthy at all).

---

## Step 9: Compare `kubectl` visibility against `crictl` visibility

| | `kubectl` | `crictl` |
|---|---|---|
| Unit of visibility | Pods (an abstraction) | Individual containers and Pod sandboxes |
| Depends on | A reachable API server | Only the local container runtime |
| Shows the "pause" sandbox container? | No | Yes |
| Typical use | Everyday cluster operation | Deep debugging, or when the API server itself is the problem |

---

## Step 10: Real host processes behind everything

```bash
ps aux | grep -E 'k3s|containerd' | grep -v grep
```

You should see the `k3s server` process itself, `containerd`, and a
`containerd-shim-runc-v2` process for roughly every running container in
your cluster — the same shim path referenced in Exercise 1's very first
`systemctl status k3s` output, and in Step 5's tour of `data/`. Every
abstraction this entire lab has worked through — Pods, Deployments,
Services, everything — ultimately resolves down to this: a handful of
real Linux processes on one real VM.

---

## Recap

In this exercise, you:

- Inspected the K3s systemd unit and confirmed its single-binary design.

- Searched K3s's logs by time window, text, and severity.

- Confirmed K3s runs fine without a `config.yaml`, since this lab's
  cluster was configured entirely through install-time behavior.

- Revisited `k3s.yaml` at its source, and know why its default loopback
  server address matters if you ever use a copy of it remotely.

- Toured `/var/lib/rancher/k3s`, including the SQLite datastore file
  underlying literally everything in this lab.

- Used `crictl` to see individual containers and Pod sandboxes — a level
  of detail `kubectl` abstracts away entirely.

- Compared `kubectl` and `crictl` visibility directly, and extended
  Exercise 14's escalation ladder one level further, down to the
  container runtime itself.

- Found the real host processes — `k3s`, `containerd`,
  `containerd-shim-runc-v2` — behind every abstraction used throughout
  this lab.

---

**Previous:** [Exercise 25 — System-Level k3s Components](25-system-level-k3s-components.md)

**Next:** [Exercise 27 — Security Contexts](27-security-contexts.md)
