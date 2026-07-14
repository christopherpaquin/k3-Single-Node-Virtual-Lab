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
- [3. Working Through the Lab](#3-working-through-the-lab)
- [4. Validating Your Work](#4-validating-your-work)

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

## 3. Working Through the Lab

Once K3s is installed and healthy, move on to the full lab checklist:

**[docs/CHECKLIST.md](docs/CHECKLIST.md)**

The checklist is broken into five phases — workload primitives, networking &
exposure, persistent storage (block + NFS), configuration management, and
operational troubleshooting — and is meant to be worked top to bottom.

---

## 4. Validating Your Work

Each step in the checklist uses a **fixed resource name** (see
[docs/CHECKLIST.md](docs/CHECKLIST.md#naming-conventions-reference) — e.g.
the Postgres PVC must be named `postgres-pvc` in the `lab-apps` namespace)
so that an automated script (`scripts/validate.sh`, not yet implemented) can
check for those exact objects rather than guessing whether *some* PVC or
StorageClass satisfies the step. The plan is for that script to run directly
on the K3s VM, inspect live cluster/VM state — e.g. `kubectl get pvc
postgres-pvc -n lab-apps`, or confirming the LVM mount backing the local-path
provisioner exists — and report pass/fail per step.
