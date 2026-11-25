#!/usr/bin/env bash
# Deletes the local kind cluster.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
kind delete cluster --name "$CLUSTER_NAME"
