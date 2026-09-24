# Mobius Platform Overview

> **Audience**: Engineers, architects, and AI agents who need to understand
> how the Mobius platform works before making changes.

> **Claude + Codex compatible**: This document provides the mental model
> needed to reason about cross-repo changes correctly.

---

## What is Mobius

Mobius is a **multi-repo GitOps platform** managing AWS EKS infrastructure. The
platform spans **22 interconnected repositories** covering:

- **Crossplane XRDs** (8 repos): Kubernetes-native AWS resource provisioning
- **Terraform / Infrastructure** (5 repos): EKS clusters, IAM, DNS, monitoring, bootstrap
- **ArgoCD / GitOps** (4 repos): Control plane, composition factory, workload delivery
- **Utilities** (3 repos): CLI tools, shared Helm charts, code intelligence
- **Application** (1 repo): FSBO web application deployed on the platform
- **Ecosystem SDK** (1 repo): Platform tooling, resolver scripts, and documentation hub (mobius-tools)

### Where We Are: ECS → EKS Migration

Production currently runs on **ECS, managed by Terraform and Jenkins**. Mobius is
the platform being built to migrate workloads to **EKS with GitOps (ArgoCD),
Crossplane, and Kustomize**. Some services already run on EKS; others remain on
ECS and will be migrated using `/mobius:migrate-ecs-service`. The platform
tooling, patterns, and repos documented here describe the EKS target state.

### Core Philosophy

1. **Declarative everything**: Every component declares what it needs via YAML
2. **ArgoCD enforces ordering**: Sync waves ensure dependencies deploy first
3. **Self-service through config files**: Teams deploy by adding `config.yaml`, not by touching the control plane
4. **Hub-spoke architecture**: One ArgoCD hub drives deployments to all clusters from `main` branches

### Key Architectural Separation

GitOps manifests (addons, observability) are separated from Terraform modules.
Terraform repos contain pure `.tf` files; GitOps repos handle ArgoCD
ApplicationSets and Kustomize overlays. This prevents conflating "what
infrastructure exists" with "what gets deployed where."

---

## The Deployment Lifecycle

When an engineer adds a new service, here is what happens from PR to running pod:

```
Engineer runs /mobius:add-service
    |
    v
1. Files generated in service repo
   (base/kustomization, overlays/config.yaml, values)
    |
    v
2. ApplicationSet wiring created in iac-eks-argocd
   (generator + project permissions)
    |
    v
3. PRs merged (argocd repo first, then service repo)
    |
    v
4. ArgoCD ApplicationSet discovers config.yaml on main
   (git generator scans overlays/*/config.yaml)
    |
    v
5. ArgoCD creates an Application per environment
   (one Application per config.yaml found)
    |
    v
6. Application syncs: Kustomize builds overlay
   -> Helm renders chart with values
   -> Kubernetes resources applied
    |
    v
7. If IRSA: XIRSARole claim -> Crossplane creates IAM role
   -> ServiceAccount annotated -> Pod gets AWS identity
    |
    v
8. Pod is running with correct identity and configuration
```

### Why This Order Matters

- **Step 3 order**: ArgoCD repo merges FIRST because it contains the
  ApplicationSet and project permissions. If the service repo merges first,
  ArgoCD has no generator to discover it.
- **Step 7 timing**: IRSA roles are created via Crossplane claims in the
  overlay. Sync waves ensure the XIRSARole composition is registered before
  claims are processed.

---

## Platform Layers

The platform is organized into six functional layers. Each layer has a specific
role and connects to others through well-defined interfaces.

| Layer | Repos | What It Does | How It Connects |
|-------|-------|--------------|-----------------|
| **Control Plane** | iac-eks-argocd | Hub ArgoCD instance, ApplicationSets, projects | Drives all deployments; every other layer flows through here |
| **Composition Factory** | iac-eks-crossplane | Crossplane providers, XRD registrations, Configuration CRs | Receives claims from GitOps layer; provisions AWS resources |
| **GitOps Deployment** | iac-eks-addons, iac-eks-observability | Service manifests, overlays, config.yaml | Discovered by control plane; contains the "what to deploy" |
| **Infrastructure** | terraform-module-*, iac-terragrunt-* | EKS clusters, IAM, networking, monitoring infra | Foundation layer; creates the clusters everything runs on |
| **Self-Service APIs** | crossplane-xrd-* (8 repos) | Kubernetes-native AWS resource provisioning | Consumed by GitOps layer; abstracts AWS behind K8s CRDs |
| **Tooling** | argocd-env-generator, helm-charts, iac-eks-pcg | Generators, shared charts, code intelligence | Support layer for all other tiers |
| **Ecosystem SDK** | mobius-tools | Platform tooling, resolver scripts, dependency graph, AI agent instructions | Meta layer — used by engineers and agents working across all tiers |

### Layer Dependencies

```
Control Plane (iac-eks-argocd)
       |
       +---> GitOps Deployment (iac-eks-addons, iac-eks-observability)
       |            |
       |            +---> Self-Service APIs (crossplane-xrd-*)
       |
       +---> Composition Factory (iac-eks-crossplane)
                    |
                    +---> Self-Service APIs (crossplane-xrd-*)
       
Infrastructure (terraform-*, iac-terragrunt-*)
       |
       +---> Creates clusters that all other layers deploy to
       
Tooling (mobius-tools, helm-charts, argocd-env-generator)
       |
       +---> Used by engineers working in all other layers
```

---

## Key Architecture Patterns

### Hub-Spoke ArgoCD

One hub cluster runs the ArgoCD control plane and manages all spoke clusters.

```
Hub cluster (e.g., ops-prod):
  - Runs ArgoCD server, controller, and repo server
  - Manages its own addons (self-targeting)
  - Manages all spoke clusters via cluster secrets

Spoke clusters (e.g., bg-qa, bg-dev):
  - Does NOT run ArgoCD
  - Managed entirely by the hub's ArgoCD
  - Cluster secrets stored in hub's iac-eks-argocd
```

ApplicationSets use git generators to discover `config.yaml` files across
service repos, automatically creating Applications for each environment.

**Deep dive**: [ArgoCD Hub-Spoke](argocd-hub-spoke.md)

### Crossplane Self-Service

Engineers create claims (e.g., XIRSARole) in their overlay YAML. Crossplane
resolves the claim through a well-defined pipeline:

```
Claim (XIRSARole) 
  -> XRD (defines the API)
  -> Composition (maps claim to resources)
  -> KCL function (generates AWS resource specs)
  -> AWS provider (creates the actual resource)
```

All XRDs are packaged as OCI images. Most are published to JFrog Artifactory;
`crossplane-xrd-generated-aws-secret` and `crossplane-xrd-ingress-acm-certificate`
publish to `ghcr.io/boatsgroup/` instead. The Composition Factory
(iac-eks-crossplane) registers these packages with each cluster via
Configuration CRs.

**Deep dive**: [Crossplane Flow](crossplane-flow.md)

### GitOps Config-as-Discovery

This pattern is unique to Mobius and powers the self-service deployment model.

**How it works**:

1. ApplicationSets define a git generator with a `path` pattern:
   ```yaml
   generators:
     - git:
         repoURL: https://github.com/boatsgroup/iac-eks-addons
         files:
           - path: "argocd/*/overlays/*/config.yaml"
   ```

2. The **existence** of `config.yaml` in an overlay IS the deployment trigger

3. No manual Application creation needed. Add `config.yaml` and ArgoCD finds it

4. The generator's `repoURL` and `path` pattern must match the service repo layout

**Key field**: `testBranch` in `config.yaml` enables feature branch testing
without touching the control plane. Must be on `main` to take effect.

### IRSA (IAM Roles for Service Accounts)

IRSA connects Kubernetes ServiceAccounts to AWS IAM roles, giving pods AWS
credentials without static secrets.

**Two provisioning paths**:

1. **Terraform path** (terraform-module-core-irsa): Pre-provisions IAM roles
   with OIDC trust policies. Used for platform-level roles.

2. **Crossplane path** (XIRSARole claim): Creates IAM role at deploy time via
   Crossplane. Used for service-level IRSA.

Both paths result in a ServiceAccount annotated with the role ARN. The pod
inherits AWS identity via IRSA token projection.

**Deep dive**: [IRSA Integration](irsa-integration.md)

### Environment Overlays

Each environment (bg-qa, bg-prod, ops-qa, ops-prod) is a Kustomize overlay that
patches base values for environment-specific configuration.

```
argocd/{service}/
  base/
    kustomization.yaml
    values.yaml
  overlays/
    bg-qa/
      config.yaml      # <- Triggers ApplicationSet discovery
      kustomization.yaml
      values.yaml
    bg-prod/
      config.yaml
      kustomization.yaml
      values.yaml
```

The `config.yaml` in each overlay triggers ApplicationSet discovery. The
overlay's `kustomization.yaml` patches the base for that environment.

**Deep dive**: [Environment Model](environment-model.md)

---

## Sync Wave Architecture

ArgoCD applications use sync waves to enforce dependency ordering within a
cluster. Lower waves deploy first.

| Wave | What Gets Deployed | Examples |
|------|-------------------|----------|
| -9 to -6 | Platform layer | Crossplane operators, Cert-Manager, External Secrets |
| -5 to -2 | Infrastructure layer | IRSA roles, XRD Configurations, Compositions |
| 0 to 2 | Workloads | Helm-based addons, operators |
| 3+ | Resources | NodePools, Karpenter configs, application-level resources |

### Detailed Wave Ordering

```
Wave -9: Crossplane operator itself
Wave -8: Crossplane providers (provider-aws, provider-kubernetes)
Wave -7: Crossplane functions (function-kcl, function-password-generator)
Wave -6: External Secrets Operator
Wave -5: IRSA Terraform module outputs (via terraform-module-core-irsa)
Wave -4: Crossplane Configuration CRs (from iac-eks-crossplane)
Wave -3: XRD + Composition registration
Wave -2: Composite resource claims
Wave  0: Helm addon deployments
Wave  2: Addon-level configurations
Wave  3: NodePool and Karpenter configs
```

---

## Cross-Repo Change Flow

Changes that span multiple repos follow a strict pattern to avoid broken
intermediate states.

```
Change flow (any multi-repo operation):

  1. JIRA ticket (optional but encouraged)
  2. Feature branches in ALL affected repos
  3. Generate/edit files
  4. Validate (kustomize build, wiring checks)
  5. Commit + PR per repo
  6. Merge in dependency order (upstream first)
```

### Merge Order Principle

**Permissions/wiring BEFORE content that triggers discovery.**

```
Typical merge order:
  iac-eks-argocd (ApplicationSet + project permissions)
    -> service repo (config.yaml that triggers discovery)
    -> infrastructure repos (if needed)
```

If you merge the service repo first, ArgoCD has no ApplicationSet to discover
the new `config.yaml`. The service sits undiscovered until the argocd repo
merges.

**Reference**: `docs/workflows/shared/multi-repo-git-workflow.md`

---

## Repository Relationships

The full platform topology showing how repos connect:

```
+==============================================================================+
|                         MOBIUS PLATFORM TOPOLOGY                            |
+==============================================================================+

                          iac-eks-argocd
                         (Control Plane Hub)
                               |
          +--------------------+--------------------+
          |                    |                    |
          v                    v                    v
    iac-eks-addons      iac-eks-crossplane    iac-eks-observability
    (GitOps Addons)     (Composition            (GitOps Observability)
          |              Factory)                      |
          |                  |                         |
          |    +-------------+                         |
          |    |    (Configuration packages via OCI -> JFrog)
          |    v                                       |
          |  crossplane-xrd-irsa-role                  |
          |  crossplane-xrd-karpenter-node-role        |
          |  crossplane-xrd-s3-bucket                  |
          |  crossplane-xrd-sqs-eventbridge            |
          |  crossplane-xrd-gateway-nlb-listener       |
          |  crossplane-xrd-generated-aws-secret       |
          |  crossplane-xrd-github-oidc                |
          |  crossplane-xrd-ingress-acm-certificate    |
          |       +-- All published to JFrog OCI       |
          |                                            |
          +---------------> EKS Clusters <-------------+
                                ^
                                |
                      iac-terragrunt-core-infra
                           (Bootstrap)
                                |
          +----------+----------+----------+----------+
          |          |          |          |          |
          v          v          v          v          v
  terraform-   terraform-   terraform-   terraform-
  module-      module-      module-      stack-
  eks          delegated-   core-irsa    monitoring-ng
  (EKS         zone         (IRSA TF     (Monitoring
   Clusters)   (DNS/ACM)     Module)      Terraform)

  +-------------------+    +--------------------+    +-------------------+
  | argocd-env-       |    | helm-charts        |    | iac-eks-pcg       |
  | generator         |    | (Shared configs)   |    | (Code intel / CGC)|
  | (CLI tool)        |    +--------------------+    +-------------------+
  +-------------------+
```

**Authoritative version**: `ecosystem/master-map.md`

---

## Where to Go Next

| Intent | Document |
|--------|----------|
| Deep dive into ArgoCD | [ArgoCD Hub-Spoke](argocd-hub-spoke.md) |
| Deep dive into Crossplane | [Crossplane Flow](crossplane-flow.md) |
| Deep dive into IRSA | [IRSA Integration](irsa-integration.md) |
| Understand environments | [Environment Model](environment-model.md) |
| Understand networking | [Networking](networking.md) |
| Full repo inventory | [Ecosystem Map](../../ecosystem/master-map.md) |
| Execute platform work | [Workflow Index](../workflows/INDEX.md) |
| Onboard to the team | [Onboarding Guide](../onboarding.md) |

---

## Quick Reference: Common Tasks

| Task | Repo | Path |
|------|------|------|
| Add new IRSA role Terraform module | terraform-module-core-irsa | `terraform/` |
| Add new IRSA role GitOps overlay | iac-eks-addons | `argocd/{addon}/overlays/{env}/config.yaml` |
| Create new XRD composition | crossplane-xrd-{name} | `kcl/` |
| Register XRD with clusters | iac-eks-crossplane | `crossplane/configurations/` |
| Add ArgoCD Application or ApplicationSet | iac-eks-argocd | `applicationsets/` |
| Configure monitoring dashboards | iac-eks-observability | `argocd/overlays/{env}/` |
| Bootstrap new EKS cluster | iac-terragrunt-core-infra | `aws/accounts/{account}/` |

---

## Anti-Patterns to Avoid

| Pattern | Why It Fails | What to Do Instead |
|---------|--------------|-------------------|
| Merging service repo before argocd repo | ApplicationSet does not exist yet | Merge argocd repo first |
| `testBranch` on a feature branch | Only takes effect on main | Merge to main first |
| Deploying claims before compositions | "No Composition found" errors | Use sync waves correctly |
| Go-templating for new XRDs | Untestable, hard to maintain | Use KCL in crossplane-xrd-* repo |
| Mixing Terraform and GitOps in same repo | Conflates infrastructure with deployment | Separate repos |
| Per-repo resolver scripts | 20 copies of logic to maintain | All resolver logic in mobius-tools |

---

## Validation Commands

Before merging any change, validate with the appropriate command:

```bash
# Terraform repos
terraform validate
pre-commit run --all-files

# ArgoCD/Kustomize repos
kustomize build argocd/{addon}/overlays/{env}

# KCL XRD repos
cd kcl && kcl run . -S items -D "params=$(cat ../test/basic.json)"
crossplane beta render claim.yaml composition.yaml functions.yaml

# Cross-repo consistency
npx mobius-validate-graph
```
