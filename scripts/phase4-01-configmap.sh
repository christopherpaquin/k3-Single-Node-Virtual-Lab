#!/usr/bin/env bash
# Checklist: Phase 4 — ConfigMap mounted into a test Pod
# validate: configmap/app-config + pod/configmap-test mounts-it
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 4 — app-config ConfigMap + configmap-test Pod"

if ! kube get configmap app-config -n lab-apps >/dev/null 2>&1; then
  fail "configmap/app-config not found in namespace lab-apps"
else
  pass "configmap/app-config exists in namespace lab-apps"
fi

if ! kube get pod configmap-test -n lab-apps >/dev/null 2>&1; then
  fail "pod/configmap-test not found in namespace lab-apps"
  step_result
fi
pass "pod/configmap-test exists in namespace lab-apps"

# ConfigMap can be consumed either as a mounted volume or as env vars —
# accept either since the checklist just says "mount it into a test Pod".
vol_ref=$(kube get pod configmap-test -n lab-apps -o jsonpath='{.spec.volumes[?(@.configMap.name=="app-config")].name}')
env_ref=$(kube get pod configmap-test -n lab-apps -o jsonpath='{.spec.containers[*].envFrom[?(@.configMapRef.name=="app-config")].configMapRef.name}')

if [ -n "$vol_ref" ]; then
  pass "pod/configmap-test mounts app-config as a volume"
elif [ -n "$env_ref" ]; then
  pass "pod/configmap-test consumes app-config via envFrom"
else
  fail "pod/configmap-test does not reference app-config (as a volume or envFrom)"
fi

step_result
