# crossplane-xrd-sqs-eventbridge

**Role**: SQS + EventBridge XRD — KCL composition for provisioning event-driven
messaging infrastructure (SQS queues + EventBridge rules) in a single claim.

**Tier**: xrd

## What It Does

Defines the `SQSEventBridge` XRD that provisions a coordinated set of event
infrastructure: an SQS queue (with optional DLQ), an EventBridge rule, and
the necessary IAM policies to wire them together. Teams get a complete
event-routing pipeline from a single Kubernetes claim, without needing to
separately manage queues, rules, and IAM permissions.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema for SQSEventBridge claims |
| `composition.yaml` | Composition pipeline |
| `crossplane.yaml` | Package metadata (`skipDependencyResolution: true`) |
| `kcl/main.k` | SQS + EventBridge resource generation |
| `kcl/config.k` | Spec field mappings |
| `test/*.json` | Test fixtures |

## Upstream (depends on)

- **iac-eks-crossplane** — hosts the Configuration CR that registers this XRD

## Downstream (consumed by)

- Event-driven microservices that need SQS/EventBridge infrastructure
- Claims created in iac-eks-addons overlays

## OCI Packages Published

```
kcl-sqs-eventbridge:{version}                   (KCL module)
crossplane-xrd-sqs-eventbridge:{version}        (Configuration package)
```

Both published to: `boatsgroup.pe.jfrog.io/bg-crossplane/`

## Critical Conventions

- `skipDependencyResolution: true` always required
- SQS queue name follows: `{cluster}-{service}-{purpose}`
- DLQ created automatically when `deadLetterQueueEnabled: true`
