---
name: add-service
description: Create a new service deployment on EKS
argument-hint: <service-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Add a Service to EKS

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command manages intake verification gates, ApplicationSet generator
> alignment, and version-lock enforcement across 2-3 repositories. Weaker models
> may cause ApplicationSet repoURL/path mismatches leading to silent discovery
> failures. If using Codex CLI, prefer `codex exec --model o3`.

This command orchestrates the full `/mobius:add-service` flow end-to-end in six phases.
The engineer provides the service name, answers a short intake, reviews recommendations,
and the LLM handles research, generation, and validation automatically.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — ApplicationSet discovery, project RBAC, sync waves
> - [Environment Model](../../docs/architecture/environment-model.md) — overlay structure, cluster-to-environment mapping
> - [Crossplane Flow](../../docs/architecture/crossplane-flow.md) — XIRSARole claims and available XRDs
> - [Networking](../../docs/architecture/networking.md) — Envoy Gateway HTTPRoute and NLB listener setup
> - [Karpenter Autoscaling](../../docs/architecture/karpenter-autoscaling.md) — NodePool scheduling patterns for operational profile selection

Detailed implementation reference:
`docs/workflows/services/add-service.md`

Audit artifact template:
`docs/workflows/services/add-service-intake.yaml`

Shell scripts still exist for manual operations, but they are optional in this command flow.

---

## Canonical Rules

- No file generation before Phase 3 recommendations are confirmed.
- No completion claim before Phase 5 validations pass.
- ApplicationSet generator `repoURL` and overlay `config.yaml` location must match.
- Helm chart and image versions must be pinned (never `latest`).
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before Phase 1 intake begins.
- JIRA ticket is prompted before intake questions — strongly encouraged for add-service but skippable.
- No file generation on `main` — a feature branch MUST exist in all affected repos before Phase 4.
- Work is not complete until a PR exists for every affected repo.
- Merge order: `iac-eks-argocd` PR merged first, service repo PR merged second.
- IRSA is **always** provisioned via Crossplane `XIRSARole`, regardless of which AWS-resource mode is chosen (see Phase 1 Q4) — this never changes.
- The AWS-resource mode (`crossplane` vs `terraform`) is a **whole-stack choice made once at intake** — never mix XRD claims and raw Terraform for the same service's non-IRSA resources.
- When generating Terraform (mode `terraform`), always check the `terraform-modules-aws` private registry catalog for an existing module before writing a raw `resource` block for that AWS resource type. Only write raw resources when no module exists for that type.

---

## Workspace Resolution (MANDATORY — before everything)

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` before anything else.

Every other boatsgroup repo this command touches (`iac-eks-argocd`, the service repo when it's not the current directory, `terraform-modules-aws`, the Terraform worktree) is referenced as `<workspace_dir>/<repo>` — never a bare `../<repo>`. `workspace_dir` defaults to the parent of the current directory (identical to the old sibling behavior) but is confirmed with the user once and honors `MOBIUS_WORKSPACE`, so engineers who don't already have every platform repo cloned get them cloned into a location they chose (see the Preflight in `docs/workflows/shared/multi-repo-git-workflow.md` § Step P2, which now clones missing repos instead of hard-stopping).

---

## Service Origin (MANDATORY — before Doc-First Gate)

Ask this before anything else except Workspace Resolution above, and before Git Prerequisites:

```
Is this a brand-new service repo, or does it already exist?

1. **Existing repo** — I already have this repo (either the current directory, or cloned under workspace_dir)
2. **Brand-new repo** — this service doesn't exist yet, create it from scratch
```

**If existing repo**, ask next:

```
Has this service ever been deployed — to ECS, EKS, or anywhere else?

1. **No, never deployed** — this repo exists but nothing has gone live yet
2. **Yes, it's live somewhere** — describe where (ECS, EKS, other)
```

Set `service_ever_deployed` (`true`/`false`) from the answer. This gates two things for the rest of the flow:

- **If `false`: skip all live-infrastructure verification.** Do not run `aws`/`kubectl`/`ecs describe`/etc. against real infrastructure to "check" this service — there is nothing live to check, and doing so wastes time and can produce misleading "not found" noise that looks like a problem.
- **If `false` AND the repo contains ECS Terraform (e.g. `iac/ecs.tf`, an `iac/` directory matching `api-node-template`'s ECS scaffold)**: this is **unused template boilerplate, not evidence of a prior or intended ECS deployment.** This commonly happens when someone runs `api-node-template`'s `scripts/setup.sh` by hand outside of this command, without stripping the ECS pieces (that stripping normally happens in `add-service/template-scaffold.md` Step S4, which only runs when this command itself does the scaffolding). **Record that this leftover ECS boilerplate must be stripped, but do NOT `rm` it now** — a deletion here would dirty the working tree before Step 0a's clean-tree check (which would then hard-stop) and before any feature branch exists (no commits allowed on `main`). Do the strip during Phase 4 generation, on the feature branch created in Phase 3.5, and commit it as part of the service-repo commit. Also: don't preserve its resource declarations as "existing dependencies to carry forward," and — critically — **do not infer an existing ECS deployment from its presence and do not route to `/mobius:migrate-ecs-service`.** That command is for services genuinely running on ECS today; unexercised template boilerplate for a never-deployed service is not that, regardless of how much AWS-resource detail the boilerplate contains.
- **If `true`**: this is out of scope for a first-time `add-service` onboarding — this service already has a deployment story somewhere. Ask the user whether they actually want `/mobius:add-service` (fresh EKS onboarding) or `/mobius:migrate-ecs-service` (if it's on ECS today and the goal is moving it to EKS). Don't assume; the answer changes which command should even be running.

Then proceed as today — Git Prerequisites (Step 0a below) runs against the current working directory, and Phase 1 Q1 resolves the service repo path normally.

**If brand-new repo**: ask next —

```
Scaffold this service from `api-node-template`? (Recommended)

1. **Yes** — clone api-node-template, run its setup script for app code, then continue
2. **No** — create an empty repo and let Phase 4 generate only the ArgoCD/Terraform wiring
```

> **Module**: Read [`add-service/template-scaffold.md`](add-service/template-scaffold.md) and execute all steps (whether the user picked "Yes" or "No" — the module handles both: template clone + setup vs. plain empty-repo creation). This module creates the sibling directory, initializes and pushes the GitHub repo, and sets `service_repo_path` for the rest of the flow.

After this module completes, `service_repo_path` is already resolved — **skip Phase 1 Q1** (it would otherwise ask again). **Skip the Doc-First Gate below** for a freshly-created repo — there are no pre-existing docs to mine for AWS dependencies (a brand-new template-scaffolded repo's own docs are boilerplate, not dependency declarations).

A freshly-scaffolded repo also has **no real code to scan**, so the Phase 2 code-import scan will find nothing. Run the dependency-intake module now to gather the service's intended dependencies and derive its AWS footprint from them:

> **Module**: Read [`add-service/dependency-intake.md`](add-service/dependency-intake.md) and execute all steps. It asks what the service will depend on (boatsgroup libs/repos, external modules, other boatsgroup services), resolves the AWS footprint of named boatsgroup libs (eshu MCP preferred, clone+scan fallback), and produces a confirmed AWS-resource + IAM-action list.

Because dependency-intake already produced that confirmed AWS-resource + IAM list, **also skip Phase 1 Q4a** (the "list the AWS resources" question) for this path — asking it again would be a third pass over the same question that can diverge from what the user just confirmed. Still ask **Q4b** (the crossplane-vs-terraform mode) if it wasn't already settled. Phase 2's AWS Resource Detection step 6 consumes the dependency-intake list as its seed rather than re-confirming from scratch.

---

## Doc-First Gate (MANDATORY — before Phase 1, skip for brand-new repos)

> **Module**: Read [`shared/doc-first-gate.md`](shared/doc-first-gate.md) and execute all steps.

**Target repo**: the application repo being onboarded (where the service code lives).

This gate reads the repo's docs to determine which AWS resources the service actually uses — S3, SQS, AppConfig, Secrets Manager, etc. — before you decide which XRD claims to generate. The XRD Routing decision below **must be informed by the doc-first gate output**, not guessed from the service name.

Do not begin Phase 1 intake until this gate completes.

---

## XRD Routing (Before Generation)

Applies only when Phase 1 Q4 resolves to `crossplane` mode (or `irsa-only`, for the IRSA claim itself — IRSA always routes through `XIRSARole` regardless of mode). When Q4 resolves to `terraform`, skip this gate entirely for non-IRSA resources — those are generated as Terraform instead (see `add-service/terraform-generation.md`).

Use this decision gate whenever AWS resources require Crossplane claims:

- If service requires only IAM role integration and existing `XIRSARole` is sufficient, continue `/mobius:add-service`.
- If service requires existing XRD claims and matching XRDs already exist, continue `/mobius:add-service`.
- If service requires a new XRD type that does not exist, stop and run `/mobius:new-xrd` first.
- If `xrd_claims` are needed and `xrd_exists=false`, stop generation and route to `/mobius:new-xrd`.

### Existing XRD Inventory

- `XIRSARole` (`crossplane-xrd-irsa-role`)
- `XKarpenterNodeRole` (`crossplane-xrd-karpenter-node-role`)
- `XS3Bucket` (`crossplane-xrd-s3-bucket`)
- `XSQSEventBridge` (`crossplane-xrd-sqs-eventbridge`)
- `XGatewayNLBListener` (`crossplane-xrd-gateway-nlb-listener`)
- `XGeneratedAWSSecret` (`crossplane-xrd-generated-aws-secret`)
- `XIngressACMCertificate` (`crossplane-xrd-ingress-acm-certificate`)

---

## Phase 1 - Gather Basics

The LLM asks these questions interactively with defaults, then confirms a normalized intake.
Questions must stay simple and bounded. The LLM MUST validate every user-provided
input — never trust chart URLs, versions, or names without verification.

### Git and JIRA Preflight (before intake questions)

Before asking intake questions, verify git prerequisites and prompt for JIRA.

#### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

**Which directory to check depends on the Service Origin path:**
- **Existing repo** (service repo not yet resolved): check the CURRENT working
  directory — Phase 1 Q1 resolves `service_repo_path` from it.
- **Brand-new repo** (`service_repo_path` already set by
  `add-service/template-scaffold.md`): the current working directory is
  usually **not** the new service repo — it's whatever repo the engineer ran
  the command from. Run these checks against `<service_repo_path>` (via
  `git -C <service_repo_path> ...`), not cwd. template-scaffold already created
  it on a clean `main`, so this normally passes trivially — but the branch
  decision below MUST be about `service_repo_path`, never cwd.

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree of the target repo is clean: `git -C <target> status --porcelain`
   returns empty (`<target>` = cwd for existing, `service_repo_path` for
   brand-new). If dirty, hard-stop — user must resolve manually.
3. Check the target repo's current branch (`git -C <target> branch --show-current`):
   - If on `main`: pull latest (`git -C <target> pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user before doing anything:
     ```
     <target-repo> is currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
        (recommended if you created it for this work)
     2. **Switch to main and create new branch** — start fresh from main
     ```
     If user chooses "use this branch", skip branch creation for the service repo in Phase 3.5.

> Note: Remaining affected repos (e.g., `iac-eks-argocd`) are preflighted in Phase 3.5 after we know which repos are involved.

#### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Prompt the user. JIRA is strongly encouraged for add-service:

```
Before we begin, is there a Jira ticket for this service deployment?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-123)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use service name only)
```

Store as `jira_ticket_id` (e.g., `PLAT-123` or `null`). This value flows into:
- Branch name in Phase 3.5
- Commit message footer in Phase 6
- PR title and body in Phase 6

1. Service repo?

   **Skip this question if `service_repo_path` was already set by the Service Origin step** (brand-new repo, already created via `add-service/template-scaffold.md`). Otherwise:

   **Determine default first**: If the current working directory is already a service repo (has `argocd/` directory), default to that repo — do not assume `iac-eks-addons`. Confirm with the user.

   Options if not in a service repo:
   - `iac-eks-addons` — **devops/platform team only** (external-secrets, cert-manager, cluster-wide addons)
   - `iac-eks-observability` — **devops/platform team only** (Prometheus, Grafana, Loki, monitoring stack)
   - `helm-charts` — shared charts
   - custom repo path/URL — for application team service repos (e.g., `lib-node-localization`, `lib-node-payments`)

   Do not default to any devops-owned repo for application teams.

2. Helm chart source? (see Helm Chart Resolution below for validation rules)
   - The user may provide any combination of: chart name, repo URL, version
   - Whatever is missing, the LLM resolves it
   - Whatever is provided, the LLM validates it

3. Target environments?
   - `bg-qa,bg-prod` (Recommended)
   - `ops-qa,ops-prod`
   - all four
   - custom list

4. AWS resources needed? Two separate sub-questions — **don't collapse them
   into one mode pick**. What the service needs is a different question from
   how it gets provisioned.

   **4a. List the AWS resources this service actually needs** — not a mode,
   an open list (e.g. "S3 bucket for uploads, SQS queue for job
   processing", or "none"). This is a best-guess answer like every other
   Phase 1 field, refined by TWO independent sources afterward — the
   Doc-First Gate's doc-mining (already ran before Phase 1, for existing
   repos) and Phase 2's code-level AWS SDK import scan
   (`add-service/research-phase.md` § AWS Resource Detection). **Both
   sources feed the same confirmation, not two separate ones** — don't ask
   the user to reconcile docs-vs-code findings across two disconnected
   prompts. If the Doc-First Gate already surfaced AWS dependencies for
   this repo, carry that list into this question as part of the seed, and
   let Phase 2's code scan add to/confirm it in one pass. Always end with
   explicit user confirmation before any of this is treated as final (never
   silently trusted — see `research-phase.md`).

   **For each resource, also pin down the specific IAM actions needed, not
   just the resource type.** Knowing "this service uses S3" doesn't tell
   you whether it needs `s3:GetObject` only or also `PutObject`/
   `DeleteObject`/`ListBucket` — that distinction matters for both the
   `XIRSARole` policy (crossplane path) and the IAM policy on the
   Terraform-managed resource (terraform path). Infer from actual call
   sites when the code makes it obvious (e.g. `s3.getObject(...)` only appears
   → read-only); when it doesn't (generic wrapper libraries, dynamically
   selected actions, no clear call sites, or the resource came from the
   user's own list rather than code) — **ask the user directly which
   actions are needed. Do not guess a permissive policy to fill the gap.**

   **4b. Given that resource list, whole-stack: Crossplane or Terraform?**
   IRSA is separate from this choice and always provisioned via
   `XIRSARole` whenever any AWS access is needed at all (i.e. in every mode
   below except `none`):
   - `none` — no AWS resources, no IRSA
   - `irsa-only` — IRSA via `XIRSARole` only, no other resources (4a came back empty but the service still needs some baseline AWS access)
   - `crossplane` — other resources from 4a via Crossplane XRD claims (existing XRD Routing rules apply)
   - `terraform` — other resources from 4a generated as raw Terraform in `terraform/` (see `add-service/terraform-generation.md`)
   - `research it` (Recommended if unsure)

   This is a whole-stack choice for the non-IRSA resources from 4a — not
   per-resource.

5. ArgoCD project?
   - `core-infrastructure` (Recommended)
   - `monitoring`
   - custom project

6. Namespace?
   - inferred from addon name (Recommended)
   - override with explicit namespace

Output of Phase 1 is a complete baseline intake record used by research and generation.

### Helm Chart Resolution (MANDATORY)

> **What it does:** Resolves and validates the Helm chart regardless of how much
> information the user provided. Handles 5 input scenarios: name only (full
> discovery), name+URL (validate), name+URL+version (validate all), URL+version
> (search repo), nothing (full discovery). Presents results with version options.
> **Key behavior:** Never skips validation — even when all three fields are provided,
> each is independently verified against the actual Helm repository. Failure handling
> covers unreachable repos, missing charts, and missing versions.
> **Module**: Read [`add-service/helm-chart-resolution.md`](add-service/helm-chart-resolution.md) and execute the discovery/validation flow before continuing to Phase 2.

---

## Phase 2 - Research (Automatic)

After Phase 1, the LLM performs all research automatically. Engineers do not run
these commands manually. The chart URL, name, and version are already validated
from the Helm Chart Resolution step in Phase 1.

> **What it does:** Deep Helm chart inspection (CRDs, hooks, probes, ServiceAccount,
> HPA, resources) and ecosystem pattern research (cross-reference existing addons,
> Karpenter compatibility, ApplicationSet reuse). Includes **affinity and scheduling
> research** — affinity key discovery, label selector discovery, multi-component
> detection, deployment strategy, graceful shutdown, PDB detection.
> **Key behavior:** All findings are recorded in the intake YAML — this phase produces
> evidence-backed recommendations, not final decisions. The engineer reviews in Phase 3.
> **Module**: Read [`add-service/research-phase.md`](add-service/research-phase.md) and execute all research steps before continuing to Phase 3.

**Phase 2A and 2B run in parallel** — they are independent and can execute concurrently:

| Sub-phase | Work |
|-----------|------|
| **2A** | Helm chart deep inspection (CRDs, hooks, probes, ServiceAccount, HPA, resources, scheduling) |
| **2B** | Ecosystem pattern research (existing addons in service repo, NodePool compatibility, ApplicationSet reuse) |

Join gate: both must complete before Phase 3 recommendations are presented.

Output of Phase 2 is evidence-backed recommendations for Phase 3.

---

## Phase 3 - Present Recommendations

The LLM presents recommendations in the exact format below, with explicit `(Recommended)` markers.
Engineer responds with either `looks good` or field-level overrides.

### CHART CHARACTERISTICS

| Field | Options | Selection |
|---|---|---|
| Helm repo URL | `<value>`, `<alt>` | `<value> (Recommended)` |
| Helm chart | `<value>`, `<alt>` | `<value> (Recommended)` |
| Helm version | `<value>`, `<alt>` | `<value> (Recommended)` |
| CRDs | `required`, `not-required` | `<value> (Recommended)` |
| Hooks | `present`, `absent` | `<value> (Recommended)` |

### AWS RESOURCES

Resources first, mode second — the table mirrors Q4a/Q4b's ordering:

| Field | Options | Selection |
|---|---|---|
| Declared dependencies (brand-new scaffold only) | `<boatsgroup libs / external modules / services>` or `none` | `<value> (Recommended)` |
| Dependency roles (per characterized boatsgroup lib) | `<lib> <aws_service>: <axis>=<chosen role>` per axis, e.g. `lib-message-bus sqs: producer-consumer=consumer` (a lib can span several AWS services and carry more than one axis; list each per service). Only rows for AWS services **still in the confirmed resource list** count — if the engineer removed a service's resource, drop its dependency-role/`NEEDS USER INPUT` row too (it must not block). An axis the engineer couldn't answer for a *confirmed* service shows `<axis>=NEEDS USER INPUT` and blocks `looks good`. | `<value> (Recommended)` |
| AWS resources needed (Q4a) | `<list>` or `none` | `<value> (Recommended)` |
| IAM actions per resource | `<action list>` per resource, or `NEEDS USER INPUT` if inference was inconclusive — for a lib-derived resource, these come from the confirmed dependency role above | `<value> (Recommended)` |
| Resource mode (Q4b) | `none`, `irsa-only`, `crossplane`, `terraform` | `<value> (Recommended)` |
| IRSA required | `yes`, `no` | `<value> (Recommended)` |
| XRD claims (mode `crossplane` only) | `<list>` or `none` | `<value> (Recommended)` |
| XRD exists (mode `crossplane` only) | `true`, `false` | `<value> (Recommended)` |
| Terraform resources (mode `terraform` only) | `<list>` or `none` | `<value> (Recommended)` |
| Terraform module per resource (mode `terraform` only) | `<terraform-modules-aws module>` or `raw resource (no module exists)` | `<value> (Recommended)` |

**Never present `NEEDS USER INPUT` as if it were resolved** — if any
resource **still in the confirmed list** has an IAM actions row that says
that going into Phase 3, stop and ask the user for those actions before
presenting `looks good` as an option. A recommendation with an unresolved
IAM-action gap isn't ready to confirm. The gate is scoped to confirmed
resources: a `NEEDS USER INPUT` on a service the engineer **removed** during
confirm/edit does not block — dropping the resource drops its gate (and its
`unresolved` entry), so rejecting an unused opaque lib service can't deadlock
confirmation or force invented IAM.

### NAMESPACE

| Field | Options | Selection |
|---|---|---|
| Namespace source | `inferred`, `override` | `<value> (Recommended)` |
| Namespace value | `<name>` | `<name> (Recommended)` |

### OPERATIONAL PROFILE

| Field | Options | Selection |
|---|---|---|
| Addon class | `critical-infrastructure`, `workload-supporting`, `daemonset` | `<value> (Recommended)` |
| Node scheduling profile | `<pattern options>` | `<value> (Recommended)` |
| Replicas/HA profile | `<pattern options>` | `<value> (Recommended)` |
| Anti-affinity profile | `none`, `soft-hostname`, `hard-hostname`, `chart-default` | `<value> (Recommended)` |
| PDB profile | `none`, `maxUnavailable: 1`, `minAvailable: N-1` | `<value> (Recommended)` |
| Deployment strategy | `RollingUpdate`, `Recreate`, `chart-default` | `<value> (Recommended)` |
| Probe profile | `<pattern options>` | `<value> (Recommended)` |
| Autoscaling profile | `<pattern options>` | `<value> (Recommended)` |

### VERIFICATION GATES

| Gate | Status |
|---|---|
| chart_version_verified | `✅` |
| values_schema_verified | `✅` |
| crd_detection_completed | `✅` |
| hook_detection_completed | `✅` |
| appset_alignment_checked | `✅` |
| project_permission_plan_ready | `✅` |

After `looks good` confirmation, write the intake audit artifact to:
`/tmp/<addon>-intake.yaml`
using `docs/workflows/services/add-service-intake.yaml`.

---

## Phase 3.5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This phase MUST succeed before Phase 4 begins. If any step fails, STOP.**

### Determine Affected Repos

By this point, the intake is complete and we know which repos are involved:

| Repo | Always affected? | Condition |
|------|-----------------|-----------|
| Service repo (from Phase 1 Q1) | Yes | Base, overlays, config.yaml |
| `iac-eks-argocd` | Usually | New ApplicationSet or project permission updates |

### Preflight Remaining Repos

The service repo was preflighted in Phase 1 Step 0a. For each ADDITIONAL affected repo (e.g., `iac-eks-argocd`), run the shared Preflight (`docs/workflows/shared/multi-repo-git-workflow.md` § Step P2), which locates the repo under `workspace_dir` and **clones it if missing** rather than hard-stopping:

1. Locate or clone: `[ -d "<workspace_dir>/iac-eks-argocd" ]` — if absent, `gh repo view boatsgroup/iac-eks-argocd` then clone into `workspace_dir` (see Step P2).
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
- With JIRA: `feat/<jira_ticket_id>-add-<service-name>` (e.g., `feat/PLAT-123-add-cert-manager`)
- Without JIRA: `feat/add-<service-name>` (e.g., `feat/add-cert-manager`)

For each repo that needs a new branch (skip repos where the user chose to keep their existing branch):

```bash
git -C <workspace_dir>/<repo> checkout -b <branch-name>
git -C <workspace_dir>/<repo> branch --show-current   # Verify
```

If branch already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

### Create the Terraform Worktree (only if resource mode is `terraform`)

The service repo gets a **second** branch for `terraform/`+`atlantis.yaml`,
opened as its own PR later (see `add-service/commit-push-pr.md` §
Terraform PR) — but create it now, as a **git worktree**, not by switching
branches mid-generation or mid-commit later. A worktree gives both
branches a real checked-out working directory at the same time, from the
same fresh `main`, with zero branch-switching required anywhere downstream:

```bash
git -C <service_repo_path> worktree add <workspace_dir>/<service-repo>-terraform -b <branch-name>-terraform main
```

This is deliberately created here, alongside the primary branch, not later
in Phase 6 — creating it later would mean switching back to `main` after
Phase 4/5 already ran, which risks `git checkout main` failing outright if
`main` already tracks `terraform/**` (e.g. a second add-service run adding
more resources to the same repo later), and risks the two branches basing
off different points if anything merged to `main` in between. Cutting both
from the same pull, right here, avoids both problems entirely.

Phase 4's Terraform Generation module writes into
`<workspace_dir>/<service-repo>-terraform/` — a completely separate working directory
from the primary `service_repo_path` checkout — so there is no working-tree
conflict between the two generation streams either.

### Gate Verification

Before proceeding to Phase 4, confirm all affected repos are on the correct branch:

```
Branch Gate Status:
  ✅ iac-eks-addons   → feat/PLAT-123-add-cert-manager
  ✅ iac-eks-argocd   → feat/PLAT-123-add-cert-manager
  ✅ <service-repo> (terraform worktree) → feat/PLAT-123-add-cert-manager-terraform   (only if resource mode is `terraform`)

Proceeding to file generation.
```

If ANY repo (or the terraform worktree, when applicable) failed, STOP. Do not generate files.

---

## Phase 4 - Generate

The LLM generates all required files across repositories after Phase 3 confirmation.

### Service Repo Generation

Target repo selected in Phase 1 (commonly `iac-eks-addons`).

**If Service Origin recorded leftover `api-node-template` ECS boilerplate to strip** (an existing never-deployed repo with a stray `iac/`), do the strip here, now that the feature branch exists — `rm -rf iac/` and remove the ECS-only deploy workflows, exactly as `template-scaffold.md` Step S4 does. It gets committed with the rest of the service-repo changes in Phase 6, so the tree was never left dirty on `main` or before the clean-tree gate.

Generated paths:

- `argocd/<addon>/base/kustomization.yaml`
- `argocd/<addon>/base/values.yaml`
- `argocd/<addon>/base/<resource>.yaml` (one per Kustomize resource needed — XIRSARole, XRD claims, ClusterSecretStore, etc.)
- `argocd/<addon>/overlays/<env>/kustomization.yaml` (for each target env)
- `argocd/<addon>/overlays/<env>/config.yaml` (for each target env)
- `argocd/<addon>/overlays/<env>/values.yaml` (for each target env)
- `argocd/<addon>/overlays/<env>/<resource>-patch.yaml` (per resource needing env-specific values)

The Kustomize overlay (Source 2 in the ApplicationSet) can contain any resources that need to exist before or after the Helm chart: IRSA roles, Crossplane XRD claims, ExternalSecrets, ClusterSecretStore configs, HTTPRoutes, etc. It is not limited to IRSA.

### Operational Hardening in Generated Files

> **Module**: Read [`add-service/operational-hardening.md`](add-service/operational-hardening.md) for anti-affinity, PDB, deployment strategy, security context, HPA, and DaemonSet generation rules. Apply all rules to `argocd/<addon>/base/values.yaml` before continuing.

### ArgoCD Repo Generation (`iac-eks-argocd`)

Generated or updated paths:

- `applicationsets/<group>/<addon>.yaml` — new ApplicationSet (3-source pattern, see template below)
- `applicationsets/<group>/kustomization.yaml` — register the new file
- `projects/<project-group>/<project>/project.yaml` — update `sourceRepos` if service repo not yet listed

> **Module**: Read [`add-service/argocd-generation.md`](add-service/argocd-generation.md) for hub routing rules, the complete 3-source ApplicationSet template, config.yaml template, and kustomization.yaml registration guidance. Execute all steps in that module before continuing to Phase 5.

### Terraform Generation (only when resource mode is `terraform`)

Generated paths — **in the `<workspace_dir>/<service-repo>-terraform` worktree created
in Phase 3.5, not the primary `service_repo_path` checkout**:

- `terraform/shared/*.tf` — one file per selected AWS resource type, plus `common.tf`
- `terraform/environments/<env>/` — one folder per target environment, with a real `backend.tf` + `terraform.tfvars` and symlinks back to `shared/*.tf`
- `atlantis.yaml` — at the **repo root**, not under `terraform/` (Atlantis only auto-discovers it there)

> **Module**: Read [`add-service/terraform-generation.md`](add-service/terraform-generation.md) for the module-first resource-type-to-module mapping, the `shared/`+`environments/` symlink pattern, and the `atlantis.yaml` template. Execute all steps in that module before continuing to Phase 5.

---

## Phase 5 - Validate (Automatic)

The LLM runs all wiring checks automatically and only proceeds if all pass.

- **Runtime GitOps preflight (primary k8s gate)** — whenever this run generated
  an `argocd/<addon>/` tree:

  > **Module**: Read [`shared/gitops-preflight-validation.md`](shared/gitops-preflight-validation.md)
  > and execute Steps G1–G5. It owns the `kustomize build` per overlay + the
  > `iac-eks-argocd` ApplicationSet dir, the `helm template` render for a Helm
  > source, and then `iac-eks-preflight` (installed once if missing) as the
  > thorough gate that catches dead values keys, ApplicationSet↔config
  > dereference gaps, AppProject permission errors, source render failures,
  > object collisions, and sync-wave inversions. A skipped preflight check
  > (exit 3) is not a pass, and a failed install is a reported blocker, never a
  > silent skip.

- Verify ApplicationSet generator `repoURL` and path patterns match service repo and overlay layout.
- Verify ArgoCD project permissions include required service repo access.
- Run `npx mobius-validate-service` for convention compliance (gateway, IRSA, structure) — this is the convention check, **not** a substitute for the preflight gate above.
- **If resource mode is `terraform`**: everything below runs against `<workspace_dir>/<service-repo>-terraform/` — the dedicated worktree Phase 3.5 created and Phase 4 generated into — **not** the primary `service_repo_path` checkout, which has no `terraform/` tree at all. Run `terraform fmt -check` against `<workspace_dir>/<service-repo>-terraform/terraform/shared/` and each `<workspace_dir>/<service-repo>-terraform/terraform/environments/<env>/`. Before `terraform validate`, run `terraform init -backend=false` in each of those environment dirs first — `validate` needs providers/modules resolved, not a live backend connection. Use `-backend=false`, not plain `init`: each environment's real `backend.tf` points at an env-specific AWS profile and S3 state bucket, and a full backend init tries to authenticate and reach that bucket — this validation gate would then fail whenever the operator's local AWS profiles or bucket access aren't set up, even when the generated HCL is completely fine. Then confirm `<workspace_dir>/<service-repo>-terraform/atlantis.yaml` (repo root of that worktree) parses as YAML and its anchor merges resolve to one project block per target environment.

#### Additional Wiring Checks

**`applicationsSync` value check** — invalid values silently break the ApplicationSet at apply time:

```bash
rg "applicationsSync:" applicationsets/<group>/<addon>.yaml
# Must be one of: create-only, create-update, create-delete, sync
```

**ApplicationSet kustomization registration** — missing entry = ApplicationSet never applied:

```bash
rg "<addon>" applicationsets/<group>/kustomization.yaml
# If no match: add the file to resources list before proceeding
```

**Project kustomization registration** — missing entry = project doesn't exist on cluster → "namespace not permitted" error:

```bash
rg "<project>" projects/<group>/kustomization.yaml
# If no match: add the project.yaml to resources list before proceeding
```

Validation output is summarized in pass/fail form before wrap up.

### Phase 5.5 — Universal Change Safety Gate (Pre-PR)

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: service repo + `iac-eks-argocd`.
- `risk_profile`: `infrastructure-config`.
- `validation_commands_by_repo`: kustomize builds, repo validators, and wiring checks already executed in Phase 5.
- `rollback_strategy`: git-native revert/reset per repo and merge-order-safe rollback notes in PR body.
- Command-specific focus: ApplicationSet wiring correctness, project permission safety,
  overlay/config discovery paths, and merge-order integrity.

If Phase A reports any blocker, fix and re-run before proceeding to Phase 6.

---

## Phase 6 — Commit, Push, and PR Creation

> **What it does:** Two-repo commit/push/PR: iac-eks-argocd first, then the service
> repo. Each PR references the other in its description.
> **Key behavior:** Merge order matters — ArgoCD wiring must merge before the service
> repo. Includes post-PR feedback scan via change-safety-validation.
> **Module**: Read [`add-service/commit-push-pr.md`](add-service/commit-push-pr.md) and execute all steps before continuing.

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → which service was deployed and to how many environments/repos
- "What was accomplished" → describe the service wiring, AWS integrations, and HA protections added
- "Why it matters" → engineers can now deploy via code push, no manual steps needed
- "What happens next" → explain merge order (iac-eks-argocd first, then service repo) and expected deployment time
- If resource mode was `terraform`: Atlantis is already org-wide enabled (no manual enablement step) — call out instead that the dedicated terraform/atlantis.yaml PR needs normal review + approval before Atlantis will run `apply` (see `add-service/commit-push-pr.md` § Terraform PR)
- If the service was scaffolded from `api-node-template`: call out that app CI/CD build/push wiring still needs manual review — this command doesn't generate it
- If any AWS permissions came from a characterized dependency: state the chosen role for each of the lib's role axes (e.g. "lib-message-bus: producer-consumer=consumer" — list every axis when a lib has more than one, plus any axis-less actions) so the reviewer can see why the IAM policy is scoped the way it is, and note that the policy reflects declared intent to re-verify once real code lands

**Repo breakdown guidance**: Use `shared/repo-roles.md` for plain-language descriptions.
Highlight merge order WHY: deployment system must know about the service before config can be deployed.
