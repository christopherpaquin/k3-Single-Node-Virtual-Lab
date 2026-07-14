#!/usr/bin/env bash
# Checklist: Phase 5 — kubectl logs -f
# validate: ops-logs-streamable
#
# Confirms `kubectl logs` works against a nginx-deployment Pod. The `-f`
# live-follow behavior itself is inherently interactive, so that part is
# still on you to eyeball.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 5 — kubectl logs (nginx-deployment)"

pod=$(kube get pods -n lab-apps -l app=nginx-deployment -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$pod" ]; then
  pod=$(kube get pods -n lab-apps -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep '^nginx-deployment-' | head -n1)
fi
if [ -z "$pod" ]; then
  fail "could not find a Pod belonging to nginx-deployment in namespace lab-apps"
  step_result
fi
pass "found nginx-deployment pod: $pod"

if kube logs "$pod" -n lab-apps --tail=5 >/tmp/phase5-logs-check.out 2>&1; then
  pass "kubectl logs $pod -n lab-apps succeeded"
else
  fail "kubectl logs $pod -n lab-apps failed (see /tmp/phase5-logs-check.out)"
fi

info "Manual check still required: run 'kubectl logs -f $pod -n lab-apps' yourself and observe live streaming."

step_result
