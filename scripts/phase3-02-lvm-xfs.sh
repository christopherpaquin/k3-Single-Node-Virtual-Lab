#!/usr/bin/env bash
# Checklist: Phase 3 Track A — LVM VG/LV formatted XFS
# validate: lvm vg=vg_lab_storage lv=lv_local_path fstype=xfs
#
# Host-level check — must run on the K3s VM itself.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track A — LVM vg_lab_storage / lv_local_path (XFS)"

if ! command -v vgs >/dev/null 2>&1; then
  fail "lvm2 tools not found (vgs/lvs) — install lvm2"
  step_result
fi

if sudo vgs vg_lab_storage >/dev/null 2>&1; then
  pass "volume group vg_lab_storage exists"
else
  fail "volume group vg_lab_storage not found"
fi

if sudo lvs vg_lab_storage/lv_local_path >/dev/null 2>&1; then
  pass "logical volume lv_local_path exists in vg_lab_storage"
else
  fail "logical volume lv_local_path not found in vg_lab_storage"
  step_result
fi

lv_path="/dev/vg_lab_storage/lv_local_path"
fstype=$(sudo blkid -s TYPE -o value "$lv_path" 2>/dev/null || true)
if [ -z "$fstype" ]; then
  fstype=$(sudo blkid -s TYPE -o value /dev/mapper/vg_lab_storage-lv_local_path 2>/dev/null || true)
fi

if [ "$fstype" = "xfs" ]; then
  pass "logical volume filesystem is XFS"
else
  fail "logical volume filesystem is '${fstype:-unknown}', expected xfs"
fi

step_result
