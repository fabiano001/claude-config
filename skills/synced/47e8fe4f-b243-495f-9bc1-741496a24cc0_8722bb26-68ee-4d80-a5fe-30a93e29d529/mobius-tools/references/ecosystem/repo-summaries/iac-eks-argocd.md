# iac-eks-argocd

**Role**: Control plane hub — the ArgoCD hub-spoke configuration that manages
all EKS cluster addons across every environment.

**Tier**: core

## What It Does

Hosts all ApplicationSets and ArgoCD Application manifests that deploy addons
to EKS clusters. Uses a hub-spoke model: the hub cluster runs ArgoCD and
manages both itself and all spoke clusters. Cluster secrets are stored here,
enabling ArgoCD to push to spoke clusters. All sync-wave ordering is enforced
through annotations on Application resources.

## Key Files

| File | Purpose |
|------|---------|
| `applicationsets/core-infrastructure/` | ApplicationSet definitions (Git File Generator pattern) |
| `hubs/{hub}/` | Per-hub bootstrap: parent app, environment configs, cluster secrets |
| `hubs/{hub}/clusters/{spoke}.yaml` | Cluster secret for spoke cluster |
| `CLAUDE.md` | Conventions guide |
| `.claude/skills/argocd-project-guard/SKILL.md` | Skill: ArgoCD project RBAC management |
| `.claude/skills/argocd-applicationset-wiring/SKILL.md` | Skill: wiring new ApplicationSets |

## Upstream (depends on)

- **iac-eks-addons** — ApplicationSets discover configs from this repo
- **iac-eks-observability** — observability configs discovered from this repo
- **iac-eks-crossplane** — Crossplane Configuration CRs deployed from here reference iac-eks-crossplane

## Downstream (consumed by)

- **iac-terragrunt-core-infra** — references ArgoCD for bootstrap
- **argocd-env-generator** — reads ApplicationSets to discover repo/service topology
- All XRD repos — Configuration CRs flow through ArgoCD

## Critical Conventions

- ApplicationSet Git File Generator pattern: `argocd/{addon}/overlays/*/config.yaml`
- Hub bootstrap under `hubs/{hub}/bootstrap/`
- Project guards prevent cross-project resource access
- Sync waves enforced at annotation level, not ApplicationSet level
