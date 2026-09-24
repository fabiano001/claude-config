# iac-eks-observability

**Role**: GitOps observability stack deployment — Prometheus, Grafana, and Loki
manifests deployed via ArgoCD across all EKS clusters.

**Tier**: gitops

## What It Does

Contains all the GitOps manifests for the complete observability stack
(kube-prometheus-stack, Loki, Grafana). Each environment gets an overlay under
`argocd/overlays/{env}/` with environment-specific values. This repo handles
the ArgoCD Application definitions and Kustomize overlays for deploying the
monitoring stack, while the underlying Terraform resources (S3 buckets, IRSA
roles for Grafana, Prometheus remote write, Loki S3) are managed separately
in terraform-stack-monitoring-ng.

## Key Files

| File | Purpose |
|------|---------|
| `argocd/overlays/{env}/` | Per-environment monitoring configuration |
| `argocd/base/` | Kustomize base for monitoring stack |
| `dashboards/` | Grafana dashboard JSON files |
| `alerting/` | Prometheus alerting rules |
| `CLAUDE.md` | Conventions guide |
| `.claude/ecosystem.md` | Repo's own perspective |
| `.claude/skills/observability-addon/SKILL.md` | Skill: adding monitoring to new environments |

## Upstream (depends on)

- **iac-eks-argocd** — monitoring apps deployed as ArgoCD Applications
- **iac-eks-addons** — observability depends on core addon infrastructure (cert-manager, external-secrets, etc.)

## Downstream (consumed by)

- EKS clusters directly — no other Mobius repos depend on observability
- Platform operators — for observability into all other components

## OTEL Collector

`argocd/otel-collector/` deploys the OpenTelemetry Collector as a DaemonSet to every
cluster. The base config is used by ops-prod and ops-qa (hub clusters); bg-dev, bg-qa,
and bg-prod each have a **standalone** `config:` in their overlay that fully overrides
the base — they do not inherit from base.

### Spanmetrics → Mimir name translation

The `spanmetrics` connector exports via `otlphttp/mimir` (OTLP protocol). Mimir applies a
namespace prefix at ingestion. Metric names in Mimir are:

| Connector output | Mimir metric name |
|---|---|
| `calls` | `traces_span_metrics_calls` |
| `duration` histogram | `traces_span_metrics_duration_bucket/count/sum` |

Duration is in **seconds** — multiply `histogram_quantile` by 1000 for ms panels.

### `deployment_environment` label requirement

The `spanmetrics` connector reads span-level attributes only. `deployment_environment` is
set by `otel-sdk-node` as a resource attribute and must be explicitly promoted:

```yaml
processors:
  attributes/promote_deployment_env:
    actions:
      - key: deployment_environment
        from_attribute: deployment_environment
        action: upsert

service:
  pipelines:
    traces:
      processors: [memory_limiter, attributes/promote_deployment_env, resource, batch]
```

This processor must be in **every** overlay that defines a standalone `config:` block
(bg-dev, bg-qa, bg-prod) as well as the base (for ops-prod, ops-qa).

The app must also set `DEPLOY_ENV` in its Helm overlay `env:` block. If unset, `otel-sdk-node`
falls back to a hardcoded default (`bg-dev`), causing all spans to report the wrong environment.

## Critical Conventions

- Each environment needs its own overlay with cluster-specific values
- Grafana datasources configured per environment (different Prometheus endpoints)
- Loki S3 bucket name follows pattern: `{cluster}-loki-logs`
- IRSA role for Loki: `{cluster}-loki`, for Grafana: `{cluster}-grafana`
- Terraform infrastructure managed separately in terraform-stack-monitoring-ng
