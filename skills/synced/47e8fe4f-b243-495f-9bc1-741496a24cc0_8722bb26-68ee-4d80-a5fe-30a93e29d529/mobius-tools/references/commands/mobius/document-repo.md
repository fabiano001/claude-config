---
name: document-repo
description: Generate AGENTS.md, docs folder, and ecosystem context for any repo
argument-hint: [repo-path]
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Document a Repository

## Model Recommendation

> **Model:** Opus recommended for large or complex repos; sonnet sufficient for
> small or well-structured codebases. Use whatever model is active in your session.

This command generates comprehensive documentation for any repository:
`AGENTS.md`, a `docs/` folder with architecture, workflow, and dependency docs,
and `.claude/ecosystem.md` for AI agent context. It works for both Mobius
platform repos and pre-migration ECS service repos that haven't been onboarded
to the ecosystem yet.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [`ecosystem/master-map.md`](../../ecosystem/master-map.md) — full platform topology
> - [`ecosystem/dependency-graph.yaml`](../../ecosystem/dependency-graph.yaml) — authoritative cross-repo dependency map
> - [`templates/agents-frontmatter.md`](../../templates/agents-frontmatter.md) — AGENTS.md frontmatter format
> - [`templates/agents-bootstrap-section.md`](../../templates/agents-bootstrap-section.md) — Bootstrap section template
> - [`templates/agents-minimap-section.md`](../../templates/agents-minimap-section.md) — Ecosystem position template

Key architectural facts:

1. **Works on any repo.** Unlike most Mobius commands that target specific repo
   types (GitOps, XRD, infrastructure), this command works on ANY repository —
   platform repos, application services, ECS services pending migration, or
   brand new projects.

2. **Two dependency layers.** The command distinguishes between **platform
   dependencies** (repo-to-repo relationships from `dependency-graph.yaml`) and
   **runtime dependencies** (service-to-service discovered via code analysis:
   HTTP clients, database clients, queue clients, AWS SDK calls). These are
   presented in separate sections to avoid confusion.

3. **Single-repo output, optional ecosystem registration.** All generated docs
   land in the target repo. If the repo is not yet registered in the Mobius
   ecosystem graph, the command offers to add it — creating a second PR in
   `mobius-tools` for the graph update.

4. **AI-proposed with user review.** The command analyzes the codebase and
   proposes documentation content. Nothing is written until the user reviews
   and approves the proposed plan.

---

## Canonical Rules

1. No file generation before the documentation plan is confirmed by the user.
2. Git preflight must pass before Phase 1 analysis begins.
3. JIRA ticket is prompted before intake — optional but encouraged.
4. No file generation on `main` — feature branch MUST exist before Phase 4.
5. Work is not complete until a PR exists with all generated files.
6. AGENTS.md frontmatter MUST use the format from `templates/agents-frontmatter.md`.
7. AGENTS.md bootstrap section MUST match `templates/agents-bootstrap-section.md` exactly.
8. Ecosystem minimap section MUST use `<!-- UNIQUE:START/END -->` and `<!-- SHARED:*:START/END -->` markers.
9. Existing documentation is NEVER silently overwritten — user chooses merge/replace/skip per file.
10. Platform dependencies (repo-to-repo) and runtime dependencies (service-to-service) are ALWAYS in separate sections.
11. AI-generated architecture descriptions are ALWAYS presented for user review — never written directly.
12. `dependency-graph.yaml` modifications go in a separate PR to `mobius-tools`, not the target repo.
13. Generated docs MUST reflect actual codebase analysis, not template boilerplate.
14. Every generated file MUST have clear section headers and be useful standalone.
15. CLAUDE.md MUST be generated at repo root with `@.claude/ecosystem.md` on line 1 and an imperative docs-first protocol — this is the primary mechanism for enforcing documentation-first behavior in future sessions. AGENTS.md MUST include the docs-first reading protocol via the canonical bootstrap section from `templates/agents-bootstrap-section.md`. Together, CLAUDE.md and AGENTS.md cover Claude Code and all AGENTS.md-reading tools (Codex, Cursor, Windsurf) respectively.
16. Deep analysis artifacts MUST be persisted to `{repo_root}/.mobius-docs-session/` and retrieved selectively during generation; do not keep full Phase 2 payloads in context.
17. `.mobius-docs-session/` artifacts are intermediate state and MUST NOT be committed.

---

## Phase 0 — Git + Environment Preflight

Before doing any analysis, verify git prerequisites and prompt for JIRA.

### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Verify for the CURRENT working directory (or provided repo path):

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree is clean: `git status --porcelain` returns empty. If dirty, hard-stop.
3. Check current branch:
   - If on `main`: pull latest (`git pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user before doing anything:
     ```
     You're currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
     2. **Switch to main and create new branch** — start fresh from main
     ```
     If user chooses "use this branch", skip branch creation in Phase 3.5.

### Step 0b: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Prompt the user. JIRA is optional for documentation PRs:

```
Before we begin, is there a Jira ticket for this documentation work?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., PLAT-456)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use repo name only)
```

Store as `jira_ticket_id` (e.g., `PLAT-456` or `null`). This value flows into:
- Branch name in Phase 3.5
- Commit message footer in Phase 6
- PR title and body in Phase 6

### Step 0c: Session Resume

Read [`shared/session-directory.md`](shared/session-directory.md), check for
`.mobius-docs-session/manifest.json`, and prompt resume/reset when stale or
scope differs.

### Step 0d: Session Ignore Guard

Ensure `.mobius-docs-session/` is ignored by git before Phase 1.
If `.gitignore` lacks this entry, append it and stage `.gitignore` with the
documentation outputs in Phase 6.

---

## Phase 1 — Repo Detection & Compatibility Check

> **Module**: Read [`document-repo/repo-detection.md`](document-repo/repo-detection.md)
> and execute all detection steps (1.1–1.6).

---

## Phase 2 — Deep Analysis

> **What it does:** Two-track analysis: Track A (Code Analysis — framework detection,
> architecture scanning, runtime dependency discovery, build/test/deploy workflows, key
> file inventory; works for ALL repos including ECS) and Track B (Ecosystem Context —
> platform dependency mapping from dependency-graph.yaml, repo summaries, cross-repo
> relationships, skill inventory; only for registered repos).
> **Key behavior:** Keeps platform deps (from graph) separate from runtime deps (from code).
> Track B is conditional — unregistered repos only get Track A analysis. Full findings are
> persisted under `.mobius-docs-session/` with a compact in-context manifest.
> **Shared module**: Read [`shared/session-directory.md`](shared/session-directory.md)
> before executing Phase 2.
> **Module**: Read [`document-repo/discovery-analysis.md`](document-repo/discovery-analysis.md)
> and execute the full discovery workflow.

---

## Phase 2.5: Delegation Routing

> **Module**: Read [`document-repo/delegation-routing.md`](document-repo/delegation-routing.md)
> and execute the full delegation routing workflow.

---

## Phase 3 — AI-Proposed Documentation Plan

After Phase 2 analysis completes, generate a proposed documentation plan and
present it to the user for review.

### Step 3.1: Build Documentation Plan

Using the Phase 2 analysis, build a proposed plan for each output file:

| Output File | Source Data |
|-------------|-------------|
| `AGENTS.md` | Repo identity, dependencies, key files, ecosystem position |
| `docs/README.md` | Index of all docs files with one-line descriptions |
| `docs/architecture.md` | Framework, patterns, data flow, key modules, API surface |
| `docs/workflow.md` | Run/test/build/deploy commands, environment config, debugging |
| `docs/dependencies.md` | Platform deps (graph) + Runtime deps (code analysis) |
| `.claude/ecosystem.md` | Repo description, role, relationships, agent context |

### Step 3.2: Present Plan for Review

Present the complete proposed plan to the user:

```
Documentation Plan for: <repo-name>

=== AGENTS.md ===
  Frontmatter: repo: <name>, org: boatsgroup, dependencies: [<list>]
  Sections: Quick Reference, Agent Instructions, Key Files,
            Cross-Repo Bootstrap, Working Rules, Ecosystem Position

=== docs/README.md ===
  Index linking: architecture.md, workflow.md, dependencies.md

=== docs/architecture.md ===
  - Overview: <one-sentence repo description>
  - Tech stack: <framework, language, key libraries>
  - Architecture: <detected patterns — layers, data flow>
  - Key modules: <N modules grouped by domain>
  - API surface: <N endpoints / routes detected> (if applicable)

=== docs/workflow.md ===
  - Local development: <detected run command>
  - Testing: <detected test framework + command>
  - Building: <detected build command>
  - Deployment: <detected CI/CD pipeline>
  - Environment: <N env vars detected>

=== docs/dependencies.md ===
  Platform Dependencies:
    <Upstream: N repos | NOT registered — will show registration option>
    <Downstream: N repos | NOT registered>
  Runtime Dependencies:
    <Databases: list>
    <Services: list>
    <AWS: list>
    <External APIs: list>
    <Message queues: list>

=== .claude/ecosystem.md ===
  Per-repo perspective with role and relationships

Approve this plan? (yes / edit specific sections / start over)
```

### Step 3.3: Handle User Feedback

- **"yes" / "looks good"**: Lock the plan. Proceed to Phase 3.5.
- **Specific edits**: Apply changes to the plan, re-present, and wait for approval.
- **"start over"**: Return to Phase 2 with adjusted analysis scope.

**Once confirmed, the approved plan is the SINGLE SOURCE OF TRUTH for generation.**

---

## Phase 3.5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This phase MUST succeed before Phase 4 begins.**

### Create Feature Branch

If on `main` (determined in Phase 0 Step 0a), create a feature branch:

Branch name pattern:
- With JIRA: `docs/<jira_ticket_id>-document-<repo-name>` (e.g., `docs/PLAT-456-document-payments-api`)
- Without JIRA: `docs/document-<repo-name>` (e.g., `docs/document-payments-api`)

```bash
git checkout -b <branch-name>
git branch --show-current   # Verify
```

If branch already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

If the user chose to keep their existing branch in Phase 0, skip branch creation.

### Gate Verification

```
Branch Gate Status:
  ✅ <repo-name>   → docs/PLAT-456-document-payments-api

Proceeding to documentation generation.
```

---

## Phase 4 — Generate Documentation

> **What it does:** Generates 7 files from approved plan: AGENTS.md (assembled from
> templates + AI-generated sections), docs/README.md (index), docs/architecture.md,
> docs/workflow.md, docs/dependencies.md (two-section: platform deps from graph +
> runtime deps from code), .claude/ecosystem.md, CLAUDE.md (docs-first enforcement
> via @-import of ecosystem.md). Optional Step 4.8: register in ecosystem
> graph (separate PR in mobius-tools).
> **Key behavior:** AGENTS.md is assembled from templates (frontmatter, bootstrap, minimap)
> plus AI-generated repo-specific sections — never fully AI-generated from scratch.
> Phase 4 reads only the required `.mobius-docs-session/` artifacts per output file.
> Note: `codex.md` is NOT generated — AGENTS.md (which Codex, Cursor, and Windsurf read natively) now includes the Docs-First Reading Protocol in its bootstrap section.
> **Module**: Read [`document-repo/code-generation.md`](document-repo/code-generation.md)
> for complete file templates, section formats, and content rules.



## Phase 5 — Validate

Run validation checks on all generated files.

| Check | What | Severity |
|-------|------|----------|
| VAL-001 | AGENTS.md frontmatter matches `dependency-graph.yaml` (if registered) | Error |
| VAL-002 | All generated files are valid Markdown | Error |
| VAL-003 | `docs/README.md` links resolve to actual files in docs/ | Error |
| VAL-004 | Bootstrap section matches canonical template from `templates/agents-bootstrap-section.md` | Warning |
| VAL-005 | Ecosystem minimap markers present (`UNIQUE:START/END`, `SHARED:*:START/END`) | Warning |
| VAL-006 | No duplicate files generated (didn't generate files that were skipped) | Error |
| VAL-007 | Mermaid diagram syntax is valid (if diagrams were generated) | Warning |
| VAL-008 | Runtime dependencies section has entries or explicit "none detected" | Warning |
| VAL-009 | All docs/ files have section headers (not empty or placeholder-only) | Error |
| VAL-010 | `.claude/ecosystem.md` exists and has content | Warning |
| VAL-011 | AGENTS.md contains `### Docs-First Reading Protocol (MANDATORY)` subsection in the Cross-Repo Bootstrap section, with ordered reading list referencing `.claude/ecosystem.md` and `docs/` | Error |

### Validation Report

```
Validation Summary:
  ✅ VAL-001  — Frontmatter consistent with graph
  ✅ VAL-002  — All Markdown valid
  ✅ VAL-003  — docs/README.md links resolve
  ✅ VAL-004  — Bootstrap section matches template
  ✅ VAL-005  — Minimap markers present
  ✅ VAL-006  — No duplicate files
  ✅ VAL-007  — Mermaid syntax valid
  ✅ VAL-008  — Dependencies section populated
  ✅ VAL-009  — All docs have content
  ✅ VAL-010  — ecosystem.md exists
  ✅ VAL-011  — AGENTS.md has ecosystem.md must-read directive

All validation gates passed. Proceeding to commit.
```

If ANY Error-severity check fails, fix and re-validate before proceeding.

### Pre-PR Flaw Scan

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:
- `affected_repos`: target repo (and optionally mobius-tools for graph registration).
- `risk_profile`: `documentation` (low risk — no application code changes).
- `validation_commands_by_repo`: Markdown validation, link checking.
- `rollback_strategy`: git-native revert/reset (documentation-only changes).

---

## Phase 6 — Commit, Push, and PR Creation

> **What it does:** Single-repo commit/push/PR (target repo). Optional second PR in
> mobius-tools for ecosystem graph registration. Post-PR feedback scan.
> **Key behavior:** Graph registration is a separate PR in a different repo — it should
> not block the primary documentation PR.
> **Module**: Read [`document-repo/commit-push-pr.md`](document-repo/commit-push-pr.md)
> and execute all steps.

This module handles:

- Staging all generated and modified files
- Creating a conventional commit
- Pushing the feature branch to the remote
- Creating a pull request with a structured description
- (Optional) Creating a second PR in `mobius-tools` for graph registration
- Running post-PR feedback scan

Commit message format:
```
docs(<repo-name>): add repository documentation

- Add AGENTS.md with frontmatter, bootstrap, and ecosystem position
- Add docs/architecture.md with service architecture and tech stack
- Add docs/workflow.md with development, testing, and deployment workflow
- Add docs/dependencies.md with platform and runtime dependencies
- Add docs/README.md index
- Add .claude/ecosystem.md with repo perspective

<JIRA_TICKET_ID>
```

---

## Phase 7: Delegation (CONDITIONAL)

> Skip if Phase 2.5 determined no delegation targets.

Execute delegated commands sequentially. Each receives:
- Phase 2 artifacts from `.mobius-docs-session/`
- Shared branch name
- `delegated: true` flag in session manifest

### Execution Order

1. `document-service` for each service target
2. `document-library` for each library target (including co-located libraries)
3. `document-iac` for each IaC target (including co-located IaC)
   - document-iac receives `delegated: true` and skips its own internal document-repo run

### Error Handling

- Failures are isolated per-target — other delegated commands still run
- Report the error context to the user
- Partial results remain on the branch — user prompted to review before PR

### Phase 7.1: Cross-Reference Reconciliation

After all delegations complete, read all generated docs and add cross-links:

1. **Service → Library links:** If a service target imports a library target, add to the service's `docs/developer-guide.md`: a link to the library's `docs/integration-guide.md`.

2. **Service → Library permissions:** If a service target imports a library target that has `docs/cloud-permissions.md`, add an "Inherited Permissions" section to the service's `docs/cloud-permissions.md` referencing the library's doc.

3. **Library "Used by" section:** Add known in-repo service consumers to the library's `docs/README.md` under a "Used by" section.

Only link to docs that were successfully generated (skip failed targets).

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → which repo was documented and how many documentation files were generated
- "What was accomplished" → describe the documentation package: AGENTS.md for AI agent context, architecture docs for engineers, dependency map for operational awareness
- "Why it matters" → engineers and AI agents can now work in this repo with full context instead of guessing; runtime dependencies are mapped for incident response; ecosystem position is clear for cross-repo changes
- "What happens next" → review the PR, keep docs updated as the service evolves, run `/mobius:refresh-docs` periodically to detect drift. Include next-command suggestions based on detected repo type:
  - If `primary_type` is an application service (Node.js, Go, Java, PHP, Python, Lambda): suggest running `/mobius:document-service` for deeper service documentation (API reference, request flow diagrams, runbook)
  - If Terraform files (`*.tf`), Helm charts (`Chart.yaml`), Kustomize, or KCL were detected: suggest running `/mobius:document-iac` for infrastructure-specific documentation (module inventory, state management, dependency maps)
  - If library targets were detected: suggest running `/mobius:document-library` for library-specific documentation (API surface, usage examples, consumer guidance)

**Repo breakdown guidance**:
- Target repo: where all generated documentation files live
- mobius-tools (if graph registration): where the ecosystem graph entry was added
