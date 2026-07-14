#!/usr/bin/env bash
# Checklist: Phase 3 Track B — shared RWX nginx-shared Deployment
# validate: pvc/nginx-shared-pvc accessMode=RWX + deployment/nginx-shared replicas=3
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track B — nginx-shared (RWX, 3 replicas)"

if ! kube get pvc nginx-shared-pvc -n lab-apps >/dev/null 2>&1; then
  fail "pvc/nginx-shared-pvc not found in namespace lab-apps"
else
  pass "pvc/nginx-shared-pvc exists in namespace lab-apps"

  access_modes=$(kube get pvc nginx-shared-pvc -n lab-apps -o jsonpath='{.status.accessModes[0]}')
  if [ "$access_modes" = "ReadWriteMany" ]; then
    pass "pvc/nginx-shared-pvc accessMode is ReadWriteMany"
  else
    fail "pvc/nginx-shared-pvc accessMode is '$access_modes', expected ReadWriteMany"
  fi

  phase=$(kube get pvc nginx-shared-pvc -n lab-apps -o jsonpath='{.status.phase}')
  if [ "$phase" = "Bound" ]; then
    pass "pvc/nginx-shared-pvc is Bound"
  else
    fail "pvc/nginx-shared-pvc phase is '$phase', expected Bound"
  fi
fi

if ! kube get deployment nginx-shared -n lab-apps >/dev/null 2>&1; then
  fail "deployment/nginx-shared not found in namespace lab-apps"
  step_result
fi
pass "deployment/nginx-shared exists in namespace lab-apps"

spec_replicas=$(kube get deployment nginx-shared -n lab-apps -o jsonpath='{.spec.replicas}')
ready_replicas=$(kube get deployment nginx-shared -n lab-apps -o jsonpath='{.status.readyReplicas}')
if [ "$spec_replicas" = "3" ] && [ "$ready_replicas" = "3" ]; then
  pass "deployment/nginx-shared has 3/3 ready replicas"
else
  fail "deployment/nginx-shared replicas: spec=$spec_replicas ready=${ready_replicas:-0}, expected 3/3"
fi

vol_claim=$(kube get deployment nginx-shared -n lab-apps -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="nginx-shared-pvc")].name}')
if [ -n "$vol_claim" ]; then
  pass "deployment/nginx-shared mounts nginx-shared-pvc as a volume"
else
  fail "deployment/nginx-shared does not reference nginx-shared-pvc as a volume"
fi

step_result
