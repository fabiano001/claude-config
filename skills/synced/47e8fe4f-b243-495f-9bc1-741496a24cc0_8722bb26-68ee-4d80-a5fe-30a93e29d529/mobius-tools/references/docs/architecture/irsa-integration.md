# IRSA Integration Model

> How Kubernetes pods get AWS credentials without static secrets, through
> IAM Roles for Service Accounts.

---

## Overview

IRSA (IAM Roles for Service Accounts) lets Kubernetes pods assume AWS IAM roles
using their ServiceAccount identity. Instead of hardcoding AWS access keys, pods
receive temporary credentials automatically via token projection.

```
Pod starts
  → kubelet injects a projected service account token (JWT)
  → token includes the pod's ServiceAccount identity
  → AWS SDK calls STS AssumeRoleWithWebIdentity
  → STS validates the token against the EKS OIDC provider
  → STS returns temporary AWS credentials
  → pod can now access AWS resources (S3, SQS, Secrets Manager, etc.)
```

This happens transparently — application code just uses the AWS SDK normally.

---

## Two Provisioning Paths

Mobius supports two ways to create IRSA roles. Both result in the same end
state: a ServiceAccount annotated with a role ARN and a trust policy that
allows the EKS cluster's OIDC provider.

### Path 1: Terraform Module (terraform-module-core-irsa)

Used for **platform-level roles** that exist before services deploy.

```
terraform-module-core-irsa
  modules/<addon>/
    ├── iam.tf          # IAM role + trust policy + attached policies
    ├── variables.tf
    └── outputs.tf
```

- Created during cluster bootstrapping via Terragrunt
- Deployed at sync wave -5 (before workloads)
- Changes require a Terraform plan/apply cycle
- Used for: ArgoCD hub role, External Secrets role, Crossplane provider role

### Path 2: Crossplane XIRSARole Claim

Used for **service-level roles** created at deploy time.

```yaml
# argocd/<service>/base/xirsarole.yaml
apiVersion: aws.platform.boatsgroup.com/v1alpha1
kind: XIRSARole
metadata:
  name: external-dns
spec:
  clusterName: bg-qa
  serviceAccountName: external-dns
  serviceAccountNamespace: external-dns
  policyArns:
    - arn:aws:iam::123456789012:policy/external-dns
```

- Created when ArgoCD syncs the service overlay
- Deployed at sync wave -2 (after compositions are registered)
- Changes are GitOps — update the claim YAML and merge
- Used for: Most service-level IRSA roles

### When to Use Which

| Scenario | Path | Why |
|----------|------|-----|
| ArgoCD hub role | Terraform | Must exist before ArgoCD itself starts |
| External Secrets Operator role | Terraform | Must exist before ESO starts fetching secrets |
| Crossplane provider role | Terraform | Must exist before providers authenticate |
| Service-specific role (external-dns, cert-manager) | XIRSARole | Created as part of the service deployment |
| Application team role | XIRSARole | Self-service via claim in overlay |

**Note on IRSA specifically: this table is unaffected by the non-IRSA
resource-mode choice below.** `/mobius:add-service` always provisions IRSA
via the `XIRSARole` claim (Path 2), regardless of whether the *other* AWS
resources a service needs (S3, SQS, RDS, etc.) go through Crossplane XRD
claims or through generated Terraform — see the next section.

### Non-IRSA AWS Resources: Crossplane XRD vs. Generated Terraform

For AWS resources *other than IRSA*, `/mobius:add-service` offers a
whole-stack choice at intake (not per-resource):

| Mode | How non-IRSA resources are provisioned | Where |
|------|------------------------------------------|-------|
| `crossplane` | Crossplane XRD claims (`XS3Bucket`, `XSQSEventBridge`, etc.) | `argocd/<service>/base/` — same as today |
| `terraform` | Raw Terraform, module-first against the `terraform-modules-aws` private registry | `terraform/shared/` + `terraform/environments/<env>/` in the service repo, with a generated `atlantis.yaml` — see `commands/mobius/add-service/terraform-generation.md` |

Both modes leave IRSA on `XIRSARole` unchanged. Pick `terraform` when the
resource has no XRD yet, or the team wants direct Terraform control instead
of a Crossplane composition; pick `crossplane` for the existing self-service
GitOps flow.

---

## How IRSA Works (Detailed)

### 1. OIDC Provider

Every EKS cluster has an OIDC provider. This is created when the cluster is
provisioned (via `terraform-module-eks`):

```
https://oidc.eks.<region>.amazonaws.com/id/<hash>
```

AWS IAM trusts this provider to authenticate tokens from the cluster.

### 2. Trust Policy

The IAM role's trust policy specifies which OIDC provider and which
ServiceAccount can assume the role:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<hash>"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.<region>.amazonaws.com/id/<hash>:sub": "system:serviceaccount:<namespace>:<sa-name>",
      "oidc.eks.<region>.amazonaws.com/id/<hash>:aud": "sts.amazonaws.com"
    }
  }
}
```

The `:sub` condition binds the role to a specific ServiceAccount in a specific
namespace. A pod in a different namespace or with a different ServiceAccount
cannot assume this role.

### 3. ServiceAccount Annotation

The ServiceAccount must be annotated with the role ARN:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/bg-qa-external-dns
```

Most Helm charts accept a `serviceAccount.annotations` value to set this.
In Mobius, the role ARN is typically set in the overlay's `values.yaml`.

### 4. Token Projection

When a pod using an annotated ServiceAccount starts, the kubelet:
1. Requests a projected service account token from the API server
2. Mounts it at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
3. Sets environment variables: `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`

The AWS SDK automatically detects these and uses them for authentication.

---

## File Layout in Service Repos

### Base (shared across environments)

```yaml
# argocd/<service>/base/xirsarole.yaml
apiVersion: aws.platform.boatsgroup.com/v1alpha1
kind: XIRSARole
metadata:
  name: <service>
spec:
  serviceAccountName: <service>
  serviceAccountNamespace: <namespace>
  policyArns:
    - arn:aws:iam::ACCOUNT_PLACEHOLDER:policy/<service>
```

### Overlay (environment-specific patches)

```yaml
# argocd/<service>/overlays/bg-qa/xirsarole-patch.yaml
apiVersion: aws.platform.boatsgroup.com/v1alpha1
kind: XIRSARole
metadata:
  name: <service>
spec:
  clusterName: bg-qa
  oidcProviderArn: arn:aws:iam::<account>:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<hash>
  policyArns:
    - arn:aws:iam::<account>:policy/<service>
```

The overlay patches account-specific fields: `clusterName`, `oidcProviderArn`,
and policy ARNs with the correct account ID.

---

## Cross-Account IRSA

For hub-spoke setups, some roles need cross-account trust. The hub's IRSA role
assumes a role in the spoke account:

```
Hub: <hub>-external-secrets (IRSA role in hub account)
  → assumes: external-secrets-cross-account (role in spoke account)
  → accesses: Spoke's AWS Secrets Manager
```

This is configured in:
- Spoke: `iac-terragrunt-core-infra` creates the `external-secrets-cross-account` role
- Hub: `iac-eks-addons` → `external-secrets` overlay → `xirsarole-patch.yaml` lists spoke role ARNs

---

## Debugging IRSA Issues

### Symptom: Pod Gets AccessDenied

```bash
# 1. Check ServiceAccount annotation
kubectl get sa -n <ns> <sa-name> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# 2. Check IAM trust policy
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')
aws iam get-role --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument'

# 3. Verify OIDC provider matches the cluster
aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer'
```

### Common Causes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AccessDenied` on STS AssumeRole | Trust policy references wrong OIDC provider | Fix `oidcProviderArn` in xirsarole-patch.yaml |
| `AccessDenied` on STS AssumeRole | Trust policy references wrong namespace or SA name | Fix `serviceAccountNamespace` or `serviceAccountName` |
| `NoCredentialProviders` | ServiceAccount missing role-arn annotation | Check Helm values set `serviceAccount.annotations` |
| `AccessDenied` on AWS API calls | IAM policy doesn't grant the needed permissions | Update policy ARN or inline policy in Terraform/XIRSARole |
| Intermittent `ExpiredToken` | Token not refreshed (rare with SDK v2) | Restart pod; check SDK version |

---

## Related Documents

- [Platform Overview](platform-overview.md) — high-level context
- [Crossplane Flow](crossplane-flow.md) — how XIRSARole claims are processed
- [Ecosystem Map](../../ecosystem/master-map.md) — terraform-module-core-irsa and crossplane-xrd-irsa-role
