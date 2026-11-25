#!/usr/bin/env bash
# Phase 3: tears everything down. Idempotent and safe to re-run.
# Order: ArgoCD Applications (cascade) -> Traefik LoadBalancer Service (NLB) -> ECR images -> terraform destroy.
set -uo pipefail
. "$(dirname "$0")/aws-env.sh"
P3="$ROOT/proof/phase3-destroy"; mkdir -p "$P3"
TFD="$(winpath "$TF_DIR")"
NAME="$(tf_output cluster_name || true)"; NAME="${NAME:-paved-road}"
VPC="$(tf_output vpc_id || true)"

if aws eks describe-cluster --name "$NAME" >/dev/null 2>&1; then
  log "cluster $NAME exists: removing workloads that would block the destroy"
  if use_eks_kubeconfig 2>/dev/null; then
    # root app first (it owns the ApplicationSet), then the portal-created and remaining apps
    kubectl -n argocd delete application root --wait=true --timeout=300s 2>&1 | tail -2
    kubectl -n argocd delete applicationset --all --wait=true --timeout=120s 2>&1 | tail -2
    kubectl -n argocd delete applications --all --wait=true --timeout=300s 2>&1 | tail -2
    # a stuck finalizer must not block the teardown
    for app in $(kubectl -n argocd get applications -o name 2>/dev/null); do
      kubectl -n argocd patch "$app" --type merge -p '{"metadata":{"finalizers":null}}' 2>&1 | tail -1
    done
    kubectl -n traefik delete svc traefik --ignore-not-found --wait=true --timeout=300s 2>&1 | tail -2
  else
    log "could not reach the cluster API; relying on terraform destroy and the NLB sweep below"
  fi
fi

if [ -n "$VPC" ]; then
  log "waiting until no load balancer is left in $VPC"
  for _ in $(seq 60); do
    n="$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$VPC'])" --output text 2>/dev/null || echo 0)"
    c="$(aws elb describe-load-balancers --query "length(LoadBalancerDescriptions[?VPCId=='$VPC'])" --output text 2>/dev/null || echo 0)"
    [ "${n:-0}" = "0" ] && [ "${c:-0}" = "0" ] && break; sleep 10
  done
  # delete security groups the in-tree cloud provider created for the load balancer (they block VPC deletion)
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" "Name=tag-key,Values=kubernetes.io/cluster/$NAME" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null); do
    aws ec2 delete-security-group --group-id "$sg" 2>&1 | tail -1
  done
fi

log "deleting ECR images"
for repo in $(aws ecr describe-repositories --query "repositories[?starts_with(repositoryName, '$NAME/')].repositoryName" --output text 2>/dev/null); do
  ids="$(aws ecr list-images --repository-name "$repo" --query 'imageIds[*]' --output json)"
  [ "$ids" != "[]" ] && aws ecr batch-delete-image --repository-name "$repo" --image-ids "$ids" >/dev/null
done

log "terraform destroy"
terraform -chdir="$TFD" init -input=false >/dev/null
terraform -chdir="$TFD" destroy -auto-approve -input=false -no-color 2>&1 | redact | tee "$P3/terraform-destroy.log"
exit "${PIPESTATUS[0]}"
