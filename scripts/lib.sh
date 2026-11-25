#!/usr/bin/env bash
# Shared helpers, sourced by the other scripts.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a
export PATH="$PATH:/c/Program Files/Go/bin:$HOME/go/bin:$HOME/bin"
CLUSTER_NAME="${CLUSTER_NAME:-paved-road}"
BASE_URL="${BASE_URL:-http://localhost:${KIND_HTTP_PORT:-8080}}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
mkdir -p "$ROOT/.local"
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

use_kind_kubeconfig() {
  kind get kubeconfig --name "$CLUSTER_NAME" > "$ROOT/.local/kubeconfig"
  export KUBECONFIG="$(winpath "$ROOT/.local/kubeconfig")"
}

build_images() { # build the three images locally
  docker build -q -t "portal:$IMAGE_TAG" "$ROOT/portal"
  docker build -q -t "go-http-service:$IMAGE_TAG" "$ROOT/templates/go-http-service"
  docker build -q -t "node-http-service:$IMAGE_TAG" "$ROOT/templates/node-http-service"
}

# wait_apps <timeout-seconds>: wait until every ArgoCD Application is Synced and Healthy.
wait_apps() {
  local deadline=$((SECONDS + $1)) out
  while [ $SECONDS -lt $deadline ]; do
    out="$(kubectl -n argocd get applications.argoproj.io --no-headers \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || true)"
    if [ -n "$out" ] && ! echo "$out" | grep -qvE 'Synced +Healthy$'; then
      echo "$out"; return 0
    fi
    log "waiting for applications ($(echo "$out" | grep -cvE 'Synced +Healthy$' || true) not ready)"
    sleep 20
  done
  echo "$out"; return 1
}
