#!/usr/bin/env bash
# Checklist: Phase 2 — Ingress
# validate: ingress/nginx-ingress host=lab.k3s.local
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 2 — Ingress (nginx-ingress, host lab.k3s.local)"

if ! kube get ingress nginx-ingress -n lab-apps >/dev/null 2>&1; then
  fail "ingress/nginx-ingress not found in namespace lab-apps"
  step_result
fi
pass "ingress/nginx-ingress exists in namespace lab-apps"

host=$(kube get ingress nginx-ingress -n lab-apps -o jsonpath='{.spec.rules[0].host}')
if [ "$host" = "lab.k3s.local" ]; then
  pass "ingress host is lab.k3s.local"
else
  fail "ingress host is '$host', expected lab.k3s.local"
fi

backend=$(kube get ingress nginx-ingress -n lab-apps -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
if [ "$backend" = "nginx-clusterip" ]; then
  pass "ingress backend service is nginx-clusterip"
else
  fail "ingress backend service is '$backend', expected nginx-clusterip"
fi

node_ip=$(kube get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -n "$node_ip" ]; then
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Host: lab.k3s.local" "http://${node_ip}/" || echo "000")
  if [ "$code" = "200" ]; then
    pass "reached http://${node_ip}/ with Host: lab.k3s.local (HTTP $code)"
  else
    fail "could not reach http://${node_ip}/ with Host: lab.k3s.local (HTTP $code) — check Traefik routing"
  fi
else
  info "could not determine node InternalIP to curl-test ingress routing"
fi

step_result
