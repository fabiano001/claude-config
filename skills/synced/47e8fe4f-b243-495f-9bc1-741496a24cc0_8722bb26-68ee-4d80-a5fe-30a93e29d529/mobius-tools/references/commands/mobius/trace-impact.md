---
name: trace-impact
description: Analyze blast radius and affected repos before making changes
argument-hint: <repo-name> [--direct-only] [--tier <tier>] [--output json]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Trace Impact

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or OpenAI `o3-mini`).
>
> Impact analysis is deterministic — the TypeScript analyzer does the BFS
> traversal. The agent's role is to present the blast radius clearly and
> advise on risk.

This command performs **blast-radius analysis** — it tells you which repos are
affected (directly and transitively) when you change a given repo. This is a
critical part of the Internal-First Research Protocol (`.claude/skills/internal-first-research/SKILL.md`).

It provides:
- Direct dependents (repos that list the target as a dependency)
- Transitive dependents (repos affected through dependency chains)
- Risk tier classification based on affected repo count and tiers
- Dependency chain paths showing how impact propagates
- Tier filtering to focus on specific repo categories

---

## Why This Matters

In a multi-repo platform, changes to core repos cascade through the dependency
graph. For example:

- Changing `iac-eks-argocd` affects **13 repos** (5 direct, 8 transitive)
- Changing `iac-eks-crossplane` affects **8 XRD repos** that compose on it
- Changing a utility repo like `helm-charts` has limited blast radius

**Hard block**: The Research Protocol requires blast-radius analysis before
any change to core or gitops tier repos. The agent must refuse to edit without
running this analysis first.

---

## Risk Tiers

| Risk Tier | Criteria | Action Required |
|-----------|----------|-----------------|
| **CRITICAL** | 10+ affected repos OR core tier repo affected | Full review, staged rollout |
| **HIGH** | 5-9 affected repos OR gitops tier affected | Review all direct dependents |
| **MEDIUM** | 2-4 affected repos | Review direct dependents |
| **LOW** | 0-1 affected repos | Standard review |

---

## CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `<repo-name>` | Repo to analyze (required) — use the short name from dependency-graph.yaml | — |
| `--direct-only` | Show only direct dependents (skip transitive) | off |
| `--tier TIER` | Filter dependents by tier: core, infrastructure, gitops, xrd, utility, meta | all |
| `--output FORMAT` | Output format: `text` or `json` | text |

---

## Execution Flow

### Step 1: Identify the target repo

If the user doesn't specify a repo, ask:

```
Which repo are you planning to change?
```

Use the short name from the dependency graph (e.g., `iac-eks-argocd`, not the
full GitHub URL).

### Step 2: Run the analyzer

```bash
npx mobius-trace-impact <repo-name>
```

### Step 3: Present the blast radius

The output includes:

```
Impact Analysis: iac-eks-argocd
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Tier:           core
Risk:           CRITICAL
Total affected: 13 repos (5 direct, 8 transitive)

Direct dependents:
  iac-eks-crossplane (infrastructure)
  iac-eks-addons (gitops)
  iac-eks-observability (gitops)
  terraform-stack-monitoring-ng (infrastructure)
  argocd-env-generator (utility)

Transitive dependents:
  crossplane-xrd-irsa-role (xrd) ← via iac-eks-crossplane
  crossplane-xrd-s3-bucket (xrd) ← via iac-eks-crossplane
  ...
```

### Step 4: Advise on risk

Based on the risk tier:
- **CRITICAL/HIGH**: Recommend staged rollout, list all affected repos that need testing
- **MEDIUM**: Note which direct dependents to verify
- **LOW**: Standard change, minimal blast radius

### Step 5: Integrate with Research Protocol

If the user is about to make changes, remind them:

> Before editing this repo, ensure you've completed the Research Protocol:
> 1. Read internal docs for this repo and its dependents
> 2. Trace dependency paths through manifests/charts/modules
> 3. Verify changes won't break downstream repos

---

## Examples

### Check blast radius before editing a core repo

```
/mobius:trace-impact iac-eks-argocd
```

### Check only direct dependents

```
/mobius:trace-impact iac-eks-crossplane --direct-only
```

### Filter by XRD repos only

```
/mobius:trace-impact iac-eks-crossplane --tier xrd
```

### CI/CD integration

```
/mobius:trace-impact iac-eks-argocd --output json
```

### Check a utility repo (low blast radius expected)

```
/mobius:trace-impact helm-charts
```

---

## JSON Output Contract

When `--output json` is used:

```json
{
  "repo": "iac-eks-argocd",
  "tier": "core",
  "risk": "CRITICAL",
  "totalAffected": 13,
  "directCount": 5,
  "transitiveCount": 8,
  "directDependents": [
    { "name": "iac-eks-crossplane", "tier": "infrastructure" },
    { "name": "iac-eks-addons", "tier": "gitops" }
  ],
  "transitiveDependents": [
    { "name": "crossplane-xrd-irsa-role", "tier": "xrd", "via": ["iac-eks-crossplane"] }
  ]
}
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:validate-graph` | Ensures the dependency graph is accurate — run before trace-impact |
| `/mobius:validate-service` | Validates a single service; trace-impact maps cross-repo blast radius |
| `/mobius:debug-service` | Diagnoses runtime issues; trace-impact prevents them proactively |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: analysis

**Context hints**:
- "Impact opener" → state total affected repos and risk tier
- "What was accomplished" → describe the blast radius — direct and transitive dependents
- "Why it matters" → explain the cascading risk and which tiers of the platform are affected
- "What happens next" → read internal docs for affected repos, consider staged rollout

**Repo breakdown guidance**:
- List the most important affected repos with their roles
- Explain dependency chains using → arrows
- Note which repos the engineer should review before making changes
