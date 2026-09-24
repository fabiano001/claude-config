---
name: migrate-ecs-service
description: Migrate an ECS service to EKS with discover/generate workflow
argument-hint: <service-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Migrate an ECS Service to EKS

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command extracts ECS service configuration from AWS, applies complex
> mapping rules (CPU/memory conversion, IAM to IRSA, ALB to Gateway API), and
> generates cross-repo artifacts. The two-phase discover/generate architecture
> with mandatory human approval gate requires careful state tracking. Weaker
> models may skip approval gates or produce incorrect resource mappings that
> fail silently at deployment time. If using Codex CLI, prefer `codex exec --model o3`.

This command migrates an existing ECS service to EKS using the Mobius GitOps
platform. Follow the canonical workflow at `docs/workflows/migration/migrate-ecs-service.md`.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Platform Overview](../../docs/architecture/platform-overview.md) — ECS (current) vs EKS (target) architecture
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — where migrated services land in the GitOps model
> - [Environment Model](../../docs/architecture/environment-model.md) — overlay structure the migration generates into
> - [Networking](../../docs/architecture/networking.md) — ALB-to-Gateway API translation, DNS cutover
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — ECS task role to IRSA mapping

## Canonical Rules

- No file generation until the intake validator reports PASS and `proposal_accepted: true` is set by a human engineer.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake — strongly encouraged for ECS migrations but skippable.
- No file generation on `main` — feature branches MUST exist in all affected repos before Generate phase.
- Work is not complete until a PR exists for every affected repo.
- Merge order: `iac-eks-argocd` PR merged first, service repo PR merged second.
  (Service repo = `helm-charts` when `chart_location: helm_charts`; application repo when `chart_location: app_repo`.)
- **EKS observability is OTEL Collector + Tempo + Mimir + Loki.** Drop ALL of: xray sidecar, xray IAM actions, datadog sidecar, cloudwatch sidecar. These are replaced at the cluster level. Never add xray back.
- **Every `api-node` service REQUIRES `ELASTICACHE_HOST`/`ELASTICACHE_PORT` in each overlay's `api.env`.** These services load config through `@dmm/lib-node-parameter-store-cache` (usually a transitive dependency), which reads the memcached endpoint from these env vars at startup. The clean-base migration image does not bake them in — omit them and the pod crash-loops at config init (`ERR_MISSING_ARGS`) even when IRSA and SSM are correct. Values per account: `shared-api-memcached.qa.bgrp.io` / `shared-api-memcached.prod.bgrp.io`, port `11211` (confirm from SSM `/configd/elasticache/server/{host,port}`).
- **NEVER generate hub wiring for any hub not confirmed in Q0.** bg-qa and bg-prod both deploy to the ops-prod hub. ops-qa and bg-dev do not exist as hubs.

---

## Doc-First Gate (MANDATORY — before intake begins)

> **Module**: Read [`shared/doc-first-gate.md`](shared/doc-first-gate.md) and execute all steps.

**Target repo**: the application repo being migrated (e.g., `portal-nextjs-platform`).

This gate:
1. Reads existing docs to extract AWS dependencies (AppConfig, S3, SQS, etc.)
2. Cross-references against registered XRDs — surfaces missing claims before file generation
3. Offers `/mobius:document-service`, `/mobius:document-library`, or `/mobius:document-repo` if docs are absent

Do not begin git preflight or Q0 until this gate completes.

---

## Git and JIRA Preflight (before intake begins)

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) (or the appropriate relative path from this file) and resolve `workspace_dir` before any repo path is used. Every `../<repo>` below is `<workspace_dir>/<repo>`.

Before asking any intake questions, verify git prerequisites and prompt for JIRA.

### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Verify for the CURRENT working directory:

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree is clean: `git status --porcelain` returns empty. If dirty, hard-stop — user must resolve manually.
3. Check current branch:
   - If on `main`: pull latest (`git pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user before doing anything:
     ```
     You're currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
        (recommended if you created it for this work)
     2. **Switch to main and create new branch** — start fresh from main
     ```
     If user chooses "use this branch", skip branch creation for `helm-charts` in the Branch Creation Gate.

> Note: Remaining affected repos (`iac-eks-argocd`) are preflighted in the Branch Creation Gate after intake is complete.

### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Prompt the user. JIRA is strongly encouraged for ECS migrations:

```
Before we begin, is there a Jira ticket for this migration?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-123)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use service name only)
```

Store as `jira_ticket_id` (e.g., `PLAT-123` or `null`). This value flows into:
- Branch name in the Branch Creation Gate
- Commit message footer in the Commit/Push/PR phase
- PR title and body in the Commit/Push/PR phase

---

## Q0 Gate (MANDATORY)

> **STOP: Answer this question FIRST before ANY extraction or file generation.**

```
Q0: Is the ECS service active and in scope?
    - Service status must be ACTIVE (not DRAINING or INACTIVE)
    - Cluster must be `node10` or `node-indexers`
    - Account must be `bg-qa` or `bg-prod`
```

Do NOT proceed until you have verified the service exists and is ACTIVE:

```bash
aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'services[0].{status:status,desiredCount:desiredCount,taskDef:taskDefinition}' \
  --output table
```

**Rules:**
- If status is `INACTIVE`: Do not migrate. The service may be decommissioned.
- If status is `DRAINING`: Confirm with service owner before proceeding.
- If cluster is not `node10` or `node-indexers`: Out of scope for this workflow.

**Ask the user:**
> "Please confirm the ECS cluster (`node10` or `node-indexers`), service name,
> and AWS profile (`bg-qa` or `bg-prod`) for this migration."

**After confirming profile, resolve the ArgoCD hub automatically:**

| AWS profile | EKS spoke | ArgoCD hub | Hub path |
|-------------|-----------|------------|----------|
| `bg-qa`     | bg-qa     | ops-prod   | `hubs/ops-prod/environments/ops-prod/us-east-1/` |
| `bg-prod`   | bg-prod   | ops-prod   | `hubs/ops-prod/environments/ops-prod/us-east-1/` |

State the resolved hub to the user and confirm before proceeding:
> "Profile `<profile>` → spoke `<spoke>` managed by **ops-prod** hub. Confirm?"

**HARD RULES:**
- NEVER generate hub wiring for `ops-qa`, `bg-dev`, or any hub not in the table above.
- NEVER assume a hub exists because it sounds like it should — only the hubs in this table exist.
- If the user names a hub not in this table, stop and ask for clarification.

---

## Q1 Gate: Intake Mode Selection (MANDATORY)

> **After Q0, ask this question before proceeding.**

```
Q1: Which intake mode do you want?
    a) deterministic - You provide all values directly
    b) ai-propose    - AI extracts from AWS and proposes values for your approval
```

Set `intake_mode` in the intake template to `deterministic` or `ai-propose`.

---

---

## Q2 Gate: Helm Chart Location (MANDATORY)

> **After Q1, ask this question before proceeding.**

```
Q2: Where does the Helm chart live for this service?
    a) app-repo    - Chart in the application repo (community standard — use for new migrations)
    b) helm-charts - Chart in the central helm-charts repo (only if chart already exists there)
    c) jfrog       - Published chart package in Jfrog (e.g., bg-helm/api-node-template)
```

Store as `chart_location: app_repo | helm_charts | jfrog`. This drives:
- Which repo is affected in the Branch Creation Gate
- Which ApplicationSet source pattern is used (git-path chart vs Jfrog chart)
- Merge order in the PR phase
- Which `--service-repo` path the wiring validator uses

**If `app_repo`:** The application repo replaces `helm-charts` in all subsequent steps.
**If `jfrog`:** No chart generation needed — only overlays + config.yaml go in the app repo.
**If `helm-charts`:** Proceed as normal with the central helm-charts repo.

---

### Deterministic Mode

User provides all required values directly (service metadata, extracted fields,
mapping outputs). Proceed to Preflight Validation after the user fills the
intake YAML.

---

### AI-Propose Mode

> **What it does:** Runs ECS extraction commands, **analyzes 7+ days of CloudWatch metrics for CPU/Memory right-sizing**, applies deterministic mapping rules,
> classifies compatibility, and determines operational hardening (anti-affinity, PDB,
> deployment strategy, graceful shutdown from deregistration delay). Presents a
> proposal table with confidence levels per field and right-sizing recommendations.
> **Key behavior:** STOPS for explicit user acceptance before proceeding. Operational
> hardening is automatically calculated from ECS desiredCount and scaling config.
> **NEW**: Includes CloudWatch metrics analysis for CPU/Memory right-sizing based on actual usage patterns.
> **Module**: Read [`migrate-ecs-service/ai-propose-mode.md`](migrate-ecs-service/ai-propose-mode.md) and execute all steps before continuing to Preflight Validation.

---

## Preflight Validation

Before generating any files, use the intake template and validator:

```bash
# 1. Copy the intake template
cp <workspace_dir>/mobius-tools/docs/workflows/migration/migrate-ecs-intake.yaml /tmp/<service>-intake.yaml

# 2. Fill in all required fields (from Q0 answers and extraction output)

# 3. Run the validator
npx mobius-validate-intake migration /tmp/<service>-intake.yaml

# 4. If ai-propose mode, ensure proposal_accepted: true
# 5. Validator must exit 0 before proceeding
```

Only proceed to file generation after the validator reports **PASS**.

### Validation Checks

The validator enforces:

| Field | Validation |
|-------|------------|
| `service_name` | Non-empty, kebab-case |
| `cluster` | One of: `node10`, `node-indexers` |
| `profile` | One of: `bg-qa`, `bg-prod` |
| `intake_mode` | One of: `deterministic`, `ai-propose` |
| `proposal_accepted` | Must be `true` if `intake_mode: ai-propose` |
| `compatibility_classification` | One of: `fully-compatible`, `supported-with-prompts`, `manual-required` |
| `service_family` | One of: `api-node`, `portal-react`, `webapp-react`, `webapp-node`, `other` |
| `target_environments` | At least one environment |
| Gate booleans | All must be `true` |

If any `manual-required` blockers exist, validation fails unless `--allow-blockers` flag is passed.

---

## Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This gate MUST succeed before the Generate phase begins. If any step fails, STOP.**

### Affected Repos

Determined by `chart_location` from Q2:

| Repo | Role | When affected? |
|------|------|----------------|
| Application repo (e.g., `portal-nextjs-platform`) | Chart + overlays + config.yaml | `chart_location: app_repo` |
| `helm-charts` | Chart + overlays + config.yaml | `chart_location: helm_charts` |
| Application repo (overlays + config.yaml only) | Overlays only, no chart | `chart_location: jfrog` |
| `iac-eks-argocd` | ApplicationSet wiring + project permissions | Always |

### Preflight Remaining Repos

The service repo (helm-charts or application repo) was preflighted in Step 0a. For `iac-eks-argocd`:

1. Verify repo exists locally: `[ -d "<workspace_dir>/iac-eks-argocd" ]`
2. Verify clean working tree: `git -C <workspace_dir>/iac-eks-argocd status --porcelain`
3. Check current branch:
   - If on `main`: `git -C <workspace_dir>/iac-eks-argocd pull origin main`
   - **If NOT on `main`**: Ask the user:
     ```
     iac-eks-argocd is on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
     2. **Switch to main and create new branch** — start fresh
     ```

If any repo has a dirty working tree, STOP. Report which repo and which files are dirty. The user must resolve manually.

### Create Feature Branches

Branch name pattern:
- With JIRA: `feat/<jira_ticket_id>-migrate-<service-name>` (e.g., `feat/PLAT-123-migrate-api-node-payments`)
- Without JIRA: `feat/migrate-<service-name>` (e.g., `feat/migrate-api-node-payments`)

For each repo that needs a new branch (skip repos where the user chose to keep their existing branch):

```bash
git -C <workspace_dir>/<repo> checkout -b <branch-name>
git -C <workspace_dir>/<repo> branch --show-current   # Verify
```

If branch already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

### Gate Verification

Before proceeding to file generation, confirm all affected repos are on the correct branch:

```
Branch Gate Status:
  ✅ helm-charts      → feat/PLAT-123-migrate-api-node-payments
  ✅ iac-eks-argocd   → feat/PLAT-123-migrate-api-node-payments

Proceeding to file generation.
```

If ANY repo failed, STOP. Do not generate files.

### AppProject Existence Check

Before generating `projects/<team>/<service>/project.yaml`, verify:

```bash
ls <workspace_dir>/iac-eks-argocd/projects/<team>/
```

- **Matching project exists** → reuse it. Add only missing `sourceRepos` or `destinations` entries. Do NOT create a new project.yaml.
- **No project exists** → generate a new `project.yaml` from the canonical template.
- **NEVER create a duplicate project** for the same team/namespace combination.

Check neighboring projects in `projects/<team>/` to understand the existing pattern before generating.

---

## Deterministic Mapping Rules

> **What it does:** Full ECS → EKS mapping rules: CPU/memory (direct 1:1), IAM task
> role → XIRSARole, ALB health checks → probes, replicas/scaling → HPA, **operational
> hardening** (anti-affinity when desiredCount ≥ 2, PDB, RollingUpdate, graceful
> shutdown), sidecar classification (drop xray/datadog/cloudwatch/log-router, flag
> unknown), and **listener rule parity** with automated ALB → Gateway API translator.
> **Key behavior:** When desiredCount ≥ 2 or scaling is enabled, HA conventions are
> REQUIRED and enforced by the intake validator — not optional.
> **Module**: Read [`migrate-ecs-service/deterministic-mapping-rules.md`](migrate-ecs-service/deterministic-mapping-rules.md) for the full mapping rule set. These rules are applied automatically in `ai-propose` mode and manually in `deterministic` mode.

> **Important**: The mapping rules include **Operational Hardening** (anti-affinity, PDB,
> deployment strategy, graceful shutdown). When `desiredCount >= 2` or `scaling_enabled`,
> these HA conventions are REQUIRED and enforced by the intake validator.

---

## Workflow Reference

Follow the step-by-step procedure in:
**`<workspace_dir>/mobius-tools/docs/workflows/migration/migrate-ecs-service.md`**

Key phases:
1. **Discover** (Steps 1-3): Extract ECS config, classify compatibility and family
2. **Human Approval Gate** (Step 4): Engineer reviews and sets `proposal_accepted: true`
3. **Generate** (Steps 5-7): Create Helm overlays, ApplicationSet, run validators

Related documents:
- `docs/workflows/migration/ecs-eks-mapping.md` - Full mapping matrix
- `docs/workflows/migration/ecs-extraction-reference.md` - AWS CLI commands
- `docs/workflows/migration/cutover-runbook-template.md` - Cutover checklist
- `/mobius:migrate-ecs-ci-cd` - After this migration, run `migrate-ecs-ci-cd` to add EKS deploy/rollback secrets to the repo's GitHub Actions workflow

---

## Inputs to Gather

| Input | Example | Source |
|-------|---------|--------|
| Intake mode | `deterministic` / `ai-propose` | User choice |
| ECS cluster | `node10` | AWS Console / Q0 |
| ECS service name | `api-node-payments` | AWS Console / Q0 |
| AWS profile | `bg-qa` | `~/.aws/config` |
| Target EKS namespace | `api-node` | Naming convention |
| Target environments | `bg-qa`, `bg-prod` | User input |
| Service family | `api-node`, `portal-react`, `webapp-react`, `webapp-node` | Classification (Step 3) |
| ALB listener rule count | `72` or `0` | AWS Console |
| CPU p95/p99 utilization (7d) | `40%` / `55%` | CloudWatch Metrics |
| Memory p95/p99 utilization (7d) | `60%` / `75%` | CloudWatch Metrics |
| Right-sized CPU requests | `123m` (QA) / `256m` (Prod) | Calculated from metrics |
| Right-sized Memory requests | `308Mi` (QA) / `512Mi` (Prod) | Calculated from metrics |

---

## Post-Execution Validation

Run all three validators. All must exit 0 before considering migration complete:

Use `<service-repo>` = `<workspace_dir>/helm-charts` when `chart_location: helm_charts`, or `<workspace_dir>/<app-repo-name>` when `chart_location: app_repo` or `jfrog`.

```bash
# Validator 1: Intake completeness and approval
npx mobius-validate-intake migration /tmp/<service>-intake.yaml

# Validator 2: Wiring consistency (ApplicationSet <-> overlay paths)
npx mobius-validate-wiring migration <service> \
  --service-repo <service-repo> \
  --envs bg-qa,bg-prod

# Validator 3: ECS <-> EKS parity (resource mapping correctness)
npx mobius-validate-intake migration-parity /tmp/<service>-intake.yaml \
  --overlay-dir <service-repo>/argocd/<service>

# Optional: For listener-heavy services (>10 rules)
npx mobius-validate-intake migration-parity /tmp/<service>-intake.yaml \
  --overlay-dir <service-repo>/argocd/<service> \
  --listener-rules-file /tmp/<service>-listener-rules.yaml
```

> **Known false positive — STRUCT-APPSET-001**: fires when the ApplicationSet lives in a
> subdirectory (e.g., `applicationsets/customer-websites/webapp-nextjs-portal-platform/`).
> This is the correct structure. Ignore STRUCT-APPSET-001 if it is the only failure and
> the subdirectory pattern matches neighboring ApplicationSets in the same group.

### Manual Verification Checklist

#### Service repo (`helm-charts` or application repo, per `chart_location`)
- [ ] `argocd/<service>/base/kustomization.yaml`
- [ ] `argocd/<service>/base/xirsarole.yaml`
- [ ] `argocd/<service>/overlays/<env>/config.yaml` for each environment
- [ ] `argocd/<service>/overlays/<env>/values.yaml` for each environment
- [ ] `argocd/<service>/overlays/<env>/kustomization.yaml` for each environment
- [ ] Anti-affinity configured in `base/values.yaml` when replicas >= 2
- [ ] PDB configured when replicas >= 2
- [ ] Resource requests/limits set in `base/values.yaml`
- [ ] CPU/Memory requests right-sized based on CloudWatch metrics (QA: p95, Prod: p99 or current, whichever is higher)
- [ ] Production resources never reduced below current ECS allocations
- [ ] No xray sidecar, xray IAM actions, datadog sidecar, or cloudwatch sidecar present
- [ ] `api-node` services: `ELASTICACHE_HOST` + `ELASTICACHE_PORT` set in EVERY overlay's `api.env` (host matches the env: `*.qa.bgrp.io` / `*.prod.bgrp.io`)

#### iac-eks-argocd repo
- [ ] `applicationsets/<group>/<service>.yaml` exists
- [ ] ApplicationSet generator `repoURL` matches `helm-charts`
- [ ] `applicationsets/<group>/kustomization.yaml` includes the service
- [ ] Project `sourceRepos` includes `helm-charts`
- [ ] `hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml` includes `<group>` for each target environment

### Universal Change Safety Gate (Pre-PR)

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `helm-charts` + `iac-eks-argocd`.
- `risk_profile`: `mixed` (application deployment config + platform wiring).
- `validation_commands_by_repo`: intake/wiring/parity validators and kustomize checks.
- `rollback_strategy`: git-native revert/reset per repo with merge-order-aware rollback.
- Command-specific focus: ECS->EKS mapping parity, service family mapping correctness,
  ApplicationSet discovery path safety, and project permission integrity.

If Phase A reports any blocker, fix and re-run before commit/PR creation.

---

## Commit, Push, and PR Creation

> **What it does:** Two-repo commit/push/PR: iac-eks-argocd first, then helm-charts.
> Each PR references the other in its description.
> **Key behavior:** Merge order matters — ArgoCD wiring must merge before helm-charts.
> Includes post-PR feedback scan via change-safety-validation.
> **Module**: Read [`migrate-ecs-service/commit-push-pr.md`](migrate-ecs-service/commit-push-pr.md) and execute all steps before continuing.

---

## Anti-Patterns

| Anti-Pattern | Why It Is Forbidden |
|--------------|---------------------|
| Automatic DNS cutover | DNS changes affect live traffic. Cutover is a human-executed checklist. |
| Automatic ECS scale-down | Removes rollback path. ECS must stay at full count during soak period. |
| Skipping human approval gate | Two-phase architecture prevents incorrect artifact generation. |
| Copying broad IAM wildcards | Flag `Resource: "*"` for human review. Do not copy as-is. |
| Setting `proposal_accepted: true` without review | Agent must NOT set this flag - only humans. |
| Generating files for `manual-required` services | Escalate to platform team first. |
| `force: true` sync in ArgoCD | Can cause data loss on stateful resources. |
| Hardcoding AWS account IDs | Use `AWS_ACCOUNT_ID` placeholder. |
| SSM/secret values in logs or files | Extract paths only. Never log values. |
| Reducing production resources below ECS values | Production stability is paramount. Never reduce CPU/Memory below current allocations. |
| Using p95 metrics for production sizing | Production must use p99 or higher for conservative sizing. |
| Ignoring CloudWatch metrics analysis | 7+ days of metrics provide critical right-sizing data. Always analyze when available. |
| Generating hub wiring for an unconfirmed hub | bg-qa and bg-prod both deploy to ops-prod hub. ops-qa, bg-dev, and similar do not exist as hubs. Only generate wiring for the hub confirmed in Q0. |
| Assuming chart_location without asking | Chart location determines affected repos and ApplicationSet source pattern. Always ask Q2 before generating files. |
| Creating a duplicate AppProject | Check `projects/<team>/` for an existing project before generating. Reuse and extend rather than create a new one. |
| Adding xray sidecar or xray IAM actions to EKS | EKS uses OTEL Collector + Tempo + Mimir + Loki. xray is ECS-only. Drop it on every migration. |
| Omitting `ELASTICACHE_HOST`/`ELASTICACHE_PORT` for an api-node service | The parameter-store-cache lib reads these at startup; the clean-base image doesn't bake them in, so config init crashes (`ERR_MISSING_ARGS`) and the pod crash-loops. Required in every overlay. Don't misdiagnose as an IRSA/SSM issue. |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which ECS service was migrated and to how many environments
- "What was accomplished" → describe the auto-generated EKS config from existing ECS settings
- "Why it matters" → the service is now managed by GitOps — config changes are tracked, reviewed, and deployed automatically
- "What happens next" → explain merge order, verify deployment, then decommission ECS service

**Repo breakdown guidance**:
- Service repo (helm-charts or iac-eks-addons): auto-generated service configuration based on existing ECS settings
- iac-eks-argocd: registers the migrated service with the deployment system. Explain that the ECS service should be decommissioned AFTER verifying the EKS deployment is healthy
