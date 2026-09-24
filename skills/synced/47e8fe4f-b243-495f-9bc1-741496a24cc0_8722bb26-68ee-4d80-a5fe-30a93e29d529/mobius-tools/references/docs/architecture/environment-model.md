# Environment Model

> How environments, clusters, and overlays relate in the Mobius platform.

---

## Overview

An **environment** in Mobius represents a deployment target — a combination of
an EKS cluster, an AWS account, and a purpose (QA, production, etc.). Each
environment has its own set of Kustomize overlays that customize service
configurations for that specific target.

---

## Current Environments

| Environment | Cluster | Hub | AWS Account | Purpose |
|-------------|---------|-----|-------------|---------|
| `ops-qa` | ops-qa | ops-qa (self) | Operations non-prod | ArgoCD hub for non-production |
| `ops-prod` | ops-prod | ops-prod (self) | Operations prod | ArgoCD hub for production |
| `bg-dev` | bg-dev | ops-qa | BG non-prod | Development workloads |
| `bg-qa` | bg-qa | ops-prod | BG non-prod | QA and staging |
| `bg-prod` | bg-prod | ops-prod | BG prod | Production workloads |

### Naming Convention

- `ops-*` — Operations cluster (runs ArgoCD, monitoring infra)
- `bg-*` — Business Group cluster (runs application workloads)
- `*-qa` / `*-dev` — Non-production
- `*-prod` — Production

Each environment name maps 1:1 to an EKS cluster name and is used consistently
across all repos as the overlay directory name.

---

## Kustomize Overlay Structure

Every service follows the same base + overlay pattern:

```
argocd/<service>/
  base/
    kustomization.yaml     # Helm chart reference, shared values
    values.yaml            # Default Helm values
    xirsarole.yaml         # Base IRSA claim (if needed)
  overlays/
    bg-qa/
      config.yaml          # ← Deployment trigger
      kustomization.yaml   # Inherits from ../../base, adds patches
      values.yaml          # Environment-specific overrides
      xirsarole-patch.yaml # Environment-specific IRSA overrides
    bg-prod/
      config.yaml
      kustomization.yaml
      values.yaml
      xirsarole-patch.yaml
```

### The Base

Contains everything shared across environments:
- Helm chart repository URL and chart name
- Default resource requests/limits
- Default replica count
- Base IRSA claim structure
- Shared configuration that rarely changes between environments

### The Overlay

Contains everything specific to one environment:
- `config.yaml` — triggers ApplicationSet discovery (see below)
- `values.yaml` — environment-specific Helm values (replica counts, resource
  sizing, feature flags, hostnames, certificate ARNs)
- `xirsarole-patch.yaml` — account-specific IAM role configuration
- Additional patches for environment-specific behavior

### config.yaml: The Deployment Trigger

The existence of `config.yaml` in an overlay IS the deployment trigger. When
ArgoCD's ApplicationSet git generator scans the repo and finds this file, it
automatically creates an Application for that service in that environment.

```yaml
# argocd/external-dns/overlays/bg-qa/config.yaml
environment: bg-qa
region: us-east-1
hub: ops-prod
enabled: true
argocd:
  project: core-infrastructure
  namespace: external-dns
  syncWave: "0"
helm:
  repoURL: https://kubernetes-sigs.github.io/external-dns
  chart: external-dns
  version: "1.14.4"
```

**Key fields:**
- `environment`, `hub` — used by cluster generators to target the right cluster
- `argocd.project` — must match an ArgoCD project with correct permissions
- `helm.*` — chart source (must match what the ApplicationSet template expects)
- `enabled` — can be set to `false` to disable without deleting

**Feature branch testing**: Setting `testBranch` in config.yaml tells ArgoCD to
read from a specific branch instead of `main`. This only takes effect when
config.yaml is already on `main`.

---

## Environment-Specific Customizations

### What Typically Differs Between Environments

| Setting | bg-dev | bg-qa | bg-prod |
|---------|--------|-------|---------|
| Replicas | 1 | 2 | 3 |
| CPU requests | 100m | 250m | 500m |
| Memory requests | 128Mi | 256Mi | 512Mi |
| Feature flags | all enabled | selective | conservative |
| Hostnames | *.dev.svc.bgrp.io | *.qa.svc.bgrp.io | *.prod.svc.bgrp.io |
| Certificate ARNs | dev account ACM | non-prod ACM | prod account ACM |
| IRSA role ARNs | dev account roles | non-prod roles | prod account roles |
| ServiceMonitor | disabled | enabled | enabled |
| Log level | debug | info | warn |

### What Stays in the Base

- Helm chart source (repo URL, chart name)
- Probe configuration (readiness, liveness, startup)
- Port definitions
- Security context
- Service type
- Base IRSA claim structure (without account-specific fields)

---

## How Environments Map to the Hub-Spoke Model

```
ops-qa (hub)
  ├── ops-qa (self-managed)
  └── bg-dev (spoke)

ops-prod (hub)
  ├── ops-prod (self-managed)
  ├── bg-qa (spoke)
  └── bg-prod (spoke)
```

Each spoke's overlays are discovered by the hub's ApplicationSets via the
`hub` field in `config.yaml` and cluster labels set during spoke registration.

The spoke's `applicationsets/kustomization.yaml` determines which ApplicationSet
groups (core-infrastructure, api-node, monitoring, etc.) target that spoke.

---

## Adding a New Environment

### Via /mobius:new-spoke

The recommended path. Creates all required files across repos:
1. Infrastructure (EKS cluster, IRSA, spoke registration)
2. ArgoCD (ExternalSecret, ClusterSecretStore, environment directory)
3. Addon overlays (per core addon)
4. Crossplane environment

### Via argocd-env-generator

For adding overlays to an existing spoke for a new service:

```bash
# Stamps out overlay directories for specified environments
argocd-env-generator generate --service <name> --envs bg-qa,bg-prod
```

### Manual

Create the overlay directory structure manually:
1. Copy from an existing environment overlay
2. Replace account IDs, cluster names, OIDC providers, hostnames
3. Add `config.yaml` to trigger discovery
4. Verify with `kustomize build`

---

## Environment Lifecycle

### Deployment Flow

```
1. Overlay exists with config.yaml  →  ApplicationSet discovers it
2. ApplicationSet creates Application  →  ArgoCD syncs to cluster
3. Kustomize builds overlay  →  Helm renders chart with values
4. Resources applied to cluster  →  Pods running
```

### Removing an Environment

To stop deploying a service to an environment:

1. **Soft disable**: Set `enabled: false` in `config.yaml` (keeps files, stops deploy)
2. **Remove overlay**: Delete the overlay directory and merge to `main`
3. ArgoCD ApplicationSet detects the removal and deletes the Application
4. ArgoCD cascades the delete to all managed resources

**Warning**: Cascade deletion removes all Kubernetes resources the Application
managed, including Crossplane claims. Crossplane claims trigger AWS resource
deletion. Verify this is intended before removing overlays for production.

---

## Related Documents

- [Platform Overview](platform-overview.md) — high-level context
- [ArgoCD Hub-Spoke](argocd-hub-spoke.md) — how environments are discovered
- [Workflow: add-service](../workflows/services/add-service.md) — overlay generation
- [Engineer's Guide](../engineer-guide.md) — commands that create overlays
