#!/usr/bin/env bash
# Checklist: Phase 3 Track A — mount point + Local Path Provisioner reconfig
# validate: mount /mnt/lv_local_path + local-path-config points there
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track A — /mnt/lv_local_path mount + local-path-config"

if findmnt /mnt/lv_local_path >/dev/null 2>&1; then
  pass "/mnt/lv_local_path is mounted"
  src=$(findmnt -no SOURCE /mnt/lv_local_path)
  info "mounted from $src"
else
  fail "/mnt/lv_local_path is not mounted"
fi

if ! kube get configmap local-path-config -n kube-system >/dev/null 2>&1; then
  fail "configmap/local-path-config not found in kube-system"
  step_result
fi
pass "configmap/local-path-config exists in kube-system"

cfg=$(kube get configmap local-path-config -n kube-system -o jsonpath='{.data.config\.json}')
if echo "$cfg" | grep -q '/mnt/lv_local_path'; then
  pass "local-path-config references /mnt/lv_local_path"
else
  fail "local-path-config does not reference /mnt/lv_local_path — check the configmap's config.json"
fi

step_result
