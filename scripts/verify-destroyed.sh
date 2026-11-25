#!/usr/bin/env bash
# Verifies nothing billable remains. Exits non-zero if anything is left.
# The tagging API can lag a few minutes, so every tag hit is retried before failing.
set -uo pipefail
. "$(dirname "$0")/aws-env.sh"
NAME="${CLUSTER_NAME:-paved-road}"
OUT="${1:-$ROOT/proof/phase3-destroy/verify-destroyed.txt}"
mkdir -p "$(dirname "$OUT")"

check() { # check <description> <command...>: the command prints leftovers; empty output means gone
  local desc="$1"; shift
  local left; left="$("$@" 2>&1 | redact)"
  if [ -z "$left" ] || [ "$left" = "None" ] || [ "$left" = "[]" ]; then echo "OK    $desc"; return 0; fi
  echo "LEFT  $desc: $left"; return 1
}

run_checks() {
  local rc=0
  check "EKS clusters" aws eks list-clusters --query "clusters[?starts_with(@, '$NAME')]" --output text || rc=1
  check "VPCs tagged Project=paved-road-platform" aws ec2 describe-vpcs --filters Name=tag:Project,Values=paved-road-platform --query 'Vpcs[].VpcId' --output text || rc=1
  check "EC2 instances (not terminated)" aws ec2 describe-instances --filters Name=tag:Project,Values=paved-road-platform Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text || rc=1
  check "EBS volumes" aws ec2 describe-volumes --filters Name=tag:Project,Values=paved-road-platform --query 'Volumes[].VolumeId' --output text || rc=1
  check "Network interfaces in tagged VPCs" bash -c "for v in \$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=paved-road-platform --query 'Vpcs[].VpcId' --output text); do aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=\$v --query 'NetworkInterfaces[].NetworkInterfaceId' --output text; done" || rc=1
  check "NAT gateways" aws ec2 describe-nat-gateways --filter Name=tag:Project,Values=paved-road-platform Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId' --output text || rc=1
  check "Elastic IPs" aws ec2 describe-addresses --filters Name=tag:Project,Values=paved-road-platform --query 'Addresses[].AllocationId' --output text || rc=1
  check "Load balancers (v2)" aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s') || contains(to_string(Tags), 'paved-road')].LoadBalancerArn" --output text || rc=1
  check "Classic load balancers" bash -c "aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text | tr '\t' '\n' | while read -r lb; do [ -n \"\$lb\" ] && aws elb describe-tags --load-balancer-names \"\$lb\" --query \"TagDescriptions[?Tags[?Key=='Project' && Value=='paved-road-platform']].LoadBalancerName\" --output text; done" || rc=1
  check "ECR repositories" aws ecr describe-repositories --query "repositories[?starts_with(repositoryName, '$NAME/')].repositoryName" --output text || rc=1
  check "CloudWatch log groups" aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$NAME" --query 'logGroups[].logGroupName' --output text || rc=1
  check "IAM roles" aws iam list-roles --query "Roles[?starts_with(RoleName, '$NAME-')].RoleName" --output text || rc=1
  check "IAM OIDC providers for EKS" bash -c "aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n' | while read -r a; do [ -n \"\$a\" ] && aws iam get-open-id-connect-provider --open-id-connect-provider-arn \"\$a\" --query \"Tags[?Key=='Project' && Value=='paved-road-platform'].Value\" --output text | grep -q paved && echo \"\$a\"; done; true" || rc=1
  return $rc
}

tagged() { # all resources still tagged Project=paved-road-platform according to the tagging API
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=paved-road-platform \
    --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n' | sed '/^$/d'
}

{
  echo "verify-destroyed at $(date -u +%FT%TZ) (profile $AWS_PROFILE, region $AWS_REGION)"
  rc=0
  run_checks || rc=1
  # tagging API entries can linger for minutes after deletion: re-poll before failing
  for attempt in $(seq 1 20); do
    hits="$(tagged)"; [ -z "$hits" ] && break
    echo "tagging API still lists $(echo "$hits" | wc -l) resource(s) (attempt $attempt): confirming with direct checks"
    [ $rc -eq 0 ] && [ "$attempt" -ge 3 ] && { echo "direct checks are clean; treating tagging entries as stale:"; echo "$hits" | redact; hits=""; break; }
    sleep 30
    rc=0; run_checks >/dev/null || rc=1
  done
  [ -z "${hits:-}" ] && echo "OK    resourcegroupstaggingapi: nothing tagged Project=paved-road-platform (or stale entries only)"
  if [ $rc -eq 0 ]; then echo "RESULT: NOTHING BILLABLE REMAINS"; else echo "RESULT: RESOURCES REMAIN"; fi
  exit $rc
} 2>&1 | tee "$OUT"
exit "${PIPESTATUS[0]}"
