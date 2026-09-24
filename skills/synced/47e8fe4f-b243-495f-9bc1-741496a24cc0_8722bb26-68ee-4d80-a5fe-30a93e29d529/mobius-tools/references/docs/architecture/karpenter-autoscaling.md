# Karpenter Autoscaling & Node Scheduling

> How workloads land on the right nodes through Karpenter NodePools,
> nodeSelectors, taints, and tolerations.

<!-- Last verified: 2026-03-02 -->

---

## Overview

Karpenter replaces the Kubernetes Cluster Autoscaler with just-in-time node
provisioning. Instead of pre-defined Auto Scaling Groups, Karpenter watches
for pending pods and launches right-sized EC2 instances that match their
scheduling constraints.

```
Pod created with nodeSelector / tolerations
  → Karpenter sees the pod is unschedulable
  → Matches pod requirements to a NodePool
  → NodePool's EC2NodeClass defines AMI, subnets, security groups
  → Karpenter launches a right-sized instance
  → Pod is scheduled onto the new node
```

Karpenter NodePools are **Kubernetes CRDs** — they live in Git and deploy
via ArgoCD, following the same GitOps model as every other platform resource.

---

## Provisioning Boundaries

Mobius uses two distinct provisioning paths for nodes. Understanding which
path owns which nodes prevents confusion during debugging and capacity planning.

### Karpenter-Managed (NodePools)

All application and platform workload nodes are provisioned by Karpenter.
NodePools are `karpenter.sh/v1` CRDs deployed via ArgoCD.

- **default** — General-purpose pool for platform addons
- **application** — Application workloads (api-node-*, webapp-node-*)
- **monitoring** — Dedicated nodes for observability stack (Loki, Tempo, Prometheus, Grafana)
- **arc-amd64** — GitHub Actions runner nodes (AMD64)
- **arc-arm64** — GitHub Actions runner nodes (ARM64)

### Terraform-Managed (Bootstrap)

A single self-managed node group provides the chicken-and-egg foundation:

- **bootstrap** — Runs ArgoCD, Karpenter itself, Crossplane, Kyverno

This node group is defined in `iac-terragrunt-core-infra` via the
`self_managed_node_groups` block. It must exist before Karpenter can start,
because Karpenter needs a running cluster to operate.

---

## Three Scheduling Patterns

Every workload in the platform uses one of three scheduling patterns. The
pattern determines which nodes a pod lands on and whether it needs taints
or tolerations.

### Pattern 1: Application Workloads

```yaml
nodeSelector:
  karpenter.sh/nodepool: application
```

- **No taints, no tolerations** — application nodes accept all pods by default
- **Used by**: api-node-*, webapp-node-*, yachtfocus, and other application services
- **NodePool owner**: `iac-eks-addons/argocd/karpenter/`

### Pattern 2: Monitoring Stack

```yaml
nodeSelector:
  nodegroup: monitoring
tolerations:
  - key: dedicated
    value: monitoring
    effect: NoSchedule
```

- **Tainted** with `dedicated=monitoring:NoSchedule` to isolate observability workloads
- **Used by**: Loki, Tempo, Prometheus, Grafana, and other observability components
- **NodePool owner**: `iac-eks-observability/argocd/karpenter/`

### Pattern 3: Bootstrap / Control Plane

```yaml
nodeSelector:
  nodepool: bootstrap
tolerations:
  - key: workload
    value: control
    effect: NoSchedule
```

- **Tainted** with `workload=control:NoSchedule` to reserve nodes for platform controllers
- **Used by**: ArgoCD, Karpenter, Crossplane, Kyverno
- **Provisioned by**: Terraform (not Karpenter) — see Provisioning Boundaries above

---

## Label and Taint Conventions

The three patterns use **different label keys intentionally**. This is not
a bug — each convention evolved with its provisioning path and changing it
would require coordinated updates across dozens of workloads.

| Pattern | nodeSelector Key | Value | Provenance |
|---------|-----------------|-------|------------|
| Application | `karpenter.sh/nodepool` | `application` | Karpenter-native label, auto-applied |
| Monitoring | `nodegroup` | `monitoring` | Legacy convention, predates Karpenter migration |
| Bootstrap | `nodepool` | `bootstrap` | Terraform `self_managed_node_groups` label |

### Taints

| Pool | Taint Key | Value | Effect | Purpose |
|------|-----------|-------|--------|---------|
| monitoring | `dedicated` | `monitoring` | `NoSchedule` | Isolate observability from app workloads |
| bootstrap | `workload` | `control` | `NoSchedule` | Reserve for platform controllers |
| arc-amd64 | `karpenter.sh/do-not-disrupt` | `true` | `NoSchedule` | Protect running CI jobs |
| arc-arm64 | `karpenter.sh/do-not-disrupt` | `true` | `NoSchedule` | Protect running CI jobs |

Application and default pools have **no taints** — any pod without specific
tolerations lands on these nodes.

---

## Ownership Model (Self-Service)

NodePools follow the **self-service pattern** — any repo can define NodePools
for its domain. There is no central registry or approval gate.

| NodePool | Owner Repo | Why There |
|----------|-----------|-----------|
| default | `iac-eks-addons` | General platform pool, lives with core addons |
| application | `iac-eks-observability` | Application workload scheduling, defined alongside monitoring |
| monitoring | `iac-eks-observability` | Observability stack needs dedicated capacity |
| arc-amd64 | `iac-eks-addons` | CI runners are a platform addon |
| arc-arm64 | `iac-eks-addons` | CI runners are a platform addon |
| bootstrap | `iac-terragrunt-core-infra` | Terraform-managed, not a Karpenter NodePool |

The ownership rule: **the team that operates the workloads owns the NodePool
definition**. The monitoring team owns monitoring nodes. The platform team
owns default and runner nodes. Infrastructure owns the bootstrap node group.

---

## How Commands Use This Information

Several `/mobius:*` commands need to understand node scheduling:

| Command | What It Needs |
|---------|--------------|
| `/mobius:validate-service` | KAR-* checks verify nodeSelector matches a known NodePool and tolerations cover pool taints |
| `/mobius:add-service` | Operational Profile recommends a node scheduling pattern based on addon class |
| `/mobius:debug-service` | Phase 3 Kubernetes diagnosis checks if pods are pending due to scheduling constraints |
| `/mobius:new-spoke` | Phase 5 bootstraps Karpenter NodePools on new spoke clusters |
| `/mobius:migrate-ecs-service` | Maps ECS task placement to Kubernetes nodeSelector + tolerations |

---

## Debugging Node Scheduling

### Symptom: Pod Stuck in Pending

```bash
# 1. Check if Karpenter sees the pod
kubectl get nodepools
kubectl get nodeclaims

# 2. Check pod events for scheduling failures
kubectl describe pod -n <ns> <pod-name> | grep -A5 Events

# 3. Verify nodeSelector matches a NodePool
kubectl get nodepool <pool-name> -o yaml | grep -A10 'template:'

# 4. Verify tolerations match pool taints
kubectl get nodepool <pool-name> -o yaml | grep -A5 'taints:'
```

### Common Causes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod pending, no NodeClaim created | nodeSelector doesn't match any NodePool | Fix `nodeSelector` to use correct label key/value |
| Pod pending, NodeClaim exists but no node | Instance type constraints too restrictive | Check NodePool `requirements` for instance families |
| Pod scheduled but OOMKilled | Landed on undersized node | Check NodePool `requirements` for instance sizes |
| Pod won't schedule to monitoring nodes | Missing `dedicated=monitoring:NoSchedule` toleration | Add toleration to workload values.yaml |
| Pod won't schedule to bootstrap nodes | Missing `workload=control:NoSchedule` toleration | Add toleration to workload values.yaml |

---

## Related Documents

- [Platform Overview](platform-overview.md) — high-level context, sync wave ordering
- [Crossplane Flow](crossplane-flow.md) — XKarpenterNodeRole for node IAM
- [Environment Model](environment-model.md) — overlay structure for per-environment NodePool patches
- [Ecosystem Map](../../ecosystem/master-map.md) — repo ownership and relationships
