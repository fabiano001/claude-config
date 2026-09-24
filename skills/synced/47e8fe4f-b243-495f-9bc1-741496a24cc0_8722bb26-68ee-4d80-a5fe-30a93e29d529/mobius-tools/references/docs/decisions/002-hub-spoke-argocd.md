# ADR-002: Hub-Spoke ArgoCD Architecture

**Status**: Accepted

**Date**: 2024-11-01

## Context

The Mobius platform manages multiple AWS EKS clusters across different AWS accounts and regions:
- Operations account: central hub cluster
- Business Group (BG) accounts: spoke clusters for workloads (QA, staging, production)

Early designs considered a multi-cluster mesh where each cluster runs its own independent ArgoCD instance, leading to:
- Duplicate ArgoCD configurations across clusters
- Inconsistent deployment policies and RBAC across teams
- No single source of truth for deployment decisions
- Difficulty enforcing platform standards at scale

## Decision

Implement a **hub-spoke architecture** where:
- A single **hub ArgoCD instance** runs in the operations account's central cluster
- **Spoke clusters** in other accounts are registered as remote clusters in hub ArgoCD
- The hub manages all service deployments, addon installations, and policy enforcement
- Spoke clusters communicate back to the hub via Kubernetes cluster secrets

All ApplicationSets, sync waves, and RBAC policies live in the hub cluster, with ApplicationSet discovery generators pulling config from the spoke clusters' repositories.

## Consequences

### Positive

- **Centralized control**: All deployment decisions flow through one ArgoCD instance. Teams can inspect and audit deployments from a single pane of glass.
- **Consistent policy enforcement**: RBAC, sync policies, and deployment standards are defined once in the hub and applied uniformly to all spokes.
- **Single reconciliation loop**: One hub controller manages deployment ordering via sync waves, eliminating race conditions between independent clusters.
- **Simplified multi-cluster management**: Adding a new cluster is straightforward — register it as a secret in the hub and it automatically inherits hub policies.

### Negative

- **Hub is a single point of failure**: If the hub cluster becomes unavailable, no new deployments can proceed across any spoke cluster. Existing workloads continue running, but GitOps reconciliation stops.
- **Cross-account networking complexity**: Spoke clusters must maintain secure network connectivity (VPN, PrivateLink, or cross-account IAM) to the hub for polling and authentication.
- **Hub performance at scale**: As spoke clusters increase, hub ArgoCD workload grows. Large ApplicationSets or frequent reconciliations can become resource-intensive.

### Neutral

- Spoke clusters can still run local tooling (monitoring, logging) independent of the hub, allowing some decentralization of observability while keeping deployment centralized.
