#!/usr/bin/env bash
# Runs the bootstrap playbook inside a container (native Windows Ansible is unavailable).
# Usage: scripts/ansible.sh <kubeconfig-file> <env> [registry] [--network <docker-network>]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG_FILE="$1"; ENV_NAME="$2"; REGISTRY="${3:-}"; NETWORK="${4:-}"
export MSYS_NO_PATHCONV=1
winpath() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
IMAGE=paved-road/ansible:1
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -q -t "$IMAGE" "$(winpath "$ROOT/bootstrap")"
NET_ARGS=(); [ -n "$NETWORK" ] && NET_ARGS=(--network "$NETWORK")
docker run --rm "${NET_ARGS[@]}" \
  -v "$(winpath "$ROOT"):/repo:ro" \
  -v "$(winpath "$KUBECONFIG_FILE"):/kube/config:ro" \
  -e ANSIBLE_FORCE_COLOR=0 -e ANSIBLE_INVENTORY=/repo/bootstrap/inventory/hosts.yml \
  -e ANSIBLE_ROLES_PATH=/repo/bootstrap/roles -e ANSIBLE_INTERPRETER_PYTHON=auto_silent \
  "$IMAGE" ansible-playbook site.yml -e "env=$ENV_NAME" -e "registry=$REGISTRY" \
  -e "git_repo_url=${GIT_REPO_URL:-https://github.com/mini4141/paved-road-platform.git}" \
  -e "git_revision=${GIT_REVISION:-main}"
