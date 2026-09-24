# Runbook: Crossplane Claim Not Ready

## Symptoms

- XRD claim stuck with `Ready=False` (e.g., XIRSARole, XS3Bucket, XGatewayNLBListener)
- Managed resources show errors or are stuck deleting
- Crossplane providers showing `HEALTHY=False`
- Webhook errors: `failed calling webhook`, x509 certificate errors

## Quick Triage (under 2 minutes)

```bash
# 1. Find claims for the service
for kind in xirsarole xkarpenternoderole xs3bucket xsqseventbridge \
  xgatewaynlblistener xgeneratedawssecret xingressacmcertificate; do
  kubectl get "$kind" -A 2>/dev/null | grep -i "<service>"
done

# 2. Check claim status
kubectl describe <claim-kind> -n <namespace> <claim-name>

# 3. Quick provider health
kubectl get providers.pkg.crossplane.io
```

## Common Causes and Fixes

### 1. Claim stuck not-ready (general)

**Check:**
```bash
kubectl get <claim-kind> -n <namespace> <claim-name> -o json | jq '{
  ready: .status.conditions,
  resourceRefs: .status.resourceRefs
}'
```

**Automated diagnosis:**
```bash
bash ../iac-eks-crossplane/scripts/crossplane-debug-claim.sh <claim-kind> <claim-name>
```

**Common reasons:**
- Managed resource can't provision (IAM permissions, quota, naming conflict)
- Provider is unhealthy or restarting
- Composition has a bug (KCL pipeline error)

### 2. Managed resources stuck with finalizers

This is the #1 Crossplane operational issue. Managed resources get stuck
when the provider can't delete the backing AWS resource.

**Check:**
```bash
# Find ALL stuck managed resources
kubectl get managed -A -o json 2>/dev/null | jq -r '.items[] |
  select(.metadata.deletionTimestamp) |
  "\(.kind)/\(.metadata.name) stuck since \(.metadata.deletionTimestamp)"'
```

**Temporary unblock:**
```bash
# Dry-run first — see what would be cleaned up
bash ../iac-eks-crossplane/scripts/crossplane-cleanup-stuck.sh --dry-run

# If the output looks correct, run for real
bash ../iac-eks-crossplane/scripts/crossplane-cleanup-stuck.sh
```

**Permanent fix:** Investigate why the AWS resource can't be deleted (dependency
ordering, IAM permissions, resource in use by another service). Fix the root
cause in the XRD composition or the service's claim configuration.

### 3. Provider package conflicts

**Symptoms:** Provider stuck in `Installing`, duplicate providers, all claims failing.

**Check:**
```bash
# Provider health
kubectl get providers.pkg.crossplane.io

# Check for duplicate CRD ownership
kubectl get crd -o json | jq -r '.items[] |
  select([.metadata.ownerReferences[]? | select(.controller == true)] | length > 1) |
  .metadata.name'

# Package locks
kubectl get locks.pkg.crossplane.io -o yaml
```

**Fix:**
```bash
bash ../iac-eks-crossplane/scripts/crossplane-provider-recovery.sh
```

### 4. TLS / webhook failures

**Symptoms:** All Crossplane operations fail with `x509` or `webhook` errors.

**Check:**
```bash
# Recent webhook errors
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | \
  grep -i "webhook\|tls\|x509\|certificate"

# Crossplane pods healthy?
kubectl get pods -n crossplane-system -l app=crossplane
```

**Fix:**
```bash
# Rotates TLS secrets, restarts components, refreshes CA bundles
bash ../iac-eks-crossplane/scripts/crossplane-reset-tls.sh
```

### 5. Stale ARN references

**Symptoms:** Managed resources show `Ready=False` with AWS `NotFound` errors.
Happens after AWS resources are recreated outside Crossplane (e.g., Terraform reprovisioned).

**Check & fix:**
```bash
# Detect stale references
bash ../iac-eks-crossplane/scripts/crossplane-detect-stale-refs.sh

# Fix: delete stale managed resources so Crossplane recreates them
bash ../iac-eks-crossplane/scripts/crossplane-detect-stale-refs.sh --fix
```

### 6. Orphaned functions stuck Terminating

**Symptoms:** Configuration package updates blocked.

**Check:**
```bash
kubectl get functions.pkg.crossplane.io -o json | jq -r '.items[] |
  select(.metadata.deletionTimestamp) |
  "\(.metadata.name) stuck since \(.metadata.deletionTimestamp)"'
```

**Fix:**
```bash
kubectl patch functions.pkg.crossplane.io <name> \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

### 7. ProviderConfig stuck (UsageAccounting)

**Symptoms:** ProviderConfig can't be deleted; ProviderConfigUsage references still exist.

**Fix:**
```bash
bash ../iac-eks-crossplane/scripts/crossplane-cleanup-usages.sh
```

## Full Health Check

When multiple issues are present or the root cause is unclear:

```bash
# Comprehensive health check
bash ../iac-eks-crossplane/scripts/crossplane-health-check.sh

# Include finalizer audit
bash ../iac-eks-crossplane/scripts/crossplane-health-check.sh --check-finalizers
```

## Script Reference

| Situation | Script |
|-----------|--------|
| Claim not ready | `crossplane-debug-claim.sh <type> <name>` |
| Overall health | `crossplane-health-check.sh` |
| Stuck resources | `crossplane-cleanup-stuck.sh --dry-run` |
| Stale references | `crossplane-detect-stale-refs.sh` |
| Provider issues | `crossplane-provider-recovery.sh` |
| TLS/webhook issues | `crossplane-reset-tls.sh` |
| Orphaned usages | `crossplane-cleanup-usages.sh` |

All scripts live in `iac-eks-crossplane/scripts/`. Never auto-run recovery
scripts — review dry-run output first.

## Post-Resolution

1. Verify claim converges: `kubectl get <claim-kind> -n <namespace> <claim-name>`
2. Check managed resources are healthy: `kubectl get managed | grep <claim-name>`
3. Run `/mobius:validate-service` if this claim backs a deployed service
