# Mobius Platform — Onboarding Guide

> Welcome to the Mobius platform. This guide gets you from zero to a working
> multi-repo development environment in 15 minutes.

---

## Prerequisites

Before starting, you need these tools installed and configured.

### macOS — From Scratch

On a **brand-new Mac**, start here. If you already have Homebrew and git, skip to [Required Tools](#required-tools).

```bash
# 1. Install Xcode Command Line Tools (gives you git, make, clang)
xcode-select --install

# 2. Install Homebrew (macOS package manager)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Follow the "Next steps" Homebrew prints to add it to your PATH.
#    On Apple Silicon Macs (M1/M2/M3/M4), this is typically:
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Required Tools

```bash
brew install node gh jq
```

| Tool | Purpose | Verify |
|------|---------|--------|
| `node` | Node.js runtime (≥ 18) — runs TypeScript CLI validators | `node --version` |
| `npm` | Package manager (bundled with Node.js) — installs dependencies | `npm --version` |
| `gh` | GitHub CLI — clones repos, manages PRs | `gh --version` |
| `jq` | JSON processor — updates Claude Code settings | `jq --version` |
| `git` | Version control (installed by Xcode CLI tools) | `git --version` |

### GitHub Authentication

```bash
gh auth login
```

Choose:
- GitHub.com
- HTTPS protocol
- Yes to authenticate git with GitHub credentials

Verify: `gh auth status` should show your username and `Logged in`.
---

## Setup Options

Choose the path that matches your task:

### Option A: Working in a Specific Repo

If you're starting work in one Mobius repo (e.g., `iac-eks-addons`):

```bash
# 1. Clone the repo you want to work in
gh repo clone boatsgroup/iac-eks-addons

cd iac-eks-addons

# 2. Bootstrap mobius-tools (if not already cloned)
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools

# 3. Install command pack (automatically builds TypeScript validators)
bash ../mobius-tools/scripts/install-command-pack.sh --force

# 4. Run the resolver — clones your deps and wires up Claude Code
bash ../mobius-tools/scripts/resolve-deps.sh

# 5. See what commands are available
/mobius:help
```

The resolver will:
- Read your repo's declared dependencies from AGENTS.md frontmatter
- Clone any missing dependency repos as sibling directories
- Update `.claude/settings.local.json` so Claude Code can access all repos

### Option B: Full Platform Setup

If you want all repos available locally (recommended for platform-level work):

```bash
# 1. Create a workspace directory
mkdir ~/repos/mobius && cd ~/repos/mobius

# 2. Clone mobius-tools first
gh repo clone boatsgroup/mobius-tools

# 3. Clone the core repos
gh repo clone boatsgroup/iac-eks-argocd
gh repo clone boatsgroup/iac-eks-crossplane

# 4. Clone the GitOps repos
gh repo clone boatsgroup/iac-eks-addons
gh repo clone boatsgroup/iac-eks-observability

# 5. Clone infrastructure repos
gh repo clone boatsgroup/terraform-module-core-irsa
gh repo clone boatsgroup/terraform-stack-monitoring-ng
gh repo clone boatsgroup/iac-terragrunt-core-infra

# 6. Clone all XRD repos
for repo in crossplane-xrd-irsa-role crossplane-xrd-karpenter-node-role \
            crossplane-xrd-s3-bucket crossplane-xrd-sqs-eventbridge \
            crossplane-xrd-gateway-nlb-listener crossplane-xrd-generated-aws-secret \
            crossplane-xrd-github-oidc crossplane-xrd-ingress-acm-certificate; do
  gh repo clone boatsgroup/$repo
done

# 7. Clone utility repos
gh repo clone boatsgroup/argocd-env-generator
gh repo clone boatsgroup/helm-charts

# 8. Verify everything
ls -la  # Should show 20 directories

# 9. Install command pack (automatically builds TypeScript validators)
bash mobius-tools/scripts/install-command-pack.sh --force

# 10. See what commands are available
/mobius:help
```

### Option C: Core + GitOps Only

For work that only touches the core control plane and GitOps repos:

```bash
mkdir ~/repos/mobius && cd ~/repos/mobius
gh repo clone boatsgroup/mobius-tools
gh repo clone boatsgroup/iac-eks-argocd
gh repo clone boatsgroup/iac-eks-crossplane
gh repo clone boatsgroup/iac-eks-addons
gh repo clone boatsgroup/iac-eks-observability

# Install command pack (automatically builds TypeScript validators)
bash mobius-tools/scripts/install-command-pack.sh --force

/mobius:help
```

---

## Optional: Automating the Bootstrap

The resolver runs automatically when an AI agent reads `AGENTS.md` — no extra
setup required. For engineers who prefer to pre-wire dependencies before opening
a session, the resolver can be invoked directly at any time:

```bash
# From inside any Mobius repo that has AGENTS.md frontmatter:
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
bash ../mobius-tools/scripts/resolve-deps.sh
```

The resolver writes a daily session marker (`/tmp/mobius-resolved-{uid}-{date}`)
so re-running it in the same day is a no-op — it safely skips repos already
resolved. There is no separate per-machine install script; `resolve-deps.sh` is
the only entry point needed.

---

## Mental Model Pass (Recommended Before Multi-Repo Changes)

Before editing files across repos, spend 2 minutes building context:

1. Run `/mobius:help` to see all available commands.
2. Read the [Docs Mind Map](ecosystem-start-here.md) for navigating all platform docs.
3. Read the [Platform Overview](architecture/platform-overview.md) for how the system works end-to-end.
4. Read the [Glossary](glossary.md) if terms like "addon", "overlay", or "spoke" are unfamiliar.

For the full ecosystem topology: [Ecosystem Map](../ecosystem/master-map.md)

---

## How It Works (5 Steps)

Understanding the system helps you debug problems and extend it correctly.

### Step 1: Every Repo Declares Its Dependencies

Each Mobius repo's `AGENTS.md` starts with YAML frontmatter:

```yaml
---
mobius:
  repo: iac-eks-addons
  org: boatsgroup
  dependencies:
    - iac-eks-argocd
    - iac-eks-crossplane
---
```

This is the runtime manifest — it tells the resolver exactly what repos this
repo needs to function.

### Step 2: Agent Reads AGENTS.md First

When Claude Code (or any AI agent) starts a session, it reads `AGENTS.md` as
its first action. The frontmatter and the "Cross-Repo Bootstrap" section
instruct it to run the resolver.

### Step 3: Resolver Finds or Clones Dependencies

`bash ../mobius-tools/scripts/resolve-deps.sh` runs four operations:

1. **Parse** — extracts the dependency list from AGENTS.md frontmatter
2. **Discover** — checks `../dep-name/` (sibling directory) for each dep
3. **Clone or Freshen** — clones if missing, or `git pull --ff-only` if present and clean
4. **Update** — merges resolved paths into `.claude/settings.local.json`

### Step 4: Claude Code Gets Native File Access

The resolver updates `additionalDirectories` in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "additionalDirectories": [
      "/Users/you/repos/mobius/iac-eks-argocd",
      "/Users/you/repos/mobius/iac-eks-crossplane"
    ]
  }
}
```

Claude Code now has read/write access to those directories as if they were
part of the current repo. The agent can branch, commit, and PR across repos.

### Step 5: Read Ecosystem Context

After resolution, read cross-repo context in this order:

1. This repo's `.claude/ecosystem.md` — the repo's own perspective
2. `../mobius-tools/ecosystem/master-map.md` — the full platform picture
3. Each dependency's `.claude/ecosystem.md` — their perspective
4. Relevant `.claude/skills/*/SKILL.md` — procedural checklists

---

## Platform Overview (Quick Reference)

The platform repos are organized in 6 tiers:

| Tier | Repos | What They Do |
|------|-------|-------------|
| **core** (2) | iac-eks-argocd, iac-eks-crossplane | Control plane triad |
| **gitops** (2) | iac-eks-addons, iac-eks-observability | GitOps deployment repos |
| **infrastructure** (5) | terraform-module-core-irsa, terraform-module-eks, terraform-module-delegated-zone, terraform-stack-monitoring-ng, iac-terragrunt-core-infra | Terraform + bootstrap |
| **xrd** (8) | crossplane-xrd-* | Kubernetes-native AWS resource APIs |
| **utility** (2) | argocd-env-generator, helm-charts | Developer tooling |
| **meta** (1) | mobius-tools | This SDK |

> **All generative commands include a built-in git workflow**: JIRA ticket
> prompt, feature branch creation, commit, push, and PR creation are handled
> automatically. You don't need to manage git operations separately — the
> command does it for you.

For the full platform map, see:
`../mobius-tools/ecosystem/master-map.md`

---

## Common First Tasks

Use `/mobius:help` to see all available commands. Here are the most common tasks
new engineers encounter and the command that handles them.

### "I need to deploy a new service to EKS"

```
/mobius:add-service
```

The command walks you through intake, generates all files across repos
(service repo + iac-eks-argocd), validates the output, creates branches,
commits, and opens PRs. It handles JIRA ticket integration, branch creation,
and merge order automatically.

- Handles: Helm chart selection, IRSA roles, per-environment overlays, ApplicationSet wiring
- Repos touched: service repo (e.g., `iac-eks-addons`) + `iac-eks-argocd`
- Workflow doc: `docs/workflows/services/add-service.md`

### "I need to create a new Crossplane resource type"

```
/mobius:new-xrd
```

Creates a new KCL-based XRD repo from scratch, registers it in
`iac-eks-crossplane`, and updates the ecosystem graph.

- Handles: XRD definition, KCL composition, OCI packaging, platform registration
- Repos touched: new `crossplane-xrd-<name>` repo + `iac-eks-crossplane` + `mobius-tools`
- Workflow doc: `docs/workflows/xrd/new-xrd.md`

### "I need to add an ArgoCD project or ApplicationSet"

```
/mobius:new-project
```

Creates project RBAC and/or ApplicationSet discovery configuration
in `iac-eks-argocd`.

- Handles: Project permissions, ApplicationSet generator setup, kustomization wiring
- Repos touched: `iac-eks-argocd`

### "I need to set up a new hub cluster"

```
/mobius:new-hub
```

Bootstraps a new ArgoCD hub cluster with infrastructure, control plane,
and optional monitoring across 3-5 repos.

- Handles: Terragrunt config, ArgoCD hub structure, Crossplane environment, monitoring
- Repos touched: `iac-terragrunt-core-infra`, `iac-eks-argocd`, `iac-eks-crossplane`, and optionally monitoring repos

### "I need to register a new spoke cluster"

```
/mobius:new-spoke
```

Registers a new spoke EKS cluster under an existing hub with full
cross-repo wiring.

- Handles: IAM trust chain, ArgoCD registration, addon overlays, Crossplane config
- Repos touched: `iac-terragrunt-core-infra`, `iac-eks-argocd`, `iac-eks-addons`, `iac-eks-crossplane`, and optionally observability/monitoring

### "I need to migrate an ECS service to EKS"

```
/mobius:migrate-ecs-service
```

Discovers the ECS service configuration, maps it to EKS equivalents,
generates GitOps manifests, and validates parity.

- Handles: ECS extraction, config mapping, Helm generation, parity validation, cutover runbook
- Repos touched: `helm-charts` + `iac-eks-argocd`
- Workflow doc: `docs/workflows/migration/migrate-ecs-service.md`

### "Something is broken — I need to debug"

```
/mobius:debug-service api-node-payments --env bg-qa
```

Auto-diagnoses across ArgoCD, Kubernetes, Crossplane, and dependency
controllers. Produces a structured report with actionable fixes.

For ApplicationSet discovery issues specifically:

```
/mobius:debug-appset core-infrastructure
```

### "I want to validate a service after changes"

```
/mobius:validate-service api-node-payments --service-repo ../helm-charts
```

Audits a service for build correctness, structural completeness, and
convention compliance. Works on local checkouts or PR branches.

### "I need to add a new AWS IAM permission for an existing service"

This is the one task that doesn't have a dedicated command yet — it's a
manual edit:

```
Repo: terraform-module-core-irsa
File: modules/{service}/iam.tf
Action: Add IAM policy statement to the role's policy
```

After editing, create a branch, commit, and open a PR in `terraform-module-core-irsa`.

---

## Troubleshooting

See `../mobius-tools/docs/troubleshooting.md` for common issues and fixes.

Quick checks:

```bash
# Verify gh is authenticated
gh auth status

# Verify jq is installed
jq --version

# Re-run resolver manually
bash ../mobius-tools/scripts/resolve-deps.sh

# Check drift between frontmatter and graph
npx mobius-validate-graph
```

---

## Getting Help

| I need... | Where to look |
|-----------|--------------|
| List of all commands | `/mobius:help` |
| How the platform works | [Platform Overview](architecture/platform-overview.md) |
| Full ecosystem topology | [Ecosystem Map](../ecosystem/master-map.md) |
| Navigate all docs | [Docs Mind Map](ecosystem-start-here.md) |
| Workflow for a specific task | [Workflow Index](workflows/INDEX.md) |
| How the resolver works | [Resolver Architecture](architecture.md) |
| Why a decision was made | [Design Decisions](decisions/) |
| Terminology questions | [Glossary](glossary.md) |
| Debugging issues | [Troubleshooting](troubleshooting.md) |
| Agent/Codex behavior | [Agent Interop](agent-interop.md) |
