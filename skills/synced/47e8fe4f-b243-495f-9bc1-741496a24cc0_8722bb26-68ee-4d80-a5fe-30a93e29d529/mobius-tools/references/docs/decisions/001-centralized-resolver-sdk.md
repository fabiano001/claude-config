# ADR-001: Centralized Resolver SDK in mobius-tools

**Status**: Accepted

**Date**: 2025-01-15

## Context

The Mobius platform consists of 20 interdependent repositories across multiple tiers: core infrastructure (Terraform), GitOps manifests (ArgoCD/Kustomize), Crossplane XRD repos, and utility repos. When an AI agent or engineer starts work in any repository, they need access to sibling repos to reason correctly about changes.

Early iterations placed dependency resolution logic in individual repos — each repo had its own script to clone and initialize dependencies. This created:
- 18 copies of resolver logic to maintain
- 18 separate pull requests whenever the resolver logic evolved
- Drift between repositories as they updated at different rates
- Unnecessary complexity scattered across the platform

## Decision

Centralize ALL dependency resolution logic in a single SDK repository (`mobius-tools`). Individual repositories contain only:
1. YAML frontmatter declaring their dependencies (in `AGENTS.md`)
2. Two lines of bootstrap instructions pointing to `mobius-tools`

The `mobius-tools` SDK provides:
- `scripts/resolve-deps.sh` — main resolver entrypoint
- `ecosystem/dependency-graph.yaml` — authoritative machine-readable dependency graph
- `ecosystem/master-map.md` — portable platform topology and context
- `scripts/validate-graph.sh` — drift detection between declared and actual dependencies

## Consequences

### Positive

- **Single source of truth**: All resolver logic lives in one place. Updates propagate instantly to all repos without waiting for individual PRs.
- **Deterministic bootstrap**: Every agent and engineer follows the same resolution flow regardless of which repo they start in.
- **Reduced drift**: One authoritative graph (`dependency-graph.yaml`) vs. 18 fragmented versions.
- **Lower maintenance burden**: Changes to resolution logic require ONE update, not 18.
- **Agent reliability**: Both Claude and Codex agents bootstrap identically, reducing session-to-session variability.

### Negative

- **Bootstrap dependency**: Developers and agents must clone `mobius-tools` before resolving other dependencies. This adds one extra step to the onboarding flow.
- **Central point of failure**: If `mobius-tools` is unavailable or contains bugs, it blocks all cross-repo work. However, this is mitigated by the SDK's simplicity and extensive testing.

### Neutral

- Repos now declare dependencies in two locations: `AGENTS.md` frontmatter (human-facing) and `ecosystem/dependency-graph.yaml` (machine-readable). Validation via `validate-graph.sh` ensures they stay in sync.
