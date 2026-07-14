#!/usr/bin/env bash
# Checklist: Phase 5 — kubectl port-forward tunnel
# validate: ops-port-forward-tunnel
#
# Starts its own short-lived port-forward on a scratch local port (18080,
# to avoid colliding with the 8080 the checklist has you use manually),
# curls it, then tears it down.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 5 — kubectl port-forward (nginx-clusterip)"

if ! kube get service nginx-clusterip -n lab-apps >/dev/null 2>&1; then
  fail "service/nginx-clusterip not found in namespace lab-apps (needed for this check)"
  step_result
fi

kube port-forward -n lab-apps svc/nginx-clusterip 18080:80 >/tmp/phase5-port-forward.out 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" >/dev/null 2>&1; wait "$pf_pid" 2>/dev/null' EXIT

sleep 2
code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:18080/ || echo "000")

if [ "$code" = "200" ]; then
  pass "reached nginx-clusterip through a port-forward tunnel on localhost:18080 (HTTP $code)"
else
  fail "could not reach service through port-forward tunnel (HTTP $code, see /tmp/phase5-port-forward.out)"
fi

kill "$pf_pid" >/dev/null 2>&1
wait "$pf_pid" 2>/dev/null
trap - EXIT

info "Manual check still required: run 'kubectl port-forward svc/nginx-clusterip 8080:80 -n lab-apps' yourself and browse to localhost:8080."

step_result
