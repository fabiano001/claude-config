# crossplane-xrd-generated-aws-secret

**Role**: Generated AWS Secret XRD — KCL composition that auto-generates
credentials (passwords, bcrypt hashes, signing keys) and stores them in
AWS Secrets Manager.

**Tier**: xrd

## What It Does

Defines the `GeneratedAwsSecret` XRD. When an addon needs database credentials
or API tokens that should be randomly generated and securely stored, this XRD
handles the full lifecycle: generating cryptographically secure credentials via
`function-password-generator`, then storing them in Secrets Manager via KCL.
ExternalSecrets can then sync the Secrets Manager secret into any Kubernetes
namespace. Idempotent — existing credentials are not regenerated.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for GeneratedAwsSecret |
| `composition.yaml` | 4-step pipeline including function-password-generator |
| `crossplane.yaml` | Package metadata |
| `kcl/main.k` | Secrets Manager resource generation |
| `kcl/config.k` | Spec field mappings |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts Configuration CR AND the custom function-password-generator

## Downstream (consumed by)

- api-node-platform addon
- Services needing auto-generated admin credentials (Kargo, Grafana)

## OCI Packages Published

```
kcl-generated-aws-secret:{version}
crossplane-xrd-generated-aws-secret:{version}
```

## Critical Conventions

- `function-password-generator` is a custom JFrog-hosted function — not upstream Crossplane
- Idempotency is critical — function-password-generator checks observed state first
- `skipDependencyResolution: true` always required
- Credentials flow: composition -> Secrets Manager -> ExternalSecrets -> K8s Secret
