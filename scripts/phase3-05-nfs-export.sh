#!/usr/bin/env bash
# Checklist: Phase 3 Track B — NFS export reachable from the VM
# validate: storage-nfs-export-reachable
#
# The NFS server and export path are environment-specific (they live on
# your hypervisor, outside this repo), so pass them in:
#   NFS_SERVER=192.168.1.1 NFS_EXPORT_PATH=/srv/nfs/k3s-lab scripts/phase3-05-nfs-export.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 3 Track B — NFS export reachable"

NFS_SERVER="${NFS_SERVER:-${1:-}}"
NFS_EXPORT_PATH="${NFS_EXPORT_PATH:-${2:-}}"

if [ -z "$NFS_SERVER" ]; then
  fail "NFS_SERVER not set"
  info "usage: NFS_SERVER=<hypervisor-ip> NFS_EXPORT_PATH=<export-path> $0"
  step_result
fi

if ! command -v showmount >/dev/null 2>&1; then
  fail "showmount not found — install nfs-common (Ubuntu) or nfs-utils (Fedora)"
  step_result
fi

exports=$(showmount -e "$NFS_SERVER" 2>&1)
if [ $? -ne 0 ]; then
  fail "could not query exports from $NFS_SERVER: $exports"
  step_result
fi
pass "reached NFS server $NFS_SERVER"

if [ -n "$NFS_EXPORT_PATH" ]; then
  if echo "$exports" | grep -qF "$NFS_EXPORT_PATH"; then
    pass "export $NFS_EXPORT_PATH is advertised by $NFS_SERVER"
  else
    fail "export $NFS_EXPORT_PATH not found in showmount output:"
    echo "$exports" | sed 's/^/         /'
  fi
else
  info "no NFS_EXPORT_PATH given — advertised exports on $NFS_SERVER:"
  echo "$exports" | sed 's/^/         /'
fi

step_result
