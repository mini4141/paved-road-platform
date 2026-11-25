#!/usr/bin/env bash
# Starts the whole platform on a local kind cluster (no AWS calls).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

if [ "$(git -C "$ROOT" rev-parse HEAD)" != "$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || echo none)" ]; then
  log "WARNING: HEAD is not pushed to origin/main; ArgoCD reads manifests from GitHub, so push first."
fi
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  log "creating kind cluster $CLUSTER_NAME"
  kind create cluster --name "$CLUSTER_NAME" --config "$(winpath "$ROOT/scripts/kind-config.yaml")" --wait 120s
fi
use_kind_kubeconfig
log "building and loading images"
build_images
for img in portal go-http-service node-http-service; do
  kind load docker-image "$img:$IMAGE_TAG" --name "$CLUSTER_NAME"
done
log "bootstrapping ArgoCD with Ansible"
kind get kubeconfig --internal --name "$CLUSTER_NAME" > "$ROOT/.local/kubeconfig-internal"
mkdir -p "$ROOT/proof/phase1-local/logs"
"$ROOT/scripts/ansible.sh" "$ROOT/.local/kubeconfig-internal" kind "" kind 2>&1 | tee "$ROOT/proof/phase1-local/logs/ansible-bootstrap.log"
log "waiting for every application to be Synced and Healthy (up to 25 min)"
wait_apps 1500
"$ROOT/scripts/seed.sh" || log "seed skipped"
cat <<URLS

Portal:   $BASE_URL/
Grafana:  $BASE_URL/grafana/
ArgoCD:   $BASE_URL/argocd/
URLS
