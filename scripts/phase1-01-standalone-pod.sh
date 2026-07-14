#!/usr/bin/env bash
# Checklist: Phase 1 — standalone Nginx Pod
# validate: pod/nginx-standalone -n default absent-after-delete
#
# A Pod with no ownerReferences is, by Kubernetes design, guaranteed not to
# be recreated if deleted — so we check that structurally instead of
# actually deleting your Pod out from under you.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 1 — standalone Pod (nginx-standalone)"

if ! kube get pod nginx-standalone -n default >/dev/null 2>&1; then
  fail "pod/nginx-standalone not found in namespace default"
  info "If you already ran the delete test, that's expected — recreate the Pod to re-check this step."
  step_result
fi
pass "pod/nginx-standalone exists in namespace default"

owners=$(kube get pod nginx-standalone -n default -o jsonpath='{.metadata.ownerReferences}')
if [ -z "$owners" ] || [ "$owners" = "[]" ] || [ "$owners" = "<no value>" ]; then
  pass "pod/nginx-standalone has no ownerReferences (a controller-managed Pod would; this confirms deleting it will NOT trigger a recreate)"
else
  fail "pod/nginx-standalone has ownerReferences ($owners) — it's controller-managed, not a standalone Pod"
fi

image=$(kube get pod nginx-standalone -n default -o jsonpath='{.spec.containers[0].image}')
case "$image" in
  *nginx*) pass "container image is nginx ($image)" ;;
  *) fail "container image '$image' does not look like nginx" ;;
esac

phase=$(kube get pod nginx-standalone -n default -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass "pod/nginx-standalone is Running"
else
  fail "pod/nginx-standalone phase is '$phase', expected Running"
fi

info "Manual check still required: delete the Pod (kubectl delete pod nginx-standalone) and confirm it does not reappear."

step_result
