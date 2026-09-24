---
name: new-project
description: Add an ArgoCD project or ApplicationSet
argument-hint: <project-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Create ArgoCD Project or ApplicationSet

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command manages a 3-level kustomization hierarchy, project RBAC with
> cluster-scoped resources, and ApplicationSet generator wiring across 1-2
> repositories. Weaker models may miss a kustomization registration level or
> use over-permissive wildcard destinations. If using Codex CLI, prefer
> `codex exec --model o3`.

This command helps you add a new ArgoCD project or ApplicationSet to
`iac-eks-argocd`.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — project RBAC model, AppProject destinations, ApplicationSet generators
> - [Environment Model](../../docs/architecture/environment-model.md) — which clusters/namespaces projects scope to

---

## Workflow Reference

Follow the canonical workflow at:
**`../mobius-tools/docs/workflows/argocd/new-project-or-applicationset.md`**

---

## Canonical Rules

- No file generation before inputs are gathered and confirmed.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake — optional for project/applicationset creation.
- No file generation on `main` — a feature branch MUST exist before Common Tasks.
- Work is not complete until a PR exists for `iac-eks-argocd`.

---

## When to Use

- Adding a new team or workload category that needs isolated ArgoCD permissions
- Creating a new ApplicationSet to discover config.yaml files from a service repo
- Setting up project permissions before deploying a new service

---

## Key Concepts

### ArgoCD Projects
Projects define:
- `sourceRepos` — which Git repos and Helm URLs can be used
- `destinations` — which namespaces and clusters can be deployed to
- `clusterResourceWhitelist` — which cluster-scoped resources can be created

### ApplicationSets
ApplicationSets use generators to discover config.yaml files and create
Applications automatically. The Git File Generator scans a specific repo
and path pattern.

---

## Git and JIRA Preflight

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

Before asking any intake questions, verify git prerequisites and prompt for JIRA.

### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Verify for `iac-eks-argocd`:

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Verify repo exists locally: `[ -d "<workspace_dir>/iac-eks-argocd" ]`. If not, hard-stop and ask user to clone it.
3. Working tree is clean: `git -C <workspace_dir>/iac-eks-argocd status --porcelain` returns empty. If dirty, hard-stop — user must resolve manually.
4. Check current branch:
   - If on `main`: pull latest (`git -C <workspace_dir>/iac-eks-argocd pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user before doing anything:
     ```
     iac-eks-argocd is on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
        (recommended if you created it for this work)
     2. **Switch to main and create new branch** — start fresh from main
     ```
     If user chooses "use this branch", skip branch creation in the Branch Creation Gate.

### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Prompt the user. JIRA is optional for project/applicationset creation:

```
Before we begin, is there a Jira ticket for this work?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-123)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use project name only)
```

Store as `jira_ticket_id` (e.g., `PLAT-123` or `null`). This value flows into:
- Branch name in the Branch Creation Gate
- Commit message footer in Commit/Push/PR
- PR title and body in Commit/Push/PR

---

## Inputs for a New Project

| Input | Example |
|-------|---------|
| Project name | `platform-addons` |
| Source repos | GitHub URLs, Helm repo URLs |
| Destination namespaces | `cert-manager`, `external-secrets` |
| Cluster scope | `*` (all) or specific clusters |

---

## Inputs for a New ApplicationSet

| Input | Example |
|-------|---------|
| ApplicationSet name | `cert-manager` |
| Service repo URL | `https://github.com/boatsgroup/iac-eks-addons` |
| Config path pattern | `argocd/<addon>/overlays/*/config.yaml` |
| Target project | `core-infrastructure` |

---

## Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This gate MUST succeed before generating any files. If any step fails, STOP.**

### Preflight `iac-eks-argocd`

If preflight was not already completed in Step 0a, run it now:

1. Verify repo exists locally: `[ -d "<workspace_dir>/iac-eks-argocd" ]`
2. Verify clean working tree: `git -C <workspace_dir>/iac-eks-argocd status --porcelain`
3. If on `main`: `git -C <workspace_dir>/iac-eks-argocd pull origin main`
4. If NOT on `main`: ask user whether to use the existing branch or switch to main.

If the working tree is dirty, STOP. Report which files are dirty. The user must resolve manually.

### Create Feature Branch

Branch name pattern:
- With JIRA: `feat/<jira_ticket_id>-new-project-<name>` (e.g., `feat/PLAT-123-new-project-platform-addons`)
- Without JIRA: `feat/new-project-<name>` (e.g., `feat/new-project-platform-addons`)

If the user chose to keep their existing branch in Step 0a, skip this step.

```bash
git -C <workspace_dir>/iac-eks-argocd checkout -b <branch-name>
git -C <workspace_dir>/iac-eks-argocd branch --show-current   # Verify
```

If the branch already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

### Gate Verification

Before generating any files, confirm `iac-eks-argocd` is on the correct branch:

```
Branch Gate Status:
  ✅ iac-eks-argocd   → feat/PLAT-123-new-project-platform-addons

Proceeding to file generation.
```

If the gate failed, STOP. Do not generate files.

---

## Common Tasks

### Add a source repo to existing project
```yaml
# In projects/<team>/<project>/project.yaml
sourceRepos:
  - "https://github.com/boatsgroup/<repo>"
  - "<helm-repo-url>"
```

### Add a destination namespace to existing project
```yaml
# In projects/<team>/<project>/project.yaml
destinations:
  # In-cluster (hub)
  - namespace: "<namespace>"
    server: https://kubernetes.default.svc

  # Spoke clusters (add one per namespace per spoke)
  - namespace: "<namespace>"
    server: "<spoke-cluster-api-server-url>"
```

> **Note**: Do NOT use `server: "*"` wildcard. Get spoke API server URLs from
> existing project files or `kubectl config get-contexts`.

### Register project in kustomization hierarchy
Projects use a 3-level kustomization hierarchy:
1. `projects/<team>/<project>/kustomization.yaml` — includes `project.yaml`
2. `projects/<team>/kustomization.yaml` — includes `<project>/`
3. `projects/kustomization.yaml` — includes `<team>/` (only if new team)

### Register ApplicationSet in kustomization
```yaml
# In applicationsets/<group>/kustomization.yaml
resources:
  - <addon>.yaml
```

Note: Each environment only includes the ApplicationSet groups it needs.
The env-level kustomization at `hubs/<hub>/environments/<hub>/<region>/applicationsets/kustomization.yaml`
references the groups.

---

## Post-Execution Checklist

Verify these files exist in `iac-eks-argocd` before opening PR:

#### For a new project
- [ ] `projects/<team>/<project>/project.yaml`
- [ ] `projects/<team>/<project>/kustomization.yaml` (includes project.yaml)
- [ ] `projects/<team>/kustomization.yaml` (includes `<project>/`)
- [ ] `projects/kustomization.yaml` (includes `<team>/` if new team)

#### For a new ApplicationSet
- [ ] `applicationsets/<group>/<addon>.yaml`
- [ ] `applicationsets/<group>/kustomization.yaml` (includes `<addon>.yaml`)

#### Validation
```bash
kustomize build projects/<team>/<project>
kustomize build applicationsets/<group>
```

---

## Validation

```bash
# Build kustomization
kustomize build <workspace_dir>/iac-eks-argocd/applicationsets/core-infrastructure

# Check project
kubectl get appproject -n argocd <project-name> -o yaml

# Check ApplicationSet
kubectl get applicationset -n argocd <appset-name>
```

---

## Commit, Push, and PR Creation

> References:
> - `docs/workflows/shared/multi-repo-git-workflow.md` § Commit Pattern, § Push + PR Pattern
> - `docs/workflows/shared/jira-integration.md` § Ticket ID Propagation

### Step 1 — Summary of Changes

Before committing, present what was generated and validated:

```
Generated files:
  iac-eks-argocd:
    - projects/<team>/<project>/project.yaml (if new project)
    - projects/<team>/<project>/kustomization.yaml (if new project)
    - projects/<team>/kustomization.yaml (updated, if new project)
    - projects/kustomization.yaml (updated, if new team)
    - applicationsets/<group>/<addon>.yaml (if new ApplicationSet)
    - applicationsets/<group>/kustomization.yaml (updated, if new ApplicationSet)

Validation: kustomize build passed.
```

### Step 1.5 — Universal Change Safety Gate (Pre-PR)

> **What it does:** Runs the universal pre-PR safety gate before committing ArgoCD
> project and ApplicationSet changes. Validates kustomize build integrity, project
> permission boundary correctness, and ApplicationSet registration. Reports any
> blockers that must be resolved before commit/push/PR. Uses shared validation
> logic from `shared/change-safety-validation.md` (Phase A).

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `iac-eks-argocd`.
- `risk_profile`: `infrastructure-config`.
- `validation_commands_by_repo`: kustomize build checks and ArgoCD project/ApplicationSet validation.
- `rollback_strategy`: git-native revert/reset for single repo.
- Command-specific focus: project permission boundaries, ApplicationSet registration,
  and kustomization inclusion integrity.

If Phase A reports any blocker, fix and re-run before commit/push/PR.

### Step 2 — Commit

```bash
# Stage all changes
git -C <workspace_dir>/iac-eks-argocd add -A

# Analyze diff
git -C <workspace_dir>/iac-eks-argocd diff --cached --stat
git -C <workspace_dir>/iac-eks-argocd diff --cached
```

Generate a commit message following the conventional commit format:

```
feat(<name>): add <project-or-appset-name> ArgoCD project/applicationset

- <bullet summarizing each generated or updated file>

<JIRA_TICKET_ID>
```

Present the message to the user with option to customize:

```
I'll commit with this message:

---
<generated message>
---

Options:
- Press enter to accept
- Type a custom message if you prefer
```

Commit: `git -C <workspace_dir>/iac-eks-argocd commit -m "<message>"`

**Hard blocks**: No AI attribution, no vague messages, no emoji.

### Step 3 — Push

```bash
git -C <workspace_dir>/iac-eks-argocd push -u origin <branch-name>
```

If push fails, show the error and suggest resolution.

### Step 4 — Create PR

```bash
gh pr create \
  --repo boatsgroup/iac-eks-argocd \
  --title "feat(<name>): add <project-or-appset-name> ArgoCD project/applicationset [<JIRA_TICKET_ID>]" \
  --body "$(cat <<'EOF'
## Summary

Add ArgoCD project/applicationset `<name>` to `iac-eks-argocd`.

## Changes

- <bullet for each generated or updated file>

## JIRA

<JIRA_TICKET_ID>
EOF
)"
```

Omit `[<JIRA_TICKET_ID>]` from the title and `## JIRA` from the body if no ticket.

Capture: `ARGOCD_PR_URL=$(gh pr view --json url -q .url)`

### Step 4.5 — Post-PR Feedback Scan

> **What it does:** Monitors the open PR in `iac-eks-argocd` for CI failures,
> review rejections, and high-severity inline comments after push. Loops until
> zero blockers remain: fix → rerun Phase A validations → push → rerun scan.
> Uses shared feedback-scan logic from `shared/change-safety-validation.md` (Phase B).

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase B (Post-PR Feedback Scan).

Context for this command:

- Single PR target: `iac-eks-argocd`.
- Required channels: checks, reviews, inline comments, issue comments.
- Blocking policy: failing required checks, `CHANGES_REQUESTED`, or high-severity security findings.
- Loop policy: fix -> rerun Phase A validations -> push -> rerun Phase B scan.

Do not claim completion until Phase B reports zero blockers.

### Step 5 — Completion Report

```
ArgoCD project/applicationset complete.

PR created:
  iac-eks-argocd: <ARGOCD_PR_URL>

Branch: feat/<JIRA_TICKET_ID>-new-project-<name>
JIRA: <JIRA_TICKET_ID> (or "none")
```

**Work is NOT complete until the PR URL is returned to the user.**

---

## Why Summary

> **What it does:** Generates a plain-language "Why This Matters" summary at
> the end of command execution. Reads shared formatting rules and repo glossary
> from `shared/why-summary.md` and `shared/repo-roles.md`, then produces an
> output section describing which team project was created, what permission
> boundaries and deployment targets were configured, and what engineers can now
> do as a result.

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which team project was created or updated
- "What was accomplished" → describe the permission boundaries and deployment targets configured
- "Why it matters" → the team can now deploy to their designated namespaces and repos
- "What happens next" → merge the PR and verify team members can deploy

**Repo breakdown guidance**:
- iac-eks-argocd: creates the team permission boundaries — which repos and namespaces the team can deploy to
