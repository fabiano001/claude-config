---
name: document-service
description: Deep-dive a service codebase and generate human-readable developer documentation
argument-hint: [service-name-or-path]
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Document a Service

## Model Recommendation

> **Model:** Opus recommended for large or complex services; sonnet sufficient for
> small or well-structured codebases. Use whatever model is active in your session.

This command generates deep developer documentation for one or more application services in a single run.
For each target, outputs target four audiences and produce up to five files per service:
`docs/README.md`, `docs/service-guide.md`, `docs/api-reference.md` (conditional),
`docs/developer-guide.md`, and `docs/runbook.md`. Not for infrastructure repositories.

In a monorepo, all apps are documented by default in a single run (one branch, one PR); pass a specific service name as the argument to limit scope to that service.

## Architecture Context

> Related specs: [`document-repo.md`](document-repo.md) (ecosystem/platform docs), [`instrument-service.md`](instrument-service.md) (OTEL instrumentation)

Key facts: (1) Complements document-repo — zero intended output-file overlap except `docs/README.md`. (2) Application services only — infrastructure repos route to `/mobius:document-repo`. (3) 10 analysis passes covering identity, API, lifecycle, business logic, data model, errors, config, security, testing, and operations. (4) AI-proposed with user review gate before file generation. (5) Multi-service loop supported — each target gets its own full analysis pass, plan approval, and generation cycle; all targets land in one branch and PR.

---

## Canonical Rules

1. No file generation before the documentation plan is confirmed by the user.
2. Git preflight must pass before Phase 1 analysis begins.
3. JIRA ticket is prompted before intake — optional but encouraged.
4. No file generation on `main` — feature branch MUST exist before Phase 4.
5. Work is not complete until a PR exists with all generated files.
6. Infrastructure repos (Terraform, Helm, Kustomize, KCL) hard-stop and route to `/mobius:document-repo`.
7. Existing documentation is NEVER silently overwritten — user chooses merge/replace/skip.
8. AI-generated descriptions are ALWAYS presented for user review before write.
9. Generated docs MUST reflect actual codebase analysis, not template boilerplate.
10. Every generated file MUST start with an audience blockquote.
11. Every analysis claim MUST trace to specific code locations (file, symbol, line when available).
12. `docs/api-reference.md` is CONDITIONAL — only generated for services with API surfaces.
13. Empty sections are OMITTED, never filled with generic text.
14. Mermaid diagrams MUST include ASCII fallback immediately below.
15. `docs/runbook.md` is table-heavy and optimized for incident lookup.
16. Monorepo detection (Step 1.1b) MUST run before service type classification.
17. If `docs/` exists at `targets[i].target_app_path`, ALL docs files MUST be read before any source code analysis for that target (Pre-Pass 0).
18. Phase 5.5 is a HARD GATE: root `CLAUDE.md`/`AGENTS.md` AND `.claude/ecosystem.md` must exist. If absent, stop and direct user to run `/mobius:document-repo` first.
19. For monorepos, all path resolution for each target uses `targets[i].target_app_path` as root, not the repo root.
20. Steps 1.3–1.6, Phase 2, Phase 4, Phase 5, and Phase 5.5 execute in a loop over `targets[]`. Steps 0, 1.1, 1.1b, 1.2, Phase 3.5, and Phase 6 execute once.
21. Phase 2 pass outputs MUST be persisted under `{repo_root}/.mobius-docs-session/` and referenced by path in later phases; do not retain full multi-target findings in context.
22. Phase 4 MUST perform selective read-back (per file, per target) from `.mobius-docs-session/` instead of reloading all 10 passes.
23. `.mobius-docs-session/` artifacts are intermediate state and MUST NOT be committed.

---

## Phase 0 — Git + Environment Preflight

> **Step 0a** (Git): Verify `gh auth status`, clean working tree, and current branch. If not on `main`, ask user to use current branch or start fresh. Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks.

> **Step 0b** (JIRA): Prompt for JIRA ticket ID (optional for documentation PRs). Store as `jira_ticket_id`.

> **Step 0c** (Session Resume): Read [`shared/session-directory.md`](shared/session-directory.md), check for `.mobius-docs-session/manifest.json`, and prompt resume/reset when stale or scope differs.

> **Step 0d** (Session Ignore Guard): Ensure `.mobius-docs-session/` is ignored by git before Phase 1. If `.gitignore` lacks this entry, append it and stage `.gitignore` later with documentation outputs.

#### Delegated Invocation

When invoked via `document-repo` delegation (session manifest contains `delegated: true`):
- **Phase 0**: Skip — inherit branch + session from document-repo.
- **Phase 1**: Skip compatibility gate — classification already confirmed by document-repo Phase 2.5.
- **Phase 2**: Consume existing artifacts from `.mobius-docs-session/`. Only run domain-specific passes (Pass 11 runs attribution + derivation only, no import scanning).
- **Phase 6**: Skip — defer commit/PR to document-repo.

---

## Phase 1 — Service Detection & Compatibility Gate

### Step 1.1: Locate Target Repository

Use provided path or CWD. Verify `git rev-parse --git-dir` succeeds.

### Step 1.1b: Detect Monorepo Structure

Check for monorepo signals in priority order: `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`, `rush.json`, `package.json workspaces`, `apps/` directory, `packages/` directory.

If monorepo detected: set `is_monorepo = true`, list all apps/packages (most recently modified first, cap 20).

- **If a service name was passed as the CLI argument**: pre-select only the matching app. If no app name matches exactly, fuzzy-match against directory names and confirm with the user.
- **If no CLI argument was given (default)**: pre-select ALL apps. Present the full list with all entries checked. Prompt: _"All N services will be documented. Deselect any you want to skip, or press Enter to continue with all."_ This is the normal path — documenting everything in one run.

For each confirmed app, record `{ target_app_path, target_app_name }` and push to `targets[]`. All subsequent path resolution for each target uses `targets[i].target_app_path` as root.

If not monorepo: set `is_monorepo = false`. Set `targets = [{ target_app_path: repo_root, target_app_name: repo_name }]`.

### Step 1.2: Detect Repo Identity

Extract from git remote URL → `package.json name` → `go.mod module path` → directory name. Record `repo_name`, `repo_org`, `remote_url`.

### Steps 1.3–1.6: Per-Target Loop

**Repeat Steps 1.3, 1.4, 1.5, and 1.6 for each target in `targets[]`. Store results in `targets[i]`.**

#### Step 1.3: Classify Service Type (per target)

Run against `{targets[i].target_app_path}`. Classify as: REST API, GraphQL API, gRPC service, Event consumer, Cron job, CLI tool, Library, or Hybrid. Record `targets[i].service_type`, `primary_protocol`, `framework`, `language_stack`, `deployment_model`, `has_api`.

#### Step 1.4: Compatibility Gate — HARD STOP (per target)

If dominant repo signals at `targets[i].target_app_path` are Terraform, Helm (`Chart.yaml`), Kustomize (`kustomization.yaml`), or KCL (`.kcl` compositions), hard-stop this target and direct user to `/mobius:document-iac` for infrastructure-specific documentation. Remove from `targets[]` and continue with remaining targets, or abort if no valid targets remain.

If target is classified as `library` → hard-stop with message: "This target appears to be a library. Use `/mobius:document-library` instead."

#### Step 1.5: Check for document-repo Output (per target)

Check for `/mobius:document-repo` outputs at `{targets[i].target_app_path}/docs/` (primary) or root `docs/` (monorepos only): `architecture.md`, `dependencies.md`, `workflow.md`. If present, use as bootstrap context for passes 1, 7, and 10 only. Code evidence always wins over bootstrap conflicts. Record in `targets[i].bootstrap_sources[]`.

#### Step 1.6: Detect Existing Documentation + Merge Strategy (per target)

Scan `{targets[i].target_app_path}/docs/` for existing target outputs (`README.md`, `service-guide.md`, `api-reference.md`, `developer-guide.md`, `runbook.md`). Present status. If any exist, prompt for strategy: `Merge` (default) / `Replace` / `Skip`. Store as `targets[i].existing_docs_strategy`.

---

## Phase 2 — Deep Dive Analysis

> **What it does:** For each target in `targets[]`, executes an 11-pass deep analysis engine: (1) Service Identity &
> Classification, (2) API Contract Discovery, (3) Request Lifecycle Tracing with Mermaid
> diagrams, (4) Business Logic Comprehension, (5) Data Model & Persistence with ER diagrams,
> (6) Error Taxonomy, (7) Configuration Surface, (8) Security Model, (9) Testing Landscape,
> (10) Operational Profile, (11) Cloud Dependency Scan. Each pass has detection tables, AST patterns, LSP enrichment,
> and fallbacks. Outputs pass-level artifacts to `.mobius-docs-session/` plus compact manifest
> metadata in context. Every doc claim must trace to a finding.

> **Module**: Read [`document-service/deep-dive-analysis.md`](document-service/deep-dive-analysis.md) and execute all 11 analysis passes **for each target in `targets[]`**. Set `phase2_discovery[i].metadata.scope_root = targets[i].target_app_path` for each entry.

Passes run in strict order per target. Preserve evidence links. Mark skipped passes with explicit reason.

---

## Phase 3 — Documentation Plan Review (USER GATE)

Build plan from `phase2_discovery[]` and present for user approval. Show one plan block per target, then an aggregate summary:

```
Documentation Plan for: {repo-name}
Repo mode:    {single-service | monorepo}
Targets:      {N} service(s) selected

--- Target 1: {targets[0].target_app_name} ({targets[0].target_app_path}) ---
Service type: {type} ({framework} on {language})

=== ANALYSIS SUMMARY ===
  Endpoints:     {N} across {M} resources
  Modules:       {N} service-layer modules
  Data entities: {N} entities in {ORM}
  Error types:   {N} custom error classes
  Env vars:      {N} ({K} required, {J} sensitive)
  Auth:          {auth_mechanism}
  Tests:         {N} test files ({unit}/{integration}/{e2e})

=== PROPOSED DOCUMENTATION ===
  {targets[0].target_app_path}/docs/README.md           — Navigation hub + quick reference
  {targets[0].target_app_path}/docs/service-guide.md    — Architecture, request flow, data model
  {targets[0].target_app_path}/docs/api-reference.md    — {N} endpoints grouped by resource  (or SKIPPED: no API)
  {targets[0].target_app_path}/docs/developer-guide.md  — Setup, config, patterns, testing
  {targets[0].target_app_path}/docs/runbook.md          — Health, errors, failure modes, troubleshooting

--- Target 2: {targets[1].target_app_name} ({targets[1].target_app_path}) ---
[repeat block for each additional target]

=== AGGREGATE ===
  Total targets:    {N}
  Total doc files:  {N*5 minus skipped conditional files}
  Branch:           {proposed-branch-name}

Approve this plan? (yes / edit sections / start over)
```

No generation starts until explicit approval. `yes` → lock plan and proceed. `edit sections` → apply and re-present. `start over` → return to Phase 2.

---

## Phase 3.5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

If on `main`, create feature branch:
- Single target, with JIRA: `docs/<jira_ticket_id>-document-service-<repo-name>`
- Single target, without JIRA: `docs/document-service-<repo-name>`
- Multiple targets, with JIRA: `docs/<jira_ticket_id>-document-service-<repo-name>-multi`
- Multiple targets, without JIRA: `docs/document-service-<repo-name>-multi`

If user chose to keep existing branch in Phase 0, skip creation.

---

## Phase 4 — Generate Documentation

> **What it does:** For each target in `targets[]`, generates up to 6 files from that target's `.mobius-docs-session/` pass artifacts: `{target_app_path}/docs/README.md`
> (navigation hub), `{target_app_path}/docs/service-guide.md` (architecture + request flow + data model),
> `{target_app_path}/docs/api-reference.md` (conditional — endpoints grouped by resource),
> `{target_app_path}/docs/developer-guide.md` (setup + config + patterns + testing), `{target_app_path}/docs/runbook.md`
> (table-heavy, optimized for 2am incident lookup), `{target_app_path}/CLAUDE.md`
> (docs-first enforcement with `@docs/README.md` auto-load on line 1).
> **Key behavior:** Each section has source mapping back to pass artifacts. Read only the pass files required for the current output document.
> Conditional rendering rules apply — api-reference.md is only generated if API
> endpoints were discovered. Merge strategy from `targets[i].existing_docs_strategy` applied per target.
> **Module**: Read [`document-service/content-generation.md`](document-service/content-generation.md)
> and generate all documentation files from the approved plan, **looping over each target in `targets[]`**. Resolve all service name and path tokens from `phase2_discovery[i]` for each iteration.

Generate up to six files per target:

1. `{target_app_path}/docs/README.md` — navigation hub
2. `{target_app_path}/docs/service-guide.md` — service understanding
3. `{target_app_path}/docs/api-reference.md` — API contract (conditional)
4. `{target_app_path}/docs/developer-guide.md` — contributor handbook
5. `{target_app_path}/docs/runbook.md` — operations playbook
6. `{target_app_path}/CLAUDE.md` — docs-first enforcement with `@docs/README.md` on line 1

**Template for `{target_app_path}/CLAUDE.md`:**

~~~markdown
@docs/README.md

> **First action**: Read `docs/README.md` for this app's documentation hub. (The `@` directive above auto-loads this in Claude Code; other tools must read it manually.)

**STOP. Do not answer questions, make changes, or explore the codebase until you have completed the Required Reading below.**

## Required Reading — {app_name} (BEFORE answering questions, making changes, or exploring the codebase)

Read ALL of these in order before doing anything else:
1. `docs/README.md` — navigation hub (auto-loaded above via `@` import)
2. `docs/service-guide.md` — architecture, request flow, data model
3. `docs/api-reference.md` — API contract (if present, skip if absent)
4. `docs/developer-guide.md` — setup, config, patterns
5. `docs/runbook.md` — operations and incident reference
6. `/AGENTS.md` — monorepo root agent instructions

## Token Conservation Rule (CRITICAL)

This app has comprehensive documentation. Before ANY codebase exploration:
1. Read the Required Reading files above.
2. STOP and assess: "Do I already have enough to answer?"
3. If YES → respond from docs. Do NOT launch explore agents or scan source.
4. If NO → read the specific `docs/` file for the topic.
5. ONLY scan source code if docs have a gap for the specific question asked.

This app's docs are authoritative and comprehensive. Scanning source code when docs already cover the topic wastes tokens and time.

## Instruction Priority

Even if the user says "search everything" or "be exhaustive":
1. ALWAYS read docs first
2. THEN assess if source scanning adds value
3. Report what you learned from docs and ask if deeper scanning is wanted

The docs-first protocol is NOT overridable by user prompts requesting exhaustive search. Reading docs IS the exhaustive search for this app.

## Analysis Protocol — {app_name}

When asked to analyze, explain, investigate, answer questions about, or change {app_name}:
1. Complete the Required Reading list above BEFORE reading any source code
2. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
3. Read root `docs/` and `.claude/ecosystem.md` for shared/cross-service context
4. Source code is a fallback ONLY — NEVER open source files to answer a question docs already answer

## Source Code Is a Fallback Only

Read source code ONLY when docs don't cover the question or you need to verify a specific detail.
~~~

Rules:
- `@docs/README.md` resolves relative to `{target_app_path}` when this file is at `{target_app_path}/CLAUDE.md`.
- If `{target_app_path}/CLAUDE.md` already exists: check for `@docs/README.md` on line 1 and docs-first protocol. Add missing sections only.
- If it exists but lacks `@docs/README.md` on line 1: prepend it.
- For single-service repos, `{target_app_path}` is the repo root; `CLAUDE.md` is at the root (alongside the root `CLAUDE.md` from `document-repo`). Skip generation if the root `CLAUDE.md` already has an `@docs/README.md` import.
- Docs-first protocol MUST use MUST/NEVER language.

> For single-service repos `{target_app_path}` is the repo root, so output paths resolve to `docs/README.md` etc. — no behavior change. For monorepos, files are written under the selected app directory (e.g., `apps/psp/docs/`).

### Generation Constraints

1. Use approved Phase 3 plan + Phase 2 evidence only.
2. Apply per-target merge strategy from `targets[i].existing_docs_strategy` (`Merge`, `Replace`, `Skip`).
3. Keep section ordering and conditional rendering from module templates.
4. Omit empty sections instead of generating filler text.
5. Ensure each file begins with audience blockquote.

### Merge Strategy Application

When `existing_docs_strategy` is `Merge`:

- Preserve valid custom content where compatible with current evidence.
- Add missing required sections.
- Replace stale or conflicting content with evidence-backed content.

When `existing_docs_strategy` is `Replace`:

- Regenerate all target files from templates.

When `existing_docs_strategy` is `Skip`:

- Generate only missing files.
- Do not modify existing files.

---

## Phase 5 — Validate

Run the following checks **for each target in `targets[]`**. Collect per-target results. After all targets pass, aggregate check confirms all staged files are present before proceeding.

| Check | What | Severity |
|-------|------|----------|
| SVC-001 | All generated files are valid Markdown | Error |
| SVC-002 | `docs/README.md` links resolve to actual files in `{target_app_path}/docs/` | Error |
| SVC-003 | All docs files have section headers with substantive content | Error |
| SVC-004 | No placeholder/TODO content in any generated file | Error |
| SVC-005 | API reference endpoint count matches Pass 2 discovery for this target | Error |
| SVC-006 | Service guide contains actual business logic descriptions (not generic) | Warning |
| SVC-007 | Runbook contains actual error classes from the codebase | Warning |
| SVC-008 | Developer guide config table matches Pass 7 variables | Warning |
| SVC-009 | All Mermaid diagram syntax is valid | Warning |
| SVC-010 | `docs/README.md` "I need to..." table links resolve | Error |
| SVC-011 | Root `CLAUDE.md` exists AND `.claude/ecosystem.md` exists (checked once, not per target) | Error (hard-stop — run `/mobius:document-repo` first if absent) |
| SVC-012 | Root `CLAUDE.md` contains `@.claude/ecosystem.md` on line 1 and docs-first directive (checked once) | Warning (auto-added if absent) |
| SVC-013 | Root `AGENTS.md` (if it exists) contains `### Docs-First Reading Protocol (MANDATORY)` in the Cross-Repo Bootstrap section | Warning |
| SVC-014 | cloud-permissions.md policy JSON is valid (parseable, has Effect/Action/Resource) when file exists | Error |
| SVC-015 | Inherited library permissions are referenced, not re-derived | Warning |

Fix all Error-severity failures before proceeding.

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md) and execute Phase A. Context: `risk_profile: documentation`, `affected_repos`: target service repo.

---

## Phase 5.5 — Agent Wiring Verification (HARD GATE)

Ensures future agent sessions use generated docs as primary context.

### Step 5.5.1: Locate Agent Config File

Check for root `CLAUDE.md`. This is checked once (not per target).

If absent, **hard-stop**:

```
HARD STOP: No CLAUDE.md found at repo root.
/mobius:document-service requires /mobius:document-repo to have been run first.

Run: /mobius:document-repo
This generates CLAUDE.md and .claude/ecosystem.md, which are required for
agent context wiring. Re-run /mobius:document-service after it completes.
```

### Step 5.5.1b: Verify AGENTS.md Docs-First Directive

Check for root `AGENTS.md`. This is checked once (not per target).

If `AGENTS.md` exists at the repo root:
1. Check for `### Docs-First Reading Protocol (MANDATORY)` inside the `## Cross-Repo Bootstrap` section.
2. If the subsection is missing, replace the entire `## Cross-Repo Bootstrap` section with the canonical text from `templates/agents-bootstrap-section.md`.
3. If no `## Cross-Repo Bootstrap` section exists at all, append the canonical bootstrap section (including the Docs-First Reading Protocol) before the first repo-specific section.

If `AGENTS.md` does not exist, skip — it is not a hard requirement for `document-service` (the user can run `/mobius:document-repo` to create it).

### Step 5.5.2: Verify .claude/ecosystem.md Exists

Check that `.claude/ecosystem.md` exists at the repo root. This is checked once (not per target).

If it does not exist, **hard-stop**:

```
HARD STOP: .claude/ecosystem.md not found.
/mobius:document-service requires /mobius:document-repo to have been run first.

Run: /mobius:document-repo
This generates .claude/ecosystem.md with ecosystem context required for
agent wiring. Re-run /mobius:document-service after it completes.
```

### Step 5.5.3: Verify/Add ecosystem.md Loading Directive

Check that `CLAUDE.md` has `@.claude/ecosystem.md` on line 1. This is checked once (not per target).

If not present, **prepend** it as line 1 (it MUST be line 1 for Claude Code's `@`-import mechanism to auto-load it at session start):

```markdown
@.claude/ecosystem.md
```

Do NOT append — the `@` import only works when it appears at the top of the file.

### Step 5.5.4: Verify/Add Docs-First Reading Directive (per target loop)

For each target in `targets[]`, check root `CLAUDE.md` for a docs-first reading instruction scoped to `{targets[i].target_app_path}/docs/`. If absent for this target, append the appropriate template. Use MUST/NEVER language.

**For single-service repos** (`is_monorepo = false`) — directive reads root `docs/`:

```markdown
## Documentation-First Reading Protocol

When answering questions about, making changes to, or exploring this service:
1. Read `docs/` FIRST — human-curated documentation is the authoritative source.
2. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
3. Read source code ONLY to fill gaps not covered by docs or to resolve a conflict.
4. Source code scanning is ONLY permitted when docs are insufficient or potentially outdated.
5. Never assume source code is more authoritative than existing documentation without verifying the docs are outdated.
```

**For monorepos** (`is_monorepo = true`) — directive reads `{target_app_name}/docs/` then root `docs/`:

```markdown
## Documentation-First Reading Protocol

This is a monorepo. When answering questions about, making changes to, or exploring a specific app or service:
1. Read `apps/{app-name}/docs/` FIRST for app-specific documentation.
2. Read root `docs/` for shared/cross-service context.
3. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
4. Read source code ONLY to fill gaps not covered by docs or to resolve conflicts.
5. Source code scanning is ONLY permitted when docs are insufficient or potentially outdated.
6. Never assume source code is more authoritative than existing documentation without verifying the docs are outdated.
7. When a question is about the monorepo itself (not a specific app), check root `docs/` and `.claude/ecosystem.md` before exploring `apps/`.
```

### Step 5.5.5: Report Wiring Status

```
Agent Wiring Status:
  Config file:            CLAUDE.md / AGENTS.md found at <path>
  .claude/ecosystem.md:   exists
  ecosystem.md directive: [already present | added]
  AGENTS.md docs-first:   [already present | added | skipped (no AGENTS.md)]
  Per-target directives:
    {target_1}: docs-first [already present | added]
    {target_2}: docs-first [already present | added]

Agent wiring complete. Proceeding to commit.
```

---

## Phase 6 — Commit, Push, and PR Creation

> **What it does:** Single-repo commit/push/PR with explicit per-target file staging. Structured PR body with per-target analysis summary rows. Post-PR feedback scan and completion gating.

> **Module**: Read [`document-service/commit-push-pr.md`](document-service/commit-push-pr.md) and execute all steps.

Commit subject: `docs(<repo-name>): add service documentation` (single target) or `docs(<repo-name>): add service documentation for N services` (multiple targets).

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md), then generate the Why Summary.

**Command type**: generative

**Context hints**:
- Impact opener: which service(s) were documented and what depth of analysis ran
- What was accomplished: deep service documentation for architecture, API, business logic, errors, and operations across all targets
- Why it matters: faster onboarding, stronger on-call readiness, clear integration contracts, safer AI-assisted changes
- What happens next: review PR, keep docs maintained, rerun to refresh as code evolves
