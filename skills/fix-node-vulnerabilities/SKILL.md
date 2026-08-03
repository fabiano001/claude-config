---
name: fix-node-vulnerabilities
description: >-
  Analyzes and remediates Node.js / npm package vulnerabilities supplied as an npm-audit JSON file,
  a Dependabot or Snyk export, or a screenshot of a vulnerability dashboard. For each finding it
  determines whether the vulnerability is direct or transitive (resolving the parent dependency to
  upgrade when transitive), computes the minimum non-breaking version bump that patches it, and for
  unavoidable major upgrades researches the breaking changes and checks whether the codebase is
  actually impacted. Produces a dependency-vulnerability-upgrade-report.md for operator approval
  BEFORE any change, then implements the version upgrades plus any required code refactoring and
  opens a PR — either inline (standard) or via a dynamic background workflow. Repo-agnostic: reads
  the lockfile referenced per vulnerability to target the correct project, so it works across repos
  with multiple lockfiles. Use when the user asks to fix / remediate npm or node vulnerabilities,
  resolve npm audit findings, address Dependabot / Snyk / CVE alerts, or upgrade vulnerable
  dependencies. Triggers on "fix node vulnerabilities", "npm audit fix", "dependabot alerts",
  "snyk", "CVE", "transitive vulnerability", "vulnerability remediation". NOT for routine dependency
  bumps unrelated to security, and NOT for non-JavaScript ecosystems (pip, cargo, maven, go).
---

# Fix Node Package Vulnerabilities

Remediate one or more Node.js package vulnerabilities end-to-end: analyze → report → get approval →
implement → open PR. **Always produce and get approval on the report before touching any file.**

## Inputs

The skill takes the vulnerability set as `$ARGUMENTS`, which is one of:

- **A JSON file path** — `npm audit --json` output, or a Dependabot / Snyk export.
- **A screenshot** (image path or pasted image) — a vulnerability dashboard (GitHub Dependabot,
  Snyk, `npm audit` terminal capture).
- **Pasted text** — a list of advisories.

The input is expected to identify, per vulnerability, **which lockfile** it belongs to (e.g.
`dynamic-app/package-lock.json`, `functions/package-lock.json`). This is how the skill targets the
right project in a multi-lockfile repo. If a lockfile is missing for a finding, ask the operator
which project it belongs to before analyzing it.

## Critical rules (read first)

1. **Report before action.** Write `dependency-vulnerability-upgrade-report.md`, present it, and get
   explicit approval **before** editing `package.json`, lockfiles, or any source.
2. **Minimum, least-breaking upgrade wins.** Prefer the smallest semver jump that clears the
   advisory. Prefer a patch/minor bump or a transitive `overrides` pin over a major bump.
3. **Never silently change behavior.** When a major upgrade forces code refactoring, the refactor
   must preserve existing functionality exactly. Call out anything that cannot.
4. **Respect repo conventions.** Read the target repo's `CLAUDE.md` / `CONTRIBUTING.md` for install
   command, branch naming, commit prefix, semantic-version bump, and lint/test gates. Honor them.
5. **Verify the fix.** After upgrading, re-run `npm audit` (or `npm audit --json`) in each touched
   project and confirm the findings are gone before opening the PR.
6. **One PR for the batch** unless the operator asks otherwise. Group all upgrades for a repo into a
   single branch/PR.

## Workflow

### 1. Parse the input → vulnerability inventory

Build a table in memory. For each vulnerability capture: package name, severity, advisory id / CVE,
vulnerable version range, the **lockfile / project** it belongs to, and (if available) the patched
version range. For a screenshot, Read the image and extract these fields; ask the operator to
confirm anything unreadable.

### 2. Classify direct vs transitive — per project

For each project (grouped by lockfile), in that project's directory:

- **Direct** if the package appears in `package.json` `dependencies` / `devDependencies`.
- **Transitive** otherwise. Find the parent to upgrade with `npm why <pkg>` (npm 7+) or
  `npm ls <pkg>`, or by parsing the lockfile. The **upgrade target** is the top-level dependency
  whose tree pulls in the vulnerable package.

See [references/analysis.md](references/analysis.md) for detection commands and the `overrides`
strategy for transitive pins.

### 3. Determine the minimum non-breaking upgrade — per target

For each upgrade target, find the **lowest** version that both satisfies the advisory's patched
range and is the smallest semver jump from the current version. Classify the jump as **patch /
minor / major**. A non-major bump that patches the issue is the goal — record it and move on.

For transitive findings, also evaluate an `overrides` pin of just the transitive dependency to a
patched version (often the least-breaking option). See [references/analysis.md](references/analysis.md).

### 4. Major upgrades — breaking-change impact analysis

Only when a major bump is the only fix:

1. Research breaking changes from the package's CHANGELOG / migration guide / release notes. Use
   context7 (`resolve-library-id` then `query-docs`) and/or WebFetch the repo's releases.
2. Enumerate each breaking change.
3. For each, grep the codebase for usage of the affected API/export to decide impact.
4. Record a checkbox per breaking change: **impacted (needs refactor) / not impacted**, with the
   affected files.

### 5. Write the report

Write `dependency-vulnerability-upgrade-report.md` at the repo root using
[assets/report-template.md](assets/report-template.md). One row per vulnerability with: type
(direct | transitive), upgrade target (parent package if transitive), current → new version,
upgrade type (major | minor | patch), severity/advisory, and — for majors — the breaking-change
summary with impact checkboxes and affected files.

### 6. Present and get approval — then choose implementation mode

Present the report summary in chat. Then ask the operator two things:

1. **Permission to proceed** with the upgrades and refactoring.
2. **Implementation mode** — use `AskUserQuestion`:
   - **Standard** — implement inline in this conversation, step by step.
   - **Dynamic workflow** — launch an Opus 4.8 dynamic background workflow (an autonomous executor
     in an isolated git worktree) that applies the upgrades, refactors impacted code, runs
     lint/test/audit, and opens the PR, reporting back on completion.

Do not start implementation until both are answered.

### 7. Implement

Follow [references/implementation.md](references/implementation.md). Summary:

- Apply version changes to `package.json` (and/or add `overrides` for transitive pins).
- Refresh the lockfile with the repo's install command (`npm install` is correct here — the
  lockfile update is the intended effect of an upgrade).
- Refactor each impacted breaking change, preserving functionality.
- Run lint, tests, and build in each touched project; fix fallout.
- Re-run `npm audit` per project and confirm findings cleared.
- Apply repo conventions (e.g. semantic-version bump where required).
- Branch, commit (repo's prefix convention), push, open the PR with `gh`, linking the report.

For **dynamic workflow** mode, hand the approved report + this workflow to the background executor
as its spec; it owns steps 7's implementation and PR. For **standard** mode, do it inline.

## Notes

- If `npm audit fix` (non-`--force`) already resolves a finding cleanly, prefer it, but still record
  the resulting version change in the report.
- Never run `npm audit fix --force` without flagging it — it allows major bumps and breaking changes.
- If a vulnerability has no available patch, mark it in the report as **no fix available** and
  recommend a mitigation (override pin to nearest safe, remove dependency, or accept risk) rather
  than forcing an unsafe change.
