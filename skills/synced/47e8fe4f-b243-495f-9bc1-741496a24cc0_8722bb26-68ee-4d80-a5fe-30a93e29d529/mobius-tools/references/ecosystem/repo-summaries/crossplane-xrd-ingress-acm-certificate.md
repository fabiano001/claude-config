# crossplane-xrd-ingress-acm-certificate

**Role**: ACM Certificate XRD — KCL composition that provisions ACM certificates
for ALB Ingress (as opposed to NLB/Gateway — see crossplane-xrd-gateway-nlb-listener
for that use case).

**Tier**: xrd

## What It Does

Defines the `IngressACMCertificate` XRD. When a service needs HTTPS via ALB
Ingress (Kubernetes Ingress with AWS ALB controller), it needs an ACM certificate
ARN to reference in the Ingress annotations. This XRD creates and manages that
ACM certificate (including DNS validation) through a Crossplane claim. The
composition handles certificate request, DNS validation record creation, and
waiting for validation.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for IngressACMCertificate |
| `composition.yaml` | Composition pipeline |
| `crossplane.yaml` | Package metadata |
| `kcl/main.k` | ACM certificate + DNS validation record generation |
| `kcl/config.k` | Spec field mappings |
| `test/*.json` | Test fixtures |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR

## Downstream (consumed by)

- Services using ALB Ingress (not Gateway API) that need HTTPS
- Claims created in iac-eks-addons overlays

## OCI Packages Published

```
kcl-ingress-acm-certificate:{version}
crossplane-xrd-ingress-acm-certificate:{version}
```

## Critical Conventions

- Different use case from crossplane-xrd-gateway-nlb-listener (ALB vs NLB)
- DNS validation requires Route53 hosted zone access (IRSA for cert-manager or Crossplane)
- `skipDependencyResolution: true` always required
- Certificate ARN available in claim status after provisioning
