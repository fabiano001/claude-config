---
name: new-spoke
description: Register a new spoke cluster to an existing ArgoCD hub
argument-hint: <spoke-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Register a New Spoke Cluster

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command orchestrates changes across 4-6 repositories with a 3-way IAM
> trust chain, hub-spoke registration, and 7-phase dependency ordering. Weaker
> models may break the cross-account trust chain, forget hub-side updates, or
> skip kustomization wiring. If using Codex CLI, prefer `codex exec --model o3`.

This command registers a spoke cluster with an existing ArgoCD hub in the hub-spoke
architecture. A spoke is a remote EKS cluster managed by a hub's ArgoCD control
plane via cross-account IAM trust. Follow all phases in order.

> **Self-contained**: This command documents the full cross-repo workflow.
> No external workflow doc required.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — spoke registration, project RBAC, ApplicationSet discovery
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — 3-way cross-account IAM trust chain
> - [Environment Model](../../docs/architecture/environment-model.md) — cluster naming, overlay structure, account topology
> - [Crossplane Flow](../../docs/architecture/crossplane-flow.md) — provider config for spoke cluster
> - [Networking](../../docs/architecture/networking.md) — NLB listeners, DNS delegation for spoke environments
> - [Karpenter Autoscaling](../../docs/architecture/karpenter-autoscaling.md) — NodePool provisioning and bootstrap node group

---

## Canonical Rules

- No file generation before intake is confirmed.
- No completion claim before Phase 7 verification passes.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake questions — strongly encouraged but skippable.
- No file generation on `main` — a feature branch MUST exist in all affected repos before Phase 1.
- Work is not complete until a PR exists for every affected repo.
- Merge order: `iac-terragrunt-core-infra` first, then `iac-eks-argocd`, then `iac-eks-addons`, then `iac-eks-crossplane`, then `terraform-stack-monitoring-ng` (if applicable).
- Phase 1 (terragrunt) MUST be fully applied before any other repo changes — the EKS API server URL is required for argocd project destinations.

---

## Q0 Gate (MANDATORY)

> **STOP: Answer these questions FIRST before ANY file generation.**

```
Q0: Which existing hub will manage this spoke?
    Check available hubs: ls <workspace_dir>/iac-eks-argocd/hubs/
    Current hubs: ops-qa (non-prod), ops-prod (prod)

Q1: What is the spoke name? (kebab-case)
Q2: What is the spoke's AWS Account ID?
Q3: What is the target AWS region?
```

**Rules:**
- Hub MUST already exist — run `/mobius:new-hub` first if needed
- Spoke name must not conflict with existing environments in any hub
- Spoke AWS account must be different from hub AWS account
- Spoke name must be kebab-case (lowercase letters, numbers, hyphens only)

**Ask the user:**
> "Which hub will manage this spoke, and what are the spoke name, account, and region?
> Current hubs: `ops-qa` (manages bg-dev), `ops-prod` (manages bg-qa, bg-prod)."

---

## Git and JIRA Preflight (before intake questions)

Before asking intake questions, verify git prerequisites and prompt for JIRA.

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
     If user chooses "use this branch", skip branch creation for this repo in the Branch Creation Gate.

> Note: Remaining affected repos are preflighted in the Branch Creation Gate (after Preflight Validation) once we know which repos are involved.

### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Prompt the user. JIRA is strongly encouraged for spoke registration:

```
Before we begin, is there a Jira ticket for this spoke registration?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-123)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use spoke name only)
```

Store as `jira_ticket_id` (e.g., `PLAT-123` or `null`). This value flows into:
- Branch name in the Branch Creation Gate
- Commit message footer in Phase 6
- PR title and body in Phase 6

---

## Intake Mode Selection (MANDATORY)

> **After Q0, ask this question before proceeding.**

```
Q4: Which intake mode do you want?
    a) deterministic - You provide all values directly
    b) ai-propose    - AI researches and proposes values for your approval
```

Set `intake_mode` in the intake template to `deterministic` or `ai-propose`.

---

### Deterministic Mode

User provides all required values directly. Proceed to Preflight Validation.

---

### AI-Propose Mode

> **What it does:** AI researches hub assignment, EKS version, core addons, and
> Crossplane/monitoring needs by querying existing clusters and ecosystem context.
> Presents a recommendation table with HIGH/MEDIUM/LOW confidence ratings per field.
> **Key behavior:** STOPS for explicit user acceptance before filling intake fields.
> Does not proceed until the engineer approves or overrides each recommendation.
> **Module**: Read [`new-spoke/ai-propose-mode.md`](new-spoke/ai-propose-mode.md) and execute all steps before continuing to Preflight Validation.

---

## Preflight Validation

Before generating any files, use the intake template and validator:

```bash
# 1. Copy the intake template
cp <workspace_dir>/mobius-tools/docs/workflows/hub/new-spoke-intake.yaml /tmp/<spoke>-intake.yaml

# 2. Fill in all required fields

# 3. Run the validator
npx mobius-validate-intake new-spoke /tmp/<spoke>-intake.yaml
```

Only proceed to file generation after the validator reports **PASS**.

### Verification Booleans (Must All Be True)

| Field | Meaning |
|-------|---------|
| `aws_account_exists` | Spoke AWS account exists and is accessible |
| `dns_zone_delegated` | DNS zone delegation is configured in Route53 |
| `eks_cluster_created` | EKS cluster provisioned via terragrunt |
| `irsa_roles_created` | Core IRSA roles created via terragrunt |
| `spoke_iam_roles_created` | `argocd-access` + `external-secrets-cross-account` exist |
| `hub_irsa_updated` | Hub IRSA registration updated with spoke account |
| `hub_spoke_account_ids_updated` | Hub terragrunt `spoke_account_ids` includes spoke |
| `eks_api_server_url_known` | EKS API URL captured from terragrunt output |

---

## Branch Creation Gate (HARD GATE)

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This gate MUST succeed before Phase 1 begins. If any step fails, STOP.**

### Determine Affected Repos

By this point, the intake is complete and we know which repos are involved:

| Repo | Always affected? | Condition |
|------|-----------------|-----------|
| `iac-terragrunt-core-infra` | Yes | EKS cluster, DNS, IRSA, spoke + hub registration |
| `iac-eks-argocd` | Yes | ExternalSecret, ClusterSecretStore, environments, project destinations |
| `iac-eks-addons` | Yes | Addon overlays for all core addons |
| `iac-eks-crossplane` | Yes | Terraform environment + ArgoCD overlay |
| `iac-eks-observability` | Conditional | Only if spoke references `monitoring` ApplicationSet |
| `terraform-stack-monitoring-ng` | Conditional | Only if `monitoring_required: true` |

### Preflight Each Repo

The current working repo was preflighted in Step 0a. For each ADDITIONAL affected repo:

1. Verify repo exists locally: `[ -d "<workspace_dir>/<repo>" ]`
2. Verify clean working tree: `git -C <workspace_dir>/<repo> status --porcelain`
3. Check current branch:
   - If on `main`: `git -C <workspace_dir>/<repo> pull origin main`
   - **If NOT on `main`**: Ask the user:
     ```
     <repo> is on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
     2. **Switch to main and create new branch** — start fresh
     ```

If any repo has a dirty working tree, STOP. Report which repo and which files are dirty. The user must resolve manually.

### Create Feature Branches

Branch name pattern:
- With JIRA: `feat/<jira_ticket_id>-new-spoke-<spoke-name>` (e.g., `feat/PLAT-123-new-spoke-bg-staging`)
- Without JIRA: `feat/new-spoke-<spoke-name>` (e.g., `feat/new-spoke-bg-staging`)

For each repo that needs a new branch (skip repos where the user chose to keep their existing branch):

```bash
git -C <workspace_dir>/<repo> checkout -b <branch-name>
git -C <workspace_dir>/<repo> branch --show-current   # Verify
```

If a branch with that name already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

### Gate Verification

Before proceeding, confirm all affected repos are on the correct branch. Report status for each repo as `✅ <repo> → <branch>` or `❌ <repo> — reason`. If ANY required repo failed, STOP. Do not generate files.

---

## IAM Trust Chain (IMPORTANT)

> **What it does:** Documents the 3 cross-account IAM trust relationships required:
> (1) Hub ArgoCD → Spoke EKS via IRSA chain, (2) Hub ESO → Spoke Secrets Manager
> via cross-account role, (3) Hub ArgoCD → Spoke EKS auth via aws-auth ConfigMap.
> **Key behavior:** All three trust relationships must exist before the spoke can
> be managed. This is a reference/verification module, not a generation module.
> **Module**: Read [`new-spoke/iam-trust-chain.md`](new-spoke/iam-trust-chain.md) for the three cross-account IAM trust relationships that must exist before the spoke can be managed.

---

## Cross-Repo Workflow

### Phase 1: Infrastructure Prerequisites (iac-terragrunt-core-infra)

**Repository:** `iac-terragrunt-core-infra`
**MUST be completed and applied BEFORE any other repo changes.**

> **WARNING — Network Directory Naming**: The terragrunt network directory name
> may NOT match the spoke name. Existing spokes use abbreviated names:
> `bg-dev` → `dev.network-us-east-1`, `bg-qa` → `qa.network-us-east-1`.
> Hubs use the full name: `ops-qa` → `ops-qa.network-us-east-1`.
> Check the actual directory name under `aws/accounts/<spoke>/us-east-1/`
> before running any `cd` commands. In the steps below, `<network-dir>` refers
> to the actual network directory name (e.g., `dev.network-us-east-1`).

#### Steps

1. **Create spoke account directory** (if new account): `aws/accounts/<spoke>/` with `account.yaml`, `us-east-1/region.yaml`, and `<network-dir>/env.yaml`.

Apply in order (each: `terragrunt plan && terragrunt apply`) under `aws/accounts/<spoke>/us-east-1/<network-dir>/`:

| # | Terragrunt module path | Notes |
|---|----------------------|-------|
| 2 | `.../networking/delegated-zones/<dns-zone>` | |
| 3 | `.../services/<spoke>-eks` | ~15-20 min; capture EKS API URL |
| 4 | `.../services/<spoke>-eks-core-addons` | |
| 5 | `.../services/<spoke>-argocd-spoke-registration` | Set `mode="spoke"`, `hub_irsa_role_arn`, `hub_external_secrets_role_arn` |

6. **UPDATE HUB REGISTRATION** (EASY TO MISS): In `aws/accounts/<hub>/.../<hub>-argocd-hub-registration/terragrunt.hcl`, add spoke account ID to `spoke_account_ids`. Apply.

7. **Capture outputs** for Phase 2:
   - EKS API URL: `aws eks describe-cluster --name <spoke> --query 'cluster.endpoint' --output text`
   - OIDC Provider ID: from `cluster.identity.oidc.issuer`, take last path segment.

#### Validation
```bash
aws eks describe-cluster --name <spoke> --query 'cluster.status'
# Expected: "ACTIVE"

aws iam get-role --role-name argocd-access --profile <spoke-account>
# Expected: role exists with correct trust policy
```

---

### Phase 2: ArgoCD Spoke Registration (iac-eks-argocd)

**Repository:** `iac-eks-argocd`

> **What it does:** Creates ExternalSecret + ClusterSecretStore for spoke credentials
> (copying from an existing spoke and replacing names/accounts/labels), updates hub
> kustomization.yaml, creates spoke environment directory with bootstrap-config.yaml
> and applicationsets kustomization, and updates ArgoCD project destinations.
> **Key behavior:** Copies from existing spoke patterns — never generates from scratch.
> Each ArgoCD project gets ~20 namespace destination entries. Conditional additional
> projects are created based on the spoke's workload profile.
> **Module**: Read [`new-spoke/phase2-argocd-registration.md`](new-spoke/phase2-argocd-registration.md) and execute all steps before continuing.

---

### Phase 3: Addon Overlays (iac-eks-addons)

**Repository:** `iac-eks-addons`

> **What it does:** For each core addon, creates an overlay directory (config.yaml,
> kustomization.yaml, values.yaml, xirsarole-patch.yaml) by copying from an existing
> spoke. ServiceMonitor is disabled initially.
> **Key behavior:** MUST also update the hub external-secrets overlay with the spoke's
> cross-account role ARN — this is the step most commonly missed and causes silent
> failures in secret synchronization.
> **Module**: Read [`new-spoke/phase3-addon-overlays.md`](new-spoke/phase3-addon-overlays.md) and execute all steps before continuing.

---

### Phase 4: Crossplane (iac-eks-crossplane)

**Repository:** `iac-eks-crossplane`

> **What it does:** Creates Terraform environment + ArgoCD overlay for Crossplane by
> copying from an existing spoke. Applies Terraform to get the provider role ARN, then
> wires runtime-configs with the captured ARN.
> **Key behavior:** Terraform must be applied first to get the ARN — the ArgoCD overlay
> cannot be completed without it. Copy-from-existing-spoke pattern.
> **Module**: Read [`new-spoke/phase4-crossplane.md`](new-spoke/phase4-crossplane.md) and execute all steps before continuing.

---

### Phase 4B: Observability Overlays (iac-eks-observability) — CONDITIONAL

> **What it does:** CONDITIONAL — only runs if the spoke references a monitoring
> ApplicationSet. Creates spoke-specific overlays only for components that run ON the
> spoke (promtail, otel-collector, karpenter, kube-prometheus-stack).
> **Key behavior:** Hub-only components are explicitly skipped. Only spoke-side
> observability agents get overlays.
> **Module**: Read [`new-spoke/phase4b-observability.md`](new-spoke/phase4b-observability.md) and execute all steps before continuing.

---

### Phase 5: Monitoring (terraform-stack-monitoring-ng) — CONDITIONAL

> **What it does:** CONDITIONAL and rare — creates `environments/<spoke>/` directory
> in terraform-stack-monitoring-ng.
> **Key behavior:** Only triggered when monitoring_required is true. Most spokes skip
> this phase entirely.
> **Module**: Read [`new-spoke/phase5-monitoring.md`](new-spoke/phase5-monitoring.md) and execute all steps before continuing.

---

### Phase 6: Commit, Push, and PR Creation

> **What it does:** Multi-repo commit/push/PR in strict merge order:
> terragrunt → argocd → addons → crossplane → observability → monitoring.
> Each PR references the predecessor PR URL in its description.
> **Key behavior:** Merge order is critical — PRs must be merged in the specified
> sequence. Includes post-PR feedback scan via change-safety-validation.
> **Module**: Read [`new-spoke/commit-push-pr.md`](new-spoke/commit-push-pr.md) and execute all steps before continuing to Phase 6B.

---

### Phase 6B: Bootstrap

**Repository:** `iac-eks-argocd`

```bash
# Set kubectl context to the hub cluster (NOT the spoke)
aws eks update-kubeconfig --name <hub> --region <region> --profile <hub-account>

# Run bootstrap script for spoke registration
./bootstrap/scripts/install.sh -u <hub> -e <spoke> -r <region>
```

> **What install.sh actually does** (10-step sequence):
> 1. Creates `argocd` namespace
> 2. Adds/updates Argo Helm repo
> 3. Installs or upgrades ArgoCD Helm chart (currently chart v9.1.4)
> 4. Waits for ArgoCD workloads (server, repo-server, app-controller) to be ready
> 5. Creates in-cluster ArgoCD cluster secret with hub/environment/region labels
> 6. Creates `github-app-repo-creds` from AWS Secrets Manager (non-fatal if AWS CLI unavailable)
> 7. Applies `bootstrap-parent-application.yaml`
> 8. Runs app-of-apps deploy helper
> 9. Prints admin credentials/access info
> 10. Runs bootstrap verification checks
>
> **Prerequisites**: `kubectl`, `helm`, cluster connectivity (kubeconfig), AWS CLI (optional but recommended)

This:
1. Syncs spoke environment via existing hub ArgoCD
2. ApplicationSets discover new `bootstrap-config.yaml`
3. Core addons start deploying to spoke cluster

---

### Phase 7: Verification

```bash
# Hub cluster — verify spoke registration
kubectl get secret -n argocd | grep <spoke>
argocd cluster list | grep <spoke>
argocd app list --selector environment=<spoke> -o json | jq '.[].status.sync.status'

# Spoke cluster — verify core addon pods
aws eks update-kubeconfig --name <spoke> --region <region> --profile <spoke-account>
for ns in cilium-system external-secrets-system cert-manager kyverno karpenter crossplane-system; do
  kubectl get pods -n $ns
done
kubectl get ns
```

### Phase 7.5: Universal Change Safety Gate (Pre-PR)

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `iac-terragrunt-core-infra`, `iac-eks-argocd`,
  `iac-eks-addons`, `iac-eks-crossplane`, plus conditional monitoring/observability repos.
- `risk_profile`: `mixed`.
- `validation_commands_by_repo`: phase validation checks, wiring validator,
  and bootstrap/verification checks.
- `rollback_strategy`: merge-order-aware git-native revert/reset per repo.
- Command-specific focus: spoke registration integrity, cross-account trust chain,
  cluster secret wiring, and bootstrap safety.

If Phase A reports any blocker, fix and re-run before final completion claim.

---

## Post-Execution Checklist

Run the wiring validator to verify all cross-repo files were created:

```bash
npx mobius-validate-wiring new-spoke <spoke-name> --hub <hub-name>

# With optional phases:
npx mobius-validate-wiring new-spoke <spoke-name> --hub <hub-name> --monitoring --observability
```

## Anti-Patterns to Avoid

| Pattern | Why Forbidden |
|---------|---------------|
| Registering spoke before hub exists | Hub ArgoCD must be running to manage spoke |
| Forgetting to update hub `spoke_account_ids` | Hub can't assume roles into spoke account |
| Missing ClusterSecretStore | ExternalSecret can't read spoke's Secrets Manager |
| Hardcoding EKS API URL before terragrunt | URL not known until cluster created |
| Enabling ServiceMonitors before monitoring | Prometheus not running → dangling monitors |
| Skipping `project.yaml` destination update | ArgoCD RBAC denies deployments to spoke namespaces |
| Using spoke account ID as hub account ID | Cross-account trust chain breaks |
| Merging `iac-eks-addons` before `iac-eks-argocd` | ApplicationSets must exist to discover config.yaml |
| Creating addon overlays without verifying hub label | Cluster generator won't match spoke to hub |
| Adding cluster files without updating `kustomization.yaml` | Resources won't be included in kustomize build |
| Using `.yml` extension | Convention is `.yaml` in this repository |
| Running `install.sh` from spoke context | Bootstrap must run on HUB cluster, targeting spoke |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which spoke cluster was registered and with which hub
- "What was accomplished" → describe the cluster registration, addon configuration, and monitoring
- "Why it matters" → the new cluster is now a deployment target — services can be deployed to it
- "What happens next" → explain multi-repo merge order, infra provisioning, and verification

**Repo breakdown guidance**: Use `shared/repo-roles.md` for plain-language descriptions of each affected repo.
