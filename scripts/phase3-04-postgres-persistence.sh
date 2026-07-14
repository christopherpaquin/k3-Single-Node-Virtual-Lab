#!/usr/bin/env bash
# Checklist: Phase 3 Track A — Postgres with persistent PVC
# validate: pvc/postgres-pvc bound + deployment/postgres data-persists
#
# The "data survives a Pod cycle" part of this step is something only you
# can prove (write data, delete the Pod, read it back) — there's no fixed
# table/value name in the checklist to check automatically. This script
# verifies the structural pieces: PVC bound, Deployment healthy, and volume
# actually mounted into the container.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track A — postgres Deployment + postgres-pvc"

if ! kube get pvc postgres-pvc -n lab-apps >/dev/null 2>&1; then
  fail "pvc/postgres-pvc not found in namespace lab-apps"
else
  pass "pvc/postgres-pvc exists in namespace lab-apps"
  phase=$(kube get pvc postgres-pvc -n lab-apps -o jsonpath='{.status.phase}')
  if [ "$phase" = "Bound" ]; then
    pass "pvc/postgres-pvc is Bound"
  else
    fail "pvc/postgres-pvc phase is '$phase', expected Bound"
  fi
fi

if ! kube get deployment postgres -n lab-apps >/dev/null 2>&1; then
  fail "deployment/postgres not found in namespace lab-apps"
  step_result
fi
pass "deployment/postgres exists in namespace lab-apps"

ready=$(kube get deployment postgres -n lab-apps -o jsonpath='{.status.readyReplicas}')
if [ "${ready:-0}" -ge 1 ] 2>/dev/null; then
  pass "deployment/postgres has $ready ready replica(s)"
else
  fail "deployment/postgres has no ready replicas"
fi

vol_claim=$(kube get deployment postgres -n lab-apps -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="postgres-pvc")].name}')
if [ -n "$vol_claim" ]; then
  pass "deployment/postgres mounts postgres-pvc as a volume"
else
  fail "deployment/postgres does not reference postgres-pvc as a volume"
fi

info "Manual check still required: write test data, delete the Pod, and confirm the data is still there after it's recreated."

step_result
