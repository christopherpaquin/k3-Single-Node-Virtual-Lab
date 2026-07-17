<div align="center">

<img src="https://raw.githubusercontent.com/kubernetes/kubernetes/master/logo/logo.png" alt="Kubernetes logo" width="120" />

# K3s Single-Node Virtual Lab

[![K3s](https://img.shields.io/badge/K3s-lightweight%20k8s-FFC61C?logo=k3s&logoColor=black)](https://k3s.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-compatible-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Fedora](https://img.shields.io/badge/Fedora-Server-51A2DA?logo=fedora&logoColor=white)](https://fedoraproject.org/server/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

</div>

A self-paced lab for standing up a single-node [K3s](https://k3s.io/) cluster and
working through core Kubernetes primitives — workloads, networking, dual-track
persistent storage (local block via LVM, and network via NFS), config
management, and troubleshooting.

This lab is designed to run on **Ubuntu** or **Fedora** (RHEL is intentionally
avoided to keep the lab free of subscription/registration requirements).

## Contents

- [1. Virtual Machine Requirements](#1-virtual-machine-requirements)
- [2. Installing K3s](#2-installing-k3s)
- [3. Installing a Web UI (Headlamp)](#3-installing-a-web-ui-headlamp)
- [4. Working Through the Lab](#4-working-through-the-lab)
- [5. Validating Your Work](#5-validating-your-work)

---

## 1. Virtual Machine Requirements

| Resource | Allocation | Notes |
|---|---|---|
| Operating System | Ubuntu 22.04/24.04 LTS **or** Fedora Server (latest) | Either works; instructions below note where the two diverge. |
| Compute | 2 vCPUs minimum | Combined control-plane + worker workload. |
| Memory | 4-8 GB RAM | Scale toward 8 GB if you plan to add monitoring/telemetry later. |
| Root Disk | 20-40 GB | OS + K3s binaries + container images. |
| Secondary Disk | 10-20 GB, raw/unformatted | Attached separately for the LVM/block storage track in the lab (Phase 3, Track A). Do not partition or format it ahead of time. |
| Network | Static or DHCP-reserved IP, outbound internet access | Needed to pull the K3s install script and container images. |

---

## 2. Installing K3s

These steps assume a fresh VM with the secondary disk attached but untouched.

> **Run every command in this section as your normal (non-root) login user**
> — the same user you'll keep using for the rest of the lab — using `sudo`
> only where a command is shown with it. Do **not** `sudo su -` / `su -` into
> `root` and run these commands unprefixed. Switching users changes `$HOME`,
> so anything you create while acting as `root` (especially the kubeconfig
> copied in §2.4) ends up under `/root` instead of your own home directory —
> which produces exactly the confusing "permission denied" errors this
> section is written to avoid. The K3s install script already re-invokes
> `sudo` internally wherever it needs root, so there's no reason to become
> `root` yourself at any point.

### 2.1 Update the OS and install prerequisites

**Ubuntu:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl open-iscsi nfs-common lvm2
```

**Fedora:**
```bash
sudo dnf upgrade -y
sudo dnf install -y curl iscsi-initiator-utils nfs-utils lvm2
```

What each package is for:

- `curl` — fetches the K3s install script in §2.2.
- `open-iscsi` / `iscsi-initiator-utils` — iSCSI initiator tooling that K3s's
  storage plumbing probes for at startup. This lab doesn't use iSCSI
  directly, but installing it avoids startup warnings.
- `nfs-common` / `nfs-utils` — NFS **client** tooling (provides the
  `mount.nfs` helper). Not needed by K3s itself, but required later for
  Phase 3 Track B (NFS-backed persistent storage) in the checklist.
- `lvm2` — LVM tooling (`pvcreate`, `vgcreate`, `lvcreate`, etc.), needed
  later for Phase 3 Track A (local block storage) in the checklist.

Installing the storage tooling now, before K3s, means Phase 3 won't require
backtracking to this step later.

### 2.2 Install K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

Run this as your normal user, per the note above — the script detects it
isn't running as `root` and transparently re-invokes the privileged parts of
itself with `sudo`, prompting for your password if needed. You never need to
type `sudo` yourself here, and you should never run it as `root` directly.

This script:

- Downloads the K3s binary to `/usr/local/bin/k3s`.
- Creates `/usr/local/bin/kubectl` (and `crictl`, `ctr`) as **symlinks to the
  `k3s` binary** — K3s bundles its own kubectl-compatible client instead of
  requiring a separate `kubectl` install. This detail matters in §2.4 below.
- Writes a systemd unit at `/etc/systemd/system/k3s.service` and
  starts/enables the `k3s` service.
- Generates a cluster kubeconfig at `/etc/rancher/k3s/k3s.yaml`, owned by
  `root` with `0600` permissions — deliberately unreadable by your normal
  user until you complete §2.4.

By default this installs K3s with containerd as the container runtime,
Flannel as the CNI, and Traefik as the ingress controller — all bundled,
matching the architecture this lab targets.

### 2.3 Verify the install

```bash
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```

- `systemctl status k3s` confirms the systemd service is `active (running)`.
- `sudo k3s kubectl ...` explicitly runs K3s's bundled client **as root** via
  `sudo`, so it can read the root-owned kubeconfig directly. This is why it
  works immediately after install, before your own user has access (§2.4).

The single node should show `Ready`.

### 2.4 Configure `kubectl` access for your user

Copy the cluster's kubeconfig to your own user so you're not running
everything through `sudo k3s kubectl` for the rest of the lab:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u)":"$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
```

What each line does:

- `mkdir -p ~/.kube` — creates kubectl's default config directory if it
  doesn't already exist.
- `sudo cp ...` — copies the root-owned kubeconfig into your own
  `~/.kube/config`; `sudo` is required here only to *read* the source file.
- `sudo chown "$(id -u)":"$(id -g)" ...` — hands ownership of the copy to
  your own user (`id -u`/`id -g` resolve to your current UID/GID), so you
  won't need `sudo` to read it afterwards.
- `chmod 600 ...` — restricts the file to your own user, since it contains a
  full-admin cluster credential.

**Now set `KUBECONFIG`.** This step is easy to skip and produces a confusing
`permission denied` error if you do: `/usr/local/bin/kubectl` is a
**symlink to the `k3s` binary** (§2.2), and K3s's bundled kubectl does *not*
follow standalone kubectl's usual default of falling back to
`~/.kube/config`. Left unset, it defaults straight to
`/etc/rancher/k3s/k3s.yaml` — the root-owned original — even though you just
set up a perfectly good copy:

```bash
export KUBECONFIG=~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
```

The `export` takes effect in your current shell immediately; appending to
`~/.bashrc` makes it persist for future logins and new shells. (If you use a
shell other than bash, add the equivalent line to that shell's rc file
instead — e.g. `~/.zshrc`.)

Confirm everything works:

```bash
kubectl get nodes
kubectl get pods -A
```

You should see the core K3s components (`coredns`, `local-path-provisioner`,
`metrics-server`, `traefik`) running in `kube-system`, and your node listed
as `Ready` — this time via plain `kubectl`, with no `sudo` needed.

> **Alternative:** installing a standalone `kubectl` binary (rather than
> relying on K3s's symlinked one) follows the normal `KUBECONFIG` /
> `~/.kube/config` default-lookup behavior out of the box, sidestepping this
> quirk entirely. See the [official kubectl install
> docs](https://kubernetes.io/docs/tasks/tools/#kubectl) if you'd prefer
> that route — either works for the rest of this lab.

---

## 3. Installing a Web UI (Headlamp)

A web UI isn't required for the lab — everything below works purely through
`kubectl` — but it's a convenient way to browse the cluster visually as you
build up resources, so it's worth installing now before you start the
checklist.

**[Headlamp](https://headlamp.dev/)** is used here rather than the older
Kubernetes Dashboard: Dashboard has been archived by the Kubernetes project
and no longer receives updates, while Headlamp is the actively maintained
project recommended as its successor (Kubernetes SIG UI).

### 3.1 Install Helm

K3s doesn't bundle the `helm` CLI, so install it first:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 3.2 Install Headlamp

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
helm install my-headlamp headlamp/headlamp --namespace kube-system
```

The Helm chart names every resource after the **release name** you gave it
(`my-headlamp`), not the chart name — so this creates a Deployment, Service,
and ServiceAccount all named `my-headlamp` in `kube-system`, not
`my-headlamp-headlamp` / `headlamp`. Check the rollout with the correct
name:

```bash
kubectl -n kube-system rollout status deployment/my-headlamp
```

### 3.3 Get an admin login token

Unlike the manual setup some guides show, this chart **already creates** a
`my-headlamp` ServiceAccount bound to the `cluster-admin` ClusterRole by
default (`clusterRoleBinding.create: true` in its `values.yaml`) — the
`helm install` output above even told you the exact command to run. No
separate `kubectl create serviceaccount`/`clusterrolebinding` step needed:

```bash
kubectl create token my-headlamp --namespace kube-system
```

Copy the printed token — you'll paste it into the Headlamp login screen.
(If you want to practice tighter RBAC instead of `cluster-admin`, re-run the
`helm install` from §3.2 with `--set clusterRoleBinding.clusterRoleName=<a
narrower ClusterRole>`.)

### 3.4 Access Headlamp

`kubectl port-forward` binds to the machine it's *run on* — if you're
working from the VM's own desktop/browser, plain `localhost` works. If
you're connecting to the VM remotely (SSH from your workstation, which is
the more common setup for this lab), `localhost` refers to your own
workstation, not the VM, and the tunnel won't be reachable there unless you
tell it to listen on all interfaces and browse to the VM's IP instead:

```bash
kubectl port-forward -n kube-system service/my-headlamp --address 0.0.0.0 8080:80
```

Then open `http://<node-ip>:8080` (the same node IP used for the NodePort
and Ingress steps in the checklist), paste the token from 3.3, and you
should see the cluster overview.

> **Security note:** `--address 0.0.0.0` exposes this tunnel to your whole
> network over plain HTTP for as long as the command keeps running — fine
> for an isolated lab VM, but stop it (`Ctrl+C`) when you're done rather
> than leaving it up indefinitely. If you'd rather not expose it at all,
> open an SSH tunnel from your workstation instead
> (`ssh -L 8080:localhost:8080 <user>@<node-ip>`) and keep the original
> `kubectl port-forward -n kube-system service/my-headlamp 8080:80` (no
> `--address`) running on the VM — then `http://localhost:8080` on your own
> workstation works too.

This `port-forward` pattern is also covered later, on your own workloads, in
[Phase 5](docs/CHECKLIST.md#phase-5-operational-troubleshooting) of the
checklist — leave a tunnel running (or re-run the command) whenever you want
to check in on the cluster visually while working through the lab.

---

## 4. Working Through the Lab

Once K3s is installed and healthy, move on to the full lab checklist:

**[docs/CHECKLIST.md](docs/CHECKLIST.md)**

The checklist is broken into five phases — workload primitives, networking &
exposure, persistent storage (block + NFS), configuration management, and
operational troubleshooting — and is meant to be worked top to bottom.

---

## 5. Validating Your Work

Each step in the checklist uses a **fixed resource name** (see
[docs/CHECKLIST.md](docs/CHECKLIST.md#naming-conventions-reference) — e.g.
the Postgres PVC must be named `postgres-pvc` in the `lab-apps` namespace)
so that a validation script can check for those exact objects rather than
guessing whether *some* PVC or StorageClass satisfies the step.

Every checklist item has a matching script under [`scripts/`](scripts/) —
the checklist itself links each item to its `script:` name — plus a master
runner, [`scripts/validate.sh`](scripts/validate.sh), that runs all of them
and prints a pass/fail summary.

**Run this on the K3s VM itself**, not your workstation — several checks
(LVM, mount points, NFS client tooling) inspect host state directly and only
make sense there. Clone/pull this repo onto the VM, then:

```bash
# run everything, in checklist order
./scripts/validate.sh

# run just one phase
./scripts/validate.sh phase3

# run a single step
./scripts/phase2-02-nodeport.sh

# list every available script
./scripts/validate.sh --list
```

By default the scripts pick up `~/.kube/config`, falling back to
`/etc/rancher/k3s/k3s.yaml`. If you're validating from a copied-out kubeconfig
(e.g. pulled from the VM to check remotely for non-host-level steps), point
`KUBECONFIG` at it instead:

```bash
KUBECONFIG=/path/to/k3s.yaml ./scripts/validate.sh
```

The two NFS steps in Phase 3 (Track B) also need `NFS_SERVER` and
`NFS_EXPORT_PATH` set, since the export lives on your hypervisor and is
environment-specific:

```bash
NFS_SERVER=192.168.1.1 NFS_EXPORT_PATH=/srv/nfs/k3s-lab ./scripts/phase3-05-nfs-export.sh
```

A few steps (data survives a Pod restart, `kubectl logs -f` streaming live,
an interactive `exec` shell) are inherently something you have to observe
yourself — their scripts verify what can be checked structurally and print a
reminder for the manual part.
