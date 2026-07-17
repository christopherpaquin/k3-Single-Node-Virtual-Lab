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

- `nfs-common` / `nfs-utils` and `lvm2` aren't required for K3s itself, but you'll
  need them later for the storage tracks in the lab checklist — installing them
  now avoids revisiting this step.

### 2.2 Install K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

This installs K3s as a systemd service, using containerd as the runtime,
Flannel as the CNI, and Traefik as the ingress controller — all bundled by
default, matching the architecture this lab targets.

### 2.3 Verify the install

```bash
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```

The single node should show `Ready`.

### 2.4 Configure `kubectl` access for your user

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u)":"$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
```

Optionally install `kubectl` separately, or keep using `k3s kubectl`. Confirm:

```bash
kubectl get nodes
kubectl get pods -A
```

You should see the core K3s components (`coredns`, `local-path-provisioner`,
`metrics-server`, `traefik`) running in `kube-system`.

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

This deploys Headlamp as a Deployment in `kube-system`, backed by a Service
named `headlamp` on port `80`.

```bash
kubectl -n kube-system rollout status deployment/my-headlamp-headlamp
```

### 3.3 Create an admin login token

Headlamp authenticates with a Kubernetes Service Account token. Create one
scoped to `cluster-admin` (fine for this single-node lab; use a narrower
`ClusterRole` if you want to practice RBAC restriction):

```bash
kubectl -n kube-system create serviceaccount headlamp-admin
kubectl create clusterrolebinding headlamp-admin \
  --serviceaccount=kube-system:headlamp-admin \
  --clusterrole=cluster-admin
kubectl create token headlamp-admin -n kube-system
```

Copy the printed token — you'll paste it into the Headlamp login screen.

### 3.4 Access Headlamp

```bash
kubectl port-forward -n kube-system service/headlamp 8080:80
```

Open `http://localhost:8080`, paste the token from 3.3, and you should see
the cluster overview. This `port-forward` pattern is also covered later, on
your own workloads, in [Phase 5](docs/CHECKLIST.md#phase-5-operational-troubleshooting)
of the checklist — leave this tunnel running (or re-run the command) whenever
you want to check in on the cluster visually while working through the lab.

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
