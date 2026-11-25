#!/usr/bin/env bash
# Loads demo data through the portal itself: the orders-api service, plus an unmanaged
# namespace with a deliberately non-compliant pod (shows up in the Kyverno audit report).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ -n "${KUBECONFIG:-}" ] || use_kind_kubeconfig
if ! kubectl -n argocd get application orders-api >/dev/null 2>&1; then
  log "creating orders-api via the portal"
  curl -fsS -o /dev/null -X POST "$BASE_URL/services" \
    -d name=orders-api -d template=go-http -d team=payments -d replicas=2 -d autoscaling=on -d max_replicas=5
fi
kubectl create namespace sandbox --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n sandbox get pod legacy-app >/dev/null 2>&1 || \
  kubectl -n sandbox run legacy-app --image=nginx:latest >/dev/null
log "seed done"
