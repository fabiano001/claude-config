---
name: refresh-docs
description: Scan all Mobius repos and refresh stale documentation in mobius-tools
argument-hint: [--since <date-or-sha>]
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Refresh Mobius Documentation

## Model Recommendation

> **Model:** Opus recommended when repo count > 15 or editorial decisions are
> complex; sonnet sufficient for targeted refresh of a small number of repos.
> Use whatever model is active in your session.

This command detects and repairs stale documentation in mobius-tools by reading
the ground truth from each sibling repo and comparing it against what the docs
currently claim. Use it whenever you suspect the docs have drifted, after adding
a new repo, or on a regular cadence to keep the platform map accurate.

---

## Canonical Rules

These constraints are non-negotiable. The agent must enforce them throughout.

- **Never rewrite editorial prose.** Sections like patterns, anti-patterns, sync
  waves, and naming conventions encode institutional knowledge. Only update them
  if factual content is provably wrong (for example, a referenced path no longer
  exists). Style and framing are not grounds for auto-rewrite.
- **Mechanical tables use markers only.** Write inside
  `<!-- GENERATED:*:START -->` / `<!-- GENERATED:*:END -->` fences. Never touch
  content outside these fences in master-map.md.
- **Editorial discrepancies require approval.** For any editorial section that
  appears stale, present a diff to the user and wait for explicit confirmation
  before making changes.
- **Always run the generator script.** Use
  `python3 scripts/generate-map-tables.py` for the three mechanical tables.
  Never hand-edit generated content.
- **Never delete content from master-map.md.** Only update existing entries or
  add new ones.
- **All changes go on a feature branch.** Never commit directly to `main`.
- **Present a change summary before committing.** The user must see all proposed
  changes — both mechanical and editorial — before any commit is created.

---

## Phase 0 — Prerequisites

Before scanning anything, verify the environment is ready.

### Step 0.1: GitHub CLI

```bash
gh auth status
```

If this fails, stop and tell the user to run `gh auth login`.

### Step 0.2: Clean working tree

```bash
git status --porcelain
```

If the working tree is dirty, stop. Report which files are modified and ask the
user to commit or stash them before proceeding.

### Step 0.3: Resolve dependencies

```bash
bash scripts/resolve-deps.sh
```

This clones or freshens all sibling repos. If it fails for any repo, report
the failure and ask the user whether to continue without that repo or abort.

---

## Phase 1 — Mechanical Table Refresh

Run the table generator:

```bash
python3 scripts/generate-map-tables.py
```

Check `git diff` to see whether the three generated tables changed:

- Repository inventory table
- Dependency table
- Skills table

Report which of the three tables changed and what was added, removed, or modified. If no tables changed, note that and continue to Phase 2.

---

## Phase 2 — Cross-Repo Scanning

Read from `ecosystem/dependency-graph.yaml` to get the authoritative list of
repos. For each sibling repo (every repo except mobius-tools), collect a snapshot.

### Per-repo reads

| File | Lines to read | Purpose |
|------|---------------|---------|
| `AGENTS.md` | frontmatter block | repo name, org, dependencies |
| `.claude/ecosystem.md` | first 20 lines | role summary, perspective |
| `README.md` | first 30 lines | high-level description (if file exists) |
| Top-level directory | listing only | structural signal |
| `.claude/skills/` | directory listing | skill names (if directory exists) |

### Per-repo snapshot

After reading, build a structured snapshot for each repo:

```
{
  name:          "iac-eks-addons",
  tier:          "gitops",
  role:          "<from dependency-graph.yaml>",
  dependencies:  ["iac-eks-argocd", ...],   # from AGENTS.md frontmatter
  skills:        ["addons-environment"],     # from .claude/skills/ listing
  top_dirs:      ["argocd/", ".claude/", "scripts/"],
  readme_summary: "<first meaningful paragraph>"
}
```

If a file is missing (for example, no `.claude/ecosystem.md`), note the gap in
the snapshot rather than erroring out. The absence itself may be a finding.

### `--since` filtering

If the user passed `--since <date-or-sha>`, read the last-commit timestamp for
each sibling repo and skip the snapshot for any repo whose most recent commit
predates the filter. Report which repos were skipped.

---

## Phase 3 — Staleness Detection

Compare the per-repo snapshots against four documentation targets.

### Documentation targets

| File | What to check |
|------|--------------|
| `ecosystem/master-map.md` | Repo inventory, dependency table, skills table, "Where to Look" table, architecture prose |
| `ecosystem/dependency-graph.yaml` | roles, tiers, dependencies, key_docs |
| `docs/architecture/platform-overview.md` | Platform descriptions, repo counts, capability claims |
| `AGENTS.md` | Shared diagram block, shared repo table block |

### Discrepancy categories

Flag findings under these categories:

**NEW REPO** — A repo appears in `dependency-graph.yaml` but has no corresponding
entry in master-map prose (beyond the generated tables). This can happen after
adding a repo to the graph without updating the narrative sections.

**ROLE DRIFT** — The repo's README or `ecosystem.md` describes its role
differently than `dependency-graph.yaml` or master-map currently state. Minor
wording differences are not drift; changed scope or capability is.

**DEPENDENCY DRIFT** — The AGENTS.md frontmatter `dependencies:` list for a repo
does not match what `dependency-graph.yaml` records. Note: `validate-graph.sh`
also covers this, but include it here for completeness.

**SKILL DRIFT** — The `.claude/skills/` directory in a repo contains skills that
are not reflected in the skills table, or lists skills that no longer exist on
disk.

**STRUCTURE DRIFT** — The top-level directory listing reveals a significant
structural change: a major new directory added, a directory removed, or a
layout that contradicts how the docs describe the repo's organization.

**STALE PATHS** — A file path referenced in any mobius-tools doc (master-map,
platform-overview, AGENTS.md) no longer exists in the target repo. Check paths
mentioned in "Key files", "Where to look", and similar reference sections.

---

## Phase 4 — Change Proposal

Present a structured report before touching any files. Group findings by whether
they can be applied automatically or need user approval.

```
## Refresh Report

### Mechanical Changes (auto-applied)
- [x] Repository inventory table: updated (added argocd-env-generator row)
- [x] Dependency table: updated (iac-eks-addons added crossplane-xrd-s3-bucket dep)
- [x] Skills table: no changes

### Editorial Changes (need your approval)
1. **master-map.md**: References `modules/{addon}/` in terraform-module-core-irsa,
   but that repo now uses `terraform/modules/{addon}/`
   → Proposed fix: update the path reference in the "Key files" table

2. **platform-overview.md**: Describes 8 XRD repos, but there are now 9
   → Proposed fix: update count and add one-line description for
     crossplane-xrd-github-oidc

3. **AGENTS.md shared table**: iac-eks-observability tier listed as "gitops" in
   dependency-graph.yaml but as "core" in the shared diagram block
   → Proposed fix: correct the shared diagram block to "gitops"

### No Issues Found
- Sync waves section: still accurate
- Anti-patterns section: still accurate
- hub-spoke diagram: still accurate
```

After presenting the report, ask:

> "Apply the mechanical changes now? Which editorial changes should I make?
> (Reply with the numbers of editorial changes to apply, or 'all', or 'none')"

Wait for the user's answer before proceeding to Phase 5.

---

## Phase 5 — Apply and Commit

Apply only the changes the user approved.

### Step 5.1: Create feature branch

```bash
git checkout -b chore/refresh-docs-YYYY-MM-DD
```

Use today's date in the branch name.

### Step 5.2: Apply mechanical changes

If the generated tables changed in Phase 1, those diffs are already in the
working tree. Stage them.

### Step 5.3: Apply approved editorial changes

Make each approved editorial edit. For each one, show the diff before staging:

```bash
git diff <file>
```

Ask for confirmation if a diff looks larger than expected relative to what was
described in the proposal.

### Step 5.4: Run CI

```bash
make ci
```

If `make ci` fails, report the failure, do not commit, and ask the user how
to proceed.

### Step 5.4b: Universal Change Safety Gate (Pre-PR)

> **What it does:** Runs the universal pre-PR safety gate before committing
> refreshed ecosystem docs and sync-state file to `mobius-tools`. Validates
> that generated tables are correct, the scan report is consistent, and
> editorial changes are within scope. Reports any blockers before commit.
> Uses shared validation logic from `shared/change-safety-validation.md` (Phase A).

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A (Pre-PR Validation Gate).

Context for this command:

- `affected_repos`: `mobius-tools` only.
- `risk_profile`: `infrastructure-config` (docs/config generation safety).
- `validation_commands_by_repo`: `make ci` and doc refresh checks from Phases 1-4.
- `rollback_strategy`: git-native revert/reset for single repo.
- Command-specific focus: generated table correctness, scan-report consistency,
  and editorial change scope control.

If Phase A reports any blocker, fix and re-run before commit/push/PR.

### Step 5.5: Commit and push

```bash
git add -A
git commit -m "chore: refresh ecosystem docs from cross-repo scan"
git push -u origin chore/refresh-docs-YYYY-MM-DD
```

Then open a pull request, including the Refresh Report from Phase 4 in the PR body:

```bash
gh pr create \
  --title "chore: refresh ecosystem docs from cross-repo scan" \
  --body "Automated refresh of ecosystem documentation. See PR description for scan summary."
```

### Step 5.6: Post-PR Feedback Scan

> **What it does:** Monitors the open PR in `mobius-tools` for CI failures,
> review rejections, and high-severity inline comments after push. Loops
> until zero blockers remain: fix → rerun Phase A validations → push → rerun
> scan. Uses shared feedback-scan logic from `shared/change-safety-validation.md` (Phase B).

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase B (Post-PR Feedback Scan).

Context for this command:

- Single PR target: `mobius-tools`.
- Required channels: checks, reviews, inline comments, issue comments.
- Blocking policy: failing required checks, `CHANGES_REQUESTED`, or high-severity security findings.
- Loop policy: fix -> rerun Phase A validations -> push -> rerun Phase B scan.

Do not claim completion until Phase B reports zero blockers.

---

## Phase 6 — Update Sync State

Write a local sync state file to support future `--since` filtering.

Target path: `ecosystem/.last-sync.yaml`

```yaml
last_sync: "2026-02-23T13:00:00Z"
repos_scanned: 19
changes_applied: 3
per_repo:
  iac-eks-argocd:
    sha: abc1234
    scanned: "2026-02-23T13:00:00Z"
  iac-eks-crossplane:
    sha: def5678
    scanned: "2026-02-23T13:00:00Z"
  # ... one entry per scanned repo
```

Record the HEAD sha for each sibling repo at scan time by running:

```bash
git -C <workspace_dir>/<repo> rev-parse --short HEAD
```

This file is `.gitignore`d — it is local state only, not committed. Future
runs use it to skip repos that have not changed since the last scan.

---

## Examples

### Full refresh

```
/mobius:refresh-docs
```

### Refresh since specific date

```
/mobius:refresh-docs --since 2026-02-01
```

Only repos with commits after 2026-02-01 are scanned. Repos with no new
commits are skipped and reported as "unchanged since last scan".

### Refresh after adding a new repo

```
# 1. Add the repo to ecosystem/dependency-graph.yaml
# 2. Run the refresh
/mobius:refresh-docs
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:help` | Lists all available commands including this one |
| `/mobius:validate-service` | Validates individual service wiring (this command validates the docs hub) |

---

## Why Summary

> **What it does:** Generates a plain-language "Why This Matters" summary at
> the end of command execution. Reads shared formatting rules and repo glossary
> from `shared/why-summary.md` and `shared/repo-roles.md`, then produces an
> output section describing how many repos were scanned, which docs are outdated,
> why stale docs cause incorrect assumptions, and which docs to prioritize updating.

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: maintenance

**Context hints**:
- "Impact opener" → state how many repos were scanned and how many have stale docs
- "What was accomplished" → describe which docs are outdated and in which repos
- "Why it matters" → stale docs cause agents and engineers to make incorrect assumptions
- "What happens next" → update the flagged docs, re-run to verify

**Repo breakdown guidance**:
- List repos with stale docs and explain what each doc is supposed to provide
- Note which docs are most critical to update first
