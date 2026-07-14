#!/usr/bin/env bash
# Checklist: Phase 4 — Secret injected as env vars into a test Pod
# validate: secret/db-credentials + pod/secret-test env-from-secret
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

section "Phase 4 — db-credentials Secret + secret-test Pod"

if ! kube get secret db-credentials -n lab-apps >/dev/null 2>&1; then
  fail "secret/db-credentials not found in namespace lab-apps"
else
  pass "secret/db-credentials exists in namespace lab-apps"
fi

if ! kube get pod secret-test -n lab-apps >/dev/null 2>&1; then
  fail "pod/secret-test not found in namespace lab-apps"
  step_result
fi
pass "pod/secret-test exists in namespace lab-apps"

secret_env=$(kube get pod secret-test -n lab-apps -o jsonpath='{.spec.containers[*].env[?(@.valueFrom.secretKeyRef.name=="db-credentials")].name}')
secret_envfrom=$(kube get pod secret-test -n lab-apps -o jsonpath='{.spec.containers[*].envFrom[?(@.secretRef.name=="db-credentials")].secretRef.name}')

if [ -n "$secret_env" ] || [ -n "$secret_envfrom" ]; then
  pass "pod/secret-test injects db-credentials via secretKeyRef/envFrom (not a literal value)"
else
  fail "pod/secret-test does not reference db-credentials via env/envFrom"
fi

# Kubernetes' env.valueFrom.secretKeyRef syntax never embeds the literal
# secret value in the Pod spec — but flag any credential-looking env var
# that was hardcoded with a literal .value instead.
literal_names=$(kube get pod secret-test -n lab-apps -o jsonpath='{.spec.containers[*].env[?(@.value)].name}')
suspicious=""
for n in $literal_names; do
  case "$n" in
    *PASS*|*SECRET*|*CRED*|*TOKEN*) suspicious="$suspicious $n" ;;
  esac
done
if [ -n "$suspicious" ]; then
  fail "pod/secret-test has plaintext env value(s) for:$suspicious — use secretKeyRef instead"
else
  pass "no plaintext credential value found in pod/secret-test spec"
fi

step_result
