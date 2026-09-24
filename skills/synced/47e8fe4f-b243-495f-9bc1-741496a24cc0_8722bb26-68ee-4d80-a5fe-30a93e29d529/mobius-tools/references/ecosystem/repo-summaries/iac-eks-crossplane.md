# iac-eks-crossplane

**Role**: Composition factory — the central Crossplane configuration repo hosting
all providers, functions, and Configuration CRs that register XRDs on clusters.

**Tier**: core

## What It Does

Deploys and manages the entire Crossplane runtime: operators, providers
(provider-aws, provider-kubernetes), and functions (function-kcl,
function-password-generator, function-patch-and-transform, function-auto-ready).
Also hosts the `Configuration` Custom Resources that reference OCI packages from
the `crossplane-xrd-*` repos — these are the glue that registers each XRD and
its Composition in every cluster that ArgoCD manages.

## Key Files

| File | Purpose |
|------|---------|
| `crossplane/providers/` | Provider CRs (provider-aws-*, provider-kubernetes) |
| `crossplane/functions/` | Function CRs (function-kcl, function-auto-ready, etc.) |
| `crossplane/configurations/` | Configuration CRs referencing OCI packages from xrd repos |
| `argocd/overlays/{env}/` | Per-environment kustomization overlays |
| `CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective |

## Upstream (depends on)

- **iac-eks-argocd** — ArgoCD deploys all resources from this repo to clusters

## Downstream (consumed by)

- All `crossplane-xrd-*` repos — every XRD's Configuration CR lives here
- **iac-eks-addons** — Crossplane claims in addons point to XRDs registered here

## Critical Conventions

- `skipDependencyResolution: true` MUST be set in every Configuration CR
- Provider and function versions are pinned — bump deliberately
- Do NOT add new Go-template XRDs here; use new `crossplane-xrd-*` repos with KCL
- Sync wave ordering: providers (-8), functions (-7), configurations (-4)
