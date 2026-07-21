# Exercise 15: Pod Restart and Recovery

**Module:** Observability & Troubleshooting

**Prerequisite:** [Exercise 14 — Logging and Troubleshooting](14-logging-and-troubleshooting.md)

---

## Introduction

Kubernetes' reliability model is built on the idea of **self-healing**:
you declare desired state, and a controller (or the kubelet, or the
container runtime, depending on the layer) continuously works to restore
it after any disruption, with no human intervention. But "restart"
actually means something different depending on what layer you're
restarting — a container, a Pod, a Deployment, the K3s service, or the
whole host. Some of these you've already done (deleting a Pod in Exercise
3, `rollout restart` in Exercises 3 and 12); this exercise fills in the
levels you haven't tried yet, then puts every level side by side.

---

## What you'll do

- Briefly recap Pod- and Deployment-level restarts you've already done.
- Scale a Deployment to zero and back, and see what that does — and
  doesn't — remove.
- Restart the K3s service itself and observe what survives.
- Reboot the whole VM and observe what comes back automatically — and
  what doesn't.
- Compare all five restart levels directly.

---

## Step 1: Recap — Pod and Deployment-level restarts

You've already done both of these, in earlier exercises:

- **Deleting a Pod managed by a Deployment** — Exercise 3, Step 5. The
  ReplicaSet replaced it within seconds, with a new name and a reset
  `AGE`.

- **`kubectl rollout restart deployment`** — Exercise 3, Step 9, and again
  in Exercise 12, Step 7. Every Pod gets recreated with a new name, same
  spec, no downtime under the default `RollingUpdate` strategy.

Nothing new to run here — just keep both in mind as you go further up the
stack below.

---

## Step 2: Scale a Deployment to zero and back

```bash
kubectl scale deployment nginx-deployment -n lab-apps --replicas=0
kubectl get pods -n lab-apps -l app=nginx-deployment
```

No Pods at all — but check what's still there:

```bash
kubectl get deployment nginx-deployment -n lab-apps
```

The Deployment object itself is untouched, just showing `0/0`. Scaling to
zero is a clean, fully reversible way to stop a workload entirely without
losing its definition, its ConfigMap/Secret references, or its Service.
Speaking of which:

```bash
kubectl get endpoints nginx-clusterip -n lab-apps
```

Empty — exactly the same symptom as the broken-selector Service from
Exercise 4, except this time there's nothing wrong at all; there are
simply no Pods to be an endpoint. `Endpoints: <none>` always means "no
matching Pods right now," which can be either a bug or, as here,
completely intentional.

Scale back up:

```bash
kubectl scale deployment nginx-deployment -n lab-apps --replicas=2
kubectl rollout status deployment/nginx-deployment -n lab-apps
kubectl get endpoints nginx-clusterip -n lab-apps
```

Endpoints repopulate on their own, with no further action needed.

---

## Step 3: Restart the K3s service itself

This is a step above anything `kubectl` can do — it restarts the
component `kubectl` itself depends on. Note the current age of your Pods
first:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Then, on the VM:

```bash
sudo systemctl restart k3s
```

Try a `kubectl` command immediately:

```bash
kubectl get nodes
```

You may see a connection error for a few seconds — the API server is
itself part of what just restarted. Wait a few seconds and retry until it
responds, then check your Pods again:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Compare `AGE` against what you noted before the restart — it should be
**unchanged**. Even though K3s bundles the control plane and the kubelet
into a single service, the actual containers are run by `containerd`, a
separate process that kept running the entire time the control plane was
cycling. Restarting K3s briefly interrupts scheduling and API access — it
does not touch already-running containers.

---

## Step 4: Reboot the whole host

This time, add a standalone Pod to the picture first, deliberately, so you
have something to check afterward that nothing manages:

```bash
kubectl run bare-pod --image=busybox:1.36 --restart=Never -n lab-apps -- sleep 3600
kubectl get pod bare-pod -n lab-apps
```

Confirm it's `Running`, note the current `AGE` of your `nginx-deployment`
Pods one more time, then:

```bash
sudo reboot
```

Give the VM a minute or two to come back up, reconnect, and check cluster
health from the top — the same sequence as Exercise 1:

```bash
sudo systemctl status k3s --no-pager
kubectl get nodes
```

Once the node shows `Ready` again:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

This time, `AGE` **has** reset — unlike Step 3, a full host reboot takes
`containerd` down with it, so every container is genuinely gone and has to
be recreated from scratch once K3s comes back up. The Deployment's desired
state survived (it's stored in K3s's datastore on disk, not in memory),
so the ReplicaSet controller simply rebuilds everything once it's running
again.

Now check the Pod nothing was managing:

```bash
kubectl get pod bare-pod -n lab-apps
```

`NotFound`. Nothing recreated it, because nothing was ever watching over
it in the first place — the exact same lesson from Exercise 2, just
proven this time against a full reboot instead of a manual delete.

---

## Step 5: Compare every level

| Level | What actually happens | What survives |
|---|---|---|
| **A container** crashes | The kubelet restarts just that container, in place, inside the same Pod | Pod identity, IP, everything else about the Pod |
| **A Pod** is deleted | Gone permanently if standalone (Exercise 2); replaced with a new Pod if managed by a controller (Exercise 3) | Depends entirely on whether a controller owns it |
| **A Deployment** is scaled to zero / restarted | Every Pod it manages is removed and/or recreated | The Deployment's own definition, its Service, its ConfigMap/Secret references |
| **The K3s service** restarts | Control plane and API access briefly interrupted | Already-running containers, managed by the separate `containerd` process, are untouched |
| **The host** reboots | Every container process is gone, full stop | Only the *desired state* stored in K3s's datastore — everything is rebuilt from that once K3s comes back up |

The pattern across every row: anything with a controller watching over it
(a Deployment, in this lab) recovers automatically, because the desired
state is durable and something is always reconciling toward it. Anything
without one — a bare Pod — never comes back on its own, no matter which
level of restart caused it to disappear.

---

## Recap

In this exercise, you:

- Recapped Pod- and Deployment-level restarts from earlier exercises.

- Scaled a Deployment to zero and confirmed the Deployment, Service, and
  all configuration survive — only the Pods themselves disappear — then
  scaled back up and watched Service endpoints repopulate automatically.

- Restarted the K3s service and confirmed already-running containers
  aren't affected, because `containerd` is a separate process from the
  control plane that briefly went down.

- Rebooted the VM entirely and confirmed containers **are** recreated
  from scratch this time — but only for Pods a controller actually
  manages; a standalone Pod never came back at all.

- Built a single comparison table spanning every restart level in this
  lab, and the one rule that predicts all of it: only what's under active
  reconciliation recovers automatically.

---

**Previous:** [Exercise 14 — Logging and Troubleshooting](14-logging-and-troubleshooting.md)

**Next:** [Exercise 16 — Health Checks](16-health-checks.md)
