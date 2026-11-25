#!/usr/bin/env bash
# Captures the proof for a phase into proof/<phase dir>. Usage: scripts/capture-proof.sh phase1|phase2
# Screenshots are taken with headless Playwright so they can be reproduced.
set -euo pipefail
PHASE="${1:?usage: capture-proof.sh phase1|phase2}"
. "$(dirname "$0")/lib.sh"

case "$PHASE" in
  phase1)
    DIR="$ROOT/proof/phase1-local"; PREFIX=local
    use_kind_kubeconfig
    ;;
  phase2)
    . "$ROOT/scripts/aws-env.sh"
    DIR="$ROOT/proof/phase2-cloud"; PREFIX=eks
    use_eks_kubeconfig
    BASE_URL="$(cat "$ROOT/.local/eks-url")"
    PUBLIC_IP="$(curl -fsS https://checkip.amazonaws.com || true)"; export PUBLIC_IP
    ;;
  *) echo "unknown phase $PHASE" >&2; exit 1 ;;
esac
export BASE_URL
mkdir -p "$DIR/logs" "$DIR/screenshots" "$DIR/tests"
clean() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'; }

log "logs: ArgoCD applications and cluster state"
kubectl -n argocd get applications.argoproj.io -o wide | clean > "$DIR/logs/argocd-app-list.txt"
kubectl get all -A | clean > "$DIR/logs/kubectl-get-all.txt"
kubectl get hpa,pdb,servicemonitor,prometheusrule -A 2>/dev/null | clean > "$DIR/logs/hpa-pdb-monitors.txt" || true

log "logs: Kyverno guardrails (deliberate bad apply is denied; audit report for the unmanaged namespace)"
{
  echo "== policies"; kubectl get validatingpolicy
  kubectl create namespace guardrail-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace guardrail-demo paved-road/managed=true --overwrite >/dev/null
  echo; echo "== kubectl apply -f policies/tests/bad-deployment.yaml (namespace guardrail-demo is portal-managed: Enforce)"
  if kubectl apply -f "$ROOT/policies/tests/bad-deployment.yaml" 2>&1; then echo "UNEXPECTED: applied"; else echo "RESULT: DENIED (expected)"; fi
  kubectl delete namespace guardrail-demo --wait=false >/dev/null 2>&1 || true
  echo; echo "== audit reports for namespace sandbox (unmanaged, Audit mode)"
  kubectl get policyreport -n sandbox -o wide 2>&1 || true
  kubectl get policyreport -n sandbox -o jsonpath='{range .items[*].results[*]}{.policy}{"\t"}{.result}{"\t"}{.message}{"\n"}{end}' 2>/dev/null | sort -u || true
} 2>&1 | clean > "$DIR/logs/kyverno-deny.log"

if [ "$PHASE" = phase2 ]; then
  log "resources.txt"
  {
    echo "# Deployed AWS resources (account IDs redacted)"
    echo "## terraform outputs"; terraform -chdir="$(winpath "$TF_DIR")" output
    echo "## EKS cluster"; aws eks describe-cluster --name paved-road --query 'cluster.{name:name,version:version,status:status,endpoint:endpoint,authMode:accessConfig.authenticationMode}' --output table
    echo "## node group"; aws eks describe-nodegroup --cluster-name paved-road --nodegroup-name spot --query 'nodegroup.{capacity:capacityType,types:instanceTypes,scaling:scalingConfig,status:status,disk:diskSize}' --output table
    echo "## nodes"; kubectl get nodes -o wide
    echo "## VPC and subnets"; aws ec2 describe-vpcs --filters Name=tag:Project,Values=paved-road-platform --query 'Vpcs[].{id:VpcId,cidr:CidrBlock}' --output table
    aws ec2 describe-subnets --filters Name=tag:Project,Values=paved-road-platform --query 'Subnets[].{id:SubnetId,az:AvailabilityZone,cidr:CidrBlock,publicIp:MapPublicIpOnLaunch}' --output table
    echo "## ECR repositories"; aws ecr describe-repositories --query "repositories[?starts_with(repositoryName,'paved-road/')].{name:repositoryName,uri:repositoryUri}" --output table
    echo "## load balancer (created by the Traefik Service)"; aws elbv2 describe-load-balancers --query 'LoadBalancers[].{name:LoadBalancerName,type:Type,scheme:Scheme,dns:DNSName}' --output table
    echo "## CloudWatch log group"; aws logs describe-log-groups --log-group-name-prefix /aws/eks/paved-road --query 'logGroups[].{name:logGroupName,retentionDays:retentionInDays}' --output table
    echo "## IAM roles and OIDC provider"; aws iam list-roles --query "Roles[?starts_with(RoleName,'paved-road-')].RoleName" --output table
    aws iam list-open-id-connect-providers --output table
    echo "## tagged resources (resourcegroupstaggingapi)"; aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=paved-road-platform --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
  } 2>&1 | clean | sed -E "s/${PUBLIC_IP:-no-ip-set}/<PUBLIC_IP>/g" > "$DIR/resources.txt"
  log "CloudWatch metric image of the cluster API server"
  aws cloudwatch get-metric-widget-image --output text --query MetricWidgetImage --metric-widget '{"metrics":[["AWS/EC2","CPUUtilization"]],"view":"timeSeries","stat":"Average","period":60,"width":900,"height":300,"title":"EC2 CPUUtilization (cluster nodes)"}' 2>/dev/null | base64 -d > "$DIR/screenshots/06-eks-cloudwatch-ec2-cpu.png" || true
fi

log "screenshots"
( cd "$ROOT/e2e" && npm ci --silent && npx playwright install chromium >/dev/null \
  && SHOTS="$DIR/screenshots" PREFIX="$PREFIX" node capture.mjs )
log "proof captured in $DIR"
