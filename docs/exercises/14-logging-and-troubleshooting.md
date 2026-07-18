# Exercise 14: Logging and Troubleshooting

**Module:** Observability & Troubleshooting

**Prerequisite:** [Exercise 13 — Secrets](13-secrets.md)

---

## Theme

You've used `kubectl logs`, `describe`, and `exec` individually since
Exercise 2. This exercise treats them as a single toolkit, adds the pieces
you haven't used yet (`--previous`, `-l`, multi-container `-c`, ephemeral
debug containers), and — at the very end — places all of it against one
more layer you haven't touched at all: the K3s service's own logs on the
host, which exist entirely outside anything `kubectl` can see.

---

## What you'll do

- View and follow container logs live.
- Recover logs from a container that already crashed and restarted.
- View logs from one container in a multi-container Pod.
- Pull logs from every Pod matching a label at once.
- Sort cluster-wide events instead of one Pod's events at a time.
- Use `kubectl exec` for one-shot commands, not just interactive shells.
- Debug a Pod that has no debugging tools of its own, using an ephemeral
  container that borrows its network namespace.
- Inspect a container's environment variables and mounted files directly.
- Compare application logs, Kubernetes events, and `journalctl -u k3s` as
  three genuinely different layers of visibility.

---

## Step 1: View and follow logs

Generate a log line first:

```bash
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -n lab-apps -- curl -s nginx-clusterip > /dev/null
```

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Pick one Pod name:

```bash
kubectl logs <pod-name> -n lab-apps
```

The official NGINX image symlinks its access and error logs to
`stdout`/`stderr`, which is exactly what `kubectl logs` reads — you should
see the request you just generated.

Now follow it live:

```bash
kubectl logs -f <pod-name> -n lab-apps
```

While that's running, send a few more requests from another terminal
(re-run the `curl-test` command above) and watch new lines appear in real
time. `Ctrl+C` to stop following.

---

## Step 2: Recover logs from a container that already crashed

```bash
kubectl run crash-demo --image=busybox --restart=Always -n lab-apps -- sh -c "echo dying now; exit 1"
```

Wait for at least one restart:

```bash
kubectl get pod crash-demo -n lab-apps
```

Once `RESTARTS` shows `1` or more, compare these two:

```bash
kubectl logs crash-demo -n lab-apps
kubectl logs crash-demo -n lab-apps --previous
```

The first shows the **current** container instance — which may have
produced little or nothing yet. `--previous` shows the **last** container
instance before the most recent restart — exactly where a crash's actual
output usually lives. This is the single most useful flag for diagnosing
`CrashLoopBackOff` in practice, and it's easy to forget it exists.

Clean up:

```bash
kubectl delete pod crash-demo -n lab-apps
```

---

## Step 3: Logs from one container in a multi-container Pod

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: multi-log-test
  namespace: lab-apps
spec:
  containers:
    - name: web
      image: nginx:1.27
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "while true; do echo sidecar heartbeat; sleep 10; done"]
EOF
```

```bash
kubectl logs multi-log-test -n lab-apps
```

This errors out, asking you to specify a container — with more than one
container in a Pod, `kubectl logs` has no way to guess which one you mean.

```bash
kubectl logs multi-log-test -n lab-apps -c web
kubectl logs multi-log-test -n lab-apps -c sidecar
```

Each container's logs are entirely separate streams. (You'll build a
proper multi-container Pod with an actual shared purpose in the
Multi-Container Pods exercise later — this one exists purely to
demonstrate `-c`.)

Clean up:

```bash
kubectl delete pod multi-log-test -n lab-apps
```

---

## Step 4: Logs from every Pod matching a label

```bash
kubectl logs -n lab-apps -l app=nginx-deployment --all-containers --prefix --tail=5
```

`--prefix` tags each line with the Pod (and container) it came from — with
more than one matching Pod, without it, the output would be an
unattributed jumble. `--tail=5` limits it to the last 5 lines per Pod so
this doesn't dump excessive history.

---

## Step 5: Sort cluster-wide events

`kubectl describe pod` (used constantly since Exercise 2) only shows
events for *that one object*. Events are actually their own resource type,
queryable cluster-wide:

```bash
kubectl get events -n lab-apps --sort-by=.metadata.creationTimestamp
```

```bash
kubectl get events -A --sort-by=.lastTimestamp
```

This is the right tool when you don't yet know *which* object is the
problem — scanning every recent event across a namespace (or the whole
cluster) by time, rather than checking one resource at a time. Kubernetes
doesn't keep these forever, either — by default, events are garbage
collected after about an hour, which is worth knowing before you go
looking for one from yesterday.

---

## Step 6: `kubectl exec` for one-shot commands, not just shells

You've used `kubectl exec -it ... -- /bin/bash` for an interactive shell
since Exercise 2. Drop `-it` for a single non-interactive command instead
— useful in scripts, or when you just need one answer:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl exec <pod-name> -n lab-apps -- nginx -T | head -20
```

`nginx -T` dumps NGINX's fully-resolved effective configuration — useful
any time you need to confirm what a running process actually believes its
config is, as opposed to what you think you configured.

---

## Step 7: Debug a Pod with no debugging tools of its own

Exercise 2 pointed out that the NGINX image has no `curl`. Spinning up a
separate debug Pod (as you've done throughout this lab) works, but it
debugs from a *different* network location. `kubectl debug` instead
attaches a temporary container directly into an **existing** Pod, sharing
its exact network namespace:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
kubectl debug -n lab-apps <pod-name> -it --image=nicolaka/netshoot --target=nginx -- bash
```

`nicolaka/netshoot` is a well-known image built specifically for this kind
of troubleshooting — `curl`, `wget`, `nslookup`, `dig`, `tcpdump`, and more
all in one place. Inside the session:

```bash
curl -s localhost
nslookup nginx-clusterip
dig nginx-clusterip.lab-apps.svc.cluster.local +short
exit
```

Because `--target=nginx` shares that container's network namespace,
`curl -s localhost` reaches NGINX directly — something you couldn't do
from a separate debug Pod. This ephemeral container doesn't persist after
you exit, and it never touched the original Pod's image or spec.

---

## Step 8: Inspect environment variables and mounted files

```bash
kubectl exec <pod-name> -n lab-apps -- env
```

Look for variables you didn't set yourself, like
`NGINX_CLUSTERIP_SERVICE_HOST` / `NGINX_CLUSTERIP_SERVICE_PORT`.
Kubernetes automatically injects Docker-links-style environment variables
for every Service that existed *before* this Pod was created, into every
Pod in the same namespace — a legacy discovery mechanism that mostly
predates relying on DNS (Exercise 7), but still happens by default.

Now check the mounted content from Exercise 12:

```bash
kubectl exec <pod-name> -n lab-apps -- ls -la /usr/share/nginx/html
kubectl exec <pod-name> -n lab-apps -- cat /usr/share/nginx/html/index.html
```

Same ConfigMap-backed file you served over HTTP back in Exercise 12,
confirmed directly from inside the container's own filesystem.

---

## Step 9: Three layers — application logs, cluster events, and the host

You've now used three genuinely different sources of information in this
lab, and it's worth being explicit about what each one actually covers:

| Layer | Command | What it tells you |
|---|---|---|
| Application | `kubectl logs` | What the container itself printed |
| Cluster control plane | `kubectl get events` / `describe` | What the scheduler/kubelet/controllers observed about a resource's lifecycle |
| Host / K3s service itself | `journalctl -u k3s` | Whether K3s's own components (API server, scheduler, kubelet) are healthy at all |

The third layer is the one you haven't used since Exercise 1 — and it
matters most precisely when the other two stop being reachable at all.
Run this directly on the VM:

```bash
sudo journalctl -u k3s -n 50 --no-pager
```

If `kubectl` itself ever starts hanging or refusing connections entirely,
`kubectl logs` and `kubectl get events` are useless — they both depend on
a working API server to even run. `journalctl -u k3s` doesn't; it reads
directly from the systemd service, which is exactly why it was the first
command in Exercise 1, and exactly why it's the right escalation point
when the cluster itself, not just one workload in it, seems unwell.

---

## Recap

In this exercise, you:

- Viewed and followed container logs live, and recovered a crashed
  container's final output with `--previous`.

- Retrieved logs from one specific container in a multi-container Pod,
  and from every Pod matching a label at once.

- Queried and sorted cluster-wide events instead of one object's events
  at a time, and know they're garbage collected after about an hour.

- Used `kubectl exec` for a one-shot command, not just an interactive
  shell.

- Debugged a Pod with no tools of its own using `kubectl debug` and an
  ephemeral container sharing its network namespace.

- Inspected auto-injected Service environment variables and mounted
  ConfigMap files directly inside a running container.

- Placed application logs, cluster events, and `journalctl -u k3s` into a
  clear three-layer mental model — and know which one still works when
  the other two don't.

---

**Previous:** [Exercise 13 — Secrets](13-secrets.md)

**Next:** [Exercise 15 — Pod Restart and Recovery](15-pod-restart-and-recovery.md)
