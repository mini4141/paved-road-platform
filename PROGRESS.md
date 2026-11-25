# PROGRESS

Resume from the first unticked item. Phases: 0 scaffold → 1 local → 2 AWS → 3 destroy → 4 write-up.

## Phase status
- [x] Phase 0 scaffold
- [x] Phase 1 local
- [x] Phase 2 AWS showcase
- [x] Phase 3 destroy
- [x] Phase 4 write-up

## Coverage matrix (SPECS §2 / CLAUDE §2)
- [x] Self-service developer platform: F1 portal + F2 golden templates
- [x] Kubernetes + cloud + FinOps: Terraform EKS spot, HPA, OpenCost
- [x] CI/CD, GitOps, reusable templates: reusable GH Actions workflows, ArgoCD app-of-apps/ApplicationSet
- [x] Fault tolerance / DR / scaling: chaos drills, gitops-restore, PDB + topology spread
- [x] Observability: Prometheus, Alertmanager, Grafana, Loki + Alloy, Tempo, OTel Collector
- [x] IaC: Terraform modules (network, eks, ecr) + tflint + Ansible bootstrap (kubernetes.core)
- [x] Measure what matters / gradual change: SLO dashboard, Kyverno Audit→Enforce
- [x] Stack: kind, EKS, Helm 3, Kustomize, metrics-server, HPA, PDB, topology spread
- [x] Stack: Traefik single LB, path routing
- [x] Stack: Kyverno (requests/limits, labels, no latest)
- [x] Stack: OpenCost in portal
- [x] Stack: Go portal + htmx + client-go dynamic client
- [x] Stack: golden templates Go + Node 24/TS with OTel
- [x] Stack: k6 load test, chaos script

## Features (SPECS §5)
- [x] F1 portal (catalog, create, detail, status partial, delete)
- [x] F2 golden templates + reusable workflows
- [x] F3 GitOps bootstrap (Ansible → ArgoCD → root app → ApplicationSet)
- [x] F4 observability (dashboards as code, Loki logs, Tempo traces, alert rule)
- [x] F5 FinOps (OpenCost cost per service in portal)
- [x] F6 drills (hpa, pod-kill, gitops-restore, node-drain; node-drain also proven on kind, EKS run in Phase 2)
- [x] F7 guardrails (Kyverno policies + tests + deny log)

## Phase 1 proof (SPECS §9)
- [x] logs/argocd-app-list.txt, logs/ansible-bootstrap.log, logs/kubectl-get-all.txt
- [x] screenshots 01-portal-catalog, 02-portal-create, 03-service-healthy, 04-argocd-tree, 05-grafana-golden-signals, 06-grafana-slo, 07-loki-logs, 08-tempo-trace, 09-cost-panel
- [x] logs/drill-hpa.log, drill-pod-kill.log, drill-gitops-restore.log, kyverno-deny.log
- [x] tests/: Go, kyverno, kubeconform, Playwright reports
- [x] scripts/test-all.sh green; CI green on main; proof/README.md complete

## Phase 2 proof (SPECS §10)
- [x] AWS identity check (aws sts get-caller-identity)
- [x] logs/terraform-apply.log (redacted), resources.txt
- [x] screenshots 01-eks-portal-catalog, 02-eks-service-healthy, 03-eks-argocd-tree, 04-eks-grafana, 05-eks-cost
- [x] logs/drill-node-drain.log, logs/drill-hpa.log
- [x] tests/playwright-eks/

## Phase 3 proof (SPECS §11)
- [x] scripts/destroy.sh completed
- [x] proof/phase3-destroy/verify-destroyed.txt shows nothing billable

## Phase 4
- [x] docs/PORTFOLIO.md, README.md, everything pushed

## Notes / blockers
- The AWS account cannot create load balancers (OperationNotPermitted): the NLB was never created and EKS proof used kubectl port-forward to Traefik. See docs/DECISIONS.md.
- EKS-side CloudWatch metric image not captured; resources.txt holds the describe output instead.
