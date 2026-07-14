#!/usr/bin/env bash
# Checklist: Phase 5 — kubectl exec -it
# validate: ops-exec-shell
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 5 — kubectl exec (nginx-deployment)"

pod=$(kube get pods -n lab-apps -l app=nginx-deployment -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$pod" ]; then
  pod=$(kube get pods -n lab-apps -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep '^nginx-deployment-' | head -n1)
fi
if [ -z "$pod" ]; then
  fail "could not find a Pod belonging to nginx-deployment in namespace lab-apps"
  step_result
fi
pass "found nginx-deployment pod: $pod"

out=$(kube exec "$pod" -n lab-apps -- sh -c 'echo exec-ok' 2>/tmp/phase5-exec-check.err)
if [ "$out" = "exec-ok" ]; then
  pass "kubectl exec into $pod succeeded"
else
  fail "kubectl exec into $pod failed (see /tmp/phase5-exec-check.err)"
fi

info "Manual check still required: run 'kubectl exec -it $pod -n lab-apps -- /bin/sh' yourself and poke around interactively."

step_result
