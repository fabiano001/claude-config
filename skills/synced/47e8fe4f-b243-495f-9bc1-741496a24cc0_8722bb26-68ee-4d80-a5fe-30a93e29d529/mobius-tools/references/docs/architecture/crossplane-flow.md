# Crossplane Composition Flow

> How Mobius provisions AWS resources through Kubernetes-native claims,
> from YAML in a PR to a running AWS resource.

---

## Overview

Crossplane lets engineers provision AWS resources (IAM roles, S3 buckets, SQS
queues, etc.) by writing YAML claims instead of Terraform or using the AWS
console. The claim goes through a well-defined pipeline that ends with a real
AWS resource managed by Crossplane's reconciliation loop.

```
Engineer writes a claim (e.g., XIRSARole)
    │
    ▼
XRD validates the claim against its schema
    │
    ▼
Composition maps claim fields to resource specs
    │
    ▼
KCL function generates the managed resource YAML
    │
    ▼
AWS provider creates the actual resource in AWS
    │
    ▼
Crossplane continuously reconciles desired vs actual state
```

---

## Claim Lifecycle

### Step 1: Engineer Creates a Claim

Claims live in service overlays alongside `config.yaml`:

```yaml
# argocd/external-dns/overlays/bg-qa/xirsarole.yaml
apiVersion: aws.platform.boatsgroup.com/v1alpha1
kind: XIRSARole
metadata:
  name: external-dns
spec:
  clusterName: bg-qa
  serviceAccountName: external-dns
  serviceAccountNamespace: external-dns
  policyArns:
    - arn:aws:iam::123456789012:policy/external-dns-policy
```

When the overlay is synced by ArgoCD, the claim is applied to the cluster.

### Step 2: XRD Validates the Schema

The CompositeResourceDefinition (XRD) defines the API schema — what fields
the claim accepts, their types, and defaults. If the claim doesn't match the
schema, the API server rejects it immediately.

### Step 3: Composition Maps Claim to Resources

The Composition selects based on the claim's API group/version/kind and runs
a pipeline of functions:

```yaml
# composition.yaml (simplified)
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
spec:
  compositeTypeRef:
    apiVersion: aws.platform.boatsgroup.com/v1alpha1
    kind: XIRSARole
  mode: Pipeline
  pipeline:
    - step: kcl
      functionRef:
        name: crossplane-contrib-function-kcl
      input:
        apiVersion: krm.kcl.dev/v1alpha1
        kind: KCLInput
        spec:
          source: oci://boatsgroup.pe.jfrog.io/bg-crossplane/kcl-irsa-role
```

### Step 4: KCL Function Generates Managed Resources

The KCL function reads the claim's spec and produces managed resource
definitions (IAM roles, policies, etc.) as output. The KCL code runs inside
Crossplane as a serverless function.

### Step 5: AWS Provider Creates Resources

The Crossplane AWS provider takes the managed resource definitions and makes
the corresponding AWS API calls to create/update the actual resources.

### Step 6: Continuous Reconciliation

Crossplane continuously compares desired state (the claim) with actual state
(the AWS resource). If someone manually modifies the AWS resource, Crossplane
reverts it to match the claim. If the claim is deleted, Crossplane deletes the
AWS resource.

---

## KCL Composition Pattern

All new XRDs use KCL (Kusion Configuration Language) with a flat-file pattern.

### File Structure

```
crossplane-xrd-<name>/
├── definition.yaml      # XRD schema (CompositeResourceDefinition)
├── composition.yaml     # Composition with KCL pipeline
├── crossplane.yaml      # Package metadata (OCI)
├── functions.yaml       # Function versions for local testing
├── kcl/
│   ├── main.k           # Entry point — reads claim, produces resources
│   ├── config.k         # Configuration helpers
│   └── helpers.k        # Shared utility functions (optional)
├── test/
│   └── basic.json       # Test parameters
└── .github/workflows/   # CI for OCI publish
```

### Flat-File Rule

All `.k` files in the `kcl/` directory share the same namespace. **Do not
use `import` statements** — just reference functions and variables directly.
This is a deliberate pattern that keeps compositions simple and testable.

```python
# main.k — correct (no imports)
_oxr = option("params").oxr
_cluster_name = _oxr.spec.clusterName

items = [
    {
        "apiVersion": "iam.aws.upbound.io/v1beta1",
        "kind": "Role",
        "metadata": {"name": _cluster_name + "-" + _oxr.spec.serviceAccountName},
        # ...
    }
]
```

### Local Testing

```bash
# Run KCL to verify output
cd kcl && kcl run . -S items -D "params=$(cat ../test/basic.json)"

# Full Crossplane render (claim → composition → managed resources)
crossplane beta render claim.yaml composition.yaml functions.yaml
```

---

## OCI Packaging and Registry

All Crossplane packages are published to JFrog Artifactory as OCI images:

```
Registry: boatsgroup.pe.jfrog.io/bg-crossplane/

Package naming:
  KCL module:      kcl-{repo-name}:{version}
  Configuration:   crossplane-xrd-{name}:{version}

Example:
  kcl-irsa-role:v0.3.1
  crossplane-xrd-irsa-role:v0.3.1
```

### Publish Flow

1. Engineer merges PR to `main` in the XRD repo
2. Engineer tags a release (e.g., `v0.3.1`)
3. GitHub Actions CI builds and pushes the OCI package to JFrog
4. The Configuration CR in `iac-eks-crossplane` references the new version

**Version management**: `kcl.mod` and `composition.yaml` versions are managed
by the release workflow. **Never manually change version numbers** — this causes
conflicts with CI.

### Required Field: `skipDependencyResolution`

Every XRD's `crossplane.yaml` must include:

```yaml
skipDependencyResolution: true
```

Without this, Crossplane tries to resolve package dependencies automatically,
which conflicts with ArgoCD-managed function installations.

---

## Configuration CRs (iac-eks-crossplane)

The Composition Factory (`iac-eks-crossplane`) registers XRD packages with
each cluster via Configuration Custom Resources:

```yaml
# argocd/crossplane/base/configurations/irsa-role.yaml
apiVersion: pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: crossplane-xrd-irsa-role
spec:
  package: boatsgroup.pe.jfrog.io/bg-crossplane/crossplane-xrd-irsa-role:v0.3.1
  skipDependencyResolution: true
```

When ArgoCD syncs this Configuration CR, Crossplane downloads the OCI package
and installs the XRD + Composition into the cluster.

### Provider Configuration

Crossplane uses provider-specific configs for AWS authentication:

```
argocd/crossplane/overlays/<env>/
├── config.yaml                # ApplicationSet discovery
├── kustomization.yaml
├── values.yaml
├── configurations/            # Configuration CR versions (per-env overrides)
├── provider-configs/          # ProviderConfig with IRSA role ARN
└── runtime-configs/           # DeploymentRuntimeConfig (provider pod settings)
```

The `provider-configs/` directory contains ProviderConfig resources that tell
the AWS provider which IAM role to assume (via IRSA) when making AWS API calls.

---

## XRD Inventory

| XRD | Claim Kind | What It Provisions | Repo |
|-----|-----------|-------------------|------|
| XIRSARole | `XIRSARole` | IAM role with OIDC trust policy for Kubernetes pods | `crossplane-xrd-irsa-role` |
| XKarpenterNodeRole | `XKarpenterNodeRole` | IAM instance profile for Karpenter-managed nodes | `crossplane-xrd-karpenter-node-role` |
| XS3Bucket | `XS3Bucket` | S3 bucket with standard configuration | `crossplane-xrd-s3-bucket` |
| XSQSEventBridge | `XSQSEventBridge` | SQS queue + EventBridge rule for event-driven messaging | `crossplane-xrd-sqs-eventbridge` |
| XGatewayNLBListener | `XGatewayNLBListener` | NLB listener + TLS termination for Envoy Gateway | `crossplane-xrd-gateway-nlb-listener` |
| XGeneratedAWSSecret | `XGeneratedAWSSecret` | Generated credentials stored in AWS Secrets Manager | `crossplane-xrd-generated-aws-secret` |
| XIngressACMCertificate | `XIngressACMCertificate` | ACM certificate for ALB Ingress | `crossplane-xrd-ingress-acm-certificate` |
| XGitHubOIDC | — | GitHub Actions OIDC federation (incomplete stub) | `crossplane-xrd-github-oidc` |

`XIRSARole` is by far the most commonly used — nearly every service needs an
IAM role for AWS access.

---

## How Services Consume XRDs

Services include claim YAML in their overlay directories. The claim is applied
when ArgoCD syncs the overlay.

### Common Pattern: IRSA Role

```
argocd/<service>/
  base/
    kustomization.yaml
    values.yaml
    xirsarole.yaml          # Base IRSA claim (shared fields)
  overlays/
    bg-qa/
      config.yaml
      kustomization.yaml
      values.yaml
      xirsarole-patch.yaml  # Environment-specific overrides (account, OIDC)
```

The base `xirsarole.yaml` defines the role structure. The overlay
`xirsarole-patch.yaml` patches environment-specific fields like account ID,
cluster name, and OIDC provider.

---

## Debugging

### Claim Not Ready

```bash
# Check claim status
kubectl describe xirsarole <claim-name>

# Check managed resources owned by the claim
kubectl get xirsarole <claim-name> -o json | \
  jq '.status.resourceRefs[]'

# Run the dedicated debug script
bash ../iac-eks-crossplane/scripts/crossplane-debug-claim.sh xirsarole <name>
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No Composition found" | Configuration CR not synced, or XRD version mismatch | Check sync wave ordering; verify Configuration CR |
| Managed resource stuck deleting | AWS resource can't be deleted (dependencies, permissions) | `crossplane-cleanup-stuck.sh --dry-run` |
| Provider `Installing` forever | Package lock conflict or duplicate providers | `crossplane-provider-recovery.sh` |
| Webhook x509 errors | TLS certificates expired | `crossplane-reset-tls.sh` |

---

## Related Documents

- [Platform Overview](platform-overview.md) — high-level context
- [IRSA Integration](irsa-integration.md) — the most common XRD use case
- [Ecosystem Map](../../ecosystem/master-map.md) — XRD repo inventory
- [Workflow: new-xrd](../workflows/xrd/new-xrd.md) — creating a new XRD
