---
name: document-library
description: Generate library documentation — integration guide, cloud permissions, developer guide
argument-hint: [library-name-or-path]
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Document a Library

## Model Recommendation

> **Model:** Opus recommended for large or complex libraries; sonnet sufficient for
> small or well-structured codebases. Use whatever model is active in your session.

This command generates deep library documentation for one or more library targets in a single run.
For each target, outputs up to five files: `docs/integration-guide.md`, `docs/cloud-permissions.md` (conditional),
`docs/developer-guide.md`, `docs/README.md`, and `CLAUDE.md`. Not for service or infrastructure repositories.

In a monorepo, all libraries are documented by default in a single run (one branch, one PR); pass a specific library name as the argument to limit scope to that library.

## Architecture Context

> Related specs: [`document-repo.md`](document-repo.md) (ecosystem/platform docs), [`document-service.md`](document-service.md) (service documentation)

Key facts: (1) Complements document-repo — zero intended output-file overlap except `docs/README.md`. (2) Libraries only — services route to `/mobius:document-service`, infrastructure repos route to `/mobius:document-repo`. (3) 6 analysis passes (L1-L6) covering API surface, capabilities, cloud dependencies, IAM permissions, config surface, and usage patterns. (4) AI-proposed with user review gate before file generation. (5) Multi-library loop supported — each target gets its own full analysis pass, plan approval, and generation cycle; all targets land in one branch and PR.

---

## Canonical Rules

1. No file generation before the documentation plan is confirmed by the user.
2. Git preflight must pass before Phase 1 analysis begins (standalone only).
3. No file generation on `main` — feature branch MUST exist before Phase 4.
4. Work is not complete until a PR exists with all generated files (standalone) or delegation returns (delegated).
5. Existing documentation is NEVER silently overwritten — user chooses merge/replace/skip.
6. AI-generated descriptions are ALWAYS presented for user review before write.
7. Generated docs MUST reflect actual codebase analysis, not template boilerplate.
8. Every generated file MUST start with an audience blockquote.
9. Every analysis claim MUST trace to specific code locations (file, symbol, line when available).
10. Empty sections are OMITTED, never filled with generic text.
11. `docs/cloud-permissions.md` is CONDITIONAL — only generated for libraries with AWS SDK usage.
12. All path resolution for each target uses `targets[i].target_app_path` as root, not the repo root.
13. `.mobius-docs-session/` artifacts are intermediate state and MUST NOT be committed.

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
- **Phase 2**: Consume existing artifacts from `.mobius-docs-session/`. Only run library-specific passes (L1-L6).
- **Phase 6**: Skip — defer commit/PR to document-repo.

---

## Phase 1 — Library Detection & Compatibility Gate

### Step 1.1: Locate Target Repository

Use provided path or CWD. Verify `git rev-parse --git-dir` succeeds.

### Step 1.1b: Detect Monorepo Structure

Check for monorepo signals in priority order: `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`, `rush.json`, `package.json workspaces`, `packages/` directory, `libs/` directory.

If monorepo detected: set `is_monorepo = true`, list all packages/libs (most recently modified first, cap 20).

- **If a library name was passed as the CLI argument**: pre-select only the matching library. If no library name matches exactly, fuzzy-match against directory names and confirm with the user.
- **If no CLI argument was given (default)**: pre-select ALL libraries. Present the full list with all entries checked. Prompt: _"All N libraries will be documented. Deselect any you want to skip, or press Enter to continue with all."_ This is the normal path — documenting everything in one run.

For each confirmed library, record `{ target_app_path, target_app_name }` and push to `targets[]`. All subsequent path resolution for each target uses `targets[i].target_app_path` as root.

If not monorepo: set `is_monorepo = false`. Set `targets = [{ target_app_path: repo_root, target_app_name: repo_name }]`.

### Step 1.2: Detect Repo Identity

Extract from git remote URL → `package.json name` → `go.mod module path` → directory name. Record `repo_name`, `repo_org`, `remote_url`.

### Steps 1.3–1.6: Per-Target Loop

**Repeat Steps 1.3, 1.4, 1.5, and 1.6 for each target in `targets[]`. Store results in `targets[i]`.**

#### Step 1.3: Classify Library Type (per target)

Run against `{targets[i].target_app_path}`. Classify as library using detection signals:
- Exported modules with no bootstrap/listener/entrypoint
- `peerDependencies` in `package.json`
- `lib-*` or `@org/*-lib` naming conventions
- Published to registry (npm, PyPI, Maven, etc.)
- No HTTP listener, event consumer, or CLI entrypoint
- Main export is a module/class/function, not an executable

Record `targets[i].library_type`, `export_type`, `language_stack`, `published_to_registry`, `primary_export`.

#### Step 1.4: Compatibility Gate — HARD STOP (per target)

If dominant repo signals at `targets[i].target_app_path` indicate a service (HTTP listener, event consumer, cron job, CLI tool), hard-stop this target with message: "This target appears to be a service. Use `/mobius:document-service` instead." Remove from `targets[]` and continue with remaining targets, or abort if no valid targets remain.

If dominant repo signals are Terraform, Helm (`Chart.yaml`), Kustomize (`kustomization.yaml`), or KCL (`.kcl` compositions), hard-stop this target and direct user to `/mobius:document-iac`. Remove from `targets[]` and continue with remaining targets, or abort if no valid targets remain.

#### Step 1.5: Check for document-repo Output (per target)

Check for `/mobius:document-repo` outputs at `{targets[i].target_app_path}/docs/` (primary) or root `docs/` (monorepos only): `architecture.md`, `dependencies.md`, `workflow.md`. If present, use as bootstrap context for L1 and L5 passes only. Code evidence always wins over bootstrap conflicts. Record in `targets[i].bootstrap_sources[]`.

#### Step 1.6: Detect Existing Documentation + Merge Strategy (per target)

Scan `{targets[i].target_app_path}/docs/` for existing target outputs (`README.md`, `integration-guide.md`, `cloud-permissions.md`, `developer-guide.md`). Present status. If any exist, prompt for strategy: `Merge` (default) / `Replace` / `Skip`. Store as `targets[i].existing_docs_strategy`.

---

## Phase 2 — Library Deep-Dive Analysis

> **What it does:** For each target in `targets[]`, executes a 6-pass library analysis engine: (L1) API Surface Discovery,
> (L2) Capability Mapping, (L3) Cloud Dependency Scan, (L4) IAM Permissions Derivation,
> (L5) Configuration Surface, (L6) Usage Pattern Analysis. Each pass has detection tables, AST patterns, LSP enrichment,
> and fallbacks. Outputs pass-level artifacts to `.mobius-docs-session/` plus compact manifest
> metadata in context. Every doc claim must trace to a finding.

> **Module**: Read [`document-library/deep-dive-analysis.md`](document-library/deep-dive-analysis.md) and execute all 6 analysis passes (L1-L6) **for each target in `targets[]`**. Set `phase2_discovery[i].metadata.scope_root = targets[i].target_app_path` for each entry.

Passes run in strict order per target. Preserve evidence links. Mark skipped passes with explicit reason.

---

## Phase 3 — Documentation Plan Review (USER GATE)

Build plan from `phase2_discovery[]` and present for user approval. Show one plan block per target, then an aggregate summary:

```
Documentation Plan for: {repo-name}
Repo mode:    {single-library | monorepo}
Targets:      {N} library/libraries selected

--- Target 1: {targets[0].target_app_name} ({targets[0].target_app_path}) ---
Library type: {type} ({language})

=== ANALYSIS SUMMARY ===
  Exported APIs:    {N} public methods/functions
  Capabilities:     {N} distinct capabilities
  Cloud deps:       {N} AWS SDK clients detected
  IAM permissions:  {N} actions across {M} services
  Config surface:   {N} configuration options
  Usage patterns:   {N} example patterns found

=== PROPOSED DOCUMENTATION ===
  {targets[0].target_app_path}/docs/README.md               — Navigation hub + quick reference
  {targets[0].target_app_path}/docs/integration-guide.md    — API surface, capabilities, examples
  {targets[0].target_app_path}/docs/cloud-permissions.md    — IAM policies (or SKIPPED: no AWS deps)
  {targets[0].target_app_path}/docs/developer-guide.md      — Setup, config, testing, contributing
  {targets[0].target_app_path}/CLAUDE.md                    — Docs-first enforcement with @docs/README.md

--- Target 2: {targets[1].target_app_name} ({targets[1].target_app_path}) ---
[repeat block for each additional target]

=== AGGREGATE ===
  Total targets:    {N}
  Total doc files:  {N*4 or N*5 depending on cloud-permissions.md conditional}
  Branch:           {proposed-branch-name}

Approve this plan? (yes / edit sections / start over)
```

No generation starts until explicit approval. `yes` → lock plan and proceed. `edit sections` → apply and re-present. `start over` → return to Phase 2.

---

## Phase 3.5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

If on `main`, create feature branch:
- Single target, with JIRA: `docs/<jira_ticket_id>-document-library-<library-name>`
- Single target, without JIRA: `docs/document-library-<library-name>`
- Multiple targets, with JIRA: `docs/<jira_ticket_id>-document-library-<repo-name>-multi`
- Multiple targets, without JIRA: `docs/document-library-<repo-name>-multi`

If user chose to keep existing branch in Phase 0, skip creation.

---

## Phase 4 — Generate Documentation

> **What it does:** For each target in `targets[]`, generates up to 5 files from that target's `.mobius-docs-session/` pass artifacts: `{target_app_path}/docs/README.md`
> (navigation hub), `{target_app_path}/docs/integration-guide.md` (API surface + capabilities + examples),
> `{target_app_path}/docs/cloud-permissions.md` (conditional — IAM policies),
> `{target_app_path}/docs/developer-guide.md` (setup + config + testing + contributing), `{target_app_path}/CLAUDE.md`
> (docs-first enforcement with `@docs/README.md` auto-load on line 1).
> **Key behavior:** Each section has source mapping back to pass artifacts. Read only the pass files required for the current output document.
> Conditional rendering rules apply — cloud-permissions.md is only generated if AWS SDK usage
> was discovered. Merge strategy from `targets[i].existing_docs_strategy` applied per target.
> **Module**: Read [`document-library/content-generation.md`](document-library/content-generation.md)
> and generate all documentation files from the approved plan, **looping over each target in `targets[]`**. Resolve all library name and path tokens from `phase2_discovery[i]` for each iteration.

Generate up to five files per target:

1. `{target_app_path}/docs/README.md` — navigation hub
2. `{target_app_path}/docs/integration-guide.md` — API surface, capabilities, usage examples
3. `{target_app_path}/docs/cloud-permissions.md` — IAM policies (conditional)
4. `{target_app_path}/docs/developer-guide.md` — setup, config, testing, contributing
5. `{target_app_path}/CLAUDE.md` — docs-first enforcement with `@docs/README.md` on line 1

**Template for `{target_app_path}/CLAUDE.md`:**

~~~markdown
@docs/README.md

> **First action**: Read `docs/README.md` for this library's documentation hub. (The `@` directive above auto-loads this in Claude Code; other tools must read it manually.)

**STOP. Do not answer questions, make changes, or explore the codebase until you have completed the Required Reading below.**

## Required Reading — {library_name} (BEFORE answering questions, making changes, or exploring the codebase)

Read ALL of these in order before doing anything else:
1. `docs/README.md` — navigation hub (auto-loaded above via `@` import)
2. `docs/integration-guide.md` — API surface, capabilities, usage examples
3. `docs/cloud-permissions.md` — IAM policies (if present, skip if absent)
4. `docs/developer-guide.md` — setup, config, testing, contributing
5. `/AGENTS.md` — monorepo root agent instructions (if monorepo)

## Token Conservation Rule (CRITICAL)

This library has comprehensive documentation. Before ANY codebase exploration:
1. Read the Required Reading files above.
2. STOP and assess: "Do I already have enough to answer?"
3. If YES → respond from docs. Do NOT launch explore agents or scan source.
4. If NO → read the specific `docs/` file for the topic.
5. ONLY scan source code if docs have a gap for the specific question asked.

This library's docs are authoritative and comprehensive. Scanning source code when docs already cover the topic wastes tokens and time.

## Instruction Priority

Even if the user says "search everything" or "be exhaustive":
1. ALWAYS read docs first
2. THEN assess if source scanning adds value
3. Report what you learned from docs and ask if deeper scanning is wanted

The docs-first protocol is NOT overridable by user prompts requesting exhaustive search. Reading docs IS the exhaustive search for this library.

## Analysis Protocol — {library_name}

When asked to analyze, explain, investigate, answer questions about, or change {library_name}:
1. Complete the Required Reading list above BEFORE reading any source code
2. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
3. Read root `docs/` and `.claude/ecosystem.md` for shared/cross-library context
4. Source code is a fallback ONLY — NEVER open source files to answer a question docs already answer

## Source Code Is a Fallback Only

Read source code ONLY when docs don't cover the question or you need to verify a specific detail.
~~~

Rules:
- `@docs/README.md` resolves relative to `{target_app_path}` when this file is at `{target_app_path}/CLAUDE.md`.
- If `{target_app_path}/CLAUDE.md` already exists: check for `@docs/README.md` on line 1 and docs-first protocol. Add missing sections only.
- If it exists but lacks `@docs/README.md` on line 1: prepend it.
- For single-library repos, `{target_app_path}` is the repo root; `CLAUDE.md` is at the root (alongside the root `CLAUDE.md` from `document-repo`). Skip generation if the root `CLAUDE.md` already has an `@docs/README.md` import.
- Docs-first protocol MUST use MUST/NEVER language.

> For single-library repos `{target_app_path}` is the repo root, so output paths resolve to `docs/README.md` etc. — no behavior change. For monorepos, files are written under the selected library directory (e.g., `packages/lib-auth/docs/`).

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

| Check ID | Severity | Description |
|----------|----------|-------------|
| LIB-001 | error | Every public API method in L1 is documented in integration-guide.md |
| LIB-002 | error | Every capability in L2 has a section in integration-guide.md |
| LIB-003 | error | cloud-permissions.md policy JSON is valid (parseable, has Effect/Action/Resource) when file exists |
| LIB-004 | warning | Every capability with cloud deps has permissions documented |
| LIB-005 | warning | Usage examples exist for every core capability |
| LIB-006 | warning | Config surface matches between L5 and developer-guide.md |
| LIB-007 | error | CLAUDE.md exists with `@docs/README.md` on line 1 |
| LIB-008 | warning | Mermaid diagrams have ASCII fallback |
| LIB-009 | warning | No empty sections or template boilerplate |

Fix all Error-severity failures before proceeding.

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md) and execute Phase A. Context: `risk_profile: documentation`, `affected_repos`: target library repo.

---

## Phase 5.5 — Agent Wiring Verification (HARD GATE)

Ensures future agent sessions use generated docs as primary context.

### Step 5.5.1: Locate Agent Config File

Check for root `CLAUDE.md` or root `AGENTS.md`. This is checked once (not per target).

If both absent, **hard-stop**:

```
HARD STOP: No CLAUDE.md or AGENTS.md found at repo root.
/mobius:document-library requires /mobius:document-repo to have been run first.

Run: /mobius:document-repo
This generates CLAUDE.md and .claude/ecosystem.md, which are required for
agent context wiring. Re-run /mobius:document-library after it completes.
```

### Step 5.5.1b: Verify AGENTS.md Docs-First Directive

Check for root `AGENTS.md`. This is checked once (not per target).

If `AGENTS.md` exists at the repo root:
1. Check for `### Docs-First Reading Protocol (MANDATORY)` inside the `## Cross-Repo Bootstrap` section.
2. If the subsection is missing, replace the entire `## Cross-Repo Bootstrap` section with the canonical text from `templates/agents-bootstrap-section.md`.
3. If no `## Cross-Repo Bootstrap` section exists at all, append the canonical bootstrap section (including the Docs-First Reading Protocol) before the first repo-specific section.

If `AGENTS.md` does not exist, skip — it is not a hard requirement for `document-library` (the user can run `/mobius:document-repo` to create it).

### Step 5.5.2: Verify .claude/ecosystem.md Exists

Check that `.claude/ecosystem.md` exists at the repo root. This is checked once (not per target).

If it does not exist, **hard-stop**:

```
HARD STOP: .claude/ecosystem.md not found.
/mobius:document-library requires /mobius:document-repo to have been run first.

Run: /mobius:document-repo
This generates .claude/ecosystem.md with ecosystem context required for
agent wiring. Re-run /mobius:document-library after it completes.
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

**For single-library repos** (`is_monorepo = false`) — directive reads root `docs/`:

```markdown
## Documentation-First Reading Protocol

When answering questions about, making changes to, or exploring this library:
1. Read `docs/` FIRST — human-curated documentation is the authoritative source.
2. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
3. Read source code ONLY to fill gaps not covered by docs or to resolve a conflict.
4. Source code scanning is ONLY permitted when docs are insufficient or potentially outdated.
5. Never assume source code is more authoritative than existing documentation without verifying the docs are outdated.
```

**For monorepos** (`is_monorepo = true`) — directive reads `{target_app_name}/docs/` then root `docs/`:

```markdown
## Documentation-First Reading Protocol

This is a monorepo. When answering questions about, making changes to, or exploring a specific library:
1. Read `packages/{library-name}/docs/` FIRST for library-specific documentation.
2. Read root `docs/` for shared/cross-library context.
3. If the documentation answers the question, DO NOT scan source code. Stop and respond from docs.
4. Read source code ONLY to fill gaps not covered by docs or to resolve conflicts.
5. Source code scanning is ONLY permitted when docs are insufficient or potentially outdated.
6. Never assume source code is more authoritative than existing documentation without verifying the docs are outdated.
7. When a question is about the monorepo itself (not a specific library), check root `docs/` and `.claude/ecosystem.md` before exploring `packages/`.
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

> **Module**: Read [`document-library/commit-push-pr.md`](document-library/commit-push-pr.md) and execute all steps.

Commit subject: `docs(<repo-name>): add library documentation` (single target) or `docs(<repo-name>): add library documentation for N libraries` (multiple targets).

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md), then generate the Why Summary.

**Command type**: generative

**Context hints**:
- Impact opener: which library/libraries were documented and what depth of analysis ran
- What was accomplished: deep library documentation for API surface, capabilities, cloud permissions, and integration patterns across all targets
- Why it matters: faster integration, clearer permissions requirements, safer library usage, reduced support burden
- What happens next: review PR, keep docs maintained, rerun to refresh as library evolves
