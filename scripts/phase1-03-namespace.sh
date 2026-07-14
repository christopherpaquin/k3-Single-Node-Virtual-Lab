#!/usr/bin/env bash
# Checklist: Phase 1 — lab-apps namespace
# validate: namespace/lab-apps + deployment/nginx-deployment -n lab-apps
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 1 — lab-apps namespace"

if kube get namespace lab-apps >/dev/null 2>&1; then
  pass "namespace/lab-apps exists"
else
  fail "namespace/lab-apps not found"
fi

if kube get deployment nginx-deployment -n lab-apps >/dev/null 2>&1; then
  pass "deployment/nginx-deployment exists in namespace lab-apps"
else
  fail "deployment/nginx-deployment not found in namespace lab-apps (still in 'default'?)"
fi

step_result
