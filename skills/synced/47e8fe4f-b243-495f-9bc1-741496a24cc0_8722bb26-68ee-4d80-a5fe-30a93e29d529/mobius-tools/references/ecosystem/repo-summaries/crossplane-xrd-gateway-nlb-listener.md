# crossplane-xrd-gateway-nlb-listener

**Role**: Gateway NLB Listener XRD — KCL composition that provisions a Network
Load Balancer with TLS termination for Envoy Gateway (Gateway API).

**Tier**: xrd

## What It Does

Defines the `GatewayNLBListener` XRD. ACM certificates cannot be exported to
Kubernetes Secrets, so Envoy Gateway cannot use them directly. This XRD solves
that problem: it creates an NLB that terminates TLS using the ACM certificate,
then forwards decrypted traffic to Envoy Gateway on port 80. The composition
creates: NLB, Target Group, TLS Listener (443), and a TargetGroupBinding CR
that links the AWS TG to the Envoy Gateway Kubernetes service.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for GatewayNLBListener |
| `composition.yaml` | 2-step pipeline (function-kcl -> function-auto-ready) |
| `crossplane.yaml` | Package metadata |
| `kcl/main.k` | NLB + TG + Listener + TargetGroupBinding generation |
| `kcl/helpers.k` | ARN patching via `_ocds` (observed composed resources) |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR

## Downstream (consumed by)

- envoy-gateway addon (in helm-charts) — typically one claim per cluster

## OCI Packages Published

```
kcl-gateway-nlb-listener:{version}
crossplane-xrd-gateway-nlb-listener:{version}
```

## Critical Conventions

- Uses `_ocds` for ARN patching — no function-patch-and-transform needed
- TargetGroupBinding is a Kubernetes CR (not AWS) created via provider-kubernetes
- `skipDependencyResolution: true` always required
- Typically one claim per cluster (unlike IRSARole which has many)
