# update-service Workflow

Canonical workflow for `/mobius:update-service` — modifying a service that has
already been onboarded to EKS. This is the companion to
[add-service.md](add-service.md), which only runs at creation time.

> **Agent + human compatible.** The command spec is
> `commands/mobius/update-service.md`; this doc is the human-readable
> companion. Both drive the same flow.

## When to use

Use `update-service` when the service already has generated wiring
(`argocd/<addon>/` exists in its repo) and you need to change it:

| Mode | Use when |
|------|----------|
| **add-resource** | The service now needs an AWS resource (S3, SQS, RDS, …) or additional IAM actions it didn't have at onboarding. This is the path that replaced hand-editing IaC for a service-level IAM permission. |
| **bump-chart** | You're moving the service to a newer pinned Helm chart version. |
| **add-environment** | The service is live in some environments and you're adding another (e.g. promoting a qa-only service to prod). |

If the service isn't onboarded yet, use [add-service](add-service.md) instead —
there's nothing to update.

## Pairing with add-service

A service onboarded from a fresh `api-node-template` scaffold is wired up from
*declared intent* (see `commands/mobius/add-service/dependency-intake.md`), not
observed code. Once real code lands and its actual AWS usage is known,
`update-service` add-resource mode reconciles the difference — the "scaffold
now, fill in later" pairing.

## Flow

1. **Workspace resolution** — resolve `workspace_dir` (see
   `commands/mobius/shared/workspace-resolution.md`); missing repos are cloned,
   not hard-stopped.
2. **Preflight** — the shared multi-repo preflight
   (`docs/workflows/shared/multi-repo-git-workflow.md`), plus a check that the
   service is actually onboarded (`argocd/<addon>/` exists).
3. **JIRA + mode selection** — pick add-resource / bump-chart / add-environment.
4. **Execute the mode** — reuses add-service's generation submodules
   (research-phase AWS detection, terraform-generation / Crossplane XRD claims,
   argocd-generation, helm-chart-resolution) to modify existing files in place.
5. **Validate** — `npx mobius-validate-wiring update-service --service-repo <path>`
   (reuses the `WIRE-ADD` wiring validator), plus mode-specific checks
   (terraform validate for add-resource in terraform mode; version-pin check for
   bump-chart; overlay/config.yaml check for add-environment).
6. **Change-safety, commit, PR** — reuses `add-service/commit-push-pr.md`,
   including the dedicated Terraform-worktree PR split when an add-resource is in
   terraform mode.

## Intake template

Fill and validate before generating:

```bash
cp docs/workflows/services/update-service-intake.yaml /tmp/my-update-intake.yaml
# edit /tmp/my-update-intake.yaml
```

## Blast radius

- **add-resource**: low — additive IAM/resource; existing workloads unaffected until they use it.
- **bump-chart**: medium — a chart bump can restart pods and may carry values-schema changes; the command flags breaking-change signals.
- **add-environment**: net-new — a new overlay/cluster target; nothing existing changes.
