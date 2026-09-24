# crossplane-xrd-irsa-role

**Role**: IAM Role XRD (most used) — KCL composition that creates IRSA roles
via Crossplane, enabling Kubernetes service accounts to assume AWS IAM roles.

**Tier**: xrd

## What It Does

Defines the `IRSARole` / `XIRSARole` Crossplane XRD. When an addon team creates
an `IRSARole` claim in `iac-eks-addons`, Crossplane runs this KCL
composition to create the AWS IAM role with the correct trust policy (OIDC
federation), role name, and attached policies. This is the most frequently used
XRD in the platform — virtually every addon needs an IRSA role.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema — API contract for IRSARole claims |
| `composition.yaml` | Composition pipeline (function-kcl -> function-auto-ready) |
| `crossplane.yaml` | Package metadata (`skipDependencyResolution: true`) |
| `kcl/main.k` | Core composition logic — generates IAM role + trust policy |
| `kcl/config.k` | Maps XR spec fields to KCL variables |
| `kcl/helpers.k` | Computed values (ARNs, policy docs) |
| `test/*.json` | Test fixtures for `make test` |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR that registers this XRD on clusters
- **iac-eks-addons** — addon `IRSARole` claims are created here

## Downstream (consumed by)

- **crossplane-xrd-karpenter-node-role** — extends irsa-role pattern for Karpenter
- Every addon in iac-eks-addons that needs AWS permissions

## OCI Packages Published

```
kcl-irsa-role:{version}                   (KCL module)
crossplane-xrd-irsa-role:{version}        (Configuration package)
```

Both published to: `boatsgroup.pe.jfrog.io/bg-crossplane/`

## Critical Conventions

- `skipDependencyResolution: true` in crossplane.yaml — never remove
- Never manually edit `composition.yaml` KCL version or `kcl.mod` version
- Use `make test` before tagging releases
- API access pattern: `spec.X` (not `spec.parameters.X`)
