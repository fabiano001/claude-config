---
name: new-xrd
description: Create a new Crossplane KCL-based XRD repo
argument-hint: <resource-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Create a New Crossplane XRD

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command creates KCL compositions with flat-file patterns, OCI packaging
> constraints, and cross-repo registration across 2-3 repositories. Weaker models
> may use incorrect KCL imports, miss `skipDependencyResolution`, or produce wrong
> publish sequences. If using Codex CLI, prefer `codex exec --model o3`.

This command creates a new KCL-based Crossplane Composite Resource Definition (XRD)
as a standalone repo and registers it with the platform.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Crossplane Flow](../../docs/architecture/crossplane-flow.md) — composition pipeline, KCL patterns, OCI packaging
> - [Platform Overview](../../docs/architecture/platform-overview.md) — where XRDs fit in the overall platform

---

## Workflow Reference

Follow the canonical workflow at:
**`../mobius-tools/docs/workflows/xrd/new-xrd.md`**

---

## Key Points

- **All new XRDs use KCL + OCI Configuration pattern**
- Do NOT use inline Go-templated compositions in `iac-eks-crossplane` (legacy)
- XRDs must be cluster-scoped for AWS resources (Crossplane v2 requirement)

---

## Canonical Rules

- No file generation before inputs are gathered and confirmed.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake — strongly encouraged for new XRDs but skippable.
- No file generation on `main` — feature branches MUST exist in all affected repos before generation.
- Work is not complete until a PR exists for every affected repo.
- Merge order: `crossplane-xrd-<name>` published and tagged first, then `iac-eks-crossplane`, then `mobius-tools`.

---

## Inputs to Gather

### Git and JIRA Preflight (before intake)

Before gathering inputs, verify git prerequisites and prompt for JIRA.

#### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Verify for the CURRENT working directory (likely the target XRD repo parent or `iac-eks-crossplane`):

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
     If user chooses "use this branch", skip branch creation for this repo later.

> Note: The new XRD repo doesn't exist yet — it will be created fresh. Remaining repos (`iac-eks-crossplane`, `mobius-tools`) are preflighted in the Branch Creation Gate.

#### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

```
Before we begin, is there a Jira ticket for this XRD?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-456)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use XRD name only)
```

Store as `jira_ticket_id`. This flows into branch names, commit footers, and PR titles.

---

| Input | Example |
|-------|---------|
| Resource name (kebab-case) | `rds-cluster` |
| AWS resource type | `RDS Cluster` |
| API group | `aws.platform.boatsgroup.com` |
| API version | `v1alpha1` |
| Module name | `crossplane-xrd-rds-cluster` |

---

## Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**No file generation until branches exist in all affected repos.**

### Affected Repos

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

| Repo | Status | What changes |
|------|--------|-------------|
| `crossplane-xrd-<name>` | New repo — will be created | XRD definition, KCL composition, tests, manifests |
| `iac-eks-crossplane` | Existing | Configuration CR registration |
| `mobius-tools` | Existing | Dependency graph + repo summary |

### Preflight Existing Repos

For `iac-eks-crossplane` and `mobius-tools`:

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

If any repo has dirty working tree, STOP.

### Create Feature Branches

Branch name pattern:
- With JIRA: `feat/<jira_ticket_id>-add-<xrd-name>` (e.g., `feat/PLAT-456-add-rds-cluster`)
- Without JIRA: `feat/add-<xrd-name>` (e.g., `feat/add-rds-cluster`)

For `iac-eks-crossplane` and `mobius-tools` (skip if user chose to keep existing branch):

```bash
git -C <workspace_dir>/<repo> checkout -b <branch-name>
```

> Note: The new XRD repo (`crossplane-xrd-<name>`) is created fresh in the next step. Its first commit will be on `main` (initial repo setup). Subsequent work happens on the branch created after repo initialization.

### Gate Verification

```
Branch Gate Status:
  ✅ crossplane-xrd-<name>   → (new repo, will be created)
  ✅ iac-eks-crossplane       → feat/PLAT-456-add-rds-cluster
  ✅ mobius-tools              → feat/PLAT-456-add-rds-cluster

Proceeding to generation.
```

---

## Summary of Steps

1. Create new repo from template (`crossplane-xrd-irsa-role` as reference)
2. Define the XRD (CompositeResourceDefinition)
3. Write KCL composition logic (flat-file pattern, no imports)
4. Write Crossplane manifests (definition.yaml, composition.yaml, crossplane.yaml)
5. Test locally with `kcl run` and `crossplane beta render`
6. Tag and publish OCI package (GitHub Actions -> JFrog)
7. Register with `iac-eks-crossplane` (Configuration CR)
8. Update `mobius-tools/ecosystem/dependency-graph.yaml`
9. Add AGENTS.md to the new repo

---

## Commit, Push, and PR Creation

> **What it does:** Three-repo commit/push/PR: crossplane-xrd-<name> first, then
> iac-eks-crossplane, then mobius-tools. Strict merge order with OCI tag sequencing.
> **Key behavior:** OCI tags must be sequenced correctly — the XRD repo must be
> published before iac-eks-crossplane can reference the new OCI image. Includes
> post-PR feedback scan via change-safety-validation.
> **Module**: Read [`new-xrd/commit-push-pr.md`](new-xrd/commit-push-pr.md) and execute all steps before continuing.

### Universal Change Safety Gate (Pre-PR)

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `crossplane-xrd-<name>`, `iac-eks-crossplane`, `mobius-tools`.
- `risk_profile`: `mixed`.
- `validation_commands_by_repo`: `kcl run`, `crossplane beta render`, and dependency graph consistency checks.
- `rollback_strategy`: git-native revert/reset per repo, plus OCI tag sequencing safety.
- Command-specific focus: XRD schema/composition validity, package publish sequence,
  and Configuration CR registration order.

If Phase A reports any blocker, fix and re-run before PR creation.

---

## Post-Execution Checklist

Verify these files exist across repos before opening PRs:

#### crossplane-xrd-<name> (new repo)
- [ ] `definition.yaml` — CompositeResourceDefinition (v2 API)
- [ ] `composition.yaml` — Composition with function-kcl pipeline
- [ ] `crossplane.yaml` — Package metadata with `skipDependencyResolution: true`
- [ ] `functions.yaml` — Required for `crossplane beta render`
- [ ] `kcl/main.k` — KCL composition entry point
- [ ] `kcl/config.k` — Configuration (reads `option("params").oxr`)
- [ ] `test/basic-params.json` — Test parameters
- [ ] `.github/workflows/` — CI for OCI publish

#### iac-eks-crossplane
- [ ] `argocd/crossplane/base/configurations/<name>.yaml` — Configuration CR

#### mobius-tools
- [ ] `ecosystem/dependency-graph.yaml` — New repo entry under `repos:`

---

## Anti-Patterns to Avoid

| Pattern | Why Forbidden |
|---------|---------------|
| `import helpers` in main.k | KCL flat-file pattern - all .k files share namespace |
| `scope: Namespaced` for AWS | Crossplane v2 requires cluster-scoped XRDs |
| Missing `skipDependencyResolution: true` | Causes package lock conflicts |
| Go-templated compositions | Legacy pattern - use KCL instead |
| Manually bump `kcl.mod` or `composition.yaml` versions | CI handles version management — manual changes cause conflicts |
| Missing `functions.yaml` | Required for `crossplane beta render` local testing |

---

## Merge Order

1. **`crossplane-xrd-<name>`** — merge PR, then tag `v0.0.1` to trigger OCI package publish
2. **`iac-eks-crossplane`** — merge PR after OCI package is published (Configuration CR registration)
3. **`mobius-tools`** — merge PR last (dependency-graph.yaml update)

See the "Commit, Push, and PR Creation" section above for the full PR creation sequence and templates.

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which new cloud resource type was created
- "What was accomplished" → describe the new self-service template and what resource it provisions
- "Why it matters" → teams can now create this resource type by adding a config file — no tickets needed
- "What happens next" → register in dependency graph, publish OCI package, verify with a test claim

**Repo breakdown guidance**:
- New XRD repo: the self-service template for the new resource type
- iac-eks-crossplane: registers the new resource type with the cloud provisioning system
- mobius-tools: updates the dependency graph to track the new repo
