# Mobius Documentation Mind Map

> Your starting point for navigating all Mobius platform documentation. Follow
> the path that matches your intent.

---

## Quick Navigation

```
                        What do you need?
                              │
      ┌──────────┬────────────┼────────────┬──────────┐
      │          │            │            │          │
  UNDERSTAND  EXECUTE     GET STARTED  JUST DEPLOY  FIX AN
  the platform WORK       as new eng   SOMETHING    INCIDENT
      │          │            │            │          │
      ▼          ▼            ▼            ▼          ▼
  Platform   /mobius:help  Onboarding  Engineer's  Runbooks
  Overview   Workflow Idx  Guide       Guide       (step-by-step
  Arch docs  Cmd Reference First 10    Commands &  incident
      │          │         Minutes     outcomes    procedures)
      ▼          ▼            ▼            ▼          ▼
  Deep dives: Shared:     Then read:  Then read:  Also see:
  • Hub-spoke • Git wkflow • Ecosystem • Glossary  • debug-service
  • Crossplane• JIRA       • Glossary  • Troubleshoot command
  • IRSA model• Validation • Arch docs
  • Networking
```

---

## Path 1: Understand the Platform

Read these in order for a complete mental model:

| Step | Document | What you'll learn |
|------|----------|-------------------|
| 1 | [Platform Overview](architecture/platform-overview.md) | How Mobius works end-to-end |
| 2 | [Ecosystem Map](../ecosystem/master-map.md) | All repos, tiers, relationships |
| 3 | [ArgoCD Hub-Spoke](architecture/argocd-hub-spoke.md) | Control plane topology |
| 4 | [Crossplane Flow](architecture/crossplane-flow.md) | Composition factory pipeline |
| 5 | [IRSA Integration](architecture/irsa-integration.md) | IAM role binding model |
| 6 | [Environment Model](architecture/environment-model.md) | Cluster and overlay structure |
| 7 | [Networking](architecture/networking.md) | Ingress, DNS, TLS |
| 8 | [Resolver Architecture](architecture.md) | How mobius-tools SDK works internally |
| 9 | [Design Decisions](decisions/) | Why the platform is built this way |

---

## Path 2: Execute Platform Work

| I need to... | Command | Workflow doc |
|--------------|---------|--------------|
| Deploy a new service | `/mobius:add-service` | [add-service.md](workflows/services/add-service.md) |
| Create a new XRD | `/mobius:new-xrd` | [new-xrd.md](workflows/xrd/new-xrd.md) |
| Add ArgoCD project/appset | `/mobius:new-project` | [new-project-or-applicationset.md](workflows/argocd/new-project-or-applicationset.md) |
| Debug ApplicationSet | `/mobius:debug-appset` | [debug-applicationset.md](workflows/argocd/debug-applicationset.md) |
| Debug a running service | `/mobius:debug-service` | Self-contained |
| Create a new hub | `/mobius:new-hub` | Self-contained |
| Register a new spoke | `/mobius:new-spoke` | Self-contained |
| Migrate from ECS | `/mobius:migrate-ecs-service` | [migrate-ecs-service.md](workflows/migration/migrate-ecs-service.md) |
| Validate a service | `/mobius:validate-service` | Self-contained |

**Shared patterns** used by multiple commands:
- [Multi-repo git workflow](workflows/shared/multi-repo-git-workflow.md) — branch, commit, push, PR
- [JIRA integration](workflows/shared/jira-integration.md) — ticket prompt, branch naming

Install commands: `bash ../mobius-tools/scripts/install-command-pack.sh --force`

---

## Path 3: Get Started as New Engineer

| Step | Action |
|------|--------|
| 1 | Read [Onboarding Guide](onboarding.md) — zero to working environment in 15 min |
| 2 | Install command pack: `bash scripts/install-command-pack.sh --force` |
| 3 | Run `/mobius:help` to see available commands |
| 4 | Read [Ecosystem Map](../ecosystem/master-map.md) for the big picture |
| 5 | Read [Glossary](glossary.md) if any terms are unfamiliar |

---

## Path 4: Just Deploy Something

Skip the theory — go straight to commands and outcomes:

| Step | Action |
|------|--------|
| 1 | Read [Engineer's Guide](engineer-guide.md) — setup, commands, what to expect |
| 2 | Run the command for your task (guide covers each one) |
| 3 | Check the [Glossary](glossary.md) if any term is unclear |

---

## Full Documentation Map

### Architecture (How the platform works)

| Document | Scope |
|----------|-------|
| [Platform Overview](architecture/platform-overview.md) | End-to-end system model |
| [ArgoCD Hub-Spoke](architecture/argocd-hub-spoke.md) | ArgoCD control plane topology |
| [Crossplane Flow](architecture/crossplane-flow.md) | Composition factory pipeline |
| [IRSA Integration](architecture/irsa-integration.md) | IAM Roles for Service Accounts |
| [Environment Model](architecture/environment-model.md) | Clusters, overlays, environments |
| [Networking](architecture/networking.md) | Envoy Gateway, NLB, DNS, TLS |
| [Resolver Architecture](architecture.md) | How mobius-tools SDK works internally |

### Design Decisions (Why the platform is built this way)

| Document | Decision |
|----------|----------|
| [ADR Index](decisions/) | All architecture decision records |

### Workflows (How to execute platform tasks)

| Document | Scope |
|----------|-------|
| [Workflow Index](workflows/INDEX.md) | Master index of all canonical procedures |
| [Git Workflow](workflows/shared/multi-repo-git-workflow.md) | Multi-repo branch/commit/PR |
| [JIRA Integration](workflows/shared/jira-integration.md) | Ticket tracking integration |

### Runbooks (How to fix common incidents)

| Runbook | When to use |
|---------|-------------|
| [ArgoCD Sync Stuck](runbooks/argocd-sync-stuck.md) | App won't sync, stuck terminating |
| [Crossplane Claim Not Ready](runbooks/crossplane-claim-not-ready.md) | XRD claim errors, stuck resources |
| [Service Unreachable](runbooks/service-unreachable.md) | 502/503, DNS not resolving |
| [IRSA AccessDenied](runbooks/irsa-access-denied.md) | AWS permission errors from pods |
| [ApplicationSet Not Discovering](runbooks/applicationset-not-discovering.md) | config.yaml merged but no Application created |

### Guides (How to get things done)

| Document | Description |
|----------|-------------|
| [Engineer's Guide](engineer-guide.md) | Commands and outcomes — no internals |
| [Onboarding](onboarding.md) | New engineers |
| [Troubleshooting](troubleshooting.md) | When things break |
| [Agent Interop](agent-interop.md) | Claude + Codex handoff |
| [Glossary](glossary.md) | Terminology reference |

### Ecosystem Reference (Source of truth)

| Artifact | Purpose |
|----------|---------|
| [Ecosystem Map](../ecosystem/master-map.md) | Full platform topology |
| [Dependency Graph](../ecosystem/dependency-graph.yaml) | Machine-readable repo graph |
| [Dependency Graph Visual](dependency-graph-visual.md) | Mermaid + ASCII diagrams |

---

## Canonical Artifacts (Source of Truth)

| Artifact | Why it matters |
|----------|----------------|
| `ecosystem/master-map.md` | Full topology and mental model for all platform repos |
| `ecosystem/dependency-graph.yaml` | Canonical machine-readable dependency graph |
| `scripts/resolve-deps.sh` | Shared runtime bootstrap for cross-repo access |
| `npx mobius-validate-graph` | Drift detection between per-repo frontmatter and graph |
| `docs/workflows/INDEX.md` | Canonical, agent-neutral execution workflows |

## Terminology Note

- Engineer-facing docs use **service deployment**.
- Internal file paths and schema often use **addon** (for example,
  `argocd/{addon}/overlays/{env}/config.yaml`).

Both terms refer to the same deployment workflow unit.
