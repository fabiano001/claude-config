# helm-charts

**Role**: Shared Helm charts — common Helm chart configurations used across
EKS clusters, including addon charts that wrap upstream Helm releases.

**Tier**: utility

## What It Does

Hosts Helm chart configurations (values files, chart wrappers) for addons
deployed across the platform. Rather than each environment repeating Helm
values, this repo provides base chart configurations that environments
override. The envoy-gateway addon lives here, as do other platform-level
Helm configurations. Charts are referenced by ArgoCD Applications in
iac-eks-argocd.

## Key Files

| File | Purpose |
|------|---------|
| `charts/` | Helm chart directories |
| `charts/envoy-gateway/` | Envoy Gateway chart configuration |
| `.claude/ecosystem.md` | Repo's own perspective |
| `CLAUDE.md` | Chart conventions guide |

## Upstream (depends on)

- Nothing — helm-charts has no declared Mobius dependencies

## Downstream (consumed by)

- **iac-eks-argocd** — references charts from this repo in Application specs
- **crossplane-xrd-gateway-nlb-listener** — the envoy-gateway addon creates GatewayNLBListener claims
- All EKS clusters — via ArgoCD-deployed Helm releases

## Critical Conventions

- Helm chart versions pinned in Chart.yaml
- Values override pattern: base chart values + per-environment overlay values
- Envoy Gateway addon: one GatewayNLBListener claim per cluster
- No platform logic in charts — keep them as wrappers around upstream charts
