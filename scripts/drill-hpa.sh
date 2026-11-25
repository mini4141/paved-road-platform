#!/usr/bin/env bash
# Drill: k6 load drives the HPA of a service from 2 to >= 4 replicas; replica count is logged over time.
# Usage: scripts/drill-hpa.sh [service] [logfile]   (env: BASE_URL, KUBECONFIG)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
SVC="${1:-orders-api}"; LOG="${2:-$ROOT/proof/phase1-local/logs/drill-hpa.log}"
[ -n "${KUBECONFIG:-}" ] || use_kind_kubeconfig
mkdir -p "$(dirname "$LOG")"
{
  echo "== HPA drill for $SVC at $(date -u +%FT%TZ)"
  echo "-- before"; kubectl -n "$SVC" get hpa,deploy "$SVC"
  BASE_URL="$BASE_URL" SERVICE="$SVC" k6 run --quiet "$(winpath "$ROOT/loadtest/k6-scale.js")" >"$ROOT/.local/k6-scale.out" 2>&1 &
  K6=$!
  max=0
  while kill -0 $K6 2>/dev/null; do
    cur="$(kubectl -n "$SVC" get deploy "$SVC" -o jsonpath='{.status.replicas}')"
    cpu="$(kubectl -n "$SVC" get hpa "$SVC" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
    echo "$(date +%T) replicas=$cur cpu_utilization=${cpu:-n/a}%"
    [ "${cur:-0}" -gt "$max" ] && max=$cur
    sleep 10
  done
  wait $K6 || true
  echo "-- k6 summary"; grep -E "http_req_failed|http_reqs|http_req_duration" "$ROOT/.local/k6-scale.out" || true
  echo "-- after"; kubectl -n "$SVC" get hpa,deploy "$SVC"
  echo "max replicas observed: $max"
  if [ "$max" -ge 4 ]; then echo "RESULT: PASS (scaled to $max replicas)"; else echo "RESULT: FAIL (max $max)"; fi
} 2>&1 | tee "$LOG"
grep -q "RESULT: PASS" "$LOG"
