#!/usr/bin/env bash
# Checklist: Phase 3 Track B — NFS client tooling + manual mount test
# validate: storage-nfs-client-mount
#
# Same environment-specific server/path as phase3-05-nfs-export.sh:
#   NFS_SERVER=192.168.1.1 NFS_EXPORT_PATH=/srv/nfs/k3s-lab scripts/phase3-06-nfs-client-mount.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track B — NFS client tooling + mount test"

if command -v mount.nfs >/dev/null 2>&1 || mount -t nfs 2>&1 | grep -qv 'unknown filesystem'; then
  pass "NFS client tooling (mount.nfs) is installed"
else
  fail "mount.nfs not found — install nfs-common (Ubuntu) or nfs-utils (Fedora)"
fi

NFS_SERVER="${NFS_SERVER:-${1:-}}"
NFS_EXPORT_PATH="${NFS_EXPORT_PATH:-${2:-}}"

if [ -z "$NFS_SERVER" ] || [ -z "$NFS_EXPORT_PATH" ]; then
  info "set NFS_SERVER and NFS_EXPORT_PATH to also test an actual mount, e.g.:"
  info "  NFS_SERVER=192.168.1.1 NFS_EXPORT_PATH=/srv/nfs/k3s-lab $0"
  step_result
fi

mnt_dir=$(mktemp -d /tmp/nfs-client-test.XXXXXX)
if sudo mount -t nfs "${NFS_SERVER}:${NFS_EXPORT_PATH}" "$mnt_dir" 2>/tmp/nfs-mount-test.err; then
  pass "mounted ${NFS_SERVER}:${NFS_EXPORT_PATH} at $mnt_dir"
  sudo umount "$mnt_dir"
  rmdir "$mnt_dir"
else
  fail "could not mount ${NFS_SERVER}:${NFS_EXPORT_PATH} (see /tmp/nfs-mount-test.err)"
  rmdir "$mnt_dir" 2>/dev/null || true
fi

step_result
