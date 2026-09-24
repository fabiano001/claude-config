---
name: mobius-tools
description: DevOps platform toolkit for EKS service deployment, ECS/Jenkins migration, OpenTelemetry instrumentation, ArgoCD hub/spoke clusters, Crossplane XRDs, and Kubernetes service debugging.
metadata:
  author: Boats Group DevOps
  version: 0.5.0
---

# Mobius Tools

Mobius Tools is the DevOps platform CLI and workflow orchestration toolkit for managing EKS-based services across the Boats Group infrastructure.

## Available Workflows

| Workflow | Purpose |
|----------|---------|
| add-service | Create a new service deployment on EKS via ArgoCD |
| update-service | Modify an already-onboarded service (IAM, chart bump, new env) |
| new-xrd | Create a new Crossplane KCL-based XRD repo |
| new-project | Add an ArgoCD project or ApplicationSet |
| debug-appset | Diagnose ApplicationSet discovery failures |
| debug-service | Debug a running EKS service (logs, status, dependencies) |
| instrument-service | Add standardized OTEL instrumentation to a service |
| instrument-library | Add OTEL instrumentation to a shared library |
| new-hub | Create a new ArgoCD hub cluster with full cross-repo wiring |
| new-spoke | Register a new spoke cluster to an existing ArgoCD hub |
| migrate-ecs-service | Migrate an ECS service to EKS with auto-extraction |
| migrate-ecs-ci-cd | Migrate ECS CI/CD pipelines |
| migrate-jenkins-to-gha | Migrate Jenkins pipelines to GitHub Actions |
| migrate-pipeline-to-atlantis | Migrate Terraform pipelines to Atlantis |
| upgrade-eks | Upgrade an EKS cluster to a new Kubernetes version |
| validate-service | Validate service completeness and conventions |
| document-service | Deep-dive a service and generate developer docs |
| document-repo | Generate AGENTS.md and ecosystem context for any repo |
| document-iac | Generate IaC-specific docs and module catalogs |
| document-library | Generate documentation for shared libraries |
| grafana | Create, debug, and explore Grafana dashboards |
| refresh-docs | Scan repos and refresh stale documentation |
| review-docs | Scan repos and propose updates to the docs site |

## Instructions

When a user requests one of these workflows, load the corresponding command specification from `references/commands/mobius/<workflow-name>.md`. Each command file contains the full step-by-step instructions, validation gates, and generation rules.

### Architecture Context

For platform reasoning beyond individual commands, consult:
- `references/docs/architecture/argocd-hub-spoke.md` — ApplicationSet discovery, project RBAC, sync waves
- `references/docs/architecture/environment-model.md` — overlay structure, cluster-to-environment mapping
- `references/docs/architecture/crossplane-flow.md` — XIRSARole claims and available XRDs

### Reference Data

- `references/data/` — AWS SDK IAM mappings, migration readiness data
- `references/templates/` — Bootstrapping templates for AGENTS.md, helm charts
- `references/ecosystem/dependency-graph.yaml` — Cross-repo dependency map

## Platform Conventions

- AWS-only (no multi-cloud)
- ArgoCD hub-spoke model for GitOps delivery
- Crossplane for cloud resource provisioning via Kubernetes
- Kustomize base/overlay pattern for environment promotion
- OpenTelemetry for observability (traces, metrics, logs)
- GitHub Actions for CI/CD
