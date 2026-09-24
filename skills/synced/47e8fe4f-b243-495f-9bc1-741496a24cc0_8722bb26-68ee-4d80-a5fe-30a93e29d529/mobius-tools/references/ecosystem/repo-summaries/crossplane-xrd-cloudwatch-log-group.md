# crossplane-xrd-cloudwatch-log-group

**Role**: CloudWatch Log Group XRD — KCL composition that provisions CloudWatch
Logs log groups with configurable retention, log class, and optional KMS
encryption at rest.

**Tier**: xrd

## What It Does

Defines the `XCloudWatchLogGroup` XRD (api: `aws.bgrp.io/v1alpha1`, cluster-scoped).
Composes exactly one managed resource: `Group.cloudwatchlogs.aws.upbound.io`.
Surfaces the log group ARN on `status.logGroupArn` so consumers can reference it.

Built for the EMR-on-EKS POC (DEVOPS-6622), where Spark drivers and executors
need a log group to write to, but the schema is deliberately general-purpose so
any team needing a managed log group can use it.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for XCloudWatchLogGroup |
| `composition.yaml` | Composition pipeline (function-kcl → patch-and-transform → auto-ready) |
| `crossplane.yaml` | Package metadata |
| `kcl/log_group.k` | CloudWatch Logs Group resource generation |
| `kcl/config.k` | Spec field mappings |
| `kcl/helpers.k` | Tag merge + optional-KMS fragment |
| `scripts/inline-kcl.py` | Inlines kcl/ so the pipeline can render before the OCI tag exists |
| `test/*.json` | Test fixtures (incl. regression guards for two KCL traps) |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR; also owns the
  `provider-aws-cloudwatchlogs` provider this XRD requires (added by DEVOPS-6730)

## Downstream (consumed by)

- The `emr` addon in iac-eks-addons (EMR-on-EKS Spark log destination)
- Any service needing a managed CloudWatch Logs log group

## OCI Packages Published

```
kcl-cloudwatch-log-group:{version}
crossplane-xrd-cloudwatch-log-group:{version}
```

## Critical Conventions

- Requires `provider-aws-cloudwatchlogs` >= v2.6.1 to be installed and Healthy
- Managed resources use `providerConfigRef.name: default-v2` (not the legacy `default`)
- `skipDependencyResolution: true` always required
- AppProject `clusterResourceWhitelist` in iac-eks-argocd must include
  `cloudwatchlogs.aws.upbound.io`, or ArgoCD refuses to manage the composed Group
- **KCL traps encoded as regression tests** — `retentionInDays: 0` must survive
  (KCL's `or` treats 0 as falsy), and tag merging must use a comprehension
  rebuild rather than `{**a, **b}` or `a | b` (both raise on key collision).
  See the repo's `CLAUDE.md` § KCL Traps.
- `crossplane beta render` no longer exists (CLI v2.x) — use
  `crossplane composition render`, or `make render-local` before the first tag
