#!/usr/bin/env bash
# Chaos drills. Usage: scripts/chaos.sh <pod-kill|node-drain|gitops-restore> <service> [logfile]
# Each drill logs before/after state and ends with RESULT: PASS|FAIL.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
DRILL="${1:?drill}"; SVC="${2:-orders-api}"
LOG="${3:-$ROOT/proof/phase1-local/logs/drill-$DRILL.log}"
[ -n "${KUBECONFIG:-}" ] || use_kind_kubeconfig
mkdir -p "$(dirname "$LOG")"
ready() { kubectl -n "$SVC" get deploy "$SVC" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0; }
wait_ready() { # wait until >= $1 ready replicas
  for _ in $(seq 60); do [ "$(ready)" -ge "$1" ] 2>/dev/null && return 0; sleep 5; done; return 1
}

pod_kill() {
  kubectl -n "$SVC" get pods -o wide
  victim="$(kubectl -n "$SVC" get pods -o jsonpath='{.items[0].metadata.name}')"
  BASE_URL="$BASE_URL" SERVICE="$SVC" DURATION=45s k6 run --quiet "$(winpath "$ROOT/loadtest/k6-smoke.js")" >"$ROOT/.local/k6-chaos.out" 2>&1 &
  K6=$!; sleep 10
  echo "-- killing pod $victim under load"; kubectl -n "$SVC" delete pod "$victim" --wait=false
  sleep 5; wait_ready 2 || true
  rc=0; wait $K6 || rc=$?
  echo "-- k6 summary"; grep -E "http_req_failed|http_reqs|http_req_duration|THRESHOLDS|✓|✗" "$ROOT/.local/k6-chaos.out" || true
  kubectl -n "$SVC" get pods -o wide
  if kubectl -n "$SVC" get pod "$victim" >/dev/null 2>&1 && [ "$(kubectl -n "$SVC" get pods -o name | wc -l)" -lt 2 ]; then rc=1; fi
  return $rc  # k6 exits non-zero when error rate >= 1% or p95 >= 500ms
}

node_drain() {
  node="${DRAIN_NODE:-$(kubectl -n "$SVC" get pods -o jsonpath='{.items[0].spec.nodeName}')}"
  echo "-- before"; kubectl -n "$SVC" get pods -o wide; kubectl -n "$SVC" get pdb
  fails=0
  ( while true; do code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BASE_URL/svc/$SVC/healthz" || echo 000)"; echo "$(date +%T) $code"; sleep 1; done ) >"$ROOT/.local/drain-probe.out" &
  PROBE=$!
  echo "-- draining $node (PDB must keep >= 1 pod available)"
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force --timeout=300s 2>&1 | tail -15
  wait_ready 2 || true
  kill $PROBE 2>/dev/null || true
  kubectl uncordon "$node"
  bad="$(grep -vc ' 200$' "$ROOT/.local/drain-probe.out" || true)"; total="$(wc -l <"$ROOT/.local/drain-probe.out")"
  echo "-- availability probe: $((total - bad))/$total OK responses during drain"
  echo "-- after"; kubectl -n "$SVC" get pods -o wide
  [ "$total" -gt 0 ] && [ "$bad" -le $((total / 20)) ] && [ "$(ready)" -ge 1 ]
}

gitops_restore() {
  echo "-- before"; kubectl get ns "$SVC"; kubectl -n "$SVC" get deploy
  kubectl delete ns "$SVC" --wait=true
  echo "-- namespace deleted at $(date +%T); waiting for ArgoCD self-heal"
  for _ in $(seq 60); do
    if kubectl get ns "$SVC" >/dev/null 2>&1 && [ "$(ready)" -ge 1 ] 2>/dev/null; then break; fi; sleep 5
  done
  echo "-- after"; kubectl get ns "$SVC"; kubectl -n "$SVC" get deploy,pods
  kubectl -n argocd get application "$SVC"
  [ "$(ready)" -ge 1 ]
}

{
  echo "== chaos drill '$DRILL' on $SVC at $(date -u +%FT%TZ)"
  if "$(echo "$DRILL" | tr - _)"; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; fi
} 2>&1 | tee "$LOG"
grep -q "RESULT: PASS" "$LOG"
