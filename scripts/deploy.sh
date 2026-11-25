#!/usr/bin/env bash
# Phase 2: deploys the platform to AWS (EKS) from this PC and runs the cloud tests.
# Steps: terraform apply -> kubeconfig -> build+push images -> Ansible bootstrap (eks overlay) -> wait Healthy -> tests/drills.
set -euo pipefail
. "$(dirname "$0")/aws-env.sh"
P2="$ROOT/proof/phase2-cloud"; mkdir -p "$P2/logs" "$P2/tests" "$P2/screenshots"
PUBLIC_IP="$(curl -fsS https://checkip.amazonaws.com || true)"; export PUBLIC_IP

log "caller identity"; aws sts get-caller-identity | redact | tee "$P2/logs/sts-caller-identity.txt"
if [ "$(git -C "$ROOT" rev-parse HEAD)" != "$(git -C "$ROOT" rev-parse origin/main)" ]; then
  echo "HEAD is not pushed to origin/main: ArgoCD reads manifests from GitHub. Push first." >&2; exit 1
fi

log "terraform apply"
TFD="$(winpath "$TF_DIR")"
terraform -chdir="$TFD" init -input=false >/dev/null
terraform -chdir="$TFD" apply -auto-approve -input=false -no-color 2>&1 | redact | tee "$P2/logs/terraform-apply.log"
NAME="$(tf_output cluster_name)"; REGISTRY="$(tf_output ecr_registry)"; REG_HOST="${REGISTRY%%/*}"

log "kubeconfig for $NAME"
aws eks wait cluster-active --name "$NAME"
use_eks_kubeconfig
kubectl get nodes -o wide | redact

log "build and push images to ECR"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REG_HOST" >/dev/null
build_images
for img in portal go-http-service node-http-service; do
  docker tag "$img:$IMAGE_TAG" "$REGISTRY/$img:$IMAGE_TAG"
  docker push -q "$REGISTRY/$img:$IMAGE_TAG"
done

log "bootstrap ArgoCD with Ansible (eks overlay)"
eks_kubeconfig "$ROOT/.local/kubeconfig-eks-ansible"
"$ROOT/scripts/ansible.sh" "$ROOT/.local/kubeconfig-eks-ansible" eks "$REGISTRY" 2>&1 | redact | tee "$P2/logs/ansible-bootstrap.log"

log "waiting for every application to be Synced and Healthy"
use_eks_kubeconfig
wait_apps 1800 | redact | tee "$P2/logs/argocd-app-list.txt"

log "waiting for the NLB"
LB=""
for _ in $(seq 60); do
  LB="$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$LB" ] && curl -fsS -o /dev/null --max-time 5 "http://$LB/healthz" 2>/dev/null && break; sleep 10
done
echo "http://$LB" > "$ROOT/.local/eks-url"
log "platform reachable at http://$LB"

export BASE_URL="http://$LB"
log "seed and tests"
"$ROOT/scripts/seed.sh"
wait_apps 600 >/dev/null
kubectl get all -A | redact > "$P2/logs/kubectl-get-all.txt"
PLAYWRIGHT_DIR=playwright-eks PROOF_DIR="$P2" E2E=1 "$ROOT/scripts/test-all.sh" || log "some tests failed (see $P2/tests)"
"$ROOT/scripts/drill-hpa.sh" orders-api "$P2/logs/drill-hpa.log" || true
"$ROOT/scripts/chaos.sh" node-drain orders-api "$P2/logs/drill-node-drain.log" || true
"$ROOT/scripts/chaos.sh" pod-kill orders-api "$P2/logs/drill-pod-kill.log" || true
