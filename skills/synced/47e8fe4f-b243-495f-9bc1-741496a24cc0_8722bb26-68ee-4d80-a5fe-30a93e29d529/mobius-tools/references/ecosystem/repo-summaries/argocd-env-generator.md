# argocd-env-generator

**Role**: Environment generation CLI — a Go tool that automates stamping out
complete multi-repo environment overlays by reading ApplicationSets and copying
existing environment directories with literal string substitution.

**Tier**: utility

## What It Does

When creating a new EKS environment (spoke or hub), the operator must create
overlay directories in iac-eks-addons, iac-eks-crossplane, iac-eks-observability,
and iac-eks-argocd — potentially dozens of directories. This tool automates
that: it reads ApplicationSets to discover which repos and services exist, finds
the reference environment's overlay directories, copies them to the target
location, and applies string replacements (env name, account ID, OIDC ID).
Output goes to a staging directory for review before committing to repos.

## Key Files

| File | Purpose |
|------|---------|
| `cmd/` | CLI entry point |
| `internal/generator/` | Core generation logic (copy + replace) |
| `internal/config/` | Config file parsing |
| `Makefile` | Build: `make build` -> `bin/spoke-generator` |
| `CLAUDE.md` | CLI usage and architecture guide |
| `.claude/ecosystem.md` | Cross-repo interaction map |

## Upstream (depends on)

- **iac-eks-argocd** — reads ApplicationSets to discover repo/service topology

## Downstream (consumed by)

- Platform operators when creating new environments (nobody automates it)

## Known Issues

- Binary named `spoke-generator` but module/repo is `argocd-env-generator`
- `globalExcludeFiles` option defined but not implemented
- Replacement order is non-deterministic (Go map) — use non-overlapping keys
- Hub bootstrap hardcodes `us-east-1`

## Critical Conventions

- Always run `discover` before `generate` to verify service count
- Use fully-qualified replacement strings (e.g., `bg-qa` not `qa`)
- Output goes to `outputs/{target}/` — manually copy to repos after review
- Run `kustomize build` on outputs before committing
