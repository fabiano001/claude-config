# terraform-module-core-irsa

**Role**: IRSA Terraform module (Terraform-only) — provides the Terraform module
for creating IAM Roles for Service Accounts on EKS.

**Tier**: infrastructure

## What It Does

Provides the Terraform module for creating IAM Roles for Service Accounts (IRSA)
on EKS. This is a pure Terraform module repository containing only `.tf` files
and module logic. The GitOps deployment manifests (ArgoCD ApplicationSets,
Kustomize overlays, Crossplane claims) have been moved to `iac-eks-addons`.
Engineers use this module to define IRSA role Terraform resources.

## Key Files

| File | Purpose |
|------|---------|
| `modules/{addon}/` | IRSA role Terraform module per addon |
| `variables.tf` | Module input variables |
| `outputs.tf` | Module outputs (role ARN, OIDC provider) |
| `CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective on platform relationships |
| `.claude/skills/core-irsa-module/SKILL.md` | Skill: creating IRSA Terraform modules |

## Upstream (depends on)

- Nothing — this is a pure Terraform module with no dependencies

## Downstream (consumed by)

- **iac-terragrunt-core-infra** — calls this module to create IRSA roles during cluster bootstrap
- **iac-eks-addons** — references role outputs for addon deployments

## Critical Conventions

- This is a Terraform-only repository — no ArgoCD/Kustomize files
- GitOps deployment manifests live in iac-eks-addons
- Module follows standard Terraform module structure
- IRSA role naming: `{cluster}-{addon}`
