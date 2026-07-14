#!/usr/bin/env bash
# Master runner for the K3s Single-Node Lab checklist validation scripts.
#
# Usage:
#   scripts/validate.sh                  # run every phase script, in order
#   scripts/validate.sh phase1           # run only phase1-*.sh scripts
#   scripts/validate.sh phase3-04        # run only scripts matching this prefix
#   scripts/validate.sh --list           # list available scripts, don't run them
#   scripts/validate.sh --help           # this message
#
# Point KUBECONFIG at your copy of the lab VM's kubeconfig before running,
# e.g.:
#   KUBECONFIG=/path/to/k3s.yaml scripts/validate.sh
# If KUBECONFIG isn't set, scripts fall back to ~/.kube/config, then
# /etc/rancher/k3s/k3s.yaml. Steps involving host-level state (LVM, mounts,
# NFS client tooling) must be run directly on the K3s VM.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

filter="${1:-}"
if [ "$filter" = "--help" ] || [ "$filter" = "-h" ]; then
  usage
  exit 0
fi

mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'phase*.sh' | sort)

if [ -n "$filter" ] && [ "$filter" != "--list" ]; then
  filtered=()
  for s in "${scripts[@]}"; do
    case "$(basename "$s")" in
      "$filter"*) filtered+=("$s") ;;
    esac
  done
  scripts=("${filtered[@]}")
fi

if [ "${#scripts[@]}" -eq 0 ]; then
  echo "No validation scripts matched '${filter:-*}'." >&2
  exit 2
fi

if [ "$filter" = "--list" ]; then
  printf '%s\n' "${scripts[@]##*/}"
  exit 0
fi

declare -a results=()
overall_fail=0

for s in "${scripts[@]}"; do
  echo
  bash "$s"
  rc=$?
  results+=("$(basename "$s"):$rc")
  [ "$rc" -ne 0 ] && overall_fail=1
done

echo
echo "===================== Summary ====================="
for r in "${results[@]}"; do
  name="${r%%:*}"
  rc="${r##*:}"
  if [ "$rc" -eq 0 ]; then
    printf '  \033[0;32mPASS\033[0m  %s\n' "$name"
  else
    printf '  \033[0;31mFAIL\033[0m  %s\n' "$name"
  fi
done
echo "====================================================="

exit "$overall_fail"
