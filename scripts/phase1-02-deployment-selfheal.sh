#!/usr/bin/env bash
# Checklist: Phase 1 — Deployment self-healing
# validate: deployment/nginx-deployment replicas=3
#
# The Deployment legitimately lives in `default` before the Phase 1
# namespace step and in `lab-apps` afterward, so this checks both and
# reports whichever it finds.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 1 — nginx-deployment self-healing (3 replicas)"

ns=""
for candidate in lab-apps default; do
  if kube get deployment nginx-deployment -n "$candidate" >/dev/null 2>&1; then
    ns="$candidate"
    break
  fi
done

if [ -z "$ns" ]; then
  fail "deployment/nginx-deployment not found in lab-apps or default"
  step_result
fi
pass "deployment/nginx-deployment found in namespace $ns"

spec_replicas=$(kube get deployment nginx-deployment -n "$ns" -o jsonpath='{.spec.replicas}')
if [ "$spec_replicas" = "3" ]; then
  pass "spec.replicas=3"
else
  fail "spec.replicas=$spec_replicas, expected 3"
fi

ready_replicas=$(kube get deployment nginx-deployment -n "$ns" -o jsonpath='{.status.readyReplicas}')
if [ "$ready_replicas" = "3" ]; then
  pass "status.readyReplicas=3 (self-healed back to full strength)"
else
  fail "status.readyReplicas=${ready_replicas:-0}, expected 3"
fi

image=$(kube get deployment nginx-deployment -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}')
case "$image" in
  *nginx*) pass "container image is nginx ($image)" ;;
  *) fail "container image '$image' does not look like nginx" ;;
esac

if [ "$ns" = "default" ]; then
  info "Still in namespace 'default' — the next checklist step moves this into lab-apps."
fi

step_result
