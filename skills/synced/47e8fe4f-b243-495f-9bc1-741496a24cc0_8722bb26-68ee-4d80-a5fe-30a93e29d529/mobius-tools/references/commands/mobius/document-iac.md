---
name: document-iac
description: Generate IaC-specific documentation — Terraform modules, GitOps addon catalogs, state management, and infrastructure dependency maps
argument-hint: [repo-path] [--archetype auto|terraform-stack|gitops-addons|gitops-control-plane]
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Document an Infrastructure-as-Code Repository

## Model Recommendation

> **Model:** Opus recommended for large or complex IaC repos (multiple environments,
> many Terraform modules, or dense Crossplane XRD hierarchies); sonnet sufficient
> for small or well-structured repos. Use whatever model is active in your session.

This command generates infrastructure-specific documentation that
`/mobius:document-repo` alone cannot produce at sufficient depth. It runs
`document-repo`'s core analysis first (AGENTS.md, ecosystem context, platform
deps), then layers IaC-archetype-specific analysis passes and output files on
top.

**When to use this vs document-repo:**

| Scenario | Use |
|----------|-----|
| Any non-IaC repo (Node.js, Go, Rust, Java, Python) | `/mobius:document-repo` |
| Any application service (even if deployed via IaC) | `/mobius:document-service` |
| Terraform/Terragrunt provisioning stacks | **`/mobius:document-iac`** |
| GitOps declarative config repos (ArgoCD, FluxCD) | **`/mobius:document-iac`** |
| Crossplane XRD/Composition repos | **`/mobius:document-iac`** |
| Helm chart library repos | **`/mobius:document-iac`** |
| Pulumi/CDK/CloudFormation stacks | **`/mobius:document-iac`** |
| Ansible/Salt/Chef/Puppet config repos | **`/mobius:document-iac`** |

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [`ecosystem/master-map.md`](../../ecosystem/master-map.md) — full platform topology
> - [`ecosystem/dependency-graph.yaml`](../../ecosystem/dependency-graph.yaml) — authoritative cross-repo dependency map
> - [`document-repo.md`](document-repo.md) — base command this extends
> - [`document-repo/discovery-analysis.md`](document-repo/discovery-analysis.md) — base analysis module

Key architectural facts:

1. **Extends document-repo, does not replace it.** This command runs document-repo's
   Phase 0–6 as a base layer, then adds IaC-specific analysis passes and output
   files. All of document-repo's canonical rules, validation checks, and commit
   workflow apply unchanged.

2. **Archetype-driven analysis.** IaC repos fall into fundamentally different
   paradigms that need different documentation strategies. The command auto-detects
   the archetype or accepts an explicit flag. Each archetype activates a different
   set of analysis passes and output templates.

3. **Non-destructive for existing docs.** GitOps addon repos often have rich
   per-addon READMEs. The command indexes and links to these rather than
   regenerating them. For Terraform stacks, it generates new IaC-specific docs
   alongside the standard document-repo output.

4. **Confidence labeling.** All dependency and relationship assertions are labeled
   as **Observed** (directly parsed from code/manifests) or **Inferred** (derived
   from naming conventions, directory structure, or heuristics). This prevents
   false confidence in generated documentation.

---

## Canonical Rules

All of [`document-repo.md`](document-repo.md) Canonical Rules 1–17 apply. The
following additional rules are specific to this command:

18. IaC archetype MUST be detected or explicitly provided before Phase 2 IaC analysis begins.
19. Terraform module interfaces (variables, outputs) MUST be parsed from `.tf` files, never inferred from usage alone.
20. GitOps addon documentation MUST index existing per-addon READMEs rather than regenerating content that already exists.
21. Environment-specific overrides MUST be documented as a matrix showing what differs per environment.
22. State backend configuration MUST be documented but MUST NOT include secrets, tokens, or account-specific lock table names in generated docs — reference them by variable name only.
23. Every dependency assertion in generated docs MUST be labeled `[Observed]` or `[Inferred]` with evidence source.
24. For GitOps repos, the addon catalog MUST be generated from directory scanning, not from assumptions about what should exist.
25. Cross-environment drift (files present in one environment overlay but not others) MUST be flagged in a dedicated section.

---

## Phase 0 — Git + Environment Preflight

> **Identical to document-repo Phase 0.** Run all steps from
> [`document-repo.md`](document-repo.md) § Phase 0 (Steps 0a–0d).

---

## Phase 1 — Repo Detection, Archetype Classification & Compatibility

### Steps 1.1–1.6: Base Detection

> Run all steps from [`document-repo.md`](document-repo.md) § Phase 1.
> Record `primary_type` and `secondary_signals` as usual.

### Step 1.7: IaC Archetype Classification

Using Phase 1 detection results plus additional IaC-specific scans, classify the
repo into one of the supported archetypes.

**If `--archetype` argument was provided and is not `auto`**: Use the provided
value. Skip auto-detection but still validate it makes sense (warn if signals
contradict the explicit archetype).

**If `--archetype auto` or no argument**: Auto-detect using this priority table:

| Priority | Signal | Archetype |
|----------|--------|-----------|
| 1 | `*.tf` files + `backend.tf` or `terraform.tfvars` + environment directories | `terraform-stack` |
| 2 | `terragrunt.hcl` at root or in subdirectories | `terraform-stack` (terragrunt variant) |
| 3 | `applicationsets/` directory OR `ApplicationSet` YAML files + (`projects/` OR `hubs/` OR `bootstrap/`) | `gitops-control-plane` |
| 4 | `applicationsets/` directory + `argocd/` with per-addon overlays (no `projects/` or `hubs/`) | `gitops-addons` (appset-managed variant) |
| 5 | `argocd/` directory + `kustomization.yaml` files + overlay directories (no ApplicationSets) | `gitops-addons` |
| 6 | `Chart.yaml` at root + `templates/` directory | `helm-chart` |
| 7 | `*.kcl` files + `kcl.mod` | `crossplane-xrd` |
| 8 | `fluxcd/` or `flux-system/` directory + `kustomization.yaml` | `gitops-flux` |
| 9 | `Pulumi.yaml` or `Pulumi.*.yaml` | `pulumi-stack` |
| 10 | `cdk.json` or `cdk.context.json` | `cdk-stack` |
| 11 | `template.yaml` or `template.json` (CloudFormation) | `cloudformation-stack` |
| 12 | `playbook*.yml` or `roles/` directory (Ansible) | `config-management` |
| 13 | `*.sls` files or `salt/` directory | `config-management` |

**Disambiguation: `gitops-control-plane` vs `gitops-addons`**

Both archetypes may contain ArgoCD YAML, but they serve fundamentally different
roles:

| Signal | `gitops-control-plane` | `gitops-addons` |
|--------|------------------------|-----------------|
| Defines ApplicationSets | Yes (primary content) | May reference but doesn't define |
| Contains `projects/`, `hubs/`, `teams/` | Yes | No |
| Contains `bootstrap/` (ArgoCD install) | Often | No |
| Per-addon overlay directories | Maybe (as targets) | Yes (primary content) |
| Contains `terraform/` for IRSA/IAM | Often (hybrid) | Rare |
| Primary purpose | Orchestrates what gets deployed where | Declares addon configs per environment |

If both control-plane signals AND addon overlay signals are present in the same
repo, classify as `gitops-control-plane` (it's the superset). The hybrid
`terraform/` directory within a control-plane repo is handled as a sub-section,
not a separate archetype.

If no archetype matches, fall back to `document-repo` behavior and inform the user:

```
No IaC archetype detected for this repository. Falling back to standard
/mobius:document-repo behavior. If this is an IaC repo, re-run with an
explicit --archetype flag.
```

### Step 1.8: Present Archetype + Existing Docs

```
IaC Documentation scan for: <repo-name>
  Archetype:   <archetype> (auto-detected | explicit)
  Variant:     <variant if applicable, e.g., "terragrunt", "kustomize+helm">
  Ecosystem:   <Registered (tier: X) | NOT registered>

  Base docs (document-repo):
    AGENTS.md              — <exists | MISSING>
    docs/README.md         — <exists | MISSING>
    docs/architecture.md   — <exists | MISSING>
    docs/workflow.md       — <exists | MISSING>
    docs/dependencies.md   — <exists | MISSING>
    .claude/ecosystem.md   — <exists | MISSING>

  IaC-specific docs (this command):
    docs/iac-overview.md              — <will generate>
    docs/module-catalog.md            — <will generate> (terraform-stack only)
    docs/addon-catalog.md             — <will generate> (gitops-addons only)
    docs/control-plane-topology.md    — <will generate> (gitops-control-plane only)
    docs/appset-catalog.md            — <will generate> (gitops-control-plane only)
    docs/project-rbac.md              — <will generate> (gitops-control-plane only)
    docs/environment-matrix.md        — <will generate>
    docs/state-and-backends.md        — <will generate> (terraform-stack only)
    docs/variables-schema.md          — <will generate> (terraform-stack only)
    docs/overlay-structure.md         — <will generate> (gitops-addons only)
```

---

## Phase 2 — Deep Analysis

### Step 2.0: Base Analysis

> Run document-repo's Phase 2 in full — both Track A and Track B.
> Read [`document-repo/discovery-analysis.md`](document-repo/discovery-analysis.md).
> All Track A and Track B outputs feed into Phase 3 planning.

### Step 2.IaC: IaC-Specific Analysis

After Track A + B complete, run archetype-specific analysis passes.

> **Module**: Read [`document-iac/iac-analysis.md`](document-iac/iac-analysis.md)
> and execute the archetype-appropriate analysis passes.

This module contains:

- **Terraform Stack Analysis** (Steps T.1–T.8): Module inventory with source/version,
  provider configuration matrix, backend/state configuration per environment,
  variable schema extraction (`variables.tf` + `terraform.tfvars`), output
  inventory, resource-type census, data source dependency map, cross-environment
  drift detection.

- **GitOps Addons Analysis** (Steps G.1–G.7): Addon directory inventory, per-addon
  Kustomize base/overlay structure, Helm values file detection, config.yaml schema
  extraction, Crossplane claim detection, ArgoCD ApplicationSet wiring discovery,
  existing README indexing.

- **GitOps Control-Plane Analysis** (Steps A.1–A.6): ApplicationSet inventory with
  generator type classification, hub-spoke topology mapping (hubs → spoke clusters
  → target namespaces), project RBAC inventory (source repos, destinations, roles),
  team/tenant configuration extraction, bootstrap configuration (ArgoCD install
  method, Helm values, sync waves), hybrid Terraform detection (IRSA roles, spoke
  provisioning within the control-plane repo).

- **Common IaC Analysis** (Steps C.1–C.3): Environment matrix extraction (which
  environments exist, naming convention, account mapping), CI/CD pipeline
  detection (Terraform plan/apply workflows, GitOps sync triggers), secret/
  sensitive value reference inventory (by variable name only, never values).

### Session Persistence

All IaC analysis outputs persist to `.mobius-docs-session/document-iac/`:

```text
.mobius-docs-session/
  document-repo/          ← base analysis (from document-repo)
    track-a.json
    track-b.json
    phase2-discovery.json
  document-iac/           ← IaC-specific analysis
    archetype.json        ← archetype classification + signals
    iac-discovery.json    ← full IaC analysis output
    module-catalog.json   ← (terraform-stack) parsed modules
    addon-catalog.json    ← (gitops-addons) parsed addons
    appset-catalog.json   ← (gitops-control-plane) parsed ApplicationSets
    topology.json         ← (gitops-control-plane) hub-spoke topology
    env-matrix.json       ← environment comparison matrix
```

---

## Phase 3 — AI-Proposed Documentation Plan

### Step 3.1: Build Combined Plan

Merge document-repo's standard plan (AGENTS.md, docs/README.md, docs/architecture.md,
docs/workflow.md, docs/dependencies.md, .claude/ecosystem.md) with IaC-specific
files based on archetype.

### Step 3.2: Present Plan

Present the combined plan. IaC-specific files appear after the base document-repo
files:

```
Documentation Plan for: <repo-name>
Archetype: <archetype>

=== BASE (document-repo) ===
  [standard document-repo plan sections — same format as document-repo § 3.2]

=== IaC-SPECIFIC ===

--- docs/iac-overview.md ---
  - Archetype: <archetype> with <variant>
  - Environments: <N> environments detected (<list>)
  - IaC toolchain: <Terraform X.Y | Kustomize | Helm | etc.>
  - Provider/registry summary

--- docs/module-catalog.md --- (terraform-stack only)
  - <N> Terraform modules detected
  - Source: <registry URL pattern>
  - Per-module: name, version constraint, description, used-in files

--- docs/addon-catalog.md --- (gitops-addons only)
  - <N> addons detected under argocd/
  - Per-addon: name, type (kustomize/helm/crossplane), environments, existing README
  - Links to existing per-addon READMEs (not regenerated)

--- docs/control-plane-topology.md --- (gitops-control-plane only)
  - Hub-spoke cluster topology: <N> hubs, <N> spokes
  - ApplicationSet discovery patterns and target namespaces
  - Bootstrap method: <Helm | Kustomize | manual> with sync wave ordering
  - Hybrid Terraform: <present | absent> (<N> modules if present)

--- docs/appset-catalog.md --- (gitops-control-plane only)
  - <N> ApplicationSets detected
  - Per-appset: name, generator type (matrix/list/git/cluster), target clusters,
    target namespace, source repo/path, sync policy
  - Discovery mapping: which addons/services each ApplicationSet manages

--- docs/project-rbac.md --- (gitops-control-plane only)
  - <N> ArgoCD projects detected
  - Per-project: source repos, allowed destinations (cluster/namespace),
    permitted resource kinds, team mapping
  - Team tenancy model: <N> teams with access boundaries

--- docs/environment-matrix.md ---
  - <N> environments compared
  - Per-environment: account ID, region, unique resources, config deltas
  - Cross-environment drift: <N> files present in some envs but not others

--- docs/state-and-backends.md --- (terraform-stack only)
  - Backend type: <S3 | local | etc.>
  - State key pattern: <pattern>
  - Lock table: <referenced by var name>

--- docs/variables-schema.md --- (terraform-stack only)
  - <N> variables across <M> files
  - Complex type variables: <N> with sub-key documentation
  - Per-environment tfvars delta summary

--- docs/overlay-structure.md --- (gitops-addons only)
  - Base → overlay inheritance tree
  - Config.yaml schema per addon type
  - Patch file inventory per environment

Approve this plan? (yes / edit specific sections / start over)
```

### Step 3.3: Handle User Feedback

Same as document-repo § 3.3.

---

## Phase 3.5 — Branch Creation Gate

> **Identical to document-repo Phase 3.5.** Branch name pattern:
> - With JIRA: `docs/<jira_ticket_id>-document-iac-<repo-name>`
> - Without JIRA: `docs/document-iac-<repo-name>`

---

## Phase 4 — Generate Documentation

### Steps 4.1–4.8: Base Generation

> Run document-repo's Phase 4 in full. Read
> [`document-repo/code-generation.md`](document-repo/code-generation.md).
> Generate AGENTS.md, docs/README.md, docs/architecture.md, docs/workflow.md,
> docs/dependencies.md, .claude/ecosystem.md, CLAUDE.md.

### Steps 4.IaC: IaC-Specific Generation

> **Module**: Read [`document-iac/iac-generation.md`](document-iac/iac-generation.md)
> and generate IaC-specific documentation files from the approved plan.

This module contains templates and content rules for:

- `docs/iac-overview.md` — IaC toolchain, archetype summary, environment map,
  provider/registry configuration
- `docs/module-catalog.md` (terraform-stack) — module inventory table with
  source, version, description, used-in references
- `docs/addon-catalog.md` (gitops-addons) — addon inventory with links to
  existing READMEs, type classification, environment coverage
- `docs/control-plane-topology.md` (gitops-control-plane) — hub-spoke cluster
  map, ApplicationSet discovery flow, bootstrap sequence, sync wave ordering,
  hybrid Terraform sub-section if `terraform/` directory is present
- `docs/appset-catalog.md` (gitops-control-plane) — ApplicationSet inventory
  with generator types, target clusters/namespaces, source repo mapping
- `docs/project-rbac.md` (gitops-control-plane) — ArgoCD project definitions,
  per-project RBAC (source repos, allowed destinations, resource kinds),
  team-to-project mapping
- `docs/environment-matrix.md` — side-by-side environment comparison, drift
  flags, account/region mapping
- `docs/state-and-backends.md` (terraform-stack) — backend configuration,
  state key patterns, lock strategy
- `docs/variables-schema.md` (terraform-stack) — variable documentation with
  types, defaults, required/optional, complex object sub-keys
- `docs/overlay-structure.md` (gitops-addons) — Kustomize base/overlay tree,
  patch inventory, config schema

### Confidence Labeling (MANDATORY)

Every dependency, relationship, or architectural assertion in generated IaC docs
MUST include a confidence label:

| Label | Meaning | Example |
|-------|---------|---------|
| `[Observed]` | Directly parsed from manifest/code | Module source URL from `*.tf` |
| `[Inferred]` | Derived from naming, structure, or heuristics | "Likely shares state with X based on key pattern" |

Format in generated Markdown:

```markdown
| Module | Version | Source | Confidence |
|--------|---------|--------|------------|
| ecs-application/aws | ~> 6.0 | JFrog Artifactory | [Observed] |
| shared-networking | (unknown) | Assumed from data sources | [Inferred] |
```

### docs/README.md Enhancement

The base document-repo generates `docs/README.md` as an index. This command
MUST ensure it includes links to all IaC-specific docs generated above.

If `docs/README.md` was generated by base Phase 4, append an "Infrastructure
Documentation" section with links to the IaC-specific files.

If `docs/README.md` was NOT generated (pre-existing gap), generate it now with
both base and IaC doc links.

---

## Phase 5 — Validate

### Base Validation

> Run all document-repo validation checks VAL-001 through VAL-012.

### IaC-Specific Validation

| Check | What | Severity |
|-------|------|----------|
| IAC-001 | Archetype classification matches actual repo signals | Warning |
| IAC-002 | Module catalog entries match `*.tf` source declarations (terraform-stack) | Error |
| IAC-003 | Addon catalog entries match `argocd/` subdirectories (gitops-addons) | Error |
| IAC-004 | Environment matrix covers all detected environment directories | Error |
| IAC-005 | No secrets/tokens/account IDs in state-and-backends.md | Error |
| IAC-006 | All confidence labels are present ([Observed] or [Inferred]) | Warning |
| IAC-007 | Cross-environment drift section is populated (or explicit "no drift detected") | Warning |
| IAC-008 | Per-addon README links resolve to actual files (gitops-addons) | Error |
| IAC-009 | docs/README.md includes links to all IaC-specific docs | Error |
| IAC-010 | Variables schema covers all `variable` blocks in `*.tf` files (terraform-stack) | Warning |
| IAC-011 | ApplicationSet catalog entries match `applicationsets/` YAML files (gitops-control-plane) | Error |
| IAC-012 | Project RBAC entries match `projects/` definitions (gitops-control-plane) | Error |
| IAC-013 | Hub-spoke topology in control-plane-topology.md matches `hubs/` directory structure | Error |
| IAC-014 | Hybrid Terraform section present if `terraform/` directory exists in control-plane repo | Warning |
| IAC-015 | Team-to-project mapping covers all entries in `teams/` directory (gitops-control-plane) | Warning |

### Pre-PR Flaw Scan

> Same as document-repo § Phase 5 Pre-PR Flaw Scan.

---

## Phase 6 — Commit, Push, and PR Creation

> **Module**: Read [`document-repo/commit-push-pr.md`](document-repo/commit-push-pr.md)
> and execute all steps.

Commit message format:

```
docs(<repo-name>): add IaC documentation (<archetype>)

- Add base documentation (AGENTS.md, architecture, workflow, dependencies)
- Add IaC overview with archetype classification and environment map
- Add <module-catalog | addon-catalog | appset-catalog + project-rbac> with <N> entries
- Add environment matrix comparing <N> environments
- Add <state-and-backends | overlay-structure | control-plane-topology> documentation
- Add variables schema reference (if terraform-stack)

<JIRA_TICKET_ID>
```

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → which IaC repo was documented, archetype, and how many documentation files were generated
- "What was accomplished" → IaC-specific documentation package: module/addon catalogs for discoverability, environment matrices for drift awareness, state management docs for operational safety, variable schemas for change confidence
- "Why it matters" → engineers can now understand infrastructure topology without reading raw Terraform/Kustomize; environment differences are explicit instead of hidden in tfvars/overlays; IaC changes can be reviewed with full context of what each module/addon does and which environments are affected
- "What happens next" → review the PR, keep IaC docs updated as infrastructure evolves, re-run after adding new modules/addons/environments

**Repo breakdown guidance**:
- Target repo: where all generated documentation files live
- mobius-tools (if graph registration): where the ecosystem graph entry was added
