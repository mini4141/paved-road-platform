# PROGRESS

Resume from the first unticked item. Phases: 0 scaffold → 1 local → 2 AWS → 3 destroy → 4 write-up.

## Phase status
- [ ] Phase 0 scaffold
- [ ] Phase 1 local
- [ ] Phase 2 AWS showcase
- [ ] Phase 3 destroy
- [ ] Phase 4 write-up

## Coverage matrix (SPECS §2 / CLAUDE §2)
- [ ] Self-service developer platform: F1 portal + F2 golden templates
- [ ] Kubernetes + cloud + FinOps: Terraform EKS spot, HPA, OpenCost
- [ ] CI/CD, GitOps, reusable templates: reusable GH Actions workflows, ArgoCD app-of-apps/ApplicationSet
- [ ] Fault tolerance / DR / scaling: chaos drills, gitops-restore, PDB + topology spread
- [ ] Observability: Prometheus, Alertmanager, Grafana, Loki + Alloy, Tempo, OTel Collector
- [ ] IaC: Terraform modules (network, eks, ecr) + tflint + Ansible bootstrap (kubernetes.core)
- [ ] Measure what matters / gradual change: SLO dashboard, Kyverno Audit→Enforce
- [ ] Stack: kind, EKS, Helm 3, Kustomize, metrics-server, HPA, PDB, topology spread
- [ ] Stack: Traefik single LB, path routing
- [ ] Stack: Kyverno (requests/limits, labels, no latest)
- [ ] Stack: OpenCost in portal
- [ ] Stack: Go portal + htmx + client-go dynamic client
- [ ] Stack: golden templates Go + Node 24/TS with OTel
- [ ] Stack: k6 load test, chaos script

## Features (SPECS §5)
- [ ] F1 portal (catalog, create, detail, status partial, delete)
- [ ] F2 golden templates + reusable workflows
- [ ] F3 GitOps bootstrap (Ansible → ArgoCD → root app → ApplicationSet)
- [ ] F4 observability (dashboards as code, Loki logs, Tempo traces, alert rule)
- [ ] F5 FinOps (OpenCost cost per service in portal)
- [ ] F6 drills (hpa, pod-kill, gitops-restore, node-drain)
- [ ] F7 guardrails (Kyverno policies + tests + deny log)

## Phase 1 proof (SPECS §9)
- [ ] logs/argocd-app-list.txt, logs/ansible-bootstrap.log, logs/kubectl-get-all.txt
- [ ] screenshots 01-portal-catalog, 02-portal-create, 03-service-healthy, 04-argocd-tree, 05-grafana-golden-signals, 06-grafana-slo, 07-loki-logs, 08-tempo-trace, 09-cost-panel
- [ ] logs/drill-hpa.log, drill-pod-kill.log, drill-gitops-restore.log, kyverno-deny.log
- [ ] tests/: Go, kyverno, kubeconform, Playwright reports
- [ ] scripts/test-all.sh green; CI green on main; proof/README.md complete

## Phase 2 proof (SPECS §10)
- [ ] AWS identity check (aws sts get-caller-identity)
- [ ] logs/terraform-apply.log (redacted), resources.txt
- [ ] screenshots 01-eks-portal-catalog, 02-eks-service-healthy, 03-eks-argocd-tree, 04-eks-grafana, 05-eks-cost
- [ ] logs/drill-node-drain.log, logs/drill-hpa.log
- [ ] tests/playwright-eks/

## Phase 3 proof (SPECS §11)
- [ ] scripts/destroy.sh completed
- [ ] proof/phase3-destroy/verify-destroyed.txt shows nothing billable

## Phase 4
- [ ] docs/PORTFOLIO.md, README.md, everything pushed

## Notes / blockers
