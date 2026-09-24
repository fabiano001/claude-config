---
name: grafana
description: Debug, create, and explore Grafana dashboards across hub-spoke EKS clusters
argument-hint: [create|debug|explore] [--env <environment>] [--service <service-name>]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Grafana Dashboard Management

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command requires cross-environment reasoning (hub-spoke topology),
> Grafana API interaction, PromQL/LogQL/TraceQL query construction, and
> multi-repo GitOps dashboard deployment. Weaker models may target the
> wrong Grafana instance, generate invalid queries, or place dashboard
> ConfigMaps in the wrong repo path.

This command provides **Grafana dashboard management** for the Mobius EKS
platform. It supports three workflows:

- **Create**: Build new dashboards and deploy them via GitOps
- **Debug**: Troubleshoot existing dashboards (missing data, broken queries, datasource issues)
- **Explore**: Discover existing dashboards, datasources, and service-to-dashboard mapping

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Platform Overview](../../docs/architecture/platform-overview.md) — hub-spoke model, deployment lifecycle
> - [Environment Model](../../docs/architecture/environment-model.md) — cluster-to-environment mapping

### Observability Stack

| Component | Role | Query Language |
|-----------|------|---------------|
| **Mimir** | Long-term metrics storage (Prometheus-compatible) | PromQL |
| **Prometheus** | Short-term metrics scraping (per-cluster) | PromQL |
| **Tempo** | Distributed tracing backend | TraceQL |
| **Loki** | Log aggregation (per-hub) | LogQL |
| **OTEL Collector** | Signal collection and routing (DaemonSet per cluster) | N/A (pipeline) |
| **Grafana** | Visualization and dashboarding (per-hub) | N/A (frontend) |

### Key Repos

| Repo | Role in Dashboard Workflow |
|------|---------------------------|
| `helm-charts` | Dashboard JSONs as ConfigMaps in `argocd<service>/base/` |
| `iac-eks-addons` | Addon-level dashboards and configs |
| `iac-eks-observability` | Observability stack deployment (Grafana, Mimir, Tempo, Prometheus) |
| `iac-eks-argocd` | ApplicationSet wiring and project permissions |

### Dashboard Deployment Model

Dashboards are deployed via **Grafana sidecar** — a sidecar container watches
for ConfigMaps with the label `grafana_dashboard: "1"` and auto-loads them.

```
Dashboard JSON created
    |
    v
Wrapped in ConfigMap (label: grafana_dashboard: "1")
    |
    v
Placed in helm-charts/argocd/<service>/base/ (or overlays/<env>/)
    |
    v
ArgoCD syncs → ConfigMap deployed to cluster
    |
    v
Grafana sidecar detects ConfigMap → Dashboard appears in Grafana UI
```

---

## Prerequisites

### Environment Variables (MANDATORY)

The Grafana API requires authentication tokens. Set these before running:

```bash
# Required — one per hub Grafana instance
export GRAFANA_OPS_QA_TOKEN="<your-ops-qa-service-account-token>"
export GRAFANA_OPS_PROD_TOKEN="<your-ops-prod-service-account-token>"
```

### Verify Token Access

```bash
# Test ops-qa
curl -s -H "Authorization: Bearer $GRAFANA_OPS_QA_TOKEN" \
  https://grafana.qa.ops.bgrp.io/api/org | jq .name

# Test ops-prod
curl -s -H "Authorization: Bearer $GRAFANA_OPS_PROD_TOKEN" \
  https://grafana.prod.ops.bgrp.io/api/org | jq .name
```

If either returns an auth error, request a new service account token from the
platform team.

---

## Phase 0 — Environment Resolution

**Goal:** Determine which Grafana instance to target based on the user's
environment.

### Hub-Spoke Topology

> **Module**: Read [`grafana/environment-reference.md`](grafana/environment-reference.md)
> for the complete environment → hub → Grafana URL mapping, datasource
> configuration, and API patterns.

**Quick reference:**

| Environment | Hub | Grafana URL | Token Env Var |
|-------------|-----|-------------|---------------|
| `ops-qa` | ops-qa | `https://grafana.qa.ops.bgrp.io` | `GRAFANA_OPS_QA_TOKEN` |
| `bg-dev` | ops-qa | `https://grafana.qa.ops.bgrp.io` | `GRAFANA_OPS_QA_TOKEN` |
| `ops-prod` | ops-prod | `https://grafana.prod.ops.bgrp.io` | `GRAFANA_OPS_PROD_TOKEN` |
| `bg-qa` | ops-prod | `https://grafana.prod.ops.bgrp.io` | `GRAFANA_OPS_PROD_TOKEN` |
| `bg-prod` | ops-prod | `https://grafana.prod.ops.bgrp.io` | `GRAFANA_OPS_PROD_TOKEN` |

**Key rule:** `bg-qa` and `bg-prod` spokes are managed by **`ops-prod`**, NOT
`ops-qa`. Only `bg-dev` routes to `ops-qa`.

### Step 0.1: Resolve Target Grafana

```
If user provides --env:
  Map environment → hub → Grafana URL (table above)

If user does NOT provide --env:
  Ask: "Which environment? (ops-qa, ops-prod, bg-dev, bg-qa, bg-prod)"

Verify token:
  curl -s -H "Authorization: Bearer $<TOKEN_ENV_VAR>" \
    <grafana-url>/api/org | jq .name

If token check fails → stop and ask user to set the env var.
```

### Step 0.2: Store Session Context

After resolution, store these values for all subsequent phases:

```
GRAFANA_URL=<resolved-url>
GRAFANA_TOKEN=$<resolved-token-env-var>
GRAFANA_HUB=<ops-qa|ops-prod>
TARGET_ENV=<user-specified-environment>
```

---

## Input & Routing

| Flag | Purpose | Example |
|------|---------|---------|
| `create` | Create a new dashboard | `/mobius:grafana create --service api-node-payments` |
| `debug` | Debug an existing dashboard | `/mobius:grafana debug --env bg-prod` |
| `explore` | Explore existing dashboards and datasources | `/mobius:grafana explore --env ops-qa` |
| `--env` | Target environment | `ops-qa`, `bg-prod`, `bg-dev` |
| `--service` | Service name (for create/debug) | `api-node-payments`, `external-dns` |

### Input Resolution

| User provides | Action |
|---------------|--------|
| Subcommand only | Run Phase 0, then route to workflow |
| Subcommand + `--env` | Resolve env, then route to workflow |
| Subcommand + `--service` | Ask for env if not provided, then route |
| Nothing | Ask: "What would you like to do? (create / debug / explore)" |

### Workflow Routing

| Subcommand | Module |
|------------|--------|
| `create` | Read [`grafana/create-dashboard.md`](grafana/create-dashboard.md) and execute all steps |
| `debug` | Read [`grafana/debug-dashboard.md`](grafana/debug-dashboard.md) and execute all steps |
| `explore` | Read [`grafana/explore-ecosystem.md`](grafana/explore-ecosystem.md) and execute all steps |

---

## Grafana API Read-Only Default

> **All Grafana API calls are READ-ONLY by default.**
>
> The `create` workflow uses the Grafana API for **prototyping only** — to
> preview a dashboard before committing. The permanent deployment path is
> always GitOps (ConfigMap → ArgoCD sync → sidecar).
>
> The `debug` and `explore` workflows are strictly read-only.

---

## Git Write Policy

> **This command creates files in service repos, not in the observability stack.**
>
> Dashboard ConfigMaps go in `helm-charts/argocd<service>/base/` or
> `iac-eks-addons/argocd/<addon>/base/` — never in `iac-eks-observability`
> (that repo manages the Grafana deployment itself, not dashboard content).

**No direct commits to `main`.** All dashboard changes follow the standard
branch → PR workflow:

1. Create feature branch in the target repo
2. Add/modify dashboard ConfigMap
3. Run `kustomize build` to validate
4. Create PR for review
5. After merge → ArgoCD syncs → Grafana sidecar loads dashboard

---

## Examples

### Create a dashboard for a service

```
/mobius:grafana create --service api-node-payments --env bg-prod
```

### Debug a dashboard with missing data

```
/mobius:grafana debug --env ops-qa
```

### Explore all dashboards in production

```
/mobius:grafana explore --env ops-prod
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:instrument-service` | Generates OTEL instrumentation; dashboards visualize the resulting telemetry |
| `/mobius:debug-service` | Debugs runtime service issues; this command debugs dashboard/observability issues |
| `/mobius:add-service` | Creates service deployments; this command adds dashboards for those services |
| `/mobius:document-iac` | Documents the observability stack in `iac-eks-observability` |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: mixed (diagnostic + generative)

**Context hints**:
- "Impact opener" → state what dashboard action was taken and for which service/environment
- "What was accomplished" → describe the dashboard created, debugged, or discovered
- "Why it matters" → dashboards are the primary observability interface; broken dashboards mean blind spots
- "What happens next" → GitOps sync will deploy the ConfigMap; verify in Grafana UI after sync
