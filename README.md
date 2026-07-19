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
- [K3s/Headlamp Install](docs/K3S-HEADLAMP-INSTALL.md)
- [2. Lab Exercises](#2-lab-exercises)

---

## 1. Virtual Machine Requirements

| Resource | Allocation | Notes |
|---|---|---|
| Operating System | Ubuntu 22.04/24.04 LTS **or** Fedora Server (latest) | Either works; instructions below note where the two diverge. |
| Compute | 2 vCPUs minimum | Combined control-plane + worker workload. |
| Memory | 4-8 GB RAM | Scale toward 8 GB if you plan to add monitoring/telemetry later. |
| Root Disk | 20-40 GB | OS + K3s binaries + container images. |
| Secondary Disk | 10-20 GB, raw/unformatted | Attached separately for the LVM/block storage track in the lab exercises (Exercise 21, Track A). Do not partition or format it ahead of time. |
| NFS Export (optional) | Any host on the same network able to export an NFS share (a hypervisor, NAS, or separate Linux box) | Only needed for the optional network storage track (Exercise 21, Track B). Not required to complete the rest of the lab. |
| Network | Static or DHCP-reserved IP, outbound internet access | Needed to pull the K3s install script and container images. |

### Adding the secondary disk

How you attach the secondary disk depends on your hypervisor/platform —
this lab doesn't assume a specific one — but the general shape is the same
everywhere:

- **VirtualBox:** VM Settings → Storage → add a second virtual hard disk
  (a new `.vdi`/`.vmdk` file) on the same or a different controller from
  the OS disk.
- **VMware Workstation/Fusion/ESXi:** VM Settings → Add a new hard disk →
  create a new virtual disk of the size above.
- **Proxmox:** VM → Hardware → Add → Hard Disk, on any available
  storage.
- **A cloud VM (AWS/Azure/GCP/etc.):** attach a second block-storage
  volume (EBS/Managed Disk/Persistent Disk) to the instance.

In every case: attach it as a second, independent disk — not a partition
on the existing OS disk — and leave it completely raw (no filesystem, no
partition table). The lab exercises handle partitioning, LVM, and
formatting themselves; anything pre-formatted here will just need to be
wiped again later. After attaching it and booting the VM, `lsblk` should
show it as an extra whole-disk entry (commonly `/dev/sdb`, but confirm
rather than assume) with no `FSTYPE` and no children — this is exactly
what the lab's storage exercise checks for.

### About the optional NFS export

Exercise 21's Track B (network-attached storage) needs an NFS share
exported from **outside** this VM — a hypervisor, a NAS, or any other
Linux host on the same network with `nfs-kernel-server` (or equivalent)
configured to export a directory to this VM's IP or subnet. Setting up
that export is outside the scope of this lab, since it depends entirely on
what's available in your environment — Track A (local block storage via
LVM) alone is enough to complete every other exercise in this lab. Skip
this requirement entirely if you don't have infrastructure to export a
share from; Exercise 21 covers this explicitly as an optional track.

Once your VM meets the requirements above, head to the
**[K3s/Headlamp Install guide](docs/K3S-HEADLAMP-INSTALL.md)** to install
K3s itself and, optionally, the Headlamp web UI.

---

## 2. Lab Exercises

Once K3s is installed and healthy, move on to the exercises below.

Unlike a simple pass/fail checklist, each exercise is a short, narrative
walkthrough of one topic: you run a command, read what it prints, and the
text tells you *why* you ran it and *what to look for* in the output before
moving to the next one. The same handful of inspection commands
(`kubectl get`, `describe`, `logs`, `events`) come up again and again on
purpose — the goal of this lab is comfort navigating a running cluster from
the CLI, not just completing tasks.

Every exercise ends with a short recap and a link to the next one, so you
can either:

- Start at **Exercise 1** and follow the "Next" link at the bottom of each
  page straight through to the end, or

- Jump directly to whichever topic you want from the index below.

Exercises are grouped into modules, and are meant to be worked in order
within a module — later exercises assume resources created in earlier ones
still exist.

### Foundations

1. [Cluster Orientation](docs/exercises/01-cluster-orientation.md)
2. [Pods and Basic Workloads](docs/exercises/02-pods-and-basic-workloads.md)
3. [Deployments and ReplicaSets](docs/exercises/03-deployments-and-replicasets.md)

### Networking

4. [Services and Port Access](docs/exercises/04-services-and-port-access.md)
5. [k3s ServiceLB](docs/exercises/05-k3s-servicelb.md)
6. [Traefik Ingress](docs/exercises/06-traefik-ingress.md)
7. [CoreDNS and Service Discovery](docs/exercises/07-coredns-and-service-discovery.md)
8. [Single-Node Networking](docs/exercises/08-single-node-networking.md)

### Configuration & Organization

9. [Namespaces](docs/exercises/09-namespaces.md)
10. [Labels, Selectors, and Annotations](docs/exercises/10-labels-selectors-and-annotations.md)
11. [Declarative YAML](docs/exercises/11-declarative-yaml.md)
12. [ConfigMaps](docs/exercises/12-configmaps.md)
13. [Secrets](docs/exercises/13-secrets.md)

### Observability & Troubleshooting

14. [Logging and Troubleshooting](docs/exercises/14-logging-and-troubleshooting.md)
15. [Pod Restart and Recovery](docs/exercises/15-pod-restart-and-recovery.md)
16. [Health Checks](docs/exercises/16-health-checks.md)

### Scheduling & Resources

17. [Resource Requests and Limits](docs/exercises/17-resource-requests-and-limits.md)
18. [Node Labels, Taints, and Scheduling](docs/exercises/18-node-labels-taints-and-scheduling.md)
19. [Single-Node Maintenance](docs/exercises/19-single-node-maintenance.md)

### Workload Types

20. [Jobs and CronJobs](docs/exercises/20-jobs-and-cronjobs.md)
21. [Local Storage](docs/exercises/21-local-storage.md)
22. [StatefulSets](docs/exercises/22-statefulsets.md)
23. [DaemonSets](docs/exercises/23-daemonsets.md)
24. [Multi-Container Pods](docs/exercises/24-multi-container-pods.md)

### Platform Internals

25. [System-Level k3s Components](docs/exercises/25-system-level-k3s-components.md)
26. [k3s Service and Host-Level Investigation](docs/exercises/26-k3s-service-and-host-level-investigation.md)

### Security

27. [Security Contexts](docs/exercises/27-security-contexts.md)
28. [Service Accounts and RBAC](docs/exercises/28-service-accounts-and-rbac.md)

### Tooling

29. [Helm](docs/exercises/29-helm.md)
30. [CLI Efficiency](docs/exercises/30-cli-efficiency.md)

### Resilience & Capstone

31. [Failure Scenarios](docs/exercises/31-failure-scenarios.md)
32. [Backup and Recovery](docs/exercises/32-backup-and-recovery.md)
33. [Final Troubleshooting Challenge](docs/exercises/33-final-troubleshooting-challenge.md)
