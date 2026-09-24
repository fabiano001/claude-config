# ArgoCD Hub-Spoke Architecture

> How Mobius uses a centralized ArgoCD control plane to manage multiple
> EKS clusters from a single pane of glass.

---

## Overview

Mobius uses a **hub-spoke model** where one EKS cluster runs the ArgoCD control
plane (the hub) and manages deployments to itself and all remote clusters (the
spokes). Spokes do not run ArgoCD — they are managed entirely by the hub.

```
Hub cluster (e.g., ops-prod):
  ┌──────────────────────────────────────────┐
  │  ArgoCD server + controller + repo-server │
  │  ApplicationSets (git + cluster generators)│
  │  Project RBAC definitions                  │
  │  ExternalSecrets + ClusterSecretStores     │
  └─────────────┬──────────────┬──────────────┘
                │              │
        ┌───────┘              └───────┐
        ▼                              ▼
  Spoke cluster (bg-qa)         Spoke cluster (bg-prod)
  ┌──────────────────┐         ┌──────────────────┐
  │  No ArgoCD       │         │  No ArgoCD       │
  │  Workloads only  │         │  Workloads only  │
  │  Managed by hub  │         │  Managed by hub  │
  └──────────────────┘         └──────────────────┘
```

### Current Topology

| Hub | Manages | Repository |
|-----|---------|------------|
| `ops-qa` | ops-qa (self), bg-dev | `iac-eks-argocd` → `hubs/ops-qa/` |
| `ops-prod` | ops-prod (self), bg-qa, bg-prod | `iac-eks-argocd` → `hubs/ops-prod/` |

---

## Hub Structure in the Repository

Each hub has a dedicated directory tree in `iac-eks-argocd`:

```
hubs/<hub>/
├── kustomization.yaml                    # Hub-level Kustomize patches
├── bootstrap-parent-application.yaml     # Entry point Application (app-of-apps)
├── bootstrap/
│   ├── <region>/values.yaml              # Helm values (IRSA ARNs, ingress, HA)
│   └── resources/
│       ├── base/                         # Per-hub base (ExternalSecret template)
│       │   ├── github-app-credentials.yaml
│       │   └── kustomization.yaml
│       └── overlays/<hub>/
│           ├── config.yaml               # Triggers argocd-resources discovery
│           ├── kustomization.yaml        # Patches ENVIRONMENT_PLACEHOLDER
│           └── clusters/                 # Spoke ExternalSecrets + ClusterSecretStores
│               ├── <spoke>.yaml
│               └── clustersecretstore-<spoke>.yaml
└── environments/
    ├── <hub>/<region>/                   # Hub self-management environment
    │   ├── bootstrap-config.yaml
    │   └── applicationsets/kustomization.yaml
    └── <spoke>/<region>/                 # Per-spoke environment
        ├── bootstrap-config.yaml
        └── applicationsets/kustomization.yaml
```

### Key Files

| File | Purpose |
|------|---------|
| `bootstrap-parent-application.yaml` | The root Application that ArgoCD syncs first. Points to the hub's kustomization. |
| `kustomization.yaml` (hub root) | Patches 3 ApplicationSets with hub-specific paths: argocd-self-mgmt, argocd-resources, bootstrap. |
| `bootstrap-config.yaml` | Per-environment file that the bootstrap ApplicationSet discovers. Contains environment name, region, hub, AWS account, and applicationsets config. |
| `clusters/<spoke>.yaml` | ExternalSecret that fetches spoke cluster credentials from AWS Secrets Manager. |
| `clustersecretstore-<spoke>.yaml` | Grants External Secrets Operator access to the spoke's Secrets Manager via cross-account IAM. |

---

## Spoke Registration

When a new spoke is registered with a hub, these cross-repo changes happen:

### 1. IAM Trust Chain (3-way)

```
Hub ArgoCD Pod
  → assumes Hub IRSA role: <hub>-argocd-hub (hub account)
  → assumes Spoke role: argocd-access (spoke account)
  → authenticates to Spoke EKS API

Hub ExternalSecrets Pod
  → assumes Hub IRSA role: <hub>-external-secrets (hub account)
  → assumes Spoke role: external-secrets-cross-account (spoke account)
  → reads Spoke Secrets Manager
```

Both trust chains require:
- Spoke-side IAM roles with trust policies allowing the hub's IRSA roles
- Hub-side `spoke_account_ids` list updated to include the spoke account
- Spoke EKS `aws-auth` ConfigMap granting the hub's ArgoCD role `system:masters`

### 2. Hub-Side Files (iac-eks-argocd)

- ExternalSecret for spoke cluster credentials
- ClusterSecretStore for cross-account Secrets Manager access
- Update hub kustomization to include new spoke files
- Spoke environment directory with `bootstrap-config.yaml`
- Project destinations updated with spoke's EKS API server URL

### 3. Spoke-Side Files (iac-eks-addons, iac-eks-crossplane)

- Addon overlays per core addon (cilium, external-secrets, external-dns, etc.)
- Crossplane Terraform environment + ArgoCD overlay
- Hub external-secrets IRSA updated with spoke cross-account role ARN

**Command**: `/mobius:new-spoke` automates the full registration flow.

---

## ApplicationSet Patterns

Mobius uses two ApplicationSet generator patterns:

### Git File Generator (Primary)

Discovers services by scanning repos for `config.yaml` files:

```yaml
generators:
  - git:
      repoURL: https://github.com/boatsgroup/iac-eks-addons
      revision: main
      files:
        - path: "argocd/*/overlays/*/config.yaml"
```

The **existence of config.yaml IS the deployment trigger**. No manual Application
creation needed. The generator reads fields from `config.yaml` to parameterize
the Application template (chart version, repo URL, namespace, etc.).

### Cluster Generator via Bootstrap Config

Discovers environments by scanning for `bootstrap-config.yaml`:

```yaml
generators:
  - git:
      repoURL: https://github.com/boatsgroup/iac-eks-argocd
      revision: main
      files:
        - path: "hubs/<hub>/environments/*/*/bootstrap-config.yaml"
```

Combined with cluster label selectors (`hub: <hub>`) to target the correct spoke.

### ApplicationSet Groups

ApplicationSets are organized into groups in `iac-eks-argocd/applicationsets/`:

| Group | What it deploys |
|-------|----------------|
| `core-infrastructure` | Platform addons: cilium, external-secrets, cert-manager, karpenter, etc. |
| `monitoring` | Observability stack: Prometheus, Grafana, Loki, etc. |
| `api-node` | Node.js API services |
| `yachtfocus` | YachtFocus application services |
| `workflow-automation` | CI/CD and automation workloads |
| `workloads` | General workloads (wildcard namespace) |

Each environment's `applicationsets/kustomization.yaml` selects which groups apply
to that cluster. A minimal spoke might only reference `core-infrastructure`, while
a hub references all groups.

---

## Sync Wave Ordering

ArgoCD applications use sync waves to enforce dependency ordering. Lower waves
deploy first:

```
Wave -100: ArgoCD self-management
Wave  -50: ArgoCD resources (ExternalSecrets for cluster credentials)
Wave  -10: ArgoCD projects
Wave    0: Bootstrap ApplicationSet

Within each ApplicationSet's Applications:
Wave  -9: Crossplane operator
Wave  -8: Crossplane providers (provider-aws, provider-kubernetes)
Wave  -7: Crossplane functions (function-kcl)
Wave  -6: External Secrets Operator
Wave  -5: IRSA roles (Terraform module outputs)
Wave  -4: Crossplane Configuration CRs
Wave  -3: XRD + Composition registration
Wave  -2: Composite resource claims
Wave   0: Helm addon deployments
Wave   2: Addon-level configurations
Wave   3: NodePool and Karpenter configs
```

### Why Ordering Matters

- Crossplane providers must exist before Configuration CRs reference them
- Configuration CRs must register XRDs before claims can be processed
- IRSA roles must exist before pods that assume them start
- cert-manager must be running before Certificate resources are created

---

## Project RBAC Model

ArgoCD projects define permission boundaries:

```yaml
# projects/devops/core-infrastructure/project.yaml
spec:
  sourceRepos:
    - https://github.com/boatsgroup/iac-eks-addons
    - https://github.com/boatsgroup/iac-eks-crossplane
  destinations:
    # Per-cluster, per-namespace entries
    - namespace: argocd
      server: https://<eks-api-url>
    - namespace: kube-system
      server: https://<eks-api-url>
    # ... (typically 20 namespace entries per spoke)
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
```

### Key Rules

- Every spoke must have its EKS API server URL in the project destinations
- `sourceRepos` must include every repo that applications in this project pull from
- Missing destinations cause: `application destination server is not permitted in project`
- Missing sourceRepos cause: `repo not permitted in project`

When a new spoke is registered, project.yaml files must be updated for every
ApplicationSet group that targets the spoke.

---

## Bootstrap Process

When a new hub is created or a spoke is registered, the bootstrap script
(`iac-eks-argocd/bootstrap/scripts/install.sh`) runs a 10-step sequence:

1. Creates `argocd` namespace
2. Adds/updates Argo Helm repo
3. Installs or upgrades ArgoCD Helm chart
4. Waits for ArgoCD workloads to be ready
5. Creates in-cluster ArgoCD cluster secret with labels
6. Creates `github-app-repo-creds` from AWS Secrets Manager
7. Applies `bootstrap-parent-application.yaml`
8. Runs app-of-apps deploy helper
9. Prints admin credentials/access info
10. Runs bootstrap verification checks

After bootstrap, ArgoCD discovers all `bootstrap-config.yaml` files and begins
deploying to the hub and its registered spokes.

---

## Scaling Considerations

| Concern | Current Approach |
|---------|-----------------|
| ApplicationSet count | ~6 groups × environments. Each generates N applications. |
| Sync frequency | Default ArgoCD polling (3 min). Can be tuned per ApplicationSet. |
| Cluster secrets | One ExternalSecret per spoke. Refreshed via External Secrets Operator. |
| Controller load | Single ArgoCD controller per hub. Scale repo-server replicas for large repos. |
| Git polling | Each ApplicationSet polls its source repo independently. |

For hubs managing 10+ spokes, consider:
- Increasing ArgoCD controller sharding
- Tuning sync retry backoff
- Using webhook-triggered syncs instead of polling

---

## Related Documents

- [Platform Overview](platform-overview.md) — high-level context
- [Environment Model](environment-model.md) — how environments map to clusters
- [Ecosystem Map](../../ecosystem/master-map.md) — full repo inventory
- [Workflow: new-hub](../workflows/) — hub creation procedure
- [Workflow: new-spoke](../workflows/) — spoke registration procedure
