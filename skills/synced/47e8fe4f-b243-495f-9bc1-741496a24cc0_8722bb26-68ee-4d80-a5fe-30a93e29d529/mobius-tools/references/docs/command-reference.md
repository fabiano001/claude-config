# Command Reference

> Complete command playbooks and validation matrix for the `/mobius:*` command pack.
>
> For a quick overview, see the [Command Quick Map](#command-quick-map) below.
> For setup, see the [Engineer's Guide](engineer-guide.md#first-time-setup-5-minutes).

---

## Command Quick Map

| Command | Primary use | Post-run validator |
|---------|-------------|--------------------|
| `/mobius:help` | List commands and choose workflow | None (navigation only) |
| `/mobius:add-service` | Create a new service deployment on EKS | `npx mobius-validate-wiring add-service <service> --service-repo <path> --envs <envs>` |
| `/mobius:update-service` | Modify an already-onboarded service (add AWS resource/IAM, bump chart, add env) | `npx mobius-validate-wiring update-service <service> --service-repo <path> --envs <envs>` |
| `/mobius:new-xrd` | Create new KCL-based Crossplane XRD repo | Embedded checklist + `kcl run` and `crossplane beta render` |
| `/mobius:new-project` | Add ArgoCD project or ApplicationSet | `kustomize build` for project/applicationset paths |
| `/mobius:debug-appset` | Diagnose ApplicationSet discovery failures | Collect diagnostic outputs (no generative validator) |
| `/mobius:debug-service` | Debug a running EKS service (logs, status, deps) | N/A (diagnostic — produces structured report) |
| `/mobius:new-hub` | Create new ArgoCD hub with cross-repo wiring | `npx mobius-validate-wiring new-hub <hub> [--monitoring --observability]` |
| `/mobius:new-spoke` | Register new spoke cluster to existing hub | `npx mobius-validate-wiring new-spoke <spoke> --hub <hub> [--monitoring --observability]` |
| `/mobius:migrate-ecs-service` | Migrate ECS service to EKS (discover -> generate) | `npx mobius-validate-intake migration`, `npx mobius-validate-wiring migration` |
| `/mobius:validate-service` | Validate service completeness (build, structure, conventions) | `npx mobius-validate-service <service> --service-repo <path>` |
| `/mobius:validate-service-docs` | Validate generated service docs against code (endpoints, config, deps) | `npx mobius-validate-service-docs <service> --service-repo <path>` |
| `/mobius:instrument-service` | Add standardized OTEL instrumentation to a Node.js service | Embedded lint + build + test run (Phase 5) |
| `/mobius:document-repo` | Generate AGENTS.md, docs/, and ecosystem context for any repo | Embedded Markdown + link validation (Phase 5) |
| `/mobius:document-service` | Deep-dive a service codebase and generate developer docs | Embedded Markdown + link validation (Phase 5) |

---

## Command Playbooks

### `/mobius:help`
- **When to use:** You are not sure which command matches the task.
- **Why this exists:** Fast routing to the correct workflow and validator path.
- **Required inputs (minimum):** None.
- **Run:** `/mobius:help`
- **After:** No files should change; proceed to the selected command.

### `/mobius:add-service`
- **When to use:** Create a new service to be deployed to EKS (Helm/Kustomize), even if the platform folder is named "addons".
- **Why this exists:** Gives engineers a standard self-service path for new service deployment and prevents repoURL/path mismatches or missing cross-repo wiring.
- **Required inputs (minimum):** Service name, service repo for `config.yaml`, intake mode, target envs.
- **Run:** `/mobius:add-service cert-manager`
- **After:** Run `npx mobius-validate-wiring add-service cert-manager --service-repo ../iac-eks-addons --envs bg-qa,bg-prod` and verify generated `argocd/<service>/overlays/<env>/config.yaml` plus `iac-eks-argocd` ApplicationSet updates.

### `/mobius:update-service`
- **When to use:** Change an **already-onboarded** service — add an AWS resource or IAM permission it now needs, bump its Helm chart version, or add a target environment. The companion to `add-service`, which only runs at creation time.
- **Why this exists:** Post-onboarding changes (especially adding an IAM permission) previously had no command — engineers hand-edited IaC. This gives them a standard, validated path and pairs with add-service's "scaffold now, fill in AWS resources later" flow.
- **Required inputs (minimum):** Service name, which mode (add-resource / bump-chart / add-environment), and the mode-specific detail (resource + IAM actions, target version, or new env).
- **Run:** `/mobius:update-service my-api`
- **After:** Run `npx mobius-validate-wiring update-service my-api --service-repo <path>` and verify the modified overlays / ApplicationSet / `terraform/` still satisfy the wiring checks.

### `/mobius:new-xrd`
- **When to use:** Create a new self-service Crossplane resource abstraction.
- **Why this exists:** Enforces KCL + OCI package pattern and platform registration sequence.
- **Required inputs (minimum):** Resource name (kebab-case), API group/version, module/repo name.
- **Run:** `/mobius:new-xrd rds-cluster`
- **After:** Validate with `kcl run` and `crossplane beta render`; verify artifacts in new `crossplane-xrd-<name>` repo, registration in `iac-eks-crossplane`, and graph update in `mobius-tools/ecosystem/dependency-graph.yaml`.

### `/mobius:new-project`
- **When to use:** Add team-scoped ArgoCD project RBAC and/or ApplicationSet discovery.
- **Why this exists:** Avoids missed kustomization registrations and under/over-permissive project config.
- **Required inputs (minimum):** Project/appset name, service repo URL, generator path pattern, target project.
- **Run:** `/mobius:new-project platform-addons`
- **After:** Run `kustomize build ../iac-eks-argocd/projects/<team>/<project>` and `kustomize build ../iac-eks-argocd/applicationsets/<group>`; verify `project.yaml` and kustomization hierarchy.

### `/mobius:debug-appset`
- **When to use:** ApplicationSet is not discovering `config.yaml` or generating Applications.
- **Why this exists:** Structured layer-by-layer diagnostics across repo pathing, generator config, RBAC, and controller logs.
- **Required inputs (minimum):** ApplicationSet name, affected addon/env.
- **Run:** `/mobius:debug-appset core-infrastructure`
- **After:** Capture outputs for `ls argocd/<addon>/overlays/<env>/config.yaml`, `git log origin/main -- <path>`, `kubectl describe applicationset -n argocd <name>`, and `kubectl get applications -n argocd | grep <addon>`.

### `/mobius:debug-service`
- **When to use:** A deployed service is not working correctly — pods crashing, routes not resolving, sync failures, or degraded health.
- **Why this exists:** Auto-diagnoses across ArgoCD, Kubernetes, and dependency controllers (Envoy Gateway, Crossplane, external-dns, cert-manager). Produces a structured report with actionable fix suggestions.
- **Required inputs (minimum):** Service name. Optionally: `--env` and `--hub`.
- **Run:** `/mobius:debug-service api-node-payments --env bg-qa`
- **After:** Follow the recommended actions in the diagnostic report. Re-run to verify fixes.

### `/mobius:new-hub`
- **When to use:** Stand up a new ArgoCD control-plane hub cluster.
- **Why this exists:** Coordinates multi-repo hub bootstrapping with strict phase ordering.
- **Required inputs (minimum):** Hub name, AWS account ID, region, DNS zone, ArgoCD hostname, intake mode.
- **Run:** `/mobius:new-hub ops-staging`
- **After:** Run `npx mobius-validate-wiring new-hub ops-staging`; include `--monitoring --observability` when applicable and verify bootstrap health (`kubectl get applicationset -n argocd`, `argocd app list`).

### `/mobius:new-spoke`
- **When to use:** Register a new spoke EKS cluster under an existing hub.
- **Why this exists:** Enforces hub-spoke IAM trust chain and cross-repo registration sequence.
- **Required inputs (minimum):** Hub name, spoke name, spoke AWS account ID, region, intake mode.
- **Run:** `/mobius:new-spoke bg-staging`
- **After:** Run `npx mobius-validate-wiring new-spoke bg-staging --hub ops-prod`; include optional flags for monitoring/observability and verify `argocd cluster list` plus spoke application sync.

### `/mobius:migrate-ecs-service`
- **When to use:** Migrate active ECS services in supported scope to EKS GitOps.
- **Why this exists:** Provides guarded discover/approve/generate flow with deterministic ECS->EKS mapping and parity checks.
- **Required inputs (minimum):** Service name, ECS cluster (`node10` or `node-indexers`), AWS profile (`bg-qa` or `bg-prod`), intake mode, target environments.
- **Run:** `/mobius:migrate-ecs-service api-node-payments`
- **After:** Run:
  - `npx mobius-validate-intake migration /tmp/api-node-payments-intake.yaml`
  - `npx mobius-validate-wiring migration api-node-payments --service-repo ../helm-charts --envs bg-qa,bg-prod`

### `/mobius:instrument-service`
- **When to use:** A Node.js service needs standardized OpenTelemetry instrumentation — traces, metrics, and structured logs — with cardinality controls and criticality-based coverage.
- **Why this exists:** Observability instrumentation is repetitive, error-prone, and inconsistent across services. This command analyzes a codebase, classifies endpoints by criticality, and generates production-ready OTEL SDK setup, custom spans, metric views, telemetry tests, Grafana dashboards, and runbooks.
- **Required inputs (minimum):** None (uses cwd). Optionally: service repo path argument.
- **Run:** `/mobius:instrument-service` (from target service repo) or `/mobius:instrument-service ../payments-api`
- **After:** Review generated instrumentation files in the PR. Run tests to verify telemetry exports. See [ADR-004](decisions/004-standardized-otel-instrumentation.md) for design rationale.

### `/mobius:document-repo`
- **When to use:** A repository is missing AGENTS.md, docs folder, or ecosystem context. Works on any repo type — platform repos, application services, or pre-migration ECS services.
- **Why this exists:** Engineers and AI agents land in undocumented repos with zero context. This command generates comprehensive documentation by analyzing the codebase and proposing content for user review.
- **Required inputs (minimum):** None (uses cwd). Optionally: repo path argument.
- **Run:** `/mobius:document-repo` (from target repo) or `/mobius:document-repo ../helm-charts`
- **After:** Review generated AGENTS.md, docs/ files, and ecosystem context in the PR. Keep docs updated as the service evolves; run `/mobius:refresh-docs` periodically to detect drift.

### `/mobius:document-service`
- **When to use:** An application service repo needs deep developer documentation — API reference, business logic walkthrough, operations runbook. Complements `document-repo` (which handles AI agent context and ecosystem registration).
- **Why this exists:** New team members need to understand what a service does, on-call engineers need runbooks for 2am incidents, API consumers need endpoint contracts, and contributors need setup and pattern guides. This command deep-dives the codebase with 10 analysis passes and generates human-readable docs.
- **Required inputs (minimum):** None (uses cwd). In a monorepo, documents all services by default. Optionally: pass a service name to limit scope (`/mobius:document-service payments-api`) or a repo path to target a different repo (`/mobius:document-service ../payments-api`).
- **Run:** `/mobius:document-service` (documents all services) or `/mobius:document-service payments-api` (single service in monorepo)
- **After:** Review generated docs/ files in the PR. Verify API reference completeness and architecture accuracy. Run periodically to refresh as the service evolves.

### `/mobius:validate-service`
- **When to use:** Audit a service for build correctness, structural completeness, and convention compliance. Works on local checkouts or PRs/branches.
- **Why this exists:** Catches missing gateway config, structural gaps, and convention drift — especially in PRs created before a platform feature was standardized.
- **Required inputs (minimum):** Service name, service repo path (or `--repo` + `--pr`/`--branch` for GitHub mode).
- **Run:** `/mobius:validate-service api-node-payments --service-repo ../helm-charts`
- **After:** Fix any reported failures; re-run until `RESULT: PASS`.

### `/mobius:validate-service-docs`
- **When to use:** Validate generated docs against actual code: endpoint inventory, config variables, runtime deps, and staleness.
- **Why this exists:** Prevents stale or incomplete docs from misleading engineers and AI workflows, especially after refactors or new dependencies.
- **Required inputs (minimum):** Service name, service repo path. Optional: docs directory path.
- **Run:** `/mobius:validate-service-docs api-node-payments --service-repo ../helm-charts`
- **After:** Fix doc discrepancies (or re-run `/mobius:document-service`), then re-validate.
- **Check catalog:** See [Prometheus Checks Catalog](prometheus-checks-catalog.md#sdoc--service-docs-validator-npx-mobius-validate-service-docs) for all 20 SDOC-* check IDs, default severities, and false-positive controls.

---

## Validator Matrix

| Command | Validator command |
|---------|-------------------|
| `/mobius:help` | None |
| `/mobius:add-service` | `npx mobius-validate-wiring add-service <service> --service-repo <path> --envs <envs>` |
| `/mobius:update-service` | `npx mobius-validate-wiring update-service <service> --service-repo <path> --envs <envs>` |
| `/mobius:new-xrd` | `kcl run . -S items -D "params=$(cat ../test/basic.json)"` and `crossplane beta render claim.yaml composition.yaml functions.yaml` |
| `/mobius:new-project` | `kustomize build ../iac-eks-argocd/projects/<team>/<project>` and `kustomize build ../iac-eks-argocd/applicationsets/<group>` |
| `/mobius:debug-appset` | Diagnostic evidence collection (no generation validator) |
| `/mobius:debug-service` | N/A (diagnostic — produces structured report) |
| `/mobius:new-hub` | `npx mobius-validate-wiring new-hub <hub> [--monitoring --observability]` |
| `/mobius:new-spoke` | `npx mobius-validate-wiring new-spoke <spoke> --hub <hub> [--monitoring --observability]` |
| `/mobius:migrate-ecs-service` | `npx mobius-validate-intake migration`, `npx mobius-validate-wiring migration` |
| `/mobius:validate-service` | `npx mobius-validate-service <service> --service-repo <path>` |
| `/mobius:validate-service-docs` | `npx mobius-validate-service-docs <service> --service-repo <path>` |
| `/mobius:instrument-service` | Embedded lint + build + test run (Phase 5) |
| `/mobius:document-repo` | Embedded Markdown + link validation (Phase 5) |
| `/mobius:document-service` | Embedded Markdown + link validation (Phase 5) |
| `npx mobius-validate-graph` | Dependency graph drift detection (standalone) |

---

## Migration Notes (Current State)

- Supported service families: `api-node`, `portal-react`, `webapp-react`, `webapp-node`.
- Intake validation enforces migration scope (`cluster`: `node10` or `node-indexers`, `profile`: `bg-qa` or `bg-prod`).
- Listener-rule translation is available via `scripts/translate-alb-rules-to-gateway.py` and `scripts/apply-listener-rule-translation.sh`.
- For listener-heavy services, run translation during discover/generate and review partial/unsupported rule output before merge.

---

## Workflow Docs

Canonical procedures live in `docs/workflows/`:

| Command | Workflow doc |
|---------|--------------|
| `/mobius:add-service` | `docs/workflows/services/add-service.md` |
| `/mobius:update-service` | `docs/workflows/services/update-service.md` |
| `/mobius:new-xrd` | `docs/workflows/xrd/new-xrd.md` |
| `/mobius:new-project` | `docs/workflows/argocd/new-project-or-applicationset.md` |
| `/mobius:debug-appset` | `docs/workflows/argocd/debug-applicationset.md` |
| `/mobius:debug-service` | Self-contained (auth: `docs/workflows/argocd/argocd-cli-auth.md`) |
| `/mobius:migrate-ecs-service` | `docs/workflows/migration/migrate-ecs-service.md` |
| `/mobius:new-hub` | Self-contained in command doc |
| `/mobius:new-spoke` | Self-contained in command doc |
| `/mobius:validate-service` | Self-contained (TypeScript CLI: `npx mobius-validate-service`) |
| `/mobius:validate-service-docs` | Self-contained (TypeScript CLI: `npx mobius-validate-service-docs`) |
| `/mobius:instrument-service` | Self-contained (references ADR-004) |
| `/mobius:document-repo` | Self-contained in command doc |
| `/mobius:document-service` | Self-contained in command doc |

See `docs/workflows/INDEX.md` for the full index.
