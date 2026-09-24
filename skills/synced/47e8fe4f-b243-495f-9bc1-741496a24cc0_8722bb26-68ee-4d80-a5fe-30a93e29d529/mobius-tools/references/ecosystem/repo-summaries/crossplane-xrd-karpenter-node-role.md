# crossplane-xrd-karpenter-node-role

**Role**: Karpenter Node Role XRD — KCL composition that creates IAM instance
profiles and roles for Karpenter-managed EC2 node pools.

**Tier**: xrd

## What It Does

Defines the `KarpenterNodeRole` XRD. Karpenter requires EC2 nodes to have an
instance profile with specific AWS-managed policies (AmazonEKSWorkerNodePolicy,
AmazonEC2ContainerRegistryReadOnly, etc.) plus the OIDC trust relationship.
This XRD creates the IAM role, attaches the required policies, creates the
instance profile, and links it — all through a single Crossplane claim.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for KarpenterNodeRole |
| `composition.yaml` | Composition pipeline |
| `crossplane.yaml` | Package metadata (`skipDependencyResolution: true`) |
| `kcl/main.k` | IAM role + instance profile creation logic |
| `kcl/config.k` | Spec field mappings |
| `test/*.json` | Test fixtures |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR
- **iac-eks-addons** — claims created here for each cluster
- **crossplane-xrd-irsa-role** — extends the irsa-role pattern (sibling dependency)

## Downstream (consumed by)

- EKS clusters with Karpenter — the node role is required before NodePools work

## OCI Packages Published

```
kcl-karpenter-node-role:{version}                   (KCL module)
crossplane-xrd-karpenter-node-role:{version}        (Configuration package)
```

Both published to: `boatsgroup.pe.jfrog.io/bg-crossplane/`

## Critical Conventions

- Depends on `crossplane-xrd-irsa-role` being registered first (sync wave ordering)
- EC2 instance profile name must match what Karpenter's EC2NodeClass references
- `skipDependencyResolution: true` always required
