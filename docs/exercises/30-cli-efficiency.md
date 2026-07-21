# Exercise 30: CLI Efficiency

**Module:** Tooling

**Prerequisite:** [Exercise 29 — Helm](29-helm.md)

---

## Introduction

This exercise doesn't introduce a new Kubernetes concept — everything
here is about `kubectl` itself as a tool: how it formats output, filters
results, and integrates with your shell. You've been running `kubectl
get`, `describe`, and `-o wide` on repeat
since Exercise 1 — deliberately, since that repetition is how the basics
actually stick. This exercise is a different kind of practice: a toolbox
of techniques that make the same investigative work faster once the
basics are automatic, rather than new concepts to learn from scratch.

---

## What you'll do

- Use every major output format `kubectl get` supports, and know when
  each earns its complexity.
- Filter with label selectors (a recap) and field selectors (new).
- Use `kubectl explain` for always-accurate, version-correct field docs.
- Use `kubectl wait` to script around a condition instead of polling by
  hand.
- Set up shell completion and a couple of genuinely useful aliases.
- Pull one specific field out of a resource without reading the whole
  object.
- Combine `kubectl` output with `grep`, `sort`, and `jq`.

---

## Step 1: Output formats

```bash
kubectl get pods -n lab-apps -o wide
```

Familiar by now — adds IP and node columns to the default table.

```bash
kubectl get deployment nginx-deployment -n lab-apps -o yaml
kubectl get deployment nginx-deployment -n lab-apps -o json
```

Full object detail — useful for reading everything, unwieldy for
extracting one specific fact.

```bash
kubectl get deployment nginx-deployment -n lab-apps -o jsonpath='{.status.readyReplicas}/{.status.replicas}'
echo
```

One exact value, nothing else — the format you've used throughout this
lab whenever a single fact was the actual goal.

```bash
kubectl get pods -n lab-apps -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName
```

A readable table with **your own** chosen columns — a middle ground
between the default table's fixed columns and `jsonpath`'s single-value
precision.

---

## Step 2: Label selectors (recap) and field selectors (new)

Label selectors — used constantly since Exercise 4:

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Field selectors filter on an object's actual **fields**, not labels —
useful for things nothing labels for you automatically:

```bash
kubectl get pods -n lab-apps --field-selector status.phase=Running
```

```bash
kubectl get pods -n lab-apps -l app=nginx-deployment
```

Pick one Pod name, then filter events down to just that one object —
faster than scrolling through `kubectl describe`'s combined output when
you already know exactly what you're looking for:

```bash
kubectl get events -n lab-apps --field-selector involvedObject.name=<pod-name>
```

---

## Step 3: `kubectl explain`

```bash
kubectl explain deployment.spec.strategy
kubectl explain pod.spec.containers.resources
```

This reads directly from the API server's own schema — always accurate
for the exact Kubernetes version you're running, unlike a search result
or blog post that might be describing a different version entirely. Worth
reaching for before searching the web, especially for a field you've seen
in this lab but want the precise definition of (`readinessProbe`,
`strategy`, `resources` — anything from Exercises 3, 16, or 17).

---

## Step 4: `kubectl wait`

Instead of manually re-running `kubectl get` in a loop to check whether
something finished:

```bash
kubectl wait --for=condition=Ready pod -l app=nginx-deployment -n lab-apps --timeout=60s
```

This blocks until every matching Pod reports `Ready`, or the timeout
expires — exactly the kind of thing a script would need, instead of a
human staring at repeated `kubectl get` output.

---

## Step 5: Watching resources

```bash
kubectl get pods -n lab-apps --watch
```

You've used this pattern since Exercise 3. `Ctrl+C` to stop. A related
variant shows only **changes**, skipping the initial full listing:

```bash
kubectl get pods -n lab-apps --watch-only
```

(Leave that running in a spare terminal if you want to see later
exercises' changes appear live — otherwise `Ctrl+C` now.)

---

## Step 6: Shell completion

```bash
source <(kubectl completion bash)
echo 'source <(kubectl completion bash)' >> ~/.bashrc
```

(Substitute `zsh` for `bash` above if that's your shell.) This completes
subcommands, flags, and — depending on your `kubectl` version — even
resource names, directly from the live cluster.

---

## Step 7: Useful aliases

```bash
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "alias kgp='kubectl get pods'" >> ~/.bashrc
echo "alias kgpa='kubectl get pods -A'" >> ~/.bashrc
source ~/.bashrc
```

The `complete -o default -F __start_kubectl k` line matters as much as the
alias itself — without it, `k get po<TAB>` won't complete the way
`kubectl get po<TAB>` does, since completion is normally registered
against the literal command name `kubectl`, not your alias for it.

---

## Step 8: Set a default namespace (recap)

Already covered directly in Exercise 9, Step 4:

```bash
kubectl config set-context --current --namespace=lab-apps
```

Worth having reinforced here as part of the general "make your own daily
workflow faster" theme of this exercise, alongside completion and
aliases.

---

## Step 9: Extract one field without reading the whole object

```bash
kubectl get deployment nginx-deployment -n lab-apps -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

One exact answer to one exact question — the image currently configured
— with no need to scroll through the full `-o yaml` output looking for
it. This is the same technique from Step 1, called out again here because
it's genuinely the single highest-value habit in this whole exercise.

---

## Step 10: Combine `kubectl` with standard Unix tools

```bash
kubectl get pods -A -o wide | grep -v Running
```

Every Pod, cluster-wide, that **isn't** healthy — a fast first check
after any change.

```bash
kubectl get events -n lab-apps --sort-by=.lastTimestamp | tail -5
```

The 5 most recent events in the namespace — the same sorting technique
from Exercise 14, piped through `tail` for brevity.

If `jq` is available (`sudo apt install -y jq` / `sudo dnf install -y
jq` if not):

```bash
kubectl get pods -n lab-apps -o json | jq '.items[] | {name: .metadata.name, status: .status.phase}'
```

`jq` is worth reaching for once a `jsonpath` expression starts getting
complicated — it's a full JSON query language, where `jsonpath` is
intentionally minimal. Without `jq` installed, `-o jsonpath` remains the
dependency-free fallback for everything in this lab.

---

## Recap

In this exercise, you:

- Used every major `kubectl get` output format, and know which situation
  each one actually fits.

- Filtered with field selectors, including scoping `kubectl get events`
  down to one specific object.

- Used `kubectl explain` for schema-accurate field documentation, rather
  than searching for a possibly outdated answer.

- Used `kubectl wait` to block on a condition programmatically, instead
  of polling by hand.

- Set up shell completion and a couple of real aliases, including the
  completion registration an alias needs to keep working.

- Reinforced pulling one exact field from a resource instead of reading
  the whole object — arguably the single most useful habit in this
  entire exercise.

- Combined `kubectl` output with `grep`, `sort`, and `jq` for fast,
  scriptable answers.

---

**Previous:** [Exercise 29 — Helm](29-helm.md)

**Next:** [Exercise 31 — Failure Scenarios](31-failure-scenarios.md)
