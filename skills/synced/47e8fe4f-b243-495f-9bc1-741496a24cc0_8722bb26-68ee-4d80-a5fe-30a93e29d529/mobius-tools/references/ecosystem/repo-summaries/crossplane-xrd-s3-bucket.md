# crossplane-xrd-s3-bucket

**Role**: S3 Bucket XRD — KCL composition that provisions S3 buckets with
standard BoatsGroup configuration (versioning, encryption, lifecycle).

**Tier**: xrd

## What It Does

Defines the `S3Bucket` / `XS3Bucket` Crossplane XRD. Teams create an `S3Bucket`
claim to get a fully-configured S3 bucket with consistent defaults: SSE-KMS
encryption, versioning enabled, lifecycle rules, and appropriate bucket policies.
The KCL composition handles all the AWS-specific configuration in a single
Kubernetes-native claim.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for S3Bucket claims |
| `composition.yaml` | Composition pipeline |
| `crossplane.yaml` | Package metadata (`skipDependencyResolution: true`) |
| `kcl/main.k` | S3 bucket resource generation |
| `kcl/config.k` | Spec field mappings |
| `test/*.json` | Test fixtures |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR that registers this XRD

## Downstream (consumed by)

- Any addon needing S3 storage (Loki, application data buckets)
- Claims created in iac-eks-addons or iac-eks-observability

## OCI Packages Published

```
kcl-s3-bucket:{version}                   (KCL module)
crossplane-xrd-s3-bucket:{version}        (Configuration package)
```

Both published to: `boatsgroup.pe.jfrog.io/bg-crossplane/`

## Critical Conventions

- `skipDependencyResolution: true` always required
- Bucket names must be globally unique — use `{cluster}-{purpose}` pattern
- Never manually edit auto-managed version fields
