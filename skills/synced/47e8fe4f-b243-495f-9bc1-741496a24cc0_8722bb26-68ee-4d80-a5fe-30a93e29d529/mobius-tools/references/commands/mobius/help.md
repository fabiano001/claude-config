---
name: help
description: List available mobius commands and when to use each
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Mobius Command Pack

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or equivalent).
>
> This command provides command discovery and routing only — no analysis or
> generation. Sonnet is sufficient.

The mobius command pack provides ergonomic shortcuts to canonical workflow docs
in `mobius-tools`. Use these commands instead of typing full workflow doc paths.

---

## Available Commands

| Command | Purpose | Model |
|---------|---------|-------|
| `/mobius:help` | Show this help (list all mobius commands) | opus |
| `/mobius:add-service` | Create a new service deployment on EKS | opus |
| `/mobius:update-service` | Modify an already-onboarded service (add AWS resource/IAM, bump chart, add environment) | opus |
| `/mobius:new-xrd` | Create a new Crossplane KCL-based XRD repo | opus |
| `/mobius:new-project` | Add an ArgoCD project or ApplicationSet | opus |
| `/mobius:debug-appset` | Diagnose ApplicationSet discovery failures | opus |
| `/mobius:debug-service` | Debug a running EKS service (logs, status, dependencies) | opus |
| `/mobius:instrument-service` | Add standardized OTEL instrumentation to a Node.js service | opus |
| `/mobius:new-hub` | Create a new ArgoCD hub cluster with full cross-repo wiring | opus |
| `/mobius:new-spoke` | Register a new spoke cluster to an existing ArgoCD hub | opus |
| `/mobius:migrate-ecs-service` | Migrate an ECS service to EKS with auto-extraction | opus |
| `/mobius:migrate-jenkins-to-gha` | Migrate a Jenkins api-node-* service, Node.js library, or Lambda to GitHub Actions | opus |
| `/mobius:validate-service` | Validate service completeness (build, structure, conventions) | opus |
| `/mobius:refresh-docs` | Scan all Mobius repos and refresh stale documentation in mobius-tools | opus |
| `/mobius:review-docs` | Scan all Mobius repos and propose targeted updates to the mobius-docs site | opus |
| `/mobius:document-repo` | Generate AGENTS.md, docs folder, and ecosystem context for any repo | opus |
| `/mobius:document-service` | Deep-dive a service codebase and generate human-readable developer docs | opus |
| `/mobius:upgrade-eks` | Upgrade an EKS cluster to a new Kubernetes version across all required repos | opus |
| `/mobius:document-iac` | Generate IaC-specific docs — module catalogs, addon inventories, control-plane topology | opus |
| `/mobius:grafana` | Create, debug, and explore Grafana dashboards across hub-spoke EKS clusters | opus |

---

## When to Use Each Command

### `/mobius:help` — Choose the right mobius command quickly
Use when you are not sure which command matches your task, or when onboarding someone
to the mobius command pack.
- Maps each command to scope and expected output
- Helps choose between closely related flows (for example, addon vs project)

**Examples**: Deciding whether to run `/mobius:add-service` or `/mobius:new-project`, or finding the right command for ECS migration work.

### `/mobius:add-service` — Deploy a new service to EKS
Use when adding a **new service** (Helm chart, Kustomize overlay, or operator)
to one or more EKS clusters via ArgoCD. This is the most common workflow.
- Creates base/overlay directory structure in `<service-repo>` (typically an engineer-owned self-service repo)
- Keeps ApplicationSet generator `repoURL` aligned to that same `<service-repo>`
- Wires ApplicationSet in `iac-eks-argocd` with matrix + clusters generator
- Generates Crossplane XIRSARole claim if AWS IAM permissions are needed
- Supports deterministic and ai-propose intake modes
- Post-execution: run `validate-add-service-wiring.sh` to verify wiring

**Examples**: Adding cert-manager, external-dns, a monitoring agent, or any Helm-chart-based service.

### `/mobius:update-service` — Modify an already-onboarded service
Use when a service is **already deployed** and you need to change it — the
companion to `add-service`, which only runs at creation time. Three modes:
- **Add an AWS resource / IAM permission** — add an S3 bucket, SQS queue, etc.,
  or extra IAM actions, to a live service (fills the previously command-less
  IAM-permission gap)
- **Bump the Helm chart version** — move to a newer pinned chart version
- **Add a target environment** — add a new env overlay to a service already live elsewhere
- Reuses add-service's generation submodules; post-execution wiring check:
  `npx mobius-validate-wiring update-service --service-repo <path>`

**Examples**: Adding an S3 bucket to a service that now needs one, bumping a
chart after an upstream release, or promoting a qa-only service to prod.

### `/mobius:new-xrd` — Create a new Crossplane composite resource
Use when you need a **new cloud resource abstraction** that teams can self-service
via Crossplane claims (S3 bucket, SQS queue, IAM role, etc.).
- Creates a new KCL-based XRD repo from scratch
- Packages as OCI Configuration for JFrog registry
- Registers with `iac-eks-crossplane` as a Configuration CR

**Examples**: Adding a new `XS3Bucket`, `XSQSQueue`, or `XRDSInstance` Crossplane type.

### `/mobius:new-project` — Add an ArgoCD project or ApplicationSet
Use when you need a **new ArgoCD project** (team-scoped RBAC boundary) or a new
ApplicationSet (auto-discovery configuration).
- Creates project YAML with source/destination permissions
- Sets up ApplicationSet with matrix generator (git files + clusters)

**Examples**: Onboarding a new team to ArgoCD, creating a `data-engineering/` service group.

### `/mobius:debug-appset` — Diagnose ApplicationSet discovery failures
Use when an ApplicationSet **isn't discovering `config.yaml` files** or Applications
aren't being created as expected.
- Layer-by-layer diagnostic flow (config.yaml → path patterns → permissions → controller logs)
- Covers common failures: wrong repo, wrong path, missing project permissions

**Examples**: "I added a config.yaml but no Application was created", "ApplicationSet shows 0 generated Applications".

### `/mobius:debug-service` — Debug a running EKS service
Use when a deployed service is **not working correctly** — pods crashing, routes
not resolving, sync failures, or degraded health status.
- Auto-diagnoses across ArgoCD, Kubernetes, and dependency controllers
- Infers controller dependencies from live state (Envoy Gateway, Crossplane, external-dns, cert-manager)
- Handles hub-first debugging with spoke context switching when needed
- Produces structured report with `[PASS]`/`[FAIL]`/`[WARN]` findings and fix commands
- Suggests `iac-eks-crossplane` debug scripts when Crossplane claims are unhealthy

**Examples**: "Pods are crash-looping after deploy", "HTTPRoute exists but service returns 404", "ArgoCD shows Degraded but sync succeeded".

### `/mobius:instrument-service` — Add OpenTelemetry to a Node.js service
Use when adding **standardized observability** (traces, metrics, structured logs) to
a Node.js service. Analyzes the codebase, classifies endpoints by criticality, and
generates SDK initialization, custom span wrappers, telemetry tests, and engineering
documentation — all following org-wide semantic conventions.
- Two discovery modes: Guided Questionnaire or AI-Proposed (SRE Mode) with criticality tiering
- Generates all three OTEL signals with cardinality controls
- Custom span wrappers for critical paths — no automated business logic modification
- Writes tests that verify telemetry is actually emitted
- Generates engineering-quality docs from the approved instrumentation plan
- Single-repo workflow: branch, commit, PR in the service repo

**Examples**: Adding observability to `api-node-payments`, instrumenting `portal-react-admin` backend.

### `/mobius:new-hub` — Create a new ArgoCD hub cluster
Use when standing up a **completely new ArgoCD control plane** for a new region or
isolated environment.
- Creates hub directory structure in `iac-eks-argocd` (bootstrap, projects, ApplicationSets)
- Documents full cross-repo workflow (terragrunt, crossplane, monitoring)
- Includes intake template and preflight validation
- Covers bootstrap and verification
- Post-execution: run `validate-new-hub-wiring.sh` to verify wiring

**Examples**: Creating an `ops-eu` hub for European region, or a `staging` hub for pre-production.

### `/mobius:new-spoke` — Register a spoke cluster to an existing hub
Use when adding a **new EKS cluster** that should be managed by an existing ArgoCD hub.
- Creates ExternalSecret, ClusterSecretStore, and project destinations in `iac-eks-argocd`
- Creates addon overlays in the spoke's target service repo (`<service-repo>`)
- Documents IAM trust chain across hub and spoke accounts
- Includes 7-phase cross-repo workflow
- Post-execution: run `validate-new-spoke-wiring.sh` to verify wiring

**Examples**: Adding `bg-staging` as a spoke to the `ops-prod` hub, registering a new dev cluster under `ops-qa`.

### `/mobius:migrate-ecs-service` — Migrate an ECS service to EKS
Use when migrating an **existing ECS Fargate/EC2 service** to EKS. Auto-extracts
ECS configuration via AWS CLI and generates all required Kubernetes/ArgoCD artifacts.
- Two-phase flow: `discover` (read-only report) then `generate` (writes files) with human approval gate
- Auto-extracts task definition, service config, IAM roles, ALB health checks, and scaling policies
- Generates Helm values overlay, ArgoCD wiring, XIRSARole claim, and cutover runbook
- Supports service families: `api-node-*`, `portal-react-*`, `webapp-react-*`, `webapp-node-*`
- Compatibility classifier flags non-standard features (EFS, GPU, batch jobs, custom sidecars)
- Detects already-migrated services and offers `adopt` mode
- Post-execution: run `npx mobius-validate-wiring migration` and `npx mobius-validate-intake migration-parity`

**Examples**: Migrating `api-node-payments` from ECS `node10` to EKS, batch-migrating `portal-react-*` services, generating a cutover runbook for production migration.

### `/mobius:migrate-jenkins-to-gha` — Migrate a Jenkins service, library, or Lambda to GitHub Actions
Use when migrating a repo **from Jenkins CI/CD** to GitHub Actions using the
`core-engineering-automation` reusable workflow library. Step 1.0 classifies the repo (from
`package.json` signals, plus Jenkinsfile *content* for lambda — never the repo name, never
Jenkinsfile presence/absence alone) as a **service**, a **library**, or a **lambda**, and routes
accordingly. Processes one repo at a time.

**Service branch** (`api-node-*`):
- Reads migration readiness from `data/api-node-eks-migration-readiness.csv` (service-only gate)
- Generates `config/` directory from existing repo config + ECS task definition (if missing)
- Generates standardized Dockerfile, .dockerignore, .env.example, configureEnv.ts
- Generates GHA workflows: `pr-ci-dispatch.yml` (CI on PR) + `pr-command-dispatch.yml` (slash commands)
- Creates IAM OIDC role (`{app}-cicd-gha`) in the correct Terraform repo (if missing)
- Creates PRs in 1-2 repos (app repo + optional Terraform repo)

**Library branch** (npm package → JFrog):
- No readiness CSV, no Docker/config/IAM — always confirms the library classification with the user
- Generates **three** dispatchers: `pr-ci-dispatch.yml`, `pr-command-dispatch.yml`, and the
  library-only `push-publication-dispatch.yml` (publishes to JFrog on push to `main`)
- Removes Jenkins-era `preversion`/`postversion`; sets `publishConfig`/`.npmrc` if missing
- Single-repo PR; post-merge `/validate` → `/publish-beta` → `/finalize`; flags the Jenkins
  `Publish_Node_Library` decommission follow-up

**Lambda branch** (Node.js AWS Lambda, deployed via Jenkins `pipelineSAM()`):
- No readiness CSV; always confirms the lambda classification with the user
- Parses the Jenkinsfile's `pipelineSAM(...)` arguments against a known-keys table — a
  `function_name` mismatch is a blocking `package.json.name` fix; `publish`/`function_bucket`/
  `npm_ci_prod`/`on_*` Slack hooks have **no workflow-input equivalent** and are reported as
  capability-gap callouts requiring sign-off, never silently dropped or invented as an input
- Detects and fixes the "no build script" gap (`node-lambda-*` reusables hard-require `dist/`)
- Generates up to **four** dispatchers: `pr-ci-dispatch.yml`, `pr-command-dispatch.yml`,
  `manual-deploy.yml`, and `push-deploy-dispatch.yml`
- **Mandatory two-phase PR protocol** (unlike the service/library single-PR flows): Phase 3a
  ships CI + commands + Jenkinsfile removal; Phase 3b — a separate PR opened only after Phase 3a
  merges — adds `push-deploy-dispatch.yml` alone, to avoid a Jenkins + GHA double-deploy on `main`
- Flags the Jenkins job decommission follow-up (Confluence Phase 5) after Phase 3b merges

Human review gates before generation and commit on all three branches.

**Examples**: Migrating `api-node-spam-fraud` (service) from Jenkins to GHA, creating the OIDC IAM role for `api-node-saved-search`; migrating `lib-node-geo` or `lib-api-hapi` (library) to publish to JFrog via GitHub Actions; migrating `lambda-node-fetch-videos` (lambda) off Jenkins `pipelineSAM()` to the `node-lambda-*` hub workflows.

### `/mobius:validate-service` — Validate service completeness
Use to **audit** an existing or in-progress service for build correctness,
structural completeness, and convention compliance.
- Runs `kustomize build` on base and each overlay
- Checks required files (config.yaml, kustomization.yaml, values.yaml)
- Detects missing gateway/HTTPRoute config when the chart supports it
- Supports local mode (working directory) and PR/branch mode (via `gh`)
- Post-execution: reports actionable fixes for any failures

**Examples**: Checking a coworker's PR for missing gateway config, validating a service before opening a PR, auditing older migrations for convention drift.

### `/mobius:document-repo` — Generate comprehensive repo documentation
Use when a repository is **missing AGENTS.md, docs folder, or ecosystem context**.
Works on any repo — platform repos, application services, or pre-migration ECS
services. Analyzes the codebase, proposes documentation, and generates everything
after user review.
- Generates AGENTS.md with frontmatter, bootstrap, and ecosystem position
- Creates docs/ folder with architecture, workflow, and dependency documentation
- Maps both platform dependencies (repo-to-repo) and runtime dependencies (databases, APIs, queues)
- Generates .claude/ecosystem.md for AI agent context
- Optionally registers the repo in the Mobius ecosystem graph
- AI-proposed content with user review before any files are written

**Examples**: Documenting a new service repo, adding AGENTS.md to an ECS service before migration, generating docs for a Terraform module that lacks documentation.

### `/mobius:document-service` — Generate deep service developer documentation
Use when a service needs **developer-facing documentation** — architecture guides,
API references, developer setup guides, and operational runbooks. Performs a 10-pass
deep analysis of the codebase (business logic, request lifecycle, error taxonomy,
security model, etc.) and generates human-readable docs.
- Generates docs/service-guide.md, docs/api-reference.md, docs/developer-guide.md, docs/runbook.md, and docs/README.md
- Traces actual request lifecycles and business rules from code, not templates
- Complements `/mobius:document-repo` (zero file overlap except docs/README.md)
- Only for application services — infrastructure repos should use `/mobius:document-iac`
- AI-proposed documentation plan with user review before any files are written

**Examples**: Generating onboarding docs for a payments API, creating an API reference for a new microservice, building operational runbooks before going on-call for a service.

### `/mobius:upgrade-eks` — Upgrade an EKS cluster to a new Kubernetes version
Use when bumping an EKS cluster from one Kubernetes minor version to the next.
Orchestrates changes across terragrunt, addons, argocd, observability, and
argocd-iac-deployment repos in the correct order.
As of 1.34:
- Updates control plane version, kube-proxy addon, and bootstrap node AMI in `iac-terragrunt-core-infra`
- Upgrades cert-manager and external-secrets Helm chart versions in `iac-eks-addons`
- Migrates deprecated Kubernetes API versions across all affected repos
- Updates Karpenter `EC2NodeClass` AMI selectors for all node pools (x86_64 + arm64)
- Runs pre-upgrade PDB checks and post-upgrade cleanup checklist

**Examples**: Upgrading `bg-qa` from 1.33 to 1.34, which is mostly about bumping cluster to a new minor version, upgrading addons and updating AMIs compatible with that release.
### `/mobius:document-iac` — Generate infrastructure-as-code documentation
Use when an IaC repository needs **infrastructure-specific documentation** beyond
what `/mobius:document-repo` produces. Auto-detects the IaC archetype (Terraform
stack, GitOps addons, ArgoCD control plane) or accepts an explicit `--archetype` flag.
Runs `document-repo` as a base layer, then adds archetype-specific analysis and output files.
- **Terraform stacks**: Module catalog, variable schema, state/backend docs, resource census, cross-environment drift detection
- **GitOps addon repos**: Addon catalog linking existing READMEs (non-destructive), overlay structure, config schema, Crossplane claim inventory
- **ArgoCD control plane**: Hub-spoke topology map, ApplicationSet catalog, project RBAC, team tenancy, bootstrap sequence, hybrid Terraform
- Environment matrix with cross-environment drift for all archetypes
- All dependency assertions labeled `[Observed]` or `[Inferred]` with evidence
- AI-proposed documentation plan with user review before any files are written

**Examples**: Documenting a Terraform provisioning repo with module inventory and variable schemas, cataloging addons in a GitOps config repo, mapping the hub-spoke topology and RBAC of an ArgoCD control-plane repo.

### `/mobius:grafana` — Manage Grafana dashboards
Use when creating, debugging, or exploring Grafana dashboards across hub-spoke EKS clusters.
- **create**: Build a new dashboard for a service and deploy it via GitOps (ConfigMap → ArgoCD → sidecar)
- **debug**: Troubleshoot existing dashboards with missing data, broken PromQL/LogQL/TraceQL queries, or datasource issues
- **explore**: Discover existing dashboards, datasources, and service-to-dashboard mapping
- Targets the correct Grafana instance based on environment (`ops-qa`, `bg-dev` → `ops-qa` hub; `bg-qa`, `bg-prod`, `ops-prod` → `ops-prod` hub)
- Grafana API is read-only except during `create` prototyping; permanent deployment always goes through GitOps

**Examples**: "Create a dashboard for api-node-payments in bg-prod", "Debug why my dashboard shows no data in ops-qa", "What dashboards exist for external-dns?".

### `/mobius:refresh-docs` — Refresh stale documentation in mobius-tools
Use when repos have changed and the central docs in mobius-tools may be out of date.
Scans all repos, compares their current state against master-map.md and
architecture docs, and proposes targeted updates.
- Regenerates mechanical tables (repo inventory, dependencies, skills) from `dependency-graph.yaml`
- Reads each repo's AGENTS.md, ecosystem.md, README for current state
- Flags editorial sections where reality diverged from documentation
- Presents a change report for your approval before modifying anything
- Creates a branch, commits, and opens a PR

**Examples**: Running after adding a new XRD repo, refreshing docs after a quarter of platform changes, checking which docs are stale before onboarding a new engineer.

### `/mobius:review-docs` — Update the mobius-docs engineering site
Use when repos have changed and the user-facing Docusaurus site (`mobius-docs`)
may be missing or stale content. Scans all repos and proposes targeted updates
to `aws-infrastructure/`, `core-concepts/`, and `deploying-your-app/` pages.
- Detects new XRD repos with no corresponding `aws-infrastructure/` page
- Identifies spec fields added or removed in `definition.yaml`
- Flags anti-patterns in CLAUDE.md not yet reflected in user docs
- Drafts full new pages from `definition.yaml` + README + examples
- Presents a change report for your approval before writing anything
- Creates a branch in `mobius-docs`, commits, and opens a PR there

**Examples**: Running after adding `crossplane-xrd-rds-instance`, refreshing XRD spec tables after a schema change, checking for stale path references after a repo restructure.

---

## Validation Scripts

After completing a workflow, verify cross-repo wiring is complete:

| Command | Validator |
|---------|-----------|
| `/mobius:new-hub` | `npx mobius-validate-wiring new-hub <hub>` |
| `/mobius:new-spoke` | `npx mobius-validate-wiring new-spoke <spoke> --hub <hub>` |
| `/mobius:add-service` | `npx mobius-validate-wiring add-service <service> --service-repo <path>` |
| `/mobius:update-service` | `npx mobius-validate-wiring update-service <service> --service-repo <path>` |
| `/mobius:migrate-ecs-service` | `npx mobius-validate-wiring migration <service> --service-repo <path>` |
| `/mobius:migrate-ecs-service` | `npx mobius-validate-intake migration-parity <intake.yaml> --overlay-dir <overlay-dir>` |
| `/mobius:instrument-service` | Embedded lint + build + test run (Phase 5) |
| `/mobius:document-repo` | Embedded Markdown + link validation (Phase 5) |
| `/mobius:document-service` | Embedded Markdown + link validation (Phase 5) |
| `/mobius:document-iac` | Embedded Markdown + link validation + IaC checks IAC-001–IAC-010 (Phase 5) |
| `/mobius:new-xrd` | Embedded checklist in command (no script) |
| `/mobius:new-project` | Embedded checklist in command (no script) |
| `/mobius:debug-appset` | N/A (diagnostic, not generative) |
| `/mobius:debug-service` | N/A (diagnostic, not generative) |
| `/mobius:grafana create` | Verify via Grafana UI after ArgoCD sync |
| `/mobius:grafana debug` | N/A (diagnostic, not generative) |
| `/mobius:grafana explore` | N/A (diagnostic, not generative) |
| `/mobius:validate-service` | `npx mobius-validate-service <service> --service-repo <path>` |
| `/mobius:refresh-docs` | `scripts/generate-map-tables.py` + cross-repo scan |
| `/mobius:review-docs` | N/A (generative, validated by PR review in mobius-docs) |

---

## Prerequisites

Before using these commands, ensure `mobius-tools` dependencies are resolved:

```bash
# Where your boatsgroup repos live (defaults to the parent of your current repo).
# Set MOBIUS_WORKSPACE to keep them somewhere else; commands honor it and clone
# missing repos there. See commands/mobius/shared/workspace-resolution.md.
workspace_dir="${MOBIUS_WORKSPACE:-$(dirname "$PWD")}"

# One-time: clone mobius-tools if not present
[ -d "$workspace_dir/mobius-tools" ] || gh repo clone boatsgroup/mobius-tools "$workspace_dir/mobius-tools"

# Resolve cross-repo dependencies (run from your working repo)
MOBIUS_WORKSPACE="$workspace_dir" bash "$workspace_dir/mobius-tools/scripts/resolve-deps.sh"
```

The resolver ensures sibling repos (`iac-eks-argocd`, `iac-eks-crossplane`, etc.)
are available for cross-repo workflows.

---

## Model Recommendations

All mobius commands recommend **opus-tier models** for execution:

| Runtime | Model |
|---------|-------|
| Claude Code | `claude-opus-4-8` |
| Codex CLI | `o3` via `codex exec --model o3` |

These commands orchestrate changes across 1-6 interconnected repositories where
a single missed file or incorrect ARN causes silent failures. Opus-tier models
provide the cross-repo reasoning required for correctness.

See each command's `## Model Recommendation` section for specific reasoning.

---

## Underlying Workflow Docs

Commands route to these canonical docs in `mobius-tools/docs/workflows/`:

| Command | Workflow Doc |
|---------|-------------|
| `/mobius:add-service` | `docs/workflows/services/add-service.md` |
| `/mobius:update-service` | `docs/workflows/services/update-service.md` |
| `/mobius:new-xrd` | `docs/workflows/xrd/new-xrd.md` |
| `/mobius:new-project` | `docs/workflows/argocd/new-project-or-applicationset.md` |
| `/mobius:debug-appset` | `docs/workflows/argocd/debug-applicationset.md` |
| `/mobius:debug-service` | Self-contained (references `docs/workflows/argocd/argocd-cli-auth.md` for auth) |
| `/mobius:instrument-service` | Self-contained (references ADR-004) |
| `/mobius:migrate-ecs-service` | `docs/workflows/migration/migrate-ecs-service.md` |
| `/mobius:new-hub` | Self-contained (no separate workflow doc) |
| `/mobius:new-spoke` | Self-contained (no separate workflow doc) |
| `/mobius:validate-service` | Self-contained (wraps `npx mobius-validate-service`) |
| `/mobius:grafana` | Self-contained with sub-modules (`grafana/create-dashboard.md`, `grafana/debug-dashboard.md`, `grafana/explore-ecosystem.md`) |
| `/mobius:refresh-docs` | Self-contained (wraps `scripts/generate-map-tables.py` + cross-repo scan) |
| `/mobius:review-docs` | Self-contained (writes to `../mobius-docs` repo) |
| `/mobius:upgrade-eks` | Self-contained (no separate workflow doc) |

If commands are not installed, reference the workflow docs directly.
