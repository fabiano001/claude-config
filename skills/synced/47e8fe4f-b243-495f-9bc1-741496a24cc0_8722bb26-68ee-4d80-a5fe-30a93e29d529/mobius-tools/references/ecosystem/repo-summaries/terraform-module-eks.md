# terraform-module-eks

**Role**: EKS cluster Terraform module — creates EKS clusters, OIDC providers,
access entries, and node groups.

**Tier**: infrastructure

## What It Does

Provisions AWS EKS clusters with all supporting resources: OIDC identity
providers (for IRSA), managed node groups, access entries for IAM-based
cluster authentication, security groups, and KMS encryption. This is the
foundational module that creates the clusters everything else deploys to.

## Key Files

| File | Purpose |
|------|---------|
| `README.md` | Module documentation and usage examples |
| `EKS_ACCESS_CONTROL.md` | How IAM access entries and OIDC providers are configured |
| `EKS_UPGRADE_RUNBOOK.md` | Step-by-step EKS version upgrade procedure |

## Upstream (depends on)

*(none)* — standalone Terraform module.

## Downstream (consumed by)

- **iac-terragrunt-core-infra** — calls this module to provision EKS clusters

## Critical Conventions

- Module versioning controlled by Terraform module registry / git tags
- OIDC provider output is consumed by IRSA roles (terraform-module-core-irsa and Crossplane XIRSARole)
- Access entries replace the deprecated `aws-auth` ConfigMap pattern
