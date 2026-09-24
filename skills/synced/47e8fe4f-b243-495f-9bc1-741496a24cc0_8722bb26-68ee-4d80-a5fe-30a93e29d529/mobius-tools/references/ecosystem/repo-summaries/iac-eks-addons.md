# iac-eks-addons

**Role**: GitOps EKS service deployment repo (internal addon workflow) —
self-service manifests and Crossplane claims deployed via ArgoCD ApplicationSets.

**Tier**: gitops

## What It Does

This repo contains all the GitOps manifests for deploying EKS services.
Teams self-service by adding `config.yaml` files under overlay directories,
which ArgoCD ApplicationSets auto-discover. Contains Kustomize bases and overlays
for addon deployments, Crossplane claim templates, and environment-specific
configurations. This is where engineers add new service deployments without
touching ArgoCD or Terraform directly.

## Key Files

| File | Purpose |
|------|---------|
| `argocd/{addon}/base/` | Kustomize base for each addon |
| `argocd/{addon}/overlays/{env}/config.yaml` | Self-service config file (teams add these) |
| `argocd/{addon}/overlays/{env}/kustomization.yaml` | Environment-specific overlay |
| `claims/{addon}/` | Crossplane claim templates |
| `CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective |
| `.claude/skills/addons-environment/SKILL.md` | Skill: adding new environment overlay |

## Upstream (depends on)

- **iac-eks-argocd** — ApplicationSets live there; addon configs are discovered by ArgoCD
- **iac-eks-crossplane** — Crossplane claims in this repo reference XRDs registered there

## Downstream (consumed by)

- **iac-eks-observability** — observability stack depends on addon infrastructure
- **crossplane-xrd-irsa-role** — xrd claims are created here
- **crossplane-xrd-karpenter-node-role** — same pattern

## Critical Conventions

- `testBranch` in config.yaml only takes effect on **main** branch
- Overlay path pattern: `argocd/{addon}/overlays/{env}/config.yaml`
- `addon` remains the internal path/schema term; docs may describe it as service deployment
- Never modify ApplicationSet files unless adding a new app category
- All addon deployments follow Kustomize base + overlay pattern
