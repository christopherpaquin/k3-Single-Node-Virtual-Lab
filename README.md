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
- [4. Lab Exercises](#4-lab-exercises)

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

### 3.2 Install Headlamp, exposed persistently over the network

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
helm install my-headlamp headlamp/headlamp \
  --namespace kube-system \
  --set service.type=NodePort \
  --set service.nodePort=30081
```

The Helm chart names every resource after the **release name** you gave it
(`my-headlamp`), not the chart name — so this creates a Deployment, Service,
and ServiceAccount all named `my-headlamp` in `kube-system`, not
`my-headlamp-headlamp` / `headlamp`.

The two `--set` flags replace the chart's default `ClusterIP` Service (only
reachable from inside the cluster, which is why the earlier version of this
guide needed `kubectl port-forward`) with a `NodePort` Service bound to a
fixed port — `30081` here, chosen so it doesn't collide with
`nginx-nodeport`'s `30080` from the checklist. A NodePort Service is exposed
on **every node's IP**, permanently, as long as the Service exists — no
running/blocking foreground command required, unlike `port-forward`.

Check the rollout:

```bash
kubectl -n kube-system rollout status deployment/my-headlamp
```

**On surviving reboots:** no extra step is needed here. Headlamp is a normal
Kubernetes Deployment, not a host process — Kubernetes itself is responsible
for keeping it running, including after a reboot. K3s was already installed
as an enabled systemd service back in §2.2, so it starts automatically on
every VM boot; once K3s is back up, it reschedules every Deployment that
existed before, Headlamp included. You can verify this after the fact with:

```bash
sudo reboot
# wait for the VM to come back, then:
kubectl get nodes
kubectl -n kube-system get pods -l app.kubernetes.io/instance=my-headlamp
```

### 3.3 Create a long-lived admin token (once)

Headlamp's in-cluster mode has no separate user database of its own — it
delegates authentication entirely to the Kubernetes API, so a bearer token
for a ServiceAccount *is* the login credential. This chart already creates a
`my-headlamp` ServiceAccount bound to `cluster-admin` by default
(`clusterRoleBinding.create: true` in its `values.yaml`), so there's no
separate `kubectl create serviceaccount`/`clusterrolebinding` step — you
just need a token for it:

```bash
kubectl create token my-headlamp --namespace kube-system --duration=8760h
```

`kubectl create token` without `--duration` issues a token that expires
after **one hour**, which is why the earlier version of this guide had you
regenerating it constantly. `--duration=8760h` (~1 year) makes it
effectively permanent for a lab: paste it into the Headlamp login screen
once via 3.4 below, and you shouldn't need to touch this again for the
lifetime of the VM.

> **Security note:** this token is a bearer credential for full
> `cluster-admin` — anyone who has it can do anything to your cluster.
> Treat it like a root password (e.g. save it in a password manager rather
> than a plain text file), and don't set a long duration like this on a
> shared or internet-facing cluster. If you'd rather practice tighter RBAC
> instead of blanket `cluster-admin`, re-run the `helm install` from §3.2
> with `--set clusterRoleBinding.clusterRoleName=<a narrower ClusterRole>`.

### 3.4 Access Headlamp

Open `http://<node-ip>:30081` from any machine on the same network as the
VM — the same node IP already used for the NodePort and Ingress steps in the
checklist — and paste the token from 3.3. No `port-forward`, no `localhost`,
and nothing needs to keep running in your terminal.

---

## 4. Lab Exercises

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

25. System-Level k3s Components
26. k3s Service and Host-Level Investigation

### Security

27. Security Contexts
28. Service Accounts and RBAC

### Tooling

29. Helm
30. CLI Efficiency

### Resilience & Capstone

31. Failure Scenarios
32. Backup and Recovery
33. Final Troubleshooting Challenge

---

Entries without a link haven't been written yet — this index will be
updated with a working link as each exercise is added. The legacy
[docs/CHECKLIST.md](docs/CHECKLIST.md) still covers some of this same
ground (workloads, networking, storage, config, ops) in the meantime and
remains usable on its own, but is being superseded by the exercises above
and will eventually be retired once every topic has a home here.
