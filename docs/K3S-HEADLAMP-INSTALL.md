# K3s and Headlamp Install Guide

This guide covers installing K3s itself, and then the Headlamp web UI on
top of it. It assumes your VM already meets the requirements in
[README §1 — Virtual Machine Requirements](../README.md#1-virtual-machine-requirements),
with a fresh OS and the secondary disk attached but untouched.

## Contents

- [1. Installing K3s](#1-installing-k3s)
- [2. Installing a Web UI (Headlamp)](#2-installing-a-web-ui-headlamp)

---

## 1. Installing K3s

These steps assume a fresh VM with the secondary disk attached but untouched.

> **Run every command in this section as your normal (non-root) login user**
> — the same user you'll keep using for the rest of the lab — using `sudo`
> only where a command is shown with it. Do **not** `sudo su -` / `su -` into
> `root` and run these commands unprefixed. Switching users changes `$HOME`,
> so anything you create while acting as `root` (especially the kubeconfig
> copied in §1.4) ends up under `/root` instead of your own home directory —
> which produces exactly the confusing "permission denied" errors this
> section is written to avoid. The K3s install script already re-invokes
> `sudo` internally wherever it needs root, so there's no reason to become
> `root` yourself at any point.

### 1.1 Update the OS and install prerequisites

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

- `curl` — fetches the K3s install script in §1.2.
- `open-iscsi` / `iscsi-initiator-utils` — iSCSI initiator tooling that K3s's
  storage plumbing probes for at startup. This lab doesn't use iSCSI
  directly, but installing it avoids startup warnings.
- `nfs-common` / `nfs-utils` — NFS **client** tooling (provides the
  `mount.nfs` helper). Not needed by K3s itself, but required later for
  the NFS-backed persistent storage track in the lab exercises.
- `lvm2` — LVM tooling (`pvcreate`, `vgcreate`, `lvcreate`, etc.), needed
  later for the local block storage track in the lab exercises.

Installing the storage tooling now, before K3s, means the storage exercises
won't require backtracking to this step later.

### 1.2 Install K3s

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
  requiring a separate `kubectl` install. This detail matters in §1.4 below.
- Writes a systemd unit at `/etc/systemd/system/k3s.service` and
  starts/enables the `k3s` service.
- Generates a cluster kubeconfig at `/etc/rancher/k3s/k3s.yaml`, owned by
  `root` with `0600` permissions — deliberately unreadable by your normal
  user until you complete §1.4.

By default this installs K3s with containerd as the container runtime,
Flannel as the CNI, and Traefik as the ingress controller — all bundled,
matching the architecture this lab targets.

### 1.3 Verify the install

```bash
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```

- `systemctl status k3s` confirms the systemd service is `active (running)`.
- `sudo k3s kubectl ...` explicitly runs K3s's bundled client **as root** via
  `sudo`, so it can read the root-owned kubeconfig directly. This is why it
  works immediately after install, before your own user has access (§1.4).

The single node should show `Ready`.

### 1.4 Configure `kubectl` access for your user

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
**symlink to the `k3s` binary** (§1.2), and K3s's bundled kubectl does *not*
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

## 2. Installing a Web UI (Headlamp)

A web UI isn't required for the lab — everything below works purely through
`kubectl` — but it's a convenient way to browse the cluster visually as you
build up resources, so it's worth installing now before you start the
exercises.

**[Headlamp](https://headlamp.dev/)** is used here rather than the older
Kubernetes Dashboard: Dashboard has been archived by the Kubernetes project
and no longer receives updates, while Headlamp is the actively maintained
project recommended as its successor (Kubernetes SIG UI).

### 2.1 Install Helm

K3s doesn't bundle the `helm` CLI, so install it first:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2.2 Install Headlamp, exposed persistently over the network

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
`nginx-nodeport`'s `30080` from the lab exercises. A NodePort Service is
exposed on **every node's IP**, permanently, as long as the Service exists —
no running/blocking foreground command required, unlike `port-forward`.

Check the rollout:

```bash
kubectl -n kube-system rollout status deployment/my-headlamp
```

**On surviving reboots:** no extra step is needed here. Headlamp is a normal
Kubernetes Deployment, not a host process — Kubernetes itself is responsible
for keeping it running, including after a reboot. K3s was already installed
as an enabled systemd service back in §1.2, so it starts automatically on
every VM boot; once K3s is back up, it reschedules every Deployment that
existed before, Headlamp included. You can verify this after the fact with:

```bash
sudo reboot
# wait for the VM to come back, then:
kubectl get nodes
kubectl -n kube-system get pods -l app.kubernetes.io/instance=my-headlamp
```

### 2.3 Create a long-lived admin token (once)

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
once via §2.4 below, and you shouldn't need to touch this again for the
lifetime of the VM.

> **Security note:** this token is a bearer credential for full
> `cluster-admin` — anyone who has it can do anything to your cluster.
> Treat it like a root password (e.g. save it in a password manager rather
> than a plain text file), and don't set a long duration like this on a
> shared or internet-facing cluster. If you'd rather practice tighter RBAC
> instead of blanket `cluster-admin`, re-run the `helm install` from §2.2
> with `--set clusterRoleBinding.clusterRoleName=<a narrower ClusterRole>`.

### 2.4 Access Headlamp

Open `http://<node-ip>:30081` from any machine on the same network as the
VM — the same node IP already used for the NodePort and Ingress exercises —
and paste the token from §2.3. No `port-forward`, no `localhost`, and
nothing needs to keep running in your terminal.

---

Once K3s and Headlamp are installed and healthy, head back to the
[README](../README.md#2-lab-exercises) to start the lab exercises.
