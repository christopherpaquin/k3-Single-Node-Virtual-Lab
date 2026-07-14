#!/usr/bin/env bash
# Checklist: Phase 3 Track A — secondary disk present and unformatted
# validate: block-device-present
#
# Host-level check — must run on the K3s VM itself, not against the API.
# The secondary disk's device name is VM-specific, so this looks for any
# whole disk with no partitions/children and no filesystem signature,
# which is what a freshly-attached, untouched disk looks like.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track A — secondary disk present (unformatted)"

if ! command -v lsblk >/dev/null 2>&1; then
  fail "lsblk not found — install util-linux"
  step_result
fi

candidates=()
while read -r name fstype; do
  [ -z "$name" ] && continue
  child_count=$(lsblk -n -o NAME "/dev/$name" 2>/dev/null | wc -l)
  if [ -z "$fstype" ] && [ "$child_count" -eq 1 ]; then
    candidates+=("$name")
  fi
done < <(lsblk -dn -o NAME,FSTYPE 2>/dev/null)

if [ "${#candidates[@]}" -gt 0 ]; then
  pass "found unformatted, unpartitioned disk(s): ${candidates[*]}"
  info "one of these should be the secondary disk from the VM requirements; the next step turns it into vg_lab_storage"
else
  fail "no unformatted whole disk found via lsblk — is the secondary disk attached?"
  info "current block devices:"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT | sed 's/^/         /'
fi

step_result
