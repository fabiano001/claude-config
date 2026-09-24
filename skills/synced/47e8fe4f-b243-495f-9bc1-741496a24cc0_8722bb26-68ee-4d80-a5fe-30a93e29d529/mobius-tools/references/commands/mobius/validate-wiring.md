---
name: validate-wiring
description: Validate post-execution file wiring across repos after a workflow completes
argument-hint: <type> <name> --service-repo <path> [--strict] [--output json]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Validate Wiring

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or OpenAI `o3-mini`).
>
> Wiring validation is deterministic — the TypeScript validator checks that
> all expected files were created in the correct locations. The agent presents
> results and suggests fixes for missing wiring.

This command validates that a workflow's **output files are correctly wired**
across repos after execution. It's the post-execution counterpart to
`/mobius:validate-intake` (pre-execution).

It catches:
- Missing files that should have been created (overlays, kustomization.yaml, config.yaml)
- Files created in wrong locations or with wrong names
- Missing cross-repo references (ApplicationSet files, IRSA claims)
- Incomplete environment coverage (some overlays created, others missed)
- Broken kustomize build after file generation

---

## Supported Wiring Types

| Type | After Which Command | What It Validates |
|------|---------------------|-------------------|
| `add-service` | `/mobius:add-service` | Service directory structure, overlays, ApplicationSet, gateway config |
| `migration` | `/mobius:migrate-ecs-service` | Migrated service files, config mapping, feature parity |
| `new-hub` | `/mobius:new-hub` | Hub cluster files across 3-5 repos (ArgoCD, Crossplane, monitoring) |
| `new-spoke` | `/mobius:new-spoke` | Spoke cluster files across 4-6 repos (registration, overlays, Crossplane, monitoring) |

---

## CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `<type>` | Wiring type (required): add-service, migration, new-hub, new-spoke | — |
| `<name>` | Service/cluster name (required) | — |
| `--service-repo PATH` | Path to the service repo (required) | — |
| `--argocd-repo PATH` | Path to iac-eks-argocd repo | auto-discovered |
| `--crossplane-repo PATH` | Path to iac-eks-crossplane repo (new-hub/new-spoke) | auto-discovered |
| `--monitoring-repo PATH` | Path to terraform-stack-monitoring-ng (new-hub/new-spoke) | auto-discovered |
| `--envs ENV1,ENV2` | Target environments | auto-discovered |
| `--strict` | Treat warnings as failures | off |
| `--output FORMAT` | Output format: `text` or `json` | text |

---

## Execution Flow

### Step 1: Identify what was executed

Ask the user (if not clear from context):

```
Which workflow did you just run, and what was the service/cluster name?
```

### Step 2: Run the validator

```bash
npx mobius-validate-wiring <type> <name> --service-repo <path> [--strict] [--output json]
```

For multi-repo workflows (new-hub, new-spoke), pass all repo paths:

```bash
npx mobius-validate-wiring new-spoke bg-spoke-3 \
  --service-repo ../iac-eks-addons \
  --argocd-repo ../iac-eks-argocd \
  --crossplane-repo ../iac-eks-crossplane \
  --monitoring-repo ../terraform-stack-monitoring-ng
```

### Step 3: Interpret results

If the validator reports failures, provide:
- **What's missing**: The specific file or cross-repo reference
- **Where it should be**: Exact path and repo
- **How to fix**: Either run the workflow step again or manually create the file

### Step 4: Verify fixes

After the user resolves issues:

```
Run again to verify all wiring is complete:
  npx mobius-validate-wiring <type> <name> --service-repo <path> --strict
```

---

## Examples

### Validate add-service wiring

```
/mobius:validate-wiring add-service my-api --service-repo ../helm-charts
```

### Validate migration wiring

```
/mobius:validate-wiring migration api-node-payments --service-repo ../helm-charts
```

### Validate new-hub wiring (multi-repo)

```
/mobius:validate-wiring new-hub bg-hub-west \
  --service-repo ../iac-eks-addons \
  --argocd-repo ../iac-eks-argocd \
  --crossplane-repo ../iac-eks-crossplane
```

### Validate new-spoke wiring (multi-repo)

```
/mobius:validate-wiring new-spoke bg-spoke-3 \
  --service-repo ../iac-eks-addons \
  --argocd-repo ../iac-eks-argocd \
  --crossplane-repo ../iac-eks-crossplane \
  --monitoring-repo ../terraform-stack-monitoring-ng
```

### Strict mode for CI

```
/mobius:validate-wiring add-service my-api --service-repo ../helm-charts --strict --output json
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:validate-intake` | Pre-execution counterpart — validates input before workflow runs |
| `/mobius:validate-service` | Deeper service audit — conventions, build, security, scheduling |
| `/mobius:add-service` | Creates service files; validate-wiring checks they're complete |
| `/mobius:new-hub` | Creates hub files across repos; validate-wiring checks all repos |
| `/mobius:new-spoke` | Creates spoke files across repos; validate-wiring checks all repos |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: validation

**Context hints**:
- "Impact opener" → state which workflow's output was validated and how many issues found
- "What was accomplished" → describe which files were checked across which repos
- "Why it matters" → explain what would be broken if the missing wiring isn't fixed
- "What happens next" → create missing files or re-run the workflow step

**Repo breakdown guidance**:
- List each repo that was checked and what files were expected vs found
- Explain what each repo's files do in the deployment pipeline
