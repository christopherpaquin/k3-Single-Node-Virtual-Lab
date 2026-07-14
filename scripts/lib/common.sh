# shellcheck shell=bash
# Shared helpers for scripts/phase*.sh validation scripts.
# Not meant to be run directly — sourced by each phase script.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

section() {
  echo -e "${BOLD}== $1 ==${NC}"
}

pass() {
  echo -e "  ${GREEN}PASS${NC}  $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}FAIL${NC}  $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
  echo -e "  ${YELLOW}INFO${NC}  $1"
}

# Call at the end of every phase script. Exits 0 if every check in this
# script passed, 1 otherwise — the exit code is what scripts/validate.sh
# uses to build its summary.
step_result() {
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}==> Step PASSED${NC} ($PASS_COUNT check(s) OK)"
    exit 0
  else
    echo -e "${RED}==> Step FAILED${NC} ($FAIL_COUNT of $((PASS_COUNT + FAIL_COUNT)) check(s) failed)"
    exit 1
  fi
}

# Resolve which kubeconfig to use, in priority order:
#   1. $KUBECONFIG, if the caller already set it (e.g. pointing at a copied creds file)
#   2. ~/.kube/config
#   3. /etc/rancher/k3s/k3s.yaml (the file K3s writes on install; usually root-only)
resolve_kubeconfig() {
  if [ -n "${KUBECONFIG:-}" ]; then
    return
  fi
  if [ -f "$HOME/.kube/config" ]; then
    export KUBECONFIG="$HOME/.kube/config"
  elif [ -r /etc/rancher/k3s/k3s.yaml ]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  fi
}

resolve_kubeconfig

# kube <kubectl args...> — talks to the cluster with whatever kubeconfig
# resolve_kubeconfig found, falling back to `sudo k3s kubectl` if no
# standalone kubectl binary is on PATH.
kube() {
  if command -v kubectl >/dev/null 2>&1; then
    kubectl "$@"
  else
    sudo k3s kubectl "$@"
  fi
}
