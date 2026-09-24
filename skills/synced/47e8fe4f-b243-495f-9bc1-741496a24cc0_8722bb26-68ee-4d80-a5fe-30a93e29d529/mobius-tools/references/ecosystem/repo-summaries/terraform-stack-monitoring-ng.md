# terraform-stack-monitoring-ng

**Role**: Monitoring Terraform infrastructure (Terraform-only) — Terraform
resources for the observability stack (S3 buckets, IAM roles, AWS resources).

**Tier**: infrastructure

## What It Does

Provisions the Terraform infrastructure needed by the monitoring stack:
S3 buckets for Loki logs, IRSA roles for Grafana and Prometheus remote write,
KMS keys for encryption, and other AWS resources. This is a pure Terraform
repository containing only `.tf` files. The GitOps deployment manifests
(ArgoCD Applications, Kustomize overlays for kube-prometheus-stack/Loki/Grafana)
have been moved to `iac-eks-observability`.

## Key Files

| File | Purpose |
|------|---------|
| `terraform/` | Terraform modules and resources |
| `modules/loki-s3/` | S3 bucket for Loki logs |
| `modules/grafana-irsa/` | IRSA role for Grafana |
| `docs/CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective |
| `.claude/skills/monitoring-terraform/SKILL.md` | Skill: adding monitoring Terraform resources |

## Upstream (depends on)

- Nothing — this is a pure Terraform module with no dependencies

## Downstream (consumed by)

- **iac-eks-observability** — references Terraform outputs for monitoring deployment
- EKS clusters directly — for monitoring infrastructure (S3 buckets, IAM roles)

## Critical Conventions

- This is a Terraform-only repository — no ArgoCD/Kustomize files
- GitOps deployment manifests live in iac-eks-observability
- Loki S3 bucket name follows pattern: `{cluster}-loki-logs`
- IRSA role for Loki: `{cluster}-loki`, for Grafana: `{cluster}-grafana`
