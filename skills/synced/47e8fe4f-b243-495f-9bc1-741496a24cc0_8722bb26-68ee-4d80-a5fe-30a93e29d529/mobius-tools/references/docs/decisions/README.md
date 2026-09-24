# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Mobius platform.
Each ADR captures the context, decision, and consequences of a significant architectural choice.

## Format

Each ADR follows this structure:

- **Title**: Short descriptive name
- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: What prompted the decision
- **Decision**: What was decided
- **Consequences**: What follows from the decision (positive and negative)

## Naming Convention

Files are numbered sequentially: `NNN-short-description.md`

## Adding a New ADR

1. Copy the template below
2. Number it sequentially
3. Fill in all sections
4. Submit as a PR for review

## Template

```markdown
# ADR-NNN: Title

**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-NNN

**Date**: YYYY-MM-DD

## Context

What is the issue that we're seeing that is motivating this decision?

## Decision

What is the change that we're making?

## Consequences

### Positive
- What becomes easier or better

### Negative
- What becomes harder or worse

### Neutral
- What stays the same but is worth noting
```

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-centralized-resolver-sdk.md) | Centralized resolver SDK in mobius-tools | Accepted | 2025-01-15 |
| [002](002-hub-spoke-argocd.md) | Hub-spoke ArgoCD over single-cluster | Accepted | 2024-11-01 |
| [003](003-kcl-over-go-templates.md) | KCL over Go templates for Crossplane compositions | Accepted | 2025-02-01 |
| [004](004-standardized-otel-instrumentation.md) | Standardized OpenTelemetry instrumentation for Node.js services | Proposed | 2026-03-02 |
