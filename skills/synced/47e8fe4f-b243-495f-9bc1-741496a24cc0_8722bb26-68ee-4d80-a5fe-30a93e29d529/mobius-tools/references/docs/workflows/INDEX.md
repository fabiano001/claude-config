# Mobius Workflow Index

> **Claude + Codex compatible**: All workflows in this index are written to be
> followed step-by-step by both human engineers and AI agents (Claude Code,
> Codex, or any agent that reads AGENTS.md).

This is the canonical entry point for platform engineering workflows. Each
workflow doc follows a standard structure and is self-contained.

---

## Command Aliases

Use slash commands instead of typing workflow doc paths:

| Command | Workflow Doc |
|---------|-------------|
| `/mobius:help` | Show all mobius commands |
| `/mobius:add-service` | `services/add-service.md` |
| `/mobius:update-service` | `services/update-service.md` |
| `/mobius:new-xrd` | `xrd/new-xrd.md` |
| `/mobius:new-project` | `argocd/new-project-or-applicationset.md` |
| `/mobius:debug-appset` | `argocd/debug-applicationset.md` |
| `/mobius:debug-service` | Self-contained (auth: `argocd/argocd-cli-auth.md`) |
| `/mobius:migrate-ecs-service` | `migration/migrate-ecs-service.md` |
| `/mobius:new-hub` | Self-contained (includes integrated git workflow) |
| `/mobius:new-spoke` | Self-contained (includes integrated git workflow) |
| `/mobius:validate-service` | Self-contained (wraps `npx mobius-validate-service`) |

**Install commands:**
```bash
bash ../mobius-tools/scripts/install-command-pack.sh --force
```

---

## Workflows

### Service Deployments

| Workflow | What it covers |
|----------|----------------|
| [add-service.md](services/add-service.md) | Creating a new EKS service deployment in a service repo with generator-scoped ApplicationSet wiring (includes integrated git workflow with JIRA, branching, and PR creation) |
| [update-service.md](services/update-service.md) | Modifying an already-onboarded EKS service — add an AWS resource/IAM, bump the Helm chart version, or add a target environment (reuses add-service's generators) |

> **Before generating files**, fill the intake template and run the validator:
> ```bash
> cp docs/workflows/services/add-service-intake.yaml /tmp/my-service-intake.yaml
> # Fill all required fields
> npx mobius-validate-intake add-service /tmp/my-service-intake.yaml
> ```

### Crossplane XRDs

| Workflow | What it covers |
|----------|----------------|
| [new-xrd.md](xrd/new-xrd.md) | Creating a new KCL-based Crossplane XRD repo and registering it (includes integrated git workflow with JIRA, branching, and PR creation) |

### GitHub Actions

| Workflow | What it covers |
|----------|----------------|
| [oidc-setup.md](github-actions/oidc-setup.md) | Setting up OIDC-based AWS authentication for a GitHub Actions workflow via the XGitHubOIDCRole Crossplane claim — no long-lived credentials |

### Hub and Spoke

| Workflow | What it covers |
|----------|----------------|
| `/mobius:new-hub` (self-contained) | Creating a new ArgoCD hub cluster with multi-repo wiring (includes integrated git workflow with JIRA, branching, and PR creation) |
| `/mobius:new-spoke` (self-contained) | Registering a new spoke cluster under an existing hub (includes integrated git workflow with JIRA, branching, and PR creation) |

### Shared Workflows

| Workflow | What it covers |
|----------|----------------|
| [multi-repo-git-workflow.md](shared/multi-repo-git-workflow.md) | Canonical multi-repo git workflow: preflight, branch creation gate, commit, push, and PR creation for commands touching 2+ repos |
| [jira-integration.md](shared/jira-integration.md) | JIRA ticket integration: pre-branch ticket prompt, branch naming from ticket IDs, ticket creation, and opt-in guidance per command |

### ArgoCD

| Workflow | What it covers |
|----------|----------------|
| [new-project-or-applicationset.md](argocd/new-project-or-applicationset.md) | Adding a new ArgoCD project or ApplicationSet (includes integrated git workflow with JIRA, branching, and PR creation) |
| [debug-applicationset.md](argocd/debug-applicationset.md) | Diagnosing and fixing ApplicationSet discovery failures |
| [argocd-cli-auth.md](argocd/argocd-cli-auth.md) | ArgoCD CLI authentication reference (credentials, hub URLs, SSO) |

### Migration

| Workflow | What it covers |
|----------|----------------|
| [migrate-ecs-service.md](migration/migrate-ecs-service.md) | Migrating ECS services to EKS with discover→generate flow, parity validation, and cutover runbook generation (includes integrated git workflow with JIRA, branching, and PR creation) |
| [ecs-eks-mapping.md](migration/ecs-eks-mapping.md) | Canonical ECS→EKS concept mapping matrix (compute, IAM/IRSA, networking, scaling, sidecars) |
| [ecs-extraction-reference.md](migration/ecs-extraction-reference.md) | AWS CLI extraction commands, field mapping, redaction rules, and error handling |
| [cutover-runbook-template.md](migration/cutover-runbook-template.md) | Standardized zero-downtime cutover checklist template with rollback procedures |
| [golden-tests.md](migration/golden-tests.md) | End-to-end golden test procedure for migration intake validation |
| [migrate-ecs-intake.yaml](migration/migrate-ecs-intake.yaml) | Intake template for ECS-to-EKS migration |

---

## Standard Workflow Structure

Every workflow doc contains:

1. **Purpose** — what problem it solves and when to use it
2. **Inputs required** — what you need before starting
3. **Repositories / files touched** — which repos and paths change
4. **Step-by-step procedure** — ordered, testable steps
5. **Validation commands** — commands to run to verify success
6. **Failure modes** — what breaks, where to look, how to fix
7. **Merge order** — cross-repo PR sequencing (when applicable)

---

## Related Docs

| Doc | Purpose |
|-----|---------|
| [../onboarding.md](../onboarding.md) | First-time setup for the platform |
| [../architecture.md](../architecture.md) | How `mobius-tools` and the resolver work |
| [../troubleshooting.md](../troubleshooting.md) | Debugging resolver and repo issues |
| [../agent-interop.md](../agent-interop.md) | How Claude and Codex share this workflow layer |
| [../ecosystem-start-here.md](../ecosystem-start-here.md) | Fast ecosystem orientation index |
| [../glossary.md](../glossary.md) | Shared terminology (service deployment vs addon) |
| [../../ecosystem/master-map.md](../../ecosystem/master-map.md) | Full platform topology |

---

## Skill Cross-Reference

Per-repo skills provide tighter, checklist-style guidance for individual repos.
These workflow docs zoom out to show the full cross-repo flow.

| Skill | Repo | Covers |
|-------|------|--------|
| `addons-addon` | `iac-eks-addons` | Base/overlay structure and config.yaml |
| `addons-environment` | `iac-eks-addons` | Adding a new environment overlay |
| `argocd-applicationset-wiring` | `iac-eks-argocd` | ApplicationSet discovery verification |
| `argocd-project-guard` | `iac-eks-argocd` | ArgoCD project permission enforcement |
| `crossplane-configuration` | `iac-eks-crossplane` | Provider and configuration management |
| `crossplane-operations` | `iac-eks-crossplane` | Day-2 ops and troubleshooting |
| `observability-addon` | `iac-eks-observability` | Observability stack addons |
