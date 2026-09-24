---
name: new-hub
description: Create a new ArgoCD hub cluster with full cross-repo wiring
argument-hint: <hub-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Create a New ArgoCD Hub Cluster

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command orchestrates changes across 4-6 repositories with cross-account
> IAM trust, bootstrap sequencing, and conditional monitoring phases. Weaker
> models may miss IAM role ARN wiring, skip conditional phases, or produce
> incorrect sync wave ordering. If using Codex CLI, prefer `codex exec --model o3`.

This command creates a new ArgoCD hub in the hub-spoke architecture. A hub is
an ArgoCD control plane cluster that manages itself and its spoke clusters.
Follow all phases in order — each depends on the previous.

> **Self-contained**: This command documents the full cross-repo workflow.
> No external workflow doc required.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — hub topology, sync waves, project RBAC
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — cross-account IAM trust chain
> - [Crossplane Flow](../../docs/architecture/crossplane-flow.md) — provider config and composition registration
> - [Networking](../../docs/architecture/networking.md) — NLB listeners, DNS delegation, ACM certificates
> - [Environment Model](../../docs/architecture/environment-model.md) — cluster naming, account topology

---

## Canonical Rules

- No file generation before Q0 gate and preflight validation pass.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake — strongly encouraged for hub creation but skippable.
- No file generation on `main` — feature branches MUST exist in all affected repos before Phase 1.
- Work is not complete until a PR exists for every affected repo.
- Merge order: `iac-terragrunt-core-infra` → `iac-eks-argocd` → `iac-eks-crossplane` → `terraform-stack-monitoring-ng` (if applicable).

---

## Q0 Gate (MANDATORY)

> **STOP: Answer these questions FIRST before ANY file generation.**

### Git and JIRA Preflight (before intake)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Before gathering intake inputs, verify git prerequisites and prompt for JIRA.

#### Step 0a: Git Prerequisites

Verify for the CURRENT working directory:

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree is clean: `git status --porcelain` returns empty. If dirty, hard-stop — user must resolve manually.
3. Check current branch:
   - If on `main`: pull latest (`git pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user:
     ```
     You're currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
        (recommended if you created it for this work)
     2. **Switch to main and create new branch** — start fresh from main
     ```

> Note: Remaining affected repos are preflighted in the Branch Creation Gate after intake confirms which repos are involved.

#### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

```
Before we begin, is there a Jira ticket for this hub creation?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-789)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA
```

Store as `jira_ticket_id`. This flows into branch names, commit footers, and PR titles.

---

```
Q0: What is the hub name? (kebab-case, must be unique)
Q1: What is the AWS Account ID for this hub?
Q2: What is the target AWS region?
```

**Rules:**
- Hub name must not conflict with existing hubs: `ls <workspace_dir>/iac-eks-argocd/hubs/`
- Hub name becomes the cluster name, Kustomize overlay name, and ArgoCD `hub` label
- AWS account must already exist and be accessible
- Hub name must be kebab-case (lowercase letters, numbers, hyphens only)

**Ask the user:**
> "What hub name, AWS account, and region are you targeting?
> Current hubs: `ops-qa` (non-prod), `ops-prod` (prod)."

---

## Intake Mode Selection (MANDATORY)

> **After Q0, ask this question before proceeding.**

```
Q3: Which intake mode do you want?
    a) deterministic - You provide all values directly
    b) ai-propose    - AI researches and proposes values for your approval
```

Set `intake_mode` in the intake template to `deterministic` or `ai-propose`.

---

### Deterministic Mode

User provides all required values directly. Proceed to Preflight Validation.

---

### AI-Propose Mode

> **What it does:** AI researches EKS version, DNS zone, ArgoCD hostname, and monitoring
> needs by querying existing hub clusters and ecosystem context. Presents a recommendation
> table with confidence ratings per field.
> **Key behavior:** STOPS for explicit user acceptance before filling intake fields.
> Same pattern as new-spoke AI-propose — does not proceed until engineer approves.
> **Module**: Read [`new-hub/ai-propose-mode.md`](new-hub/ai-propose-mode.md) and execute all steps before continuing to Preflight Validation.

---

## Preflight Validation

Before generating any files, use the intake template and validator:

```bash
# 1. Copy the intake template
cp <workspace_dir>/mobius-tools/docs/workflows/hub/new-hub-intake.yaml /tmp/<hub>-intake.yaml

# 2. Fill in all required fields

# 3. Run the validator
npx mobius-validate-intake new-hub /tmp/<hub>-intake.yaml
```

Only proceed to file generation after the validator reports **PASS**.

### Verification Booleans (Must All Be True)

| Field | Meaning |
|-------|---------|
| `aws_account_exists` | AWS account exists and is accessible |
| `dns_zone_delegated` | DNS zone delegation is configured in Route53 |
| `eks_cluster_created` | EKS cluster provisioned via terragrunt |
| `irsa_roles_created` | Core IRSA roles created via terragrunt |
| `github_app_secret_exists` | GitHub App credentials exist in AWS Secrets Manager |

---

## Inputs to Gather

| Input | Example | Required |
|-------|---------|----------|
| Hub name (kebab-case) | `ops-staging` | Yes |
| AWS Account ID | `123456789012` | Yes |
| AWS Region | `us-east-1` | Yes |
| DNS zone | `staging.ops.bgrp.io` | Yes |
| ArgoCD hostname | `argo.staging.ops.bgrp.io` | Yes |
| ACM certificate ARN | `arn:aws:acm:us-east-1:123456789012:certificate/...` | Yes |
| EKS version | `1.33` (match latest used by existing hubs) | Yes |
| Cluster name | `ops-staging` | Yes |
| Terragrunt account dir | `ops-staging` | Yes |
| ArgoCD hub role ARN | `arn:aws:iam::123456789012:role/ops-staging-argocd-hub` | Yes |
| Initial spokes | `[]` | No |
| Monitoring required | `false` | No |

---

## Branch Creation Gate (HARD GATE)

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This gate MUST succeed before Phase 1 begins. If any step fails, STOP.**

### Determine Affected Repos

By this point, intake is complete and we know which repos are involved:

| Repo | Always affected? | Condition |
|------|-----------------|-----------|
| `iac-terragrunt-core-infra` | Yes | Infrastructure prerequisites |
| `iac-eks-argocd` | Yes | Hub directory structure |
| `iac-eks-crossplane` | Yes | Crossplane environment and overlays |
| `terraform-stack-monitoring-ng` | Conditional | Only if `monitoring_required: true` |
| `iac-eks-observability` | Conditional | Only if `monitoring_required: true` |

### Preflight Each Affected Repo

The current working directory was preflighted in Step 0a. For each ADDITIONAL affected repo:

1. Verify repo exists locally: `[ -d "<workspace_dir>/<repo>" ]`. If not, hard-stop and report.
2. Verify clean working tree: `git -C <workspace_dir>/<repo> status --porcelain`. If dirty, hard-stop — report which files are dirty.
3. Check current branch:
   - If on `main`: `git -C <workspace_dir>/<repo> pull origin main`. Proceed normally.
   - **If NOT on `main`**: Ask the user:
     ```
     <repo> is on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
     2. **Switch to main and create new branch** — start fresh
     ```

If any repo has a dirty working tree, STOP. The user must resolve manually.

### Create Feature Branches

Branch name pattern:
- With JIRA: `feat/<jira_ticket_id>-new-hub-<hub-name>` (e.g., `feat/PLAT-789-new-hub-ops-staging`)
- Without JIRA: `feat/new-hub-<hub-name>` (e.g., `feat/new-hub-ops-staging`)

For each repo that needs a new branch (skip repos where the user chose to keep their existing branch):

```bash
git -C <workspace_dir>/<repo> checkout -b <branch-name>
git -C <workspace_dir>/<repo> branch --show-current   # Verify
```

If the branch already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

### Gate Verification

Before proceeding to Phase 1, confirm all affected repos are on the correct branch:

```
Branch Gate Status:
  ✅ iac-terragrunt-core-infra → feat/PLAT-789-new-hub-ops-staging
  ✅ iac-eks-argocd             → feat/PLAT-789-new-hub-ops-staging
  ✅ iac-eks-crossplane         → feat/PLAT-789-new-hub-ops-staging
  ✅ terraform-stack-monitoring-ng → feat/PLAT-789-new-hub-ops-staging  (if applicable)
  ✅ iac-eks-observability      → feat/PLAT-789-new-hub-ops-staging  (if applicable)

Proceeding to file generation.
```

If ANY repo failed, STOP. Do not generate files.

---

## Cross-Repo Workflow

### Phase 1: Infrastructure Prerequisites (iac-terragrunt-core-infra)

**Repository:** `iac-terragrunt-core-infra`
**MUST be completed and applied BEFORE any other repo changes.**

#### Steps

1. **Create account directory** (if new account):
   ```
   aws/accounts/<hub>/
   ├── account.yaml
   └── us-east-1/
       ├── region.yaml
       └── <hub>.network-us-east-1/
           ├── env.yaml
           └── services/
   ```

Apply in order (each: `terragrunt plan && terragrunt apply`):

| # | Terragrunt module path |
|---|----------------------|
| 2 | `.../networking/delegated-zones/<dns-zone>` |
| 3 | `.../services/<hub>-eks` _(~15-20 min)_ |
| 4 | `.../services/<hub>-eks-core-irsa-addons` |
| 5 | `.../services/<hub>-argocd-hub-registration` |

All paths are under `aws/accounts/<hub>/us-east-1/<hub>.network-us-east-1/`.
   - Inputs:
     - `mode = "hub"`
     - `cluster_name = "<hub>"`
     - `environment = "<hub>"`
     - `spoke_account_ids = []` (initially empty)
     - `tags` — Standard resource tags

6. **Create GitHub App credentials in AWS Secrets Manager:**
   - Secret name: `<hub>/argocd/github-app-credentials` (hub-prefixed path in Secrets Manager)
   - The hub prefix is required because the overlay kustomization patches
     ENVIRONMENT_PLACEHOLDER in the base ExternalSecret with `<hub>/argocd/github-app-credentials`
   - Required for ArgoCD to access private Git repos

#### Validation
```bash
aws eks describe-cluster --name <hub> --query 'cluster.status'
# Expected: "ACTIVE"
```

---

### Phase 2: ArgoCD Hub Structure (iac-eks-argocd)

**Repository:** `iac-eks-argocd`

> **What it does:** Creates the hub directory tree by copying from an existing hub (ops-qa).
> Key files include: kustomization.yaml (patches 3 ApplicationSets with hub-specific paths),
> bootstrap-parent-application.yaml, per-hub base directory (github-app-credentials
> ExternalSecret with ENVIRONMENT_PLACEHOLDER), overlay, and hub self-environment with
> all 6 ApplicationSet references.
> **Key behavior:** Each hub has its OWN base directory — the overlay references `../../base`
> relative to itself. Copy-from-existing-hub pattern, never generate from scratch.
> **Module**: Read [`new-hub/phase2-argocd-structure.md`](new-hub/phase2-argocd-structure.md) and execute all steps before continuing.

---

### Phase 3: Crossplane Environment (iac-eks-crossplane)

**Repository:** `iac-eks-crossplane`

> **What it does:** Creates Terraform environment + ArgoCD overlay for Crossplane by
> copying from the ops-qa hub. Captures the provider role ARN from Terraform apply,
> then wires it into runtime-configs.
> **Key behavior:** Same copy-and-apply pattern as new-spoke Phase 4 Crossplane.
> Terraform must be applied first to get the ARN before ArgoCD overlay is complete.
> **Module**: Read [`new-hub/phase3-crossplane.md`](new-hub/phase3-crossplane.md) and execute all steps before continuing.

---

### Phase 4: Monitoring (terraform-stack-monitoring-ng) — CONDITIONAL

**Only if `monitoring_required: true`.**

> **What it does:** CONDITIONAL — creates monitoring Terraform environment (must copy
> ALL files including dashboard JSONs) AND creates observability GitOps overlays for
> up to 15 components in iac-eks-observability.
> **Key behavior:** Unlike spoke monitoring (which is rare), hub monitoring creates
> overlays across TWO repos: terraform-stack-monitoring-ng AND iac-eks-observability.
> Must copy all dashboard JSON files — missing dashboards cause silent monitoring gaps.
> **Module**: Read [`new-hub/phase4-monitoring.md`](new-hub/phase4-monitoring.md) and execute all steps before continuing.

---

### Phase 5: Bootstrap

**Repository:** `iac-eks-argocd`

> **What it does:** Runs `install.sh -u <hub> -e <hub> -r <region>` on the hub cluster
> to bootstrap ArgoCD. Follows a 10-step sequence: namespace → Helm → ArgoCD → cluster
> secret → github creds → bootstrap app → app-of-apps → verify.
> **Key behavior:** Results in sync wave ordering (-100 → -50 → -10 → 0). The bootstrap
> must be run on the actual cluster — this is the only phase that requires cluster access.
> **Module**: Read [`new-hub/phase5-bootstrap.md`](new-hub/phase5-bootstrap.md) and execute all steps before continuing.

---

### Phase 6: Verification

```bash
# ArgoCD parent application exists and is healthy
kubectl get application <hub>-bootstrap-parent -n argocd

# All ApplicationSets created
kubectl get applicationset -n argocd

# All Applications healthy
argocd app list --project core-infrastructure

# Sync waves respected
argocd app get <hub>-bootstrap-parent --show-operation

# ArgoCD UI accessible
curl -k https://<argocd_hostname>/healthz
```

### Phase 6.5: Universal Change Safety Gate (Pre-PR)

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `iac-terragrunt-core-infra`, `iac-eks-argocd`,
  `iac-eks-crossplane`, plus conditional monitoring/observability repos.
- `risk_profile`: `mixed`.
- `validation_commands_by_repo`: preflight checks, phase validation checks,
  and wiring verification from prior phases.
- `rollback_strategy`: merge-order-aware git-native revert/reset per repo.
- Command-specific focus: infra prerequisite safety, hub bootstrap wiring,
  cross-repo merge-order integrity, and conditional phase correctness.

If Phase A reports any blocker, fix and re-run before Phase 7.

---

## Phase 7 — Commit, Push, and PR Creation

> **What it does:** Multi-repo commit/push/PR in merge order:
> terragrunt → argocd → crossplane → monitoring → observability.
> Each PR references the predecessor PR URL in its description.
> **Key behavior:** Merge order is critical — PRs must be merged in the specified
> sequence. Includes post-PR feedback scan via change-safety-validation.
> **Module**: Read [`new-hub/commit-push-pr.md`](new-hub/commit-push-pr.md) and execute all steps before continuing.

---

## Post-Execution Checklist

Run the wiring validator to verify all cross-repo files were created:

```bash
npx mobius-validate-wiring new-hub <hub-name>

# With optional phases:
npx mobius-validate-wiring new-hub <hub-name> --monitoring --observability
```

### Manual Verification

If the validator is not available, verify these files exist:

#### iac-eks-argocd
- [ ] `hubs/<hub>/kustomization.yaml`
- [ ] `hubs/<hub>/bootstrap/bootstrap-parent-application.yaml`
- [ ] `hubs/<hub>/bootstrap/resources/base/kustomization.yaml`
- [ ] `hubs/<hub>/bootstrap/resources/overlays/<hub>/kustomization.yaml`
- [ ] `hubs/<hub>/environments/<hub>/` (hub self-management)

#### iac-eks-crossplane
- [ ] `argocd/crossplane/overlays/<hub>/config.yaml`
- [ ] `argocd/crossplane/overlays/<hub>/kustomization.yaml`

#### iac-terragrunt-core-infra
- [ ] Account directory for hub exists
- [ ] EKS cluster module configured

#### iac-eks-observability (if monitoring required)
- [ ] Component overlays in `argocd/<component>/overlays/<hub>/`

#### terraform-stack-monitoring-ng (if monitoring required)
- [ ] `environments/<hub>/` with backend.tf

---

## Anti-Patterns to Avoid

| Pattern | Why Forbidden |
|---------|---------------|
| Skipping `bootstrap/resources/base/` in new hub | Each hub has its OWN base — overlay references `../../base` relative to itself |
| Copying `clusters/` dir from reference hub | New hub has no spokes yet — add via `/mobius:new-spoke` |
| Hardcoding `spoke_account_ids` in hub registration | Start empty; update when spokes are added |
| Skipping DNS zone delegation | ArgoCD ingress and cert-manager will fail |
| Using hub name with underscores | Breaks Kubernetes label selectors and DNS names |
| Applying bootstrap before IRSA roles exist | ArgoCD pods can't assume roles → auth failures |
| Merging `iac-eks-argocd` before terragrunt applied | EKS cluster must exist for bootstrap to work |
| Creating monitoring env for non-production hub | Only production-like hubs need `terraform-stack-monitoring-ng` |
| Using `.yml` extension | Convention is `.yaml` in this repository |

---

## Merge Order

1. **`iac-terragrunt-core-infra`** — EKS cluster, DNS, IRSA, hub registration
2. **`iac-eks-argocd`** — Hub directory structure
3. **`iac-eks-crossplane`** — Crossplane Terraform environment + overlays
4. **`terraform-stack-monitoring-ng`** — Only if monitoring required
5. **Bootstrap execution** — After all merges complete and applied
6. **Verification** — After bootstrap succeeds

> **CRITICAL**: Step 1 MUST be fully applied (not just merged) before proceeding.
> The EKS cluster, IAM roles, and Secrets Manager entries must physically exist
> in AWS before ArgoCD bootstrap can succeed.

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which new hub cluster was created and how many repos were modified
- "What was accomplished" → describe the new deployment hub, cloud infrastructure, and monitoring setup
- "Why it matters" → a new isolated deployment region/boundary is now available for services
- "What happens next" → explain multi-repo merge order and infrastructure provisioning timeline

**Repo breakdown guidance**: Use `shared/repo-roles.md` for plain-language descriptions of each affected repo.
