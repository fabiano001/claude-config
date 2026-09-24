# Runbook: Service Unreachable

## Symptoms

- HTTP requests return 502 Bad Gateway or 503 Service Unavailable
- DNS hostname doesn't resolve (NXDOMAIN or SERVFAIL)
- Traffic reaches the load balancer but not the pods
- Service works internally (via port-forward) but not externally

## Quick Triage (under 2 minutes)

```bash
# 1. Are pods running?
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<service>

# 2. Does the Service have endpoints?
kubectl get endpoints -n <namespace> <service-name>

# 3. Is the HTTPRoute accepted?
kubectl get httproute -n <namespace> | grep <service>

# 4. Does DNS resolve?
dig <hostname> +short
```

## Diagnostic Layers

Traffic flows through 5 layers. Check from the bottom up — the first failing
layer is usually the root cause.

```
DNS (Route53) → NLB → Envoy Gateway → Service/Endpoints → Pod
```

### Layer 1: Pod Health

**Check:**
```bash
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<service> -o wide
kubectl logs -n <namespace> <pod-name> --tail=50
```

**If pods are CrashLoopBackOff:** See the application logs. Common causes:
missing env vars, database connection failures, OOM. This is an application
issue, not networking.

**If pods are Pending:** Check scheduling: `kubectl describe pod <pod-name>`.
Look for resource limits, node affinity, or Karpenter issues.

### Layer 2: Service and Endpoints

**Check:**
```bash
kubectl get svc -n <namespace> <service-name> -o yaml
kubectl get endpoints -n <namespace> <service-name>
```

**If endpoints are empty:** Pod labels don't match the Service selector, or
pods aren't ready. Compare:
```bash
# Service selector
kubectl get svc -n <namespace> <service-name> -o jsonpath='{.spec.selector}'

# Pod labels
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<service> --show-labels
```

### Layer 3: Envoy Gateway / HTTPRoute

**Check:**
```bash
# Gateway status
kubectl get gateway -n envoy-gateway-system

# HTTPRoute status — is it accepted?
kubectl get httproute -n <namespace> <route-name> -o json | \
  jq '.status.parents[].conditions[] | "\(.type): \(.status) - \(.message)"'

# Envoy proxy pods running?
kubectl get pods -n envoy-gateway-system

# Envoy logs for errors
kubectl logs -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=main-gateway \
  --tail=100 | grep -i "error\|<hostname>"
```

**If HTTPRoute not accepted:** Check that the Gateway exists and the route
references it correctly. Verify the route's `parentRefs` match the Gateway name.

**If HTTPRoute accepted but 502:** The backend Service isn't reachable from
Envoy. Check Layer 2 (endpoints) and verify the Service port matches what
the HTTPRoute `backendRefs` specifies.

### Layer 4: NLB / Target Group

**Check:**
```bash
# Find target groups for this service
aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, '<service>')].TargetGroupArn" \
  --output text

# Check target health
aws elbv2 describe-target-health --target-group-arn <arn>
```

**If targets are unhealthy:** Health check path or port mismatch.
Fix in the Helm values overlay or the `XGatewayNLBListener` claim.

**If no targets registered:** The NLB isn't finding pods. Check Service selector
and TargetGroupBinding configuration.

### Layer 5: DNS (Route53 + external-dns)

**Check:**
```bash
# Does the DNS record exist?
aws route53 list-hosted-zones --query "HostedZones[?contains(Name, '<domain>')].Id" --output text
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?contains(Name, '<hostname>')]"

# external-dns logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns \
  --tail=200 | grep -i "<hostname>"
```

**If record doesn't exist:** external-dns hasn't created it.
- Verify the HTTPRoute has the correct hostname annotation
- Check external-dns logs for errors
- Verify external-dns has Route53 permissions (IRSA role)

**If record exists but points to wrong target:** Stale record from a previous deployment.
external-dns should auto-correct when the HTTPRoute is reconciled.

## cert-manager / TLS Issues

If the service is reachable on HTTP but HTTPS fails:

```bash
# Certificate status
kubectl get certificate -n <namespace> | grep <service>
kubectl describe certificate -n <namespace> <cert-name>

# Full cert chain: Certificate → CertificateRequest → Order → Challenge
kubectl get certificaterequest -n <namespace> | grep <service>
kubectl get order -n <namespace> | grep <service>
kubectl get challenge -n <namespace> 2>/dev/null | grep <service>
```

**Common TLS issues:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Certificate `Ready=False` for hours | CertificateRequest not approved | Check cert-manager logs, ClusterIssuer |
| Order `State=errored` | ACME server rejected it | Check domain validation, DNS propagation |
| Challenge `presented=false` | DNS-01 can't create TXT record | Check external-dns or Route53 permissions |
| `no such issuer` | ClusterIssuer missing | `kubectl get clusterissuer` — verify deployment |

## Permanent Fix Paths

| Problem | Fix repo | Fix file |
|---------|----------|----------|
| HTTPRoute hostname wrong | Service repo | `argocd/<service>/overlays/<env>/values.yaml` |
| NLB listener config | Service repo | `XGatewayNLBListener` claim in overlays |
| DNS not created | Service repo | HTTPRoute hostname in values.yaml (external-dns watches this) |
| ACM certificate | Service repo | Certificate resource or `XIngressACMCertificate` claim |
| Envoy Gateway config | `iac-eks-addons` | Envoy Gateway addon overlays |
| Route53 zone delegation | `iac-terragrunt-core-infra` | DNS zone Terragrunt modules |

## Post-Resolution

1. Verify end-to-end: `curl -v https://<hostname>/health`
2. Check ArgoCD: `argocd app get <app-name>` — should be Synced + Healthy
3. Run `/mobius:validate-service <service> --service-repo <path>` to confirm
