# Exercise 29: Helm

**Module:** Tooling

**Prerequisite:** [Exercise 28 — Service Accounts and RBAC](28-service-accounts-and-rbac.md).
Also assumes Helm is installed ([K3s/Headlamp Install
§2.1](../K3S-HEADLAMP-INSTALL.md#21-install-helm), for Headlamp).

---

## Introduction

**Helm** is the de-facto package manager for Kubernetes — a way to
package a set of related manifests (Deployments, Services, ConfigMaps,
RBAC objects, and more) into a single versioned, parameterized bundle
called a **chart**, which can be installed, upgraded, and removed as one
unit instead of managing every underlying object by hand. Where Exercise
11 (Declarative YAML) covered *individual* manifests, Helm exists for
distributing and configuring a *whole application's* worth of them at
once — most non-trivial real-world Kubernetes software is distributed
this way rather than as raw YAML.

You've already used Helm twice in this lab without necessarily thinking
of it as "learning Helm": installing Headlamp by hand back in the
[K3s/Headlamp Install guide](../K3S-HEADLAMP-INSTALL.md), and finding the
`HelmChart` custom resource that installed Traefik
*automatically* in Exercise 6. This exercise works the Helm CLI itself
directly, end to end — install, inspect, override, upgrade, roll back,
uninstall — using a fresh chart, so Headlamp stays untouched.

---

## What you'll do

- Verify Helm and add a public chart repository.
- Search for and install a chart.
- Inspect exactly what resources a Helm release actually created.
- Override configuration from the command line and from a values file.
- Upgrade a release, view its revision history, and roll it back.
- Uninstall a release cleanly, in one command.
- Compare a Helm CLI release against K3s's own `HelmChart` mechanism from
  Exercise 6.

---

## Step 1: Verify Helm

```bash
helm version
```

Already installed back in [K3s/Headlamp Install
§2.1](../K3S-HEADLAMP-INSTALL.md#21-install-helm) for Headlamp — nothing
new to set up here.

---

## Step 2: Add a repository and search for a chart

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

```bash
helm search repo bitnami/nginx
```

This searches only repositories you've explicitly added — Helm doesn't
maintain any kind of global index the way, say, a package manager's
central registry does.

---

## Step 3: Install it

```bash
helm install helm-demo bitnami/nginx -n lab-apps --set replicaCount=2
```

Same core pattern as installing Headlamp in [K3s/Headlamp Install
§2.2](../K3S-HEADLAMP-INSTALL.md#22-install-headlamp-exposed-persistently-over-the-network)
— a release name (`helm-demo`), a chart reference, a namespace, and this
time a `--set` override.

```bash
helm status helm-demo -n lab-apps
```

---

## Step 4: Inspect what the release actually created

```bash
kubectl get all -n lab-apps -l app.kubernetes.io/instance=helm-demo
```

That label — `app.kubernetes.io/instance` — is the exact recommended
label schema you applied by hand back in Exercise 10, applied here
automatically by the chart. Every resource this release owns carries it.

See the raw manifest Helm actually applied:

```bash
helm get manifest helm-demo -n lab-apps | head -40
```

This is real, plain Kubernetes YAML — Helm's whole job is templating and
applying manifests like this one; nothing about the resources themselves
is Helm-specific once they exist in the cluster.

---

## Step 5: Override values two ways

From the command line, as part of an upgrade:

```bash
helm upgrade helm-demo bitnami/nginx -n lab-apps --set replicaCount=3 --set service.type=NodePort
kubectl get pods -n lab-apps -l app.kubernetes.io/instance=helm-demo
```

Three replicas now, and a NodePort Service.

From a values file instead — the more maintainable option once you have
more than one or two overrides:

```bash
cat <<'EOF' > helm-demo-values.yaml
replicaCount: 2
service:
  type: ClusterIP
EOF

helm upgrade helm-demo bitnami/nginx -n lab-apps -f helm-demo-values.yaml
kubectl get pods -n lab-apps -l app.kubernetes.io/instance=helm-demo
kubectl get svc -n lab-apps -l app.kubernetes.io/instance=helm-demo
```

Back to 2 replicas and `ClusterIP` — this time driven entirely by a file
you could commit to version control, rather than a growing pile of
command-line flags.

---

## Step 6: View release history and roll back

```bash
helm history helm-demo -n lab-apps
```

Three revisions: the original install, and the two upgrades from Step 5.

```bash
helm rollback helm-demo 1 -n lab-apps
helm history helm-demo -n lab-apps
```

Notice rolling back doesn't erase history and "go back in time" — it adds
a **new** revision (`4`) whose configuration matches revision `1`. This is
the same idea as `kubectl rollout undo` from Exercise 3: a rollback is
just another forward-moving change, not a deletion of what happened since.

```bash
kubectl get pods -n lab-apps -l app.kubernetes.io/instance=helm-demo
```

Back to the original 2-replica configuration from Step 3.

---

## Step 7: Uninstall cleanly

```bash
helm uninstall helm-demo -n lab-apps
kubectl get all -n lab-apps -l app.kubernetes.io/instance=helm-demo
```

Empty — every resource the release owned is gone, in one command. Compare
that against how much individual `kubectl delete` bookkeeping this would
otherwise take, for a chart installing a dozen or more separate objects at
once (Headlamp, back in [K3s/Headlamp Install
§2.2](../K3S-HEADLAMP-INSTALL.md#22-install-headlamp-exposed-persistently-over-the-network),
is a good example of exactly that).

Clean up the local values file too:

```bash
rm -f helm-demo-values.yaml
```

---

## Step 8: Helm CLI releases versus K3s's `HelmChart` resource

You've now used both mechanisms in this lab:

| | Helm CLI (`helm install`, this exercise and Headlamp) | K3s `HelmChart` resource (Traefik, Exercise 6) |
|---|---|---|
| Triggered by | You, running a command | K3s's own `helm-controller`, reconciling a Kubernetes object |
| Tracked as | Helm release secrets in-cluster | A `HelmChart` custom resource plus a one-shot install Job |
| Typical use | Anything you install yourself, on demand | Bundled platform components K3s manages on your behalf |
| Underlying tool | Helm | Also Helm — just invoked automatically, not by hand |

Both ultimately do the same thing — render a chart's templates and apply
the result — the difference is entirely about *who* (or what) is driving
that process.

---

## Recap

In this exercise, you:

- Added a Helm repository, searched it, and installed a chart with an
  inline override.

- Inspected a release's actual resources using the same
  `app.kubernetes.io/instance` label convention from Exercise 10, and
  viewed the raw manifest Helm applied.

- Overrode configuration both from the command line and from a values
  file, and understand when each is more appropriate.

- Viewed a release's revision history and rolled it back, and recognized
  the same "rollback is a new forward change" pattern from Exercise 3's
  `kubectl rollout undo`.

- Uninstalled a multi-resource release in a single command.

- Compared a Helm CLI release against K3s's `HelmChart` mechanism from
  Exercise 6 — the same underlying tool, triggered two different ways.

---

**Previous:** [Exercise 28 — Service Accounts and RBAC](28-service-accounts-and-rbac.md)

**Next:** [Exercise 30 — CLI Efficiency](30-cli-efficiency.md)
