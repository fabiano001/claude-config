# Runbook: IRSA AccessDenied

## Symptoms

- Pod logs show `AccessDenied` or `not authorized to perform`
- Pod logs show `NoCredentialProviders` or `WebIdentityErr`
- AWS SDK errors: `An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation`
- ExternalSecret can't sync from Secrets Manager
- S3 proxy can't fetch assets from bucket

## Quick Triage (under 2 minutes)

```bash
# 1. Get the IRSA role ARN from the ServiceAccount
kubectl get sa -n <namespace> <service-account> \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# 2. Check if the annotation exists at all
kubectl get sa -n <namespace> <service-account> -o yaml | grep role-arn

# 3. Verify the pod is using the right ServiceAccount
kubectl get pod -n <namespace> <pod-name> -o jsonpath='{.spec.serviceAccountName}'
```

## How IRSA Works (Quick Reference)

```
Pod → ServiceAccount (with role-arn annotation)
  → EKS projects a JWT token into the pod
    → Pod calls STS AssumeRoleWithWebIdentity
      → IAM trust policy validates:
          - OIDC provider matches the cluster
          - Subject matches namespace:serviceaccount
        → IAM role is assumed
          → AWS API calls use that role's permissions
```

Any break in this chain causes `AccessDenied`.

## Common Causes and Fixes

### 1. No IRSA annotation on ServiceAccount

**Check:**
```bash
kubectl get sa -n <namespace> <service-account> -o yaml
```

If `eks.amazonaws.com/role-arn` annotation is missing, the pod has no AWS identity.

**Fix (permanent):**
- If using Crossplane: Check the XIRSARole claim in `argocd/<service>/overlays/<env>/`
- If using Terraform: Check `terraform-module-core-irsa` for the role definition
- Verify the Helm chart creates a ServiceAccount with the annotation (check `values.yaml`
  for `serviceAccount.annotations`)

### 2. Trust policy references wrong OIDC provider

The most common IRSA issue. Each EKS cluster has its own OIDC provider.
If the trust policy references cluster A's OIDC provider but the pod runs on
cluster B, authentication fails silently.

**Check:**
```bash
# Get the role name from the ARN
ROLE_ARN=$(kubectl get sa -n <namespace> <service-account> \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')

# Inspect the trust policy
aws iam get-role --role-name "$ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

**What to look for in the trust policy:**
```json
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234:sub": "system:serviceaccount:<namespace>:<sa-name>"
    }
  }
}
```

- The OIDC provider ID must match the cluster where the pod runs
- The `sub` field must match `system:serviceaccount:<actual-namespace>:<actual-sa-name>`

**Fix (permanent):**
- Crossplane path: Update the XIRSARole claim's OIDC provider reference
- Terraform path: Update the OIDC provider in `terraform-module-core-irsa`

### 3. Trust policy references wrong namespace or SA name

**Check:** Same as above — compare the trust policy `sub` field against:
```bash
echo "system:serviceaccount:$(kubectl get pod -n <namespace> <pod> \
  -o jsonpath='{.metadata.namespace}'):$(kubectl get pod -n <namespace> <pod> \
  -o jsonpath='{.spec.serviceAccountName}')"
```

**Fix:** Update the trust policy through IaC (XIRSARole claim or Terraform).

### 4. IAM policy missing required permissions

The trust policy is correct (role assumption works) but the role doesn't have
permissions for the specific AWS API the service needs.

**Check:**
```bash
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')

# List attached policies
aws iam list-attached-role-policies --role-name "$ROLE_NAME"

# List inline policies
aws iam list-role-policies --role-name "$ROLE_NAME"

# Inspect a specific policy
aws iam get-policy-version --policy-arn <policy-arn> \
  --version-id $(aws iam get-policy --policy-arn <policy-arn> \
  --query 'Policy.DefaultVersionId' --output text)
```

**Fix (permanent):**
- Terraform path: Edit the IAM policy in `terraform-module-core-irsa/modules/<service>/iam.tf`
- Crossplane path: The XIRSARole XRD has a `policyArns` field for attaching existing policies

### 5. Pod token not being projected

Rare but possible: the EKS cluster's OIDC provider is misconfigured or the
pod spec doesn't project the service account token.

**Check:**
```bash
# Verify token is projected into the pod
kubectl get pod -n <namespace> <pod-name> -o json | jq '
  .spec.containers[0].volumeMounts[] |
  select(.mountPath | contains("serviceaccount"))'

# Verify token env vars
kubectl exec -n <namespace> <pod-name> -- env | grep AWS_WEB_IDENTITY
```

Expected env vars:
- `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- `AWS_ROLE_ARN=arn:aws:iam::...:role/...`

If missing, the EKS pod identity webhook may not be running:
```bash
kubectl get pods -n kube-system | grep eks-pod-identity
```

### 6. Cross-account IRSA

For services that access resources in a different AWS account:

**Check:** The trust policy must include the OIDC provider from the source
account's cluster AND a role chain or direct trust in the target account.

**Fix:** This requires coordination between:
- `terraform-module-core-irsa` (role in target account with cross-account trust)
- XIRSARole claim (role in source account that can assume target role)

## Permanent Fix Paths

| Provisioning method | Fix repo | Fix path |
|--------------------|----------|----------|
| Crossplane XIRSARole | Service repo | `argocd/<service>/overlays/<env>/xirsarole-patch.yaml` or `base/xirsarole.yaml` |
| Terraform | `terraform-module-core-irsa` | `modules/<service>/iam.tf` |
| Inline Helm SA annotation | Service repo | `argocd/<service>/overlays/<env>/values.yaml` → `serviceAccount.annotations` |

Never run `aws iam create-*`, `aws iam put-*`, or `aws iam attach-*` commands
directly. All IAM changes go through IaC.

## Post-Resolution

1. Restart pods to pick up new credentials: `kubectl rollout restart deployment -n <namespace> <deployment>`
2. Verify AWS access: `kubectl exec -n <namespace> <pod> -- aws sts get-caller-identity`
3. Check the service-specific operation (Secrets Manager get, S3 read, etc.)
4. Run `/mobius:validate-service` to confirm overall health
