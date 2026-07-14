#!/usr/bin/env bash
# Checklist: Phase 2 — NodePort
# validate: service/nginx-nodeport type=NodePort nodePort=30080
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 2 — NodePort (nginx-nodeport:30080)"

if ! kube get service nginx-nodeport -n lab-apps >/dev/null 2>&1; then
  fail "service/nginx-nodeport not found in namespace lab-apps"
  step_result
fi
pass "service/nginx-nodeport exists in namespace lab-apps"

svc_type=$(kube get service nginx-nodeport -n lab-apps -o jsonpath='{.spec.type}')
if [ "$svc_type" = "NodePort" ]; then
  pass "service type is NodePort"
else
  fail "service type is '$svc_type', expected NodePort"
fi

node_port=$(kube get service nginx-nodeport -n lab-apps -o jsonpath='{.spec.ports[0].nodePort}')
if [ "$node_port" = "30080" ]; then
  pass "nodePort is 30080"
else
  fail "nodePort is '$node_port', expected 30080"
fi

node_ip=$(kube get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -n "$node_ip" ]; then
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${node_ip}:30080/" || echo "000")
  if [ "$code" = "200" ]; then
    pass "reached http://${node_ip}:30080/ (HTTP $code)"
  else
    fail "could not reach http://${node_ip}:30080/ (HTTP $code) — check firewall/service selector"
  fi
else
  info "could not determine node InternalIP to curl-test reachability"
fi

step_result
