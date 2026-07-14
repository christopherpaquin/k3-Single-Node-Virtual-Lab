#!/usr/bin/env bash
# Checklist: Phase 3 Track B — nfs-subdir-external-provisioner + StorageClass
# validate: deployment/nfs-subdir-external-provisioner -n nfs-provisioning + storageclass/nfs-client
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track B — nfs-subdir-external-provisioner + nfs-client StorageClass"

if ! kube get deployment nfs-subdir-external-provisioner -n nfs-provisioning >/dev/null 2>&1; then
  fail "deployment/nfs-subdir-external-provisioner not found in namespace nfs-provisioning"
else
  pass "deployment/nfs-subdir-external-provisioner exists in namespace nfs-provisioning"
  ready=$(kube get deployment nfs-subdir-external-provisioner -n nfs-provisioning -o jsonpath='{.status.readyReplicas}')
  if [ "${ready:-0}" -ge 1 ] 2>/dev/null; then
    pass "nfs-subdir-external-provisioner has $ready ready replica(s)"
  else
    fail "nfs-subdir-external-provisioner has no ready replicas"
  fi
fi

if kube get storageclass nfs-client >/dev/null 2>&1; then
  pass "storageclass/nfs-client exists"
else
  fail "storageclass/nfs-client not found"
fi

step_result
