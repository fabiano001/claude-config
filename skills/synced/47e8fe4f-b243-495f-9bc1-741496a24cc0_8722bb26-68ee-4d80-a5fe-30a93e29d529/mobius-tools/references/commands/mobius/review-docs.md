---
name: review-docs
description: Scan all Mobius repos and propose targeted updates to the mobius-docs Docusaurus site
argument-hint: [--since <date-or-sha>] [--repo <repo-name>]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Review and Update mobius-docs

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command reads XRD definition schemas, AGENTS.md role descriptions,
> CLAUDE.md conventions, and existing Docusaurus content simultaneously, then
> identifies semantic gaps and drafts new or updated prose. Weaker models
> produce generic filler or miss the distinction between what the docs claim
> and what the code actually does.

This command detects and repairs stale or missing content in the
[`mobius-docs`](https://github.com/boatsgroup/mobius-docs) Docusaurus site by
reading the ground truth from each Mobius repo and comparing it against what
the user-facing docs currently cover.

Use it after adding a new XRD, after significant platform changes, or on a
regular cadence to keep the engineering site accurate.

---

## Key Distinction: Two Documentation Sets

Mobius has two documentation layers with different audiences:

| Layer | Repo | Audience | What it covers |
|-------|------|----------|----------------|
| **Skill docs** | `mobius-tools/.claude/skills/mobius/docs/` | Platform/DevOps engineers | ApplicationSet mechanics, hub-spoke architecture, bootstrap, directory standards |
| **User docs** | `mobius-docs/docs/` | Application engineers | How to deploy apps, config.yaml reference, observability, operations |

This command maintains the **user docs** (`mobius-docs`). The skill docs are
maintained by the authors of this command pack and are not modified here.

---

## Canonical Rules

- **Never rewrite working prose.** Only update content where the underlying
  platform reality has changed. Style is not grounds for edits.
- **Draft, don't overwrite.** For missing content, propose new sections or
  pages. For stale content, show a diff. Let the user decide what to apply.
- **Source of truth is the repos.** `definition.yaml` for XRD schemas,
  `AGENTS.md` + `CLAUDE.md` for patterns and conventions, `README.md` for
  high-level descriptions.
- **All changes go on a feature branch** in `mobius-docs`. Never commit to
  `main` in either repo.
- **Present a change summary before committing.** The user must approve all
  proposed changes before any file is written.
- **Update `sidebars.ts`** whenever a new page is created.

---

## Phase 0 — Prerequisites

### Step 0.1: GitHub CLI

```bash
gh auth status
```

If this fails, stop and tell the user to run `gh auth login`.

### Step 0.2: Locate mobius-docs

```bash
ls <workspace_dir>/mobius-docs/docs/
```

If the repo is not found at `<workspace_dir>/mobius-docs`, clone it:

```bash
gh repo clone boatsgroup/mobius-docs <workspace_dir>/mobius-docs
```

### Step 0.3: Clean working trees

```bash
git -C . status --porcelain
git -C <workspace_dir>/mobius-docs status --porcelain
```

If either repo has uncommitted changes, stop and tell the user to commit or
stash before proceeding.

### Step 0.4: Resolve sibling repos

```bash
bash scripts/resolve-deps.sh
```

---

## Phase 1 — Catalog mobius-docs

Read the current state of the Docusaurus site before scanning repos.

### Step 1.1: Page inventory

List every `.mdx` and `.md` file under `<workspace_dir>/mobius-docs/docs/` recursively.
For each file, note:
- Path (e.g., `aws-infrastructure/s3-bucket.mdx`)
- Section heading (first `#` heading)
- One-line topic summary (from opening paragraph)

Build a **page catalog**:

```
{
  "aws-infrastructure/s3-bucket.mdx": {
    heading: "S3 Bucket",
    topic: "Provisioning S3 buckets via Crossplane XIRSARole + XS3Bucket claim"
  },
  ...
}
```

### Step 1.2: Sidebar structure

Read `<workspace_dir>/mobius-docs/sidebars.ts` to understand section groupings and page
order. This matters when placing new pages.

### Step 1.3: XRD page coverage

Identify which `crossplane-xrd-*` repos already have a corresponding page
under `aws-infrastructure/`. Record any that are missing.

---

## Phase 2 — Scan Mobius Repos

Read from `ecosystem/dependency-graph.yaml` to get the authoritative repo
list. For each repo, collect a snapshot.

### `--since` filtering

If the user passed `--since <date-or-sha>`, check the last-commit timestamp
for each sibling repo:

```bash
git -C <workspace_dir>/<repo> log -1 --format="%ci"
```

Skip repos whose most recent commit predates the filter. Report which repos
were skipped.

### `--repo` filtering

If the user passed `--repo <repo-name>`, scan only that repo and skip Phase 1
catalog (still read mobius-docs for the specific section that repo touches).

### Per-repo reads

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD API schema — spec fields, required fields, defaults |
| `AGENTS.md` | Role, capabilities, patterns, anti-patterns |
| `CLAUDE.md` or `docs/CLAUDE.md` | Conventions, workflow details |
| `.claude/ecosystem.md` (first 30 lines) | Role summary from the repo's own perspective |
| `README.md` (first 40 lines) | High-level description |
| Top-level directory listing | Structural signal |
| `CHANGELOG.md` or release tags | Recent changes if available |

### Triggers: what warrants a doc update

Not every repo change warrants a doc update. Apply these triggers to focus the
scan on meaningful changes:

| Trigger | What to check in mobius-docs |
|---------|------------------------------|
| **New XRD repo** | Missing page in `aws-infrastructure/` |
| **New spec field in `definition.yaml`** | Corresponding XRD page — spec reference table |
| **Removed or renamed spec field** | Same XRD page — stale field references |
| **New anti-pattern in CLAUDE.md** | `deploying-your-app/` pages — callout/warning blocks |
| **New addon in `iac-eks-addons`** | `deploying-your-app/environment-overlays.mdx` — examples |
| **New platform pattern in AGENTS.md** | `core-concepts/` pages |
| **IRSA or IAM pattern changes** | `deploying-your-app/config-yaml-reference.mdx` |
| **New CLI command or tool** | `reference/command-reference.mdx` |
| **New Crossplane function version** | `aws-infrastructure/` pages using that function |

---

## Phase 3 — Staleness Detection

Compare per-repo snapshots against the page catalog. Flag findings under these
categories:

### NEW PAGE NEEDED

A repo or major capability exists in the platform but has no corresponding
page in mobius-docs. Most common case: a new `crossplane-xrd-*` repo with no
`aws-infrastructure/` page.

For each missing page, note:
- Repo name and tier
- What the page should cover
- Which `definition.yaml` fields are the API surface
- Which existing page is the closest structural model to copy

### STALE SCHEMA

An existing XRD page documents spec fields that no longer match
`definition.yaml`. Either new fields were added without updating docs, or old
fields were removed/renamed.

Show a diff of: what the doc says vs. what `definition.yaml` actually defines.

### STALE PATH REFERENCE

A doc references a file path (e.g., `argocd/karpenter/overlays/{env}/`) that
no longer exists in the referenced repo, or uses a naming convention that has
since changed.

### PATTERN DRIFT

AGENTS.md or CLAUDE.md documents a pattern or anti-pattern that is not
reflected in the relevant user doc page. For example, a new "don't do X"
added to a repo's CLAUDE.md that isn't mentioned in the docs page that teaches
that workflow.

### MISSING EXAMPLE

The docs describe how to use a Crossplane XRD but don't include a working
claim YAML example, while the repo has one in `examples/`.

---

## Phase 4 — Change Proposal

Present a structured report before touching any files. Group findings by
whether they require a new page, an update to an existing page, or are
informational only.

```
## Review Report

### New Pages (propose + draft)
1. **aws-infrastructure/github-oidc.mdx** — crossplane-xrd-github-oidc has no doc page
   Proposed: draft from definition.yaml + README, modeled on s3-bucket.mdx
   Note: repo is marked as a stub in known-inconsistencies — flag in page frontmatter

### Updates to Existing Pages (show diff, need approval)
2. **aws-infrastructure/irsa-role.mdx** — spec table missing 3 new fields added in v0.4.0
   Fields to add: `sessionDuration`, `maxSessionDuration`, `trustPolicyExtra`
   → Show proposed diff

3. **deploying-your-app/config-yaml-reference.mdx** — CLAUDE.md for iac-eks-addons
   added anti-pattern: "never set testBranch to a SHA hash"
   → Propose adding a :::warning admonition

### Stale Paths (show diff, need approval)
4. **platform-runbooks/cluster-setup.mdx** — references
   `iac-eks-argocd/docs/12-cluster-setup-runbook.md` which no longer exists
   → Propose replacing with reference to skill docs

### Informational (no action needed)
- iac-eks-crossplane: no doc-relevant changes detected
- All XRD repos except github-oidc: spec tables current
```

After presenting the report, ask:

> "Draft the new pages now? Which updates should I apply?
> (Reply with numbers, 'all', or 'none'. For new pages, I'll draft and show
> you before writing.)"

Wait for the user's answer before proceeding to Phase 5.

---

## Phase 5 — Draft New Pages

For each approved new page:

### Step 5.1: Identify the model page

Find the closest existing page in `aws-infrastructure/` or the relevant
section to use as a structural template. Read it fully.

### Step 5.2: Read source material

For an XRD page:
- Read `definition.yaml` fully — this is the API contract
- Read `README.md` — high-level description
- Read `CLAUDE.md` — patterns and anti-patterns
- Read `examples/basic.yaml` or `examples/*.yaml` — working claim YAML

### Step 5.3: Draft the page

Structure new `aws-infrastructure/{xrd-name}.mdx` pages as follows:

```mdx
---
sidebar_label: "{Human name}"
title: "{Human name} — Crossplane Claim"
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Overview

{One paragraph: what AWS resource(s) this provisions, what problem it solves,
when to use it.}

## Prerequisites

{List what must exist before creating a claim: IRSA role, cluster, namespace.}

## Basic Example

{Working claim YAML from examples/, annotated with comments on required fields.}

## Spec Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
{One row per spec field from definition.yaml openAPIV3Schema}

## Common Patterns

{2-3 use cases with YAML snippets. Draw from CLAUDE.md if available.}

## Troubleshooting

{Known failure modes and fixes. Cross-link to troubleshooting/ section.}
```

Show the full draft to the user before writing.

---

## Phase 6 — Apply Changes

Apply only the changes the user approved.

### Step 6.1: Create feature branch in mobius-docs

```bash
git -C <workspace_dir>/mobius-docs checkout -b docs/review-{YYYY-MM-DD}
```

Use today's date.

### Step 6.2: Write new pages

Write each approved new page. After writing each one, run a quick sanity check:

```bash
# Verify frontmatter is valid
head -5 <workspace_dir>/mobius-docs/docs/{path}

# Confirm no broken MDX syntax (look for unclosed JSX tags)
grep -n "<[A-Z]" <workspace_dir>/mobius-docs/docs/{path}
```

### Step 6.3: Update sidebars.ts

For each new page, add it to the correct position in `<workspace_dir>/mobius-docs/sidebars.ts`.
Read the file first to understand the existing structure, then add the new
entry in the correct section and alphabetical position.

### Step 6.4: Apply diffs to existing pages

For each approved edit to an existing page, make the targeted change. Show
`git diff` before staging.

### Step 6.5: Commit

```bash
git -C <workspace_dir>/mobius-docs add -A
git -C <workspace_dir>/mobius-docs commit -m "docs: {summary of changes from review report}"
git -C <workspace_dir>/mobius-docs push -u origin docs/review-{YYYY-MM-DD}
```

### Step 6.6: Open PR in mobius-docs

```bash
gh pr create \
  --repo boatsgroup/mobius-docs \
  --title "docs: sync platform docs from cross-repo scan ({YYYY-MM-DD})" \
  --body "..."
```

Include the Review Report from Phase 4 in the PR body.

---

## Phase 7 — Update Sync State

Write a local sync state file for future `--since` filtering.

Target path: `ecosystem/.last-docs-review.yaml`

```yaml
last_review: "{ISO timestamp}"
repos_scanned: {n}
changes_applied: {n}
mobius_docs_branch: "docs/review-{YYYY-MM-DD}"
per_repo:
  crossplane-xrd-irsa-role:
    sha: abc1234
    scanned: "{ISO timestamp}"
    findings: 0
  crossplane-xrd-s3-bucket:
    sha: def5678
    scanned: "{ISO timestamp}"
    findings: 1
    applied: true
```

This file is `.gitignore`d — local state only, not committed. Future runs use
it to skip repos that have not changed since the last review.

---

## Examples

### Full review

```
/mobius:review-docs
```

### Review since a specific date

```
/mobius:review-docs --since 2026-04-01
```

Only repos with commits after 2026-04-01 are scanned.

### Review a single repo

```
/mobius:review-docs --repo crossplane-xrd-irsa-role
```

Scans only that repo and checks the `aws-infrastructure/irsa-role.mdx` page.

### After adding a new XRD repo

```
# 1. Add repo to ecosystem/dependency-graph.yaml
# 2. Run a targeted review
/mobius:review-docs --repo crossplane-xrd-{name}
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:refresh-docs` | Refreshes ecosystem docs in mobius-tools (master-map, dependency-graph). This command refreshes user docs in mobius-docs. |
| `/mobius:new-xrd` | After creating a new XRD, run this to draft the aws-infrastructure/ page |
| `/mobius:add-service` | After adding a new addon pattern, run this to update deploying-your-app/ examples |
| `/mobius:help` | Lists all available commands including this one |
