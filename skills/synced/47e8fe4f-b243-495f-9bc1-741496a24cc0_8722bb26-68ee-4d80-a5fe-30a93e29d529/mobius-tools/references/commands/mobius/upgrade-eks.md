---
name: upgrade-eks
description: Upgrade an EKS cluster one Kubernetes minor version across all required repos
argument-hint: <cluster-name> [target-version] [ticket]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# EKS Cluster Version Upgrade

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-5` or OpenAI `o3`).
>
> This workflow touches 4–6 repositories with hard ordering constraints between
> phases and between clusters. A missed AMI alias, an un-audited PodDisruptionBudget,
> or an out-of-order phase causes stalled node drains, unschedulable workloads, or a
> control plane that cannot be rolled back after its 7-day window. Opus-tier
> reasoning is required for correctness.

This command upgrades **one cluster** by **one Kubernetes minor version**. It is not a
campaign runner: to move a cluster two minors, or to move the whole estate, invoke it
once per cluster per minor version, in the order given in
[`upgrade-eks/cluster-topology.md`](upgrade-eks/cluster-topology.md).

> **Self-contained**: This command documents the full cross-repo workflow.
> No external workflow doc required.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Karpenter Autoscaling](../../docs/architecture/karpenter-autoscaling.md) — NodePool provisioning, drift, bootstrap node group
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — which hub manages which spoke, ApplicationSet discovery
> - [Environment Model](../../docs/architecture/environment-model.md) — cluster naming, overlay structure, account topology
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — addon service account roles that must survive the upgrade
> - [Networking](../../docs/architecture/networking.md) — subnet IP capacity, NLB listeners

---

## Canonical Rules

- **One minor version per run.** EKS permits only one minor per in-place upgrade. Refuse a two-minor jump; propose sequential runs.
- **One cluster per run.** Never batch clusters.
- **Confirm the live version via the AWS API, never from the repo.** The repo may be ahead of an unapplied plan.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before intake begins.
- JIRA ticket is prompted before intake questions — strongly encouraged but skippable. It drives every commit message.
- No file generation on `main` — a feature branch MUST exist in the affected repo before any edit.
- No file generation before intake is confirmed.
- **Disruption readiness (Phase 2) MUST pass before the control plane changes (Phase 3).** A PDB with `disruptionsAllowed: 0` stalls Karpenter drift silently and indefinitely.
- **Never run `kubectl` without asserting which cluster it is pointed at.** Use the `expect_ctx` guard from Phase 0 Step 0.4 at the top of every `kubectl` block, including in phases that never switch context. Because the estate order upgrades hubs first, a spoke's checks run against a leftover hub context **pass**, which turns Phase 8 from a completion gate into a rubber stamp. A **spoke** run spans two clusters in two different AWS accounts, so a context switch is often a credential switch too; a **self-hub** run (`ops-qa`, `ops-prod`) is one cluster with one context, and hub-vs-target comparisons are not available to make.
- **NodePool names are not EC2NodeClass names.** NodePools are `default`, `application`, `monitoring`, `arc-*`; their NodeClasses carry the `-nodes` suffix. `karpenter.sh/nodepool` holds the **NodePool** name, so a selector built from a NodeClass name matches nothing and exits 0 — which is indistinguishable from a converged pool.
- **Karpenter drift must be frozen before the control plane apply and unfrozen only when the AMI alias is re-pinned.** An unchanged `alias:` re-resolves against the new control plane version the moment Phase 3.1 applies, so uncontrolled node replacement would otherwise begin during Phase 3 and run through the multi-PR window of Phases 3–5.
- **The agent never pushes branches, opens PRs, or applies infrastructure.** Terraform applies go through Atlantis; manifest applies go through ArgoCD. Both are the user's to trigger.
- Do not advance a phase until the user confirms the previous phase's PR is **merged and applied**.
- No completion claim before Phase 8 verification passes.

---

## Q0 Gate (MANDATORY)

> **STOP: Answer these questions FIRST before ANY file generation.**

```
Q0: Which cluster is being upgraded?
    Valid clusters and their accounts/hubs: see upgrade-eks/cluster-topology.md

Q1: What is the cluster's CURRENT version, per the AWS API?
    aws eks describe-cluster --name <cluster> --query 'cluster.[version,platformVersion,status]'
    Do NOT read this from terragrunt.hcl. If the API call returns empty, see the
    cross-account caveat in upgrade-eks/phase0-intake-preflight.md.

Q2: What is the target version?
    MUST be current + exactly one minor. If the user asks for more, stop and
    propose sequential runs.

Q3: Is there a JIRA ticket?
    Prompt for it. Strongly encouraged — it prefixes every commit message.

Q4: For prod clusters (ops-prod, bg-qa, bg-prod) — is there a freeze window and
    rollback sign-off?
    The in-place rollback window is 7 days from the control plane upgrade. That
    deadline, not the upgrade itself, is the real go/no-go date.
```

Do not proceed until Q0–Q3 are answered (Q4 for prod clusters). Confirm all values back
to the user before starting Phase 0.

---

## Version-Specific Knowledge

> **Module**: Read [`upgrade-eks/version-deltas.md`](upgrade-eks/version-deltas.md) for
> the breaking changes, target addon versions, and AMI alias targets for the specific
> source→target pair.
>
> **This is the module with a shelf life.** It is refreshed once per campaign. If its
> `Observed` date is more than a few weeks stale, or if it has no section for the
> requested source→target pair, re-derive the facts from the AWS APIs and Kubernetes
> release notes and update the module before proceeding. Everything else in this
> command is version-agnostic doctrine.

> **Module**: Read [`upgrade-eks/cluster-topology.md`](upgrade-eks/cluster-topology.md)
> for the cluster inventory, hub/spoke mapping, terragrunt unit paths, upgrade order,
> and the Karpenter NodeClass inventory.

---

## Phase 0 — Intake & Preflight

> **Module**: Read [`upgrade-eks/phase0-intake-preflight.md`](upgrade-eks/phase0-intake-preflight.md) and execute all steps before continuing.

Derives every input from AWS rather than asking, then runs the preflight gates. **All
gates must pass.** For EKS Upgrade Insights that means `ERROR` or `UNKNOWN` stops the run —
a `WARNING` applies to Kubernetes N+2 or later and is *recorded, not blocking*. Blocking on
`WARNING`s deadlocks the estate, since the next upgrade is the prerequisite for reaching the
version they refer to.

---

## Phase 1 — Deprecated API & Manifest Audit

> **Module**: Read [`upgrade-eks/phase1-api-audit.md`](upgrade-eks/phase1-api-audit.md) and execute all steps before continuing.

Static scan of rendered manifests plus version-specific behaviour greps. Read-only —
no repo changes.

---

## Phase 2 — Disruption Readiness

> **Module**: Read [`upgrade-eks/phase2-disruption-readiness.md`](upgrade-eks/phase2-disruption-readiness.md) and execute all steps before continuing.

**Gate for Phase 3.** Audits PDBs, Karpenter disruption budgets, topology spread
constraints, and admission webhook timeouts. Any PDB with `disruptionsAllowed: 0` is a
hard blocker.

---

## Phase 3 — Control Plane

> **Module**: Read [`upgrade-eks/phase3-control-plane.md`](upgrade-eks/phase3-control-plane.md) and execute all steps before continuing.

**Four sequential PRs.** First a **drift freeze** in `iac-eks-addons` /
`iac-eks-observability` (Step 3.0, synced via ArgoCD) — without it, the control plane apply
starts uncontrolled node replacement on its own, because the Karpenter AMI alias is
version-agnostic. Then three in `iac-terragrunt-core-infra`: control plane + headroom,
kube-proxy, bootstrap AMI, each applied via Atlantis before the next begins.

> **Precondition**: if `vpc-cni` is behind the target Kubernetes API, Phase 4's
> `vpc-cni` hops run **before** this phase. See `version-deltas.md`.

---

## Phase 4 — Managed Addon Versions

> **Module**: Read [`upgrade-eks/phase4-managed-addons.md`](upgrade-eks/phase4-managed-addons.md) and execute all steps before continuing.

**Repo**: `terraform-module-eks` + per-unit version pin. The four addons not overridden
per-cluster live in the shared module's defaults — this phase is why they don't drift
silently.

---

## Phase 5 — Addon Chart Compatibility

> **Module**: Read [`upgrade-eks/phase5-chart-compat.md`](upgrade-eks/phase5-chart-compat.md) and execute all steps before continuing.

**Repos**: `iac-eks-addons`, `iac-eks-observability`. Compatibility check first; bumps
only if compat requires them, and always as separate PRs.

---

## Phase 6 — Karpenter Data Plane

> **Module**: Read [`upgrade-eks/phase6-karpenter-dataplane.md`](upgrade-eks/phase6-karpenter-dataplane.md) and execute all steps before continuing.

**Repos**: `iac-eks-addons`, `iac-eks-observability`. One NodePool per commit, per
branch, per PR — this is what makes a bad AMI attributable and independently revertible.
Each PR does **two** things for its NodePool: re-pin the AMI alias *and* lift that pool's
Step 3.0 drift freeze. Neither works without the other, and no `nodes: "0"` / `Drifted`
budget may survive this phase.

---

## Phase 7 — ArgoCD Sync Verification

> **Module**: Read [`upgrade-eks/phase7-argocd-verification.md`](upgrade-eks/phase7-argocd-verification.md) and execute all steps before continuing.

**Mixed context — this phase is not "the hub phase".** ArgoCD `Application` and
`ApplicationSet` objects live on the **hub** (steps 7.1, 7.2, 7.4), but the CRDs and
Crossplane resources they deploy live on the **target** (steps 7.3, 7.5). Switch per step
with the `expect_ctx` guard; do not set the hub context once and run the whole phase there,
or the upgraded cluster's CRDs and providers are never inspected. On a **self-hub** run
(`ops-qa`, `ops-prod`) hub and target are the same cluster and one context covers both.

---

## Phase 8 — Post-Upgrade Validation

> **Module**: Read [`upgrade-eks/phase8-post-validation.md`](upgrade-eks/phase8-post-validation.md) and execute all steps before continuing.

Control plane, kubelet, and addon versions all on target; traffic signals green. **No
completion claim before this passes.**

---

## Phase 9 — Cleanup

> **Module**: Read [`upgrade-eks/phase9-cleanup.md`](upgrade-eks/phase9-cleanup.md) and execute all steps before continuing.

Restores bootstrap headroom, removes temporary annotations, cleans superseded launch
templates, and updates `version-deltas.md` with the new observed state.

---

## Git Workflow

> **Module**: Read [`upgrade-eks/commit-push-pr.md`](upgrade-eks/commit-push-pr.md) for
> the branch naming rules, commit message conventions, and the apply-gated PR contract.
> This module is called from **every** phase that writes files.

---

## Change Safety

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> before requesting any PR, and again after PR feedback.

## Completion Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and
> [`shared/repo-roles.md`](shared/repo-roles.md) when writing the final summary.

State plainly:

- Which cluster moved from which version to which version, confirmed via the AWS API.
- Every PR opened, per repo, and its merge/apply status.
- **The rollback deadline** — 7 days from the control plane apply, with the absolute date.
- Any drift or debt found and deliberately not fixed, with a ticket reference.
- Which clusters remain on the old version and what the next run is.
