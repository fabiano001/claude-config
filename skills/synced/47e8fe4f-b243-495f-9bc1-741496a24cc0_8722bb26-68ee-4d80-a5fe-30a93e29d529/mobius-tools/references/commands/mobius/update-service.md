---
name: update-service
description: Modify an already-onboarded EKS service (add AWS resource/IAM, bump Helm chart, add environment)
argument-hint: <service-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->

# Update an Already-Onboarded Service

`/mobius:add-service` runs once, at creation time. Everything that comes *after*
a service is live — adding an AWS resource or IAM permission it didn't need at
launch, bumping its Helm chart, adding a new environment — had no command until
now, and the engineer guide explicitly flagged the IAM-permission case as "the
one task without a dedicated command." `/mobius:update-service` fills that gap.

It is deliberately thin: every generation step **reuses `add-service`'s
submodules** rather than duplicating them. The only genuinely new logic is
locating the existing service's already-generated files and modifying them in
place instead of creating them from scratch.

> **Use an opus-tier model** — same reasoning as add-service: this edits
> ApplicationSet/overlay/Terraform wiring across 2-3 repos where a silent
> mismatch causes discovery failures.

## Pairing with add-service

This command is the "fill in later" half of the scaffold-now pairing: a service
onboarded from a fresh `api-node-template` scaffold was wired up from *declared
intent* (see `add-service/dependency-intake.md`), not observed code. Once real
code lands and its actual AWS usage is known, `update-service` (add-resource
mode) reconciles the difference.

---

## Workspace Resolution (MANDATORY — before everything)

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` before anything else.

Every repo this command touches (`iac-eks-argocd`, the service repo, the
Terraform worktree) is referenced as `<workspace_dir>/<repo>`. Missing repos are
cloned into `workspace_dir` by the shared Preflight, not hard-stopped.

---

## Phase 0 — Locate the service and pick the update mode

### Step 0a — Preflight

Run the shared Preflight (`docs/workflows/shared/multi-repo-git-workflow.md`
§ Preflight Checks) for the service repo and `iac-eks-argocd`: `gh auth`,
locate-or-clone under `workspace_dir`, clean tree, branch check.

### Step 0b — Confirm the service is actually onboarded

This command modifies an **existing** deployment. Verify the service already has
generated wiring before proceeding:

```bash
[ -d "<workspace_dir>/<service-repo>/argocd/<addon>" ] || echo "NOT ONBOARDED"
```

If the service isn't onboarded yet, stop and point the user at
`/mobius:add-service` — there's nothing to update.

### Step 0c — JIRA + mode selection

Prompt for a JIRA ticket (same as add-service Step 0b), then ask what to update:

```
What do you want to change about <service-name>?

1. **Add an AWS resource / IAM permission** — e.g. add an S3 bucket, SQS queue,
   or extra IAM actions to an already-onboarded service
2. **Bump the Helm chart version** — move to a newer pinned chart version
3. **Add a target environment** — add a new env overlay (e.g. add ops-prod to a
   service currently only in bg-qa/bg-prod)
```

Route to the matching module below. Multiple modes in one run are allowed — run
them in sequence, but confirm each independently before generation.

### Step 0d — Branch + Worktree Gate (HARD GATE, before any generation)

This is the same gate add-service runs in its Phase 3.5 — update-service needs
it too, because Phase 3's commit/PR flow (`add-service/commit-push-pr.md`)
assumes the branches and, for terraform changes, the Terraform worktree already
exist. Create them here, before Phase 1 generates anything:

1. **Feature branch** in the service repo (branch pattern
   `feat/<jira_ticket_id>-update-<service-name>` or `feat/update-<service-name>`),
   and in `iac-eks-argocd` too **only if** this update changes project
   permissions (e.g. add-environment that grants a new cluster/account). Use the
   shared Branch Creation Gate (`docs/workflows/shared/multi-repo-git-workflow.md`
   § Branch Creation Gate).
2. **Terraform worktree** — create it exactly as add-service Phase 3.5 does
   **whenever this run will touch `terraform/`**: an add-resource in `terraform`
   mode, or an add-environment for a service that's already `terraform` mode.
   Skip it otherwise (crossplane-only add-resource, bump-chart, add-environment
   for a crossplane service):
   ```bash
   git -C <service_repo_path> worktree add <workspace_dir>/<service-repo>-terraform -b <branch-name>-terraform main
   ```
   The terraform-touching submodules write into this worktree, and
   `commit-push-pr.md` opens the third (Terraform) PR from it. Without this step
   there is nowhere valid to commit the Terraform change — do not skip it for a
   terraform-touching update.

If any repo (or the worktree, when required) fails to branch, STOP before Phase 1.

---

## Phase 1 — Execute the selected mode

- **Add AWS resource / IAM** → Read [`update-service/add-resource.md`](update-service/add-resource.md)
- **Bump Helm chart** → Read [`update-service/bump-chart.md`](update-service/bump-chart.md)
- **Add environment** → Read [`update-service/add-environment.md`](update-service/add-environment.md)

Each module reuses add-service's generation submodules and produces a concrete,
reviewable diff against the existing service.

---

## Phase 2 — Validate

Re-run the same wiring validation add-service uses, since update-service edits
the same artifact surface:

- **Runtime GitOps preflight (primary k8s gate)** — whenever the mode touched an
  `argocd/<addon>/` tree (add-resource, add-environment, or a bump-chart that
  re-pins a Helm version):

  > **Module**: Read [`shared/gitops-preflight-validation.md`](shared/gitops-preflight-validation.md)
  > and execute Steps G1–G5. It owns the `kustomize build` per affected overlay /
  > ApplicationSet dir and the `helm template` render, then runs
  > `iac-eks-preflight --all` (installed once if missing) as the thorough gate on
  > the post-change tree. A skipped check (exit 3) is not a pass; a failed install
  > is a reported blocker.
  > Note: for **bump-chart** the version-aware `delta` (which surfaces
  > `KEY_DROPPED_BY_UPGRADE`) does **not** run here — it must run *before* the pin
  > is rewritten, so it lives in `bump-chart.md` Step BC2. This Phase 2 gate is the
  > post-pin render/graph check.

- `npx mobius-validate-wiring update-service <service-name> --service-repo <path>`
  — the `<service-name>` positional is required (the CLI exits with "name is
  required" without it). This is an alias that reuses the existing `WIRE-ADD`
  wiring validator (the post-state must satisfy the same structural rules
  whether the files were just created or just modified).
- Mode-specific checks: for add-resource in `terraform` mode, the same
  `terraform fmt -check` / `terraform init -backend=false` / `terraform validate`
  gate from add-service Phase 5 against the affected `terraform/` dirs; for
  bump-chart, re-verify the new version resolves and pins (never `latest`); for
  add-environment, confirm the new overlay's `config.yaml` exists and the
  ApplicationSet generator path matches.

---

## Phase 3 — Change Safety, Commit, PR

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md) (Phase A pre-PR), then [`add-service/commit-push-pr.md`](add-service/commit-push-pr.md) for the commit/push/PR mechanics.

The commit-push-pr flow is reused as-is, including the workspace_dir paths and
(for a `terraform`-mode add-resource) the dedicated Terraform-worktree PR split.
Merge order is the same: `iac-eks-argocd` first where project permissions
changed, service repo second.

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md).

**Command type**: generative (modifies existing wiring).

**Context hints**: what changed about the existing service and why; that the
change is additive to a live deployment (call out blast radius — an IAM/resource
add is low-risk, a chart bump can restart pods, a new environment is net-new);
merge order and expected reconcile time.
