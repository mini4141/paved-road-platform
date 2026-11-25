# Proof index

Each artifact on one line, with what it proves. Screenshots are produced by `scripts/capture-proof.sh` (headless Playwright);
logs and test reports are produced by the scripts named in the repository README. Account IDs are redacted.

## Phase 1: local (kind)

### Screenshots (`phase1-local/screenshots/`)
- `01-portal-catalog.png`: portal catalog lists `orders-api` as Synced/Healthy with replica counts and links.
- `02-portal-create.png`: the self-service create form (name, template, team, replicas, autoscaling).
- `03-service-healthy.png`: service detail: Synced/Healthy, 2/2 replicas, OpenCost cost per hour, scorecard, events.
- `04-argocd-tree.png`: ArgoCD tree: `root` app-of-apps with the `policies` app and the `addons` ApplicationSet generating every add-on.
- `05-grafana-golden-signals.png`: golden-signals dashboard with real traffic, p95 latency with exemplars, replicas and Loki logs.
- `06-grafana-slo.png`: platform SLO dashboard: availability against the 99.5% target and burn rates.
- `07-loki-logs.png`: Loki (via Grafana Explore): structured JSON logs of `orders-api` collected by Alloy.
- `08-tempo-trace.png`: Tempo: a trace of `orders-api` exported over OTLP through the OTel Collector.
- `09-cost-panel.png`: platform overview: nodes, pods, CPU/memory and OpenCost cost per hour by namespace.

### Logs (`phase1-local/logs/`)
- `ansible-bootstrap.log`: the Ansible playbook installing ArgoCD, the cluster label and the root app.
- `argocd-app-list.txt`: every Application (add-ons, policies, root, `orders-api`) Synced and Healthy.
- `kubectl-get-all.txt`, `hpa-pdb-monitors.txt`: cluster state; HPA, PodDisruptionBudgets, ServiceMonitors, PrometheusRules.
- `drill-hpa.log`: k6 load drives `orders-api` from 2 to 5 replicas (replica count over time); PASS.
- `drill-pod-kill.log`: a pod is killed under k6 load: 0% errors, pod replaced; PASS.
- `drill-gitops-restore.log`: the namespace is deleted and ArgoCD recreates it (self-heal); PASS.
- `drill-node-drain.log`: a node is drained; the PDB keeps the service available (probe stayed 200); PASS.
- `kyverno-deny.log`: the deliberately bad Deployment is denied in a portal-managed namespace; Audit report in an unmanaged one.

### Tests (`phase1-local/tests/`)
- `go-portal.log`, `go-template.log`, `node-template.log`: unit tests (one per handler / endpoint).
- `terraform.log`: `terraform fmt -check`, `validate` and `tflint`.
- `kyverno.log`: `kyverno test policies` (good pods pass, bad pods fail each policy).
- `kubeconform.log`: rendered Helm charts, add-on values (kind and eks) and Kustomize validated with kubeconform.
- `k6-smoke.log`: k6 smoke: p95 < 500 ms and errors < 1%.
- `playwright/junit.xml`, `playwright/html/`: Playwright golden path: create a service, wait for Healthy, open its URL.
