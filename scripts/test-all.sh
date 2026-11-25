#!/usr/bin/env bash
# Runs every local test layer; exits non-zero on the first failing layer group.
# Set E2E=1 to include the Playwright e2e and k6 smoke (they need a running platform: scripts/dev-up.sh).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
PHASE_DIR="${PROOF_DIR:-$ROOT/proof/phase1-local}/tests"
mkdir -p "$PHASE_DIR"
FAILED=0
run() { # run <name> <command...>: log to $PHASE_DIR/<name>.log
  local name="$1"; shift
  log "== $name"
  if "$@" >"$PHASE_DIR/$name.log" 2>&1; then log "PASS $name"; else log "FAIL $name (see $PHASE_DIR/$name.log)"; tail -15 "$PHASE_DIR/$name.log"; FAILED=1; fi
}

run go-portal bash -c "cd '$ROOT/portal' && go vet ./... && go test -v ./..."
run go-template bash -c "cd '$ROOT/templates/go-http-service' && go vet ./... && go test -v ./..."
run node-template bash -c "cd '$ROOT/templates/node-http-service' && npm ci --silent && npm run build && npm test"
run terraform bash -c "cd '$ROOT/infra' && terraform fmt -check -recursive && for d in envs/showcase; do (cd \$d && terraform init -backend=false -input=false >/dev/null && terraform validate); done && tflint --recursive --config '$ROOT/infra/.tflint.hcl'"
run kyverno bash -c "kyverno test '$ROOT/policies'"
run kubeconform "$ROOT/scripts/kubeconform.sh"
if [ "${E2E:-0}" = "1" ]; then
  [ -n "${KUBECONFIG:-}" ] || use_kind_kubeconfig
  run k6-smoke bash -c "BASE_URL='$BASE_URL' SERVICE=orders-api k6 run --quiet '$(winpath "$ROOT/loadtest/k6-smoke.js")'"
  run playwright bash -c "cd '$ROOT/e2e' && npm ci --silent && npx playwright install chromium >/dev/null && BASE_URL='$BASE_URL' REPORT_DIR='$PHASE_DIR/${PLAYWRIGHT_DIR:-playwright}' npx playwright test"
fi
[ $FAILED -eq 0 ] && log "ALL TESTS PASSED" || log "SOME TESTS FAILED"
exit $FAILED
