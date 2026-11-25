# AI usage

This repository was built with Claude Code (an AI coding agent) working from `SPECS.md` and `CLAUDE.md`.

- The agent wrote the code, manifests, scripts and docs, and ran the tooling on the author's PC.
- Every output is verified by executed checks, not by reading: `go test`, `terraform validate`, tflint, `helm template | kubeconform`, `kyverno test`, a Playwright e2e, k6 and the chaos drills. Results are saved under `proof/`.
- Versions of charts and images are looked up at build time and pinned. Decisions that went beyond the specs are logged in `docs/DECISIONS.md`.
- Cloud deploys are driven by scripts the author can read and re-run; nothing is created by hand.
