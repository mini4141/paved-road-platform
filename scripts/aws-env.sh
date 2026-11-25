#!/usr/bin/env bash
# Sourced by the AWS scripts: pins the profile and region (never the default profile).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export AWS_PROFILE=paved-road-platform-deployer
export AWS_REGION=ap-southeast-2
export AWS_DEFAULT_REGION=ap-southeast-2
export AWS_PAGER=""
TF_DIR="$ROOT/infra/envs/showcase"
EKS_KUBECONFIG="$ROOT/.local/kubeconfig-eks"

# redact 12-digit account IDs, access keys and the deployer's public IP from stdin
redact() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/(AKIA|ASIA)[A-Z0-9]{16}/<ACCESS_KEY>/g; s/k8s-aws-v1\.[A-Za-z0-9_=-]+/<TOKEN>/g' \
  | sed -E "s/${PUBLIC_IP:-no-ip-set}/<PUBLIC_IP>/g"; }

tf_output() { terraform -chdir="$(winpath "$TF_DIR")" output -raw "$1" 2>/dev/null; }

# eks_kubeconfig <file> [internal]: write a kubeconfig with a short-lived token (usable inside the Ansible container).
eks_kubeconfig() {
  local name endpoint ca token
  name="$(tf_output cluster_name)"
  endpoint="$(aws eks describe-cluster --name "$name" --query cluster.endpoint --output text)"
  ca="$(aws eks describe-cluster --name "$name" --query cluster.certificateAuthority.data --output text)"
  token="$(aws eks get-token --cluster-name "$name" --query status.token --output text)"
  cat > "$1" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: eks
  cluster: { server: $endpoint, certificate-authority-data: $ca }
users:
- name: deployer
  user: { token: $token }
contexts:
- name: eks
  context: { cluster: eks, user: deployer }
current-context: eks
EOF
}

# Host kubeconfig: kubectl refreshes tokens itself through `aws eks get-token` (exec plugin).
use_eks_kubeconfig() {
  aws eks update-kubeconfig --name "$(tf_output cluster_name)" --kubeconfig "$EKS_KUBECONFIG" \
    --alias paved-road-eks --profile "$AWS_PROFILE" >/dev/null
  export KUBECONFIG="$(winpath "$EKS_KUBECONFIG")"
}
