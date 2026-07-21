# Exercise 20: Jobs and CronJobs

**Module:** Workload Types

**Prerequisite:** [Exercise 19 — Single-Node Maintenance](19-single-node-maintenance.md)

---

## Introduction

Every workload so far has been something meant to run forever — a
Deployment keeps its replica count up indefinitely, restarting a
completed or crashed Pod as a failure to correct, not an outcome to
accept. A **Job** models the opposite kind of work: something with a
genuine finish line — a batch process, a database migration, a report —
that should run to completion exactly once (or a fixed number of times)
and then stop, with success or failure being a real, expected outcome
rather than something to loop on forever. A **CronJob** wraps that in a
schedule, creating a new Job at fixed intervals — cluster-native cron,
for the same kind of periodic task you might otherwise put in a host
crontab.

---

## What you'll do

- Create a one-time Job and inspect the Pod it creates.
- Watch a Job fail repeatedly and stop after a configured backoff limit —
  a different failure pattern than `CrashLoopBackOff`.
- Create a CronJob and watch it spawn Jobs on a schedule.
- Trigger a Job manually from a CronJob's template, outside its schedule.
- Suspend and resume a CronJob.
- Understand how completed Job history is automatically pruned.

---

## Step 1: Create a one-time Job

```bash
kubectl create job hello-job -n lab-apps --image=busybox:1.36 -- sh -c "echo Hello from a Job; sleep 5"
```

```bash
kubectl get pods -n lab-apps -l job-name=hello-job
```

The Job controller created exactly one Pod, named after the Job itself.
Wait a few seconds, then check the Job's own status:

```bash
kubectl get job hello-job -n lab-apps
```

`COMPLETIONS` should read `1/1` once the Pod finishes.

```bash
kubectl logs -n lab-apps -l job-name=hello-job
```

---

## Step 2: A Job that fails and retries, with a backoff limit

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: fail-job
  namespace: lab-apps
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: fail
          image: busybox:1.36
          command: ["sh", "-c", "echo failing now; exit 1"]
EOF
```

Watch it over the next several seconds:

```bash
kubectl get pods -n lab-apps -l job-name=fail-job
```

You'll see **multiple** Pods appear over time, one per attempt — not one
Pod restarting in place. With `restartPolicy: Never` at the Pod level, the
Job controller's response to a failed Pod is to create an entirely new
Pod for the next attempt, rather than restarting a container inside the
same one. This is a genuinely different failure mechanism from
`CrashLoopBackOff` (Exercise 2), even though both involve a container
exiting with an error.

Once `backoffLimit: 2` is exhausted (the initial attempt plus 2 retries —
3 Pods total):

```bash
kubectl get job fail-job -n lab-apps
kubectl describe job fail-job -n lab-apps
```

Look for a `BackoffLimitExceeded` condition/event. Unlike a Deployment's
Pod, which will keep restarting a failing container forever, a Job gives
up permanently once its retry budget is spent — by design, since a Job is
meant to represent finite work with a defined success or failure outcome,
not a long-running service.

Clean up:

```bash
kubectl delete job fail-job -n lab-apps
```

---

## Step 3: Create a CronJob

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello-cron
  namespace: lab-apps
spec:
  schedule: "*/2 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: hello
              image: busybox:1.36
              command: ["sh", "-c", "date; echo Hello from a CronJob"]
EOF
```

`*/2 * * * *` means every 2 minutes. Check it once, then check again after
waiting a couple of minutes:

```bash
kubectl get cronjob hello-cron -n lab-apps
```

`LAST SCHEDULE` should populate once the first run happens.

```bash
kubectl get jobs -n lab-apps
```

Each scheduled run creates its own child `Job` object, named
`hello-cron-<timestamp>` — a CronJob doesn't run anything itself; it's
purely a factory that creates ordinary Jobs on a timer.

---

## Step 4: Trigger a Job manually, outside the schedule

Sometimes you don't want to wait for the next scheduled run — think "run
this backup right now" instead of waiting until 2 AM:

```bash
kubectl create job hello-cron-manual --from=cronjob/hello-cron -n lab-apps
kubectl get pods -n lab-apps -l job-name=hello-cron-manual
kubectl logs -n lab-apps -l job-name=hello-cron-manual
```

`--from=cronjob/hello-cron` copies the CronJob's Pod template into a
brand-new, immediately-run Job — completely independent of its schedule.

---

## Step 5: Suspend and resume

```bash
kubectl patch cronjob hello-cron -n lab-apps -p '{"spec":{"suspend":true}}'
kubectl get cronjob hello-cron -n lab-apps
```

`SUSPEND` now shows `True`. Wait past the next scheduled tick and confirm
nothing new was created:

```bash
kubectl get jobs -n lab-apps
```

No new `hello-cron-<timestamp>` Job should appear, no matter how long you
wait — suspending stops the schedule from firing at all, without deleting
the CronJob definition itself.

Resume it:

```bash
kubectl patch cronjob hello-cron -n lab-apps -p '{"spec":{"suspend":false}}'
```

---

## Step 6: Job history limits

A CronJob doesn't let completed Job objects accumulate forever — by
default it keeps the last 3 successful and the last 1 failed Job, pruning
older ones automatically:

```bash
kubectl get cronjob hello-cron -n lab-apps -o jsonpath='{.spec.successfulJobsHistoryLimit} {.spec.failedJobsHistoryLimit}'
echo
```

You can tighten or loosen this:

```bash
kubectl patch cronjob hello-cron -n lab-apps -p '{"spec":{"successfulJobsHistoryLimit":2,"failedJobsHistoryLimit":1}}'
```

If you leave this CronJob running, you'll see old `hello-cron-<timestamp>`
Job objects disappear on their own once the count exceeds these limits —
nothing you need to clean up by hand, and worth knowing about before
wondering why a Job you expected to still be there is gone.

---

## Clean up

None of this exercise's resources are needed later:

```bash
kubectl delete cronjob hello-cron -n lab-apps
kubectl delete job hello-job hello-cron-manual -n lab-apps
```

---

## Recap

In this exercise, you:

- Created a one-time Job and confirmed its completion status and logs.

- Watched a failing Job create a new Pod per retry attempt — rather than
  restarting a container in place — and stop permanently once its
  `backoffLimit` was exhausted.

- Created a CronJob and watched it spawn independent Job objects on a
  schedule.

- Triggered an immediate, one-off run from a CronJob's template using
  `--from=cronjob/...`, without touching the schedule.

- Suspended and resumed a CronJob, and confirmed suspension genuinely
  stops new runs rather than just pausing them.

- Understand how CronJobs automatically prune old completed Job history.

---

**Previous:** [Exercise 19 — Single-Node Maintenance](19-single-node-maintenance.md)

**Next:** [Exercise 21 — Local Storage](21-local-storage.md)
