#!/usr/bin/env bash
# Checklist: Phase 2 — ClusterIP + cluster DNS
# validate: service/nginx-clusterip type=ClusterIP + dns-resolves
#
# Spins up its own short-lived pod to run the nslookup rather than relying
# on your `dns-test` pod still being around (the checklist has you delete
# it once you've eyeballed the result yourself).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 2 — ClusterIP (nginx-clusterip) + DNS resolution"

if ! kube get service nginx-clusterip -n lab-apps >/dev/null 2>&1; then
  fail "service/nginx-clusterip not found in namespace lab-apps"
  step_result
fi
pass "service/nginx-clusterip exists in namespace lab-apps"

svc_type=$(kube get service nginx-clusterip -n lab-apps -o jsonpath='{.spec.type}')
if [ "$svc_type" = "ClusterIP" ]; then
  pass "service type is ClusterIP"
else
  fail "service type is '$svc_type', expected ClusterIP"
fi

fqdn="nginx-clusterip.lab-apps.svc.cluster.local"
info "Running a throwaway pod to check DNS resolution for $fqdn ..."
if kube run dns-check-validate -n lab-apps --rm -i --restart=Never --image=busybox:1.36 \
    --command --timeout=60s -- nslookup "$fqdn" >/tmp/dns-check-validate.out 2>&1; then
  pass "cluster DNS resolves $fqdn"
else
  fail "cluster DNS did NOT resolve $fqdn (see /tmp/dns-check-validate.out)"
fi
kube delete pod dns-check-validate -n lab-apps --ignore-not-found >/dev/null 2>&1

step_result
