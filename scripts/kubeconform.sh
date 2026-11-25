#!/usr/bin/env bash
# Renders the golden chart, in-repo charts, add-on values and kustomize overlays, then validates them with kubeconform.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
KC=(kubeconform -strict -ignore-missing-schemas -summary
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')
cd "$ROOT"
echo "== charts/golden-service"; helm template orders-api charts/golden-service --set nameOverride=orders-api | "${KC[@]}"
echo "== charts/portal";          helm template portal charts/portal | "${KC[@]}"
echo "== charts/platform-observability"; helm template obs charts/platform-observability | "${KC[@]}"
echo "== policies (kustomize)";   kubectl kustomize policies/overlays/enforce | "${KC[@]}"
echo "== gitops";                 "${KC[@]}" gitops/root-app.yaml gitops/root/
for a in traefik:traefik/traefik metrics-server:metrics-server/metrics-server opencost:opencost/opencost kyverno:kyverno/kyverno; do
  name="${a%%:*}"; chart="${a#*:}"
  ver="$(python -c "import json;print(json.load(open('gitops/addons/$name/addon.json'))['chartVersion'])")"
  for env in kind eks; do
    echo "== addon $name ($env)"
    helm template "$name" "$chart" --version "$ver" -f "gitops/addons/$name/values-common.yaml" -f "gitops/addons/$name/values-$env.yaml" | "${KC[@]}"
  done
done
