# iac-terragrunt-core-infra

**Role**: Bootstrap / provisioning — Terragrunt-based multi-account AWS
infrastructure that provisions EKS clusters and their prerequisite resources.

**Tier**: infrastructure

## What It Does

Uses Terragrunt to orchestrate Terraform modules across multiple AWS accounts
(bg-prod, bg-qa, bg-dev, etc.). Provisions VPCs, EKS clusters, IAM roles,
and the initial node groups. The output feeds into the GitOps layer
(iac-eks-addons, iac-eks-observability) which then manages the addon layer.
Terragrunt handles remote state in S3 and dependency ordering between modules.

## Key Files

| File | Purpose |
|------|---------|
| `aws/accounts/{account}/` | Per-account Terragrunt configurations |
| `aws/accounts/{account}/{cluster}/eks/terragrunt.hcl` | EKS cluster definition |
| `aws/accounts/{account}/{cluster}/vpc/terragrunt.hcl` | VPC definition |
| `terragrunt.hcl` | Root config (remote state, provider auth) |
| `CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective |

## Upstream (depends on)

- **terraform-module-core-irsa** — calls IRSA module for IAM role creation
- **iac-eks-argocd** — references ArgoCD for cluster addon bootstrap

## Downstream (consumed by)

- Nobody — this is the bottom of the dependency graph for infrastructure provisioning
- EKS clusters are the output, consumed by everything else

## Known Inconsistencies

- State bucket naming: `bg-{account}` vs `{account}` — varies by account
- Directory typo: `bq-qa-eks-core-addons` should be `bg-qa` — do not rename without coordination
- EKS module version drift: v0.0.14 vs v0.0.15 across accounts

## Critical Conventions

- Always use `terragrunt run-all plan` before apply
- Remote state in S3 with DynamoDB locking
- AWS auth via `aws-vault` or environment variables
