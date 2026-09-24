---
name: debug-service
description: Debug a running EKS service (logs, status, dependencies)
argument-hint: <service-name> [--env <environment>] [--hub <hub-name>]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Debug Service

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command performs live-cluster diagnostics across ArgoCD, Kubernetes, and
> dependency controllers (Envoy Gateway, Crossplane, external-dns, cert-manager).
> It must correlate symptoms across multiple systems and recommend targeted fixes.
> Weaker models may miss cross-layer failure chains or suggest fixes in the wrong
> component.

This command provides **automated runtime debugging** for services deployed on
EKS via ArgoCD. It runs all diagnostic checks automatically and presents a
structured report with actionable fix suggestions.

It is the **runtime counterpart** to:
- `/mobius:validate-service` — which catches issues **before merge**
- `/mobius:debug-appset` — which diagnoses **ApplicationSet discovery** failures

Use this command when a service is deployed but not working correctly (pods
crashing, routes not resolving, sync failures, degraded health).

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — sync waves, project RBAC, ApplicationSet discovery
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — trust chain for AccessDenied debugging
> - [Networking](../../docs/architecture/networking.md) — Envoy Gateway, NLB, DNS/ACM for connectivity issues
> - [Crossplane Flow](../../docs/architecture/crossplane-flow.md) — composition pipeline for claim debugging
> - [Environment Model](../../docs/architecture/environment-model.md) — cluster-to-environment mapping for target identification
> - [Karpenter Autoscaling](../../docs/architecture/karpenter-autoscaling.md) — NodePool scheduling patterns for pod-pending diagnosis

---

## Prerequisites

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

Before starting diagnostics, this command ensures:

1. **AWS SSO session** is active for the target environment
2. **kubectl** is pointed at the correct hub cluster
3. **ArgoCD CLI** is installed and authenticated

See: `docs/workflows/argocd/argocd-cli-auth.md` for the full authentication flow.

---

## AWS Read-Only Policy (MANDATORY)

> **All AWS CLI usage in this command is strictly READ-ONLY.**
>
> This command uses `aws` CLI calls to gather diagnostic evidence (IAM role
> trust policies, target group health, Route53 records, Secrets Manager values).
> It **never** creates, modifies, or deletes AWS resources via the CLI.

**How AWS changes are made in this platform:**

| Change type | Change path | Repository |
|-------------|------------|------------|
| IAM roles, VPCs, EKS clusters, core infra | Terragrunt / Terraform | `iac-terragrunt-core-infra`, `terraform-module-core-irsa` |
| IRSA roles, S3 buckets, SQS queues, secrets | Crossplane XRD claims | `iac-eks-crossplane` + individual `crossplane-xrd-*` repos |
| NLB listeners, ACM certificates | Crossplane XRD claims | `crossplane-xrd-gateway-nlb-listener`, `crossplane-xrd-ingress-acm-certificate` |
| Route53 DNS records | external-dns controller | Managed automatically from HTTPRoute/Ingress resources |

**If a fix requires an AWS change**, the diagnostic report tells you **which
IaC file to edit** — never an `aws` CLI write command.

Forbidden `aws` CLI operations (never run these):
- `aws iam create-*`, `aws iam put-*`, `aws iam attach-*`, `aws iam delete-*`
- `aws elbv2 create-*`, `aws elbv2 modify-*`, `aws elbv2 delete-*`
- `aws route53 change-resource-record-sets`
- `aws secretsmanager create-*`, `aws secretsmanager put-*`, `aws secretsmanager update-*`
- Any `aws` command that mutates state

---

## Git Write Policy (MANDATORY)

> **This command is READ-ONLY during diagnosis.** Run `kubectl`, `argocd`, `git log/show/diff`, and `aws` read commands only. Do NOT write files, stage changes, commit, or push during any diagnostic phase.

**No direct commits to `main` or any branch.** If a fix is identified, present it to the user as a proposed change — do not apply it autonomously.

**Fix workflow is required for any file change.** If the user approves applying a fix:

1. Prompt for JIRA ticket (reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt).
2. Create a feature branch in the affected repo: `feat/<jira_ticket_id>-fix-<service-name>` (or `feat/fix-<service-name>` if no ticket).
3. Apply the fix on the branch.
4. Run any applicable validators (e.g., `kustomize build`).
5. Create a PR — never commit directly to `main`.

**The fix routing table below identifies which repo and path to edit — not a license to commit directly.**

---

## Input

| Flag | Purpose | Example |
|------|---------|---------|
| `<service-name>` | Service/addon name to debug | `external-dns`, `api-node-payments` |
| `--env <environment>` | Target environment (optional — discovered if omitted) | `ops-qa`, `bg-prod` |
| `--hub <hub-name>` | ArgoCD hub to connect to (optional — inferred from env) | `ops-qa`, `ops-prod` |

### Input Resolution

| User provides | LLM action |
|---------------|------------|
| Service name only | Run `argocd app list \| grep <service>`, present matches, user picks |
| Service name + `--env` | Construct app name `<service>-<env>`, verify it exists |
| Service name + `--hub` | Login to specified hub, then discover apps matching service |
| Nothing | Ask: "Which service are you debugging?" |

---

## Doc-First Gate (run before Phase 0)

> **Module**: Read [`shared/doc-first-gate.md`](shared/doc-first-gate.md) and execute all steps.

**Target repo**: the application repo for the service being debugged.

When debugging, knowing the intended AWS dependencies (AppConfig, S3, SQS, etc.) is critical — a missing IAM action or absent Crossplane claim is often the root cause of startup failures, permission errors, or crash loops. This gate surfaces those dependencies from docs before inspecting the cluster.

If docs are missing: offer to generate them. Proceed anyway in debug scenarios — don't block live incident investigation.

---

## Phase 0 — Prerequisites & Authentication

**Goal:** Ensure the LLM has cluster access before running any diagnostics.

### Step 0.1: AWS SSO Login

```
Ask the user:
  "Which AWS profile should I use? (e.g., bg-qa, bg-prod, ops-qa)"
  
  If the user is unsure, list available profiles:
    aws configure list-profiles

  Then login:
    aws sso login --profile <profile>
```

If SSO session is already active (`aws sts get-caller-identity --profile <profile>` succeeds), skip this step and inform the user.

### Step 0.2: kubectl Context

```bash
# Verify current context
kubectl config current-context

# If wrong context, update:
aws eks update-kubeconfig --name <cluster-name> --region us-east-1 --profile <profile>
```

### Step 0.3: ArgoCD CLI Check

```bash
# Check if argocd CLI is installed
which argocd
```

If not installed, ask:
> "ArgoCD CLI is not installed. Can I install it with `brew install argocd`?"

### Step 0.4: ArgoCD Authentication

Follow the flow in `docs/workflows/argocd/argocd-cli-auth.md`:

```bash
# Determine hub from environment
# ops-qa, bg-dev → argo.qa.ops.bgrp.io
# ops-prod, bg-qa, bg-prod → argo.prod.ops.bgrp.io

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

argocd login <hub-url> --username admin --password "$ARGOCD_PASSWORD"
```

### Hub Resolution

> See the full environment→hub mapping in
> [`docs/workflows/argocd/argocd-cli-auth.md`](../../docs/workflows/argocd/argocd-cli-auth.md#hub-resolution).

**Key rule:** `bg-qa` and `bg-prod` are managed by **`ops-prod`**, not `ops-qa`.
When in doubt, check `iac-eks-argocd/hubs/*/environments/` to discover the mapping.

---

## Phase 1 — Service Discovery

**Goal:** Identify the ArgoCD Application and its target namespace.

### Step 1.1: Find matching applications

```bash
argocd app list -o json | jq -r '.[] | select(.metadata.name | test("<service>")) | 
  "\(.metadata.name)\t\(.status.sync.status)\t\(.status.health.status)\t\(.spec.destination.namespace)"'
```

Present results:

```
Found 2 applications matching "external-dns":

  1. external-dns-ops-qa      Synced    Healthy    external-dns
  2. external-dns-ops-prod    Synced    Degraded   external-dns

Which application to debug? (or press enter for #2 — Degraded)
```

The LLM should auto-select the unhealthy one if there is exactly one degraded/failed app. If all are healthy, ask the user which to investigate.

### Step 1.2: Extract application metadata

```bash
argocd app get <app-name> -o json | jq '{
  name: .metadata.name,
  namespace: .spec.destination.namespace,
  server: .spec.destination.server,
  project: .spec.project,
  syncStatus: .status.sync.status,
  healthStatus: .status.health.status,
  repoURL: .spec.source.repoURL,
  path: .spec.source.path,
  targetRevision: .spec.source.targetRevision
}'
```

Store these values — they drive all subsequent phases.

---

## Phase 2 — ArgoCD Layer Diagnosis

**Goal:** Determine if the issue is at the ArgoCD sync/management layer.

> **What it does:** Checks ArgoCD sync status/history, health status per-resource, app
> events, and controller logs. Performs **cross-repo ApplicationSet path tracing**
> (config.yaml → ApplicationSet → Project → Application chain with mismatch matrix),
> CRD validation (Established condition, missing CRDs, webhook CA issues), and stuck
> Application deletion detection.
> **Key behavior:** The ApplicationSet path tracing is the most valuable diagnostic —
> it traces the full config.yaml → ApplicationSet → Project → Application chain and
> builds a mismatch matrix showing where the wiring breaks.
> **Module**: Read [`debug-service/phase2-argocd.md`](debug-service/phase2-argocd.md) and execute all steps before continuing.

If ArgoCD layer is healthy but service is degraded → proceed to Phase 3.

---

## Phase 3 — Kubernetes Layer Diagnosis

**Goal:** Investigate pod-level and workload-level issues on the target cluster.

> **What it does:** Inspects pod status/logs/events/describe, service/endpoint health,
> HTTPRoute/Ingress status, and namespace events. Includes **stuck & terminating
> resource scan** (finalizer detection with owner/fix-path table) and **namespace
> stuck terminating** detection.
> **Key behavior:** Finalizer detection is critical — stuck resources with finalizers
> are a common cause of namespace termination failures, especially in preview
> environments. The owner/fix-path table maps each finalizer to its controller.
> **Module**: Read [`debug-service/phase3-kubernetes.md`](debug-service/phase3-kubernetes.md) and execute all steps before continuing.

---

## Phase 4 — Dependency Diagnosis (Inferred)

**Goal:** Check controllers that the service depends on, inferred from its actual state.

> **What it does:** Infers service dependencies from ArgoCD resource tree and running
> resources. Checks Envoy Gateway, Crossplane (claims, managed resources stuck with
> finalizers, stale ARN refs, provider package conflicts, TLS/webhook failures, orphaned
> functions, ProviderConfig stuck), External DNS, and cert-manager (full
> Certificate → CertificateRequest → Order → Challenge chain).
> **Key behavior:** Dependencies are INFERRED, not declared — the module discovers
> what the service actually depends on from its runtime state, not from config files.
> **Module**: Read [`debug-service/phase4-dependencies.md`](debug-service/phase4-dependencies.md) and execute all steps before continuing.

---

## Phase 4b — AWS Layer Diagnosis (Read-Only)

**Goal:** Verify AWS-side resources that back the Kubernetes workload.
**Constraint:** ALL commands in this phase are **read-only**. See AWS Read-Only
Policy above.

> **What it does:** READ-ONLY AWS checks triggered by signals from earlier phases.
> Covers IAM/IRSA trust verification, NLB/target group health, Route53 record
> verification, Secrets Manager access, and S3 access.
> **Key behavior:** Every finding includes an IaC fix path (which repo/file to edit),
> never raw AWS CLI write commands. All commands are strictly read-only.
> **Module**: Read [`debug-service/phase4b-aws.md`](debug-service/phase4b-aws.md) and execute all steps before continuing.

---

## Phase 5 — Diagnostic Report & Remediation Plan

**Goal:** Present findings, separate temporary remediation from permanent IaC
fixes, build a cross-repo change plan, and offer to implement it.

### 5A: Findings Report

Output a structured report with a header block (`DEBUG REPORT: <service-name> / Environment: <env> / Time: <timestamp>`), then one section per phase (`PHASE 2: ArgoCD Layer`, `PHASE 3: Kubernetes Layer`, `PHASE 4: Dependencies`, `PHASE 4b: AWS Layer`). Each check shows a severity tag: `[PASS]`, `[WARN]`, `[FAIL]`, or `[SKIP]` with a brief message. `[FAIL]` findings include a `→` sub-line with the specific error detail.

### Severity levels

| Level | Meaning |
|-------|---------|
| `[PASS]` | Check passed — no issues found |
| `[WARN]` | Non-critical issue or anomaly worth investigating |
| `[FAIL]` | Issue found that likely contributes to the problem |
| `[SKIP]` | Check not applicable (dependency not present) |

### 5B: Root Cause Hypothesis

Synthesize all findings into a coherent explanation. Connect the dots across
layers — don't just list problems, explain the **failure chain**:

```
═══ ROOT CAUSE HYPOTHESIS ═══

The XIRSARole Crossplane claim references the wrong OIDC provider
(ops-qa instead of bg-prod). This caused the IAM role trust policy
to reject the pod's service account token. Without valid AWS
credentials, the ExternalSecret operator can't retrieve DATABASE_URL
from Secrets Manager, causing the container to crash on startup.

Failure chain:
  Wrong OIDC in XIRSARole claim
    → IAM trust policy mismatch
      → Pod gets AccessDenied on STS AssumeRoleWithWebIdentity
        → ExternalSecret can't sync (stale since 4h)
          → DATABASE_URL missing from pod env
            → Container exits with code 1 (CrashLoopBackOff)
```

### 5C: Temporary Remediation (unblock now)

These are `kubectl` / `argocd` commands that **unblock the immediate problem**
but do NOT constitute a permanent fix. They may be reverted on next sync or
redeployment.

> **Temporary fixes are for emergencies only.** They buy time while the
> permanent IaC fix is prepared and merged.

```
═══ TEMPORARY REMEDIATION (if needed to unblock) ═══

1. Force-refresh the ExternalSecret to re-sync from Secrets Manager:
   kubectl annotate externalsecret -n <ns> <secret-name> \
     force-sync=$(date +%s) --overwrite

2. Restart the deployment to pick up new secret values:
   kubectl rollout restart deployment -n <ns> <deployment-name>

3. If Crossplane managed resource is stuck, unblock with:
   bash <workspace_dir>/iac-eks-crossplane/scripts/crossplane-debug-claim.sh xirsarole <name>

⚠️  These are TEMPORARY. The root cause requires IaC changes below.
```

### 5D: Permanent Fix Plan (IaC changes)

This is the critical section. **Every permanent fix is a code change in a
repo.** No manual `kubectl` or `aws` commands are permanent fixes.

The LLM builds a cross-repo change plan listing every file that needs to
change, in which repo, with a description of what to change:

Output a fix plan grouped by repo showing: change number, file path, what to change, and why it matters. Include merge order and post-merge validation commands (`/mobius:validate-service`, `argocd app sync`, `argocd app get`).

### 5E: Offer to Implement

After presenting the plan, ask the user:

> "I've mapped all the changes needed across repos. Want me to implement
> this plan? I'll:
> 1. Create a feature branch in each affected repo
> 2. Make the changes listed above
> 3. Run `/mobius:validate-service` to verify
> 4. Show you the diffs for review before committing
>
> Or would you prefer to make these changes yourself?"

If the user says yes:
1. Create branches in affected repos
2. Make the file edits
3. Run validation (kustomize build, validate-service.sh)
4. Show diffs and ask for confirmation
5. Commit with conventional commit messages
6. Offer to push and create PRs

### 5F: Post-Fix Validation

After changes are applied (whether by the LLM or the user), always validate:

```bash
# 1. Validate service completeness
npx mobius-validate-service <service> \
  --service-repo <path>

# 2. Force ArgoCD sync to apply changes
argocd app sync <app-name>

# 3. Wait for health convergence
argocd app wait <app-name> --health --timeout 120

# 4. Re-run debug-service to confirm all checks pass
# (The LLM runs Phases 2-4 again as a verification sweep)

# 5. Verify pods are running
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<service>
```

If validation fails after the fix, the LLM reports what's still broken and
iterates on the plan. Do not claim success until all checks pass.

### Change path reference

Every finding's fix MUST point to the correct IaC path. Never suggest a
manual `aws` or `kubectl` write command as a permanent fix.

| Problem domain | Fix repo | Fix path |
|---------------|----------|----------|
| Service config (values, overlays, config.yaml) | Service repo (`helm-charts`, `iac-eks-addons`, `iac-eks-observability`) | `argocd/<service>/overlays/<env>/` |
| ApplicationSet wiring | `iac-eks-argocd` | `applicationsets/<group>/<appset>.yaml` |
| ArgoCD project permissions | `iac-eks-argocd` | `projects/<team>/<project>/project.yaml` |
| IRSA roles (via Crossplane) | Service repo | `argocd/<service>/overlays/<env>/xirsarole-patch.yaml` or `base/xirsarole.yaml` |
| IRSA roles (via Terraform) | `terraform-module-core-irsa` | Module variables and role definitions |
| S3 buckets, SQS, secrets (Crossplane) | Service repo or `iac-eks-crossplane` | XRD claim YAML in service overlays |
| NLB listeners (Crossplane) | Service repo | `XGatewayNLBListener` claim in overlays |
| Core infra (VPCs, EKS, accounts) | `iac-terragrunt-core-infra` | Terragrunt modules |
| DNS records | Automatic (external-dns) | Fix HTTPRoute hostname in service values.yaml |
| TLS certificates | Automatic (cert-manager) | Fix Certificate resource or ClusterIssuer config |
| Crossplane providers/functions | `iac-eks-crossplane` | Provider/Function/Configuration CRs |
| Monitoring/alerting | `iac-eks-observability` | Observability stack overlays |

---

## Reference Tables

> **What it does:** Provides Crossplane script reference table (6 scripts with exact
> commands) and controller namespace quick reference (8 controllers with log commands).
> **Key behavior:** Purely reference data — no execution steps. Used for quick lookup
> during diagnosis.
> **Module**: Read [`debug-service/reference-tables.md`](debug-service/reference-tables.md) for Crossplane script reference and controller namespace quick reference.

---

## Examples

### Debug a specific service

```
/mobius:debug-service external-dns --env ops-qa
```

### Debug a service (auto-discover environment)

```
/mobius:debug-service api-node-payments
```

The LLM finds all ArgoCD apps matching `api-node-payments`, shows their status,
and auto-selects the unhealthy one (or asks if all are healthy).

### Debug with explicit hub

```
/mobius:debug-service cert-manager --hub ops-prod
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:debug-appset` | Diagnoses ApplicationSet **discovery** failures; debug-service diagnoses **runtime** failures after discovery succeeds |
| `/mobius:validate-service` | Validates service completeness **before merge**; debug-service investigates **after deployment** |
| `/mobius:add-service` | Generates service files; debug-service debugs the deployed result |
| `/mobius:migrate-ecs-service` | Migrates ECS services; debug-service catches post-migration runtime issues |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: diagnostic

**Context hints**:
- "Impact opener" → state the root cause found and how many cascading failures
- "What was accomplished" → describe the diagnosis — what's broken, the failure chain, and the fix
- "Why it matters" → describe the user/business impact of the outage and which environments are affected
- "What happens next" → explain the fix, merge order, and expected recovery time

**Repo breakdown guidance**:
- Identify which repo contains the root cause and which repos need fixes
- Explain the failure chain using → arrows
- Note which environments are affected and which are healthy
