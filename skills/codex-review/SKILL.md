---
name: codex-review
description: Runs an independent code-review pass using a dedicated Claude Opus 4.8 subagent — NOT Codex (the Codex CLI dependency was removed; no Codex API key is available). Accepts either a GitHub PR URL (derives the diff/branch/ticket automatically) OR a freeform review brief from the calling agent describing exactly what to review and what to look for (specific files, a diff range, uncommitted changes, a custom focus area, etc.) — this is what other skills/agents should use when they want something reviewed that isn't a PR. Generates a structured markdown report classifying each finding as "Real issue (fix)" or "Not a real issue", and offers to apply fixes. Supports autonomous mode for auto-fixing. Use when the user or a calling agent asks for a codex review, codex code review, AI peer review of a branch/diff/file, or a second opinion on any code — despite the "codex" name (kept for backwards compatibility with callers like `ticket-driver`), this is now an Opus 4.8 agent review.
---

# Codex Review (Opus 4.8 agent — no Codex CLI involved)

**Naming note:** the skill name/invocation (`/codex-review`) and the `CODEX-REVIEW` file-naming convention are kept unchanged so `ticket-driver` and any other caller that references this skill by name or globs its report filenames don't need to change. Internally, this skill no longer uses Codex CLI at all — it dispatches an independent Claude Opus 4.8 subagent (via the `Agent` tool) to do the review, since no Codex API key is available.

Review a target — a PR, a diff, specific files, uncommitted changes, or anything else a calling agent hands off — using a fresh, independent Opus 4.8 subagent. Produce a structured markdown report with actionable determinations. Optionally fix issues — the report is saved directly to durable memory storage, so there's no stash step.

## Inputs

Two ways to invoke this skill — detected from the input in Step 1:

| Mode | Input shape | What it's for |
|------|-------------|----------------|
| **PR mode** | A GitHub PR URL (`https://github.com/{owner}/{repo}/pull/{n}` or `{owner}/{repo}#{n}`) | The existing, ticket-driver-facing flow — auto-derives the base/head branches and ticket number from the PR itself. |
| **Direct mode** | Anything else — a freeform description of what to review, written by the user OR by a calling agent/skill | For any caller that wants a review of something that isn't a PR: specific files, a diff between two refs, uncommitted changes, a directory, "just this function," etc. **The calling agent supplies the review target AND, optionally, custom instructions on what to focus on** (e.g., "review this diff for race conditions only" or "review these 3 files for the error-handling pattern described in the ticket"). If no custom instructions are given, the default general-purpose bug/security/performance/style checklist (Step 2) applies. |

Direct mode is the general-purpose entry point — use it whenever the thing to review isn't a PR (e.g., a research worktree with no PR yet, a pre-PR sanity check, a single file, a spike's output). PR mode remains the default when the input is unambiguously a PR URL.

## Modes (fix behavior)

Orthogonal to PR/Direct mode above — this controls whether findings get auto-fixed:

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Interactive** (default) | Caller doesn't say "autonomous" | Generates report, asks before fixing |
| **Autonomous** | Caller says "autonomous", "auto-fix", or "auto mode" | Fixes all "Real issue / Fix" items, commits, pushes |

Determine this mode from the caller's message. If unclear, default to **Interactive**.

## Critical Rules

- In **Interactive** mode: NEVER make changes without explicit user approval
- In **Autonomous** mode: Only auto-fix issues determined as "Real issue" with recommendation "Fix" — skip "Leave as is" items
- ALWAYS research the actual codebase before making a determination on each finding — the reviewer agent's claim is a starting hypothesis, not a verdict. This matters MORE now than it did with the old two-AI Codex debate flow, since there's no second AI opinion to lean on.
- Save the report to `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/` before applying any fixes
- ALWAYS dispatch the review via a fresh `Agent` tool call with `model: "claude-opus-4-8"` — do NOT review inline in the current session (an independent subagent that hasn't seen the implementation reasoning is the point) and do NOT invoke the `codex` CLI or `/codex-peer-review` (no Codex API key available)

## Workflow

### Step 1: Determine mode and resolve the review scope

**Detect PR mode vs Direct mode first.** Check whether the input matches a GitHub PR URL pattern:
- `https://github.com/{owner}/{repo}/pull/{number}`
- `{owner}/{repo}#{number}`

If it matches → **PR mode** (1A). Otherwise → **Direct mode** (1B): treat the entire input as a freeform review brief written by the caller (user or calling agent).

#### 1A. PR mode

Extract `owner`, `repo`, and `pr_number` from the URL, then fetch PR metadata:
```bash
gh pr view {number} --repo {owner}/{repo} --json title,number,url,headRefName,baseRefName,author
```

From the response, extract:
- **`baseRefName`** — the PR's target branch (e.g., `main`). This is the base for the review diff.
- **`headRefName`** — the PR's source branch (e.g., `TRIDENT-822`). This is the current branch.
- **Ticket number** — extract from the PR title (convention: title starts with `TICKET-123:` or `[TICKET-123]`). This becomes `REPORT_LABEL` (Step 5). If no ticket number is found, fall back to `PR-{number}`.

Verify you are on the correct branch:
```bash
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"
```

If `CURRENT_BRANCH` does not match `headRefName`, warn the user and ask if they want to continue.

Verify there are changes to review:
```bash
git diff {baseRefName}...HEAD --stat
```

If no changes, inform the user and stop.

Set `REVIEW_BRIEF` to the standard PR-diff instruction (used verbatim in Step 2's prompt template): review the diff between `{baseRefName}` and `HEAD`.

#### 1B. Direct mode

There is no PR to look up — the caller's input IS the review target and (optionally) custom instructions. Capture it verbatim as `REVIEW_BRIEF`. Do NOT try to force-parse it into a diff range or file list yourself; the reviewer subagent (Step 2) has its own Bash/Read/Grep/Glob tools and will interpret the brief directly. Examples of what a caller might pass as `REVIEW_BRIEF`:
- `"Review the diff between main and TRIDENT-926-research in lambda-node-trident-partner-lender for logic bugs in the polling scheduler."`
- `"Review src/utils/refreshSubmission.ts and its tests for correctness — focus on the idempotency guard."`
- `"Review my uncommitted changes (git diff, no ref) for anything that would break the build."`
- `"Review the last 3 commits on this branch."`

Resolve `REPORT_LABEL` for file-naming purposes (Step 5), in priority order:
1. If the brief itself contains a ticket-key pattern (`[A-Z]+-[0-9]+`, e.g. `TRIDENT-926`), use it.
2. Else, if running inside a git repo, use the current branch name (`git branch --show-current`), sanitized (replace `/` with `-`).
3. Else, fall back to `ADHOC-<date +%Y%m%dT%H%M%S>` (standalone Bash call for the timestamp).

There is no branch-match or diff-existence check in Direct mode — if there's genuinely nothing to review (e.g., the brief points at a diff range with zero changes), the reviewer subagent will discover that itself and should report it explicitly per Step 2's "if you find nothing to review, say so" instruction.

### Step 2: Run the Opus 4.8 reviewer agent

Dispatch a single independent code-review pass using the `Agent` tool with `model: "claude-opus-4-8"`. This is a fresh subagent with no memory of the implementation session — that independence is the whole point, since it reviews cold rather than rubber-stamping reasoning it already agrees with.

**Prompt template** — the `{REVIEW_BRIEF}` slot is filled from Step 1 (1A's standard PR-diff instruction, or 1B's caller-supplied freeform brief verbatim). Everything else is a fixed contract that applies regardless of mode:

```
{REVIEW_BRIEF}

You have Bash, Read, Grep, and Glob access — use them to locate and inspect whatever the
instruction above asks you to review (a diff between two refs, specific files, uncommitted
changes, an entire directory, etc.). Read surrounding context beyond the exact lines named —
do not rely on a diff hunk alone if you need more context to judge correctness. If the
instruction doesn't fully specify scope, use your judgment and state at the top of your
response what you interpreted the scope to be.

For each issue you find, report:
- File and line (file:line)
- One-line claim
- Severity: Critical | Important | Minor
- Category: bug | security | performance | style | design | other
- Evidence: concrete reasoning — a specific failure mode, exploit path, or scenario where this
  breaks. Not a vague "could be an issue."

If you find zero issues, or there is nothing in scope to review, say so explicitly — do not
invent findings just to have something to report.

Ignore: pre-existing issues outside what was asked, issues a linter/typechecker/CI would already
catch, and pedantic style nitpicks a senior engineer wouldn't flag in review — UNLESS the
instruction above explicitly asks you to focus on exactly that.
```

**Direct-mode extra note:** if the caller's brief names a specific repo/path that differs from the current working directory, tell the reviewer subagent explicitly which path to operate in (subagents inherit the current working directory by default, so don't assume it can infer a different repo from prose alone).

**Prerequisites:** none. No Codex CLI, no `~/.codex/config.toml`, no `jq`. This step runs entirely within Claude Code via the `Agent` tool.

**Reviewer model** is always `claude-opus-4-8` for this step — no detection logic needed. Record it in the report header (Step 5) and the user-facing summary (Step 6) as `**Reviewer model:** claude-opus-4-8 (independent subagent)`.

### Step 3: Parse the reviewer agent's findings

The agent returns a flat list of findings (or explicitly reports zero — treat that as "no findings" and skip directly to Step 6/8 with an empty report). For each finding, capture:
- **File and line**
- **Severity** (`Critical` | `Important` | `Minor`)
- **Category** (`bug` | `security` | `performance` | `style` | `design` | `other`)
- **Claim** (the one-line claim)
- **Evidence**

There is no `Source` or `Contested` concept here — a single independent agent produced these findings, not a two-AI debate. Step 4 below is where cross-checking against the actual codebase happens, and it now carries more weight than it did in the old two-AI flow since there's no second opinion to fall back on.

### Step 4: Research each finding against the codebase

For each finding from the reviewer agent:

1. Read the file referenced at the relevant lines
2. Understand the context — why the code is written this way
3. Check related files, patterns, and tests in the codebase
4. Apply the verdict mapping below to translate the reviewer's severity into this skill's determination

**Verdict mapping:**

| Reviewer severity | Determination | Default recommendation | Notes |
|--------------------|---------------|------------------------|-------|
| `Critical` | **Real issue** | **Fix** | High-confidence, high-impact claim. Verify against the codebase before accepting — this step is the only check now, so don't rubber-stamp it. |
| `Important` | **Real issue** | **Fix** | Medium-confidence claim. Assess size (S/M/L) and risk (S/M/L); recommend `Fix` unless your codebase research shows it would cause regressions. |
| `Minor` | **Not a real issue** | — | Style/convention-level observation. Informational only — surfaced in the report but doesn't block on it. |

After mapping, you may still **override** the determination if codebase research shows otherwise (e.g., a `Critical` claim on intentional code that an existing test already validates — downgrade to "Not a real issue" with a justification; or a `Minor` observation that's actually masking a real bug — upgrade to "Real issue"). Record the override reasoning in the report's per-finding analysis.

See [references/determination-criteria.md](references/determination-criteria.md) for size/risk heuristics.

### Step 5: Generate the report

Create a markdown file following the template in [references/report-template.md](references/report-template.md).

**File naming convention:**
```
{REPORT_LABEL}-CODEX-REVIEW-{ITERATION}.md
```

- Use `REPORT_LABEL` resolved in Step 1 — PR mode: the ticket number extracted from the PR title (e.g., `TRIDENT-822`), or `PR-{number}` if no ticket number was found. Direct mode: the ticket-key-in-brief / current-branch / `ADHOC-<timestamp>` fallback chain from 1B.
- Iteration starts at `1`. If `{REPORT_LABEL}-CODEX-REVIEW-1.md` exists in the save directory, use `2`, and so on
- **Save directly to** `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/` (create the directory with `mkdir -p` if it doesn't exist). This is durable storage that survives worktree cleanup and lives outside any project tree — no stash step is needed because the file is never written into the working tree in the first place.

### Step 6: Present results and offer fixes (Interactive mode)

After saving the report:

1. Display a header line: `**Reviewer model:** claude-opus-4-8 (independent subagent)` so the user knows which model produced the findings
2. Display a summary table (total findings, real issues, not real issues, fix vs leave-as-is)
3. If ANY real issues with recommendation "Fix" were found, ask the user:
   > "I found {N} fixable issues. Would you like me to fix any of them?"
4. List each fixable issue with its size/risk so the user can choose

### Step 7: Apply fixes (if requested)

When the user requests fixes:

1. Implement the selected fixes one at a time
2. After ALL fixes are applied, run the project's test suite and linter
3. If any tests or lint checks fail, determine if caused by the fix or pre-existing, and fix accordingly
4. Re-run tests and linter until all pass
5. Summarize what was fixed and confirm passing status

### Step 8: Confirm report saved

After fixes are applied (or if no fixes requested), the report is already saved durably at `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/{REPORT_LABEL}-CODEX-REVIEW-{ITERATION}.md` from Step 5 — there is nothing to stash because the file was never written inside the project tree. Print one line confirming the saved path. Do NOT run `git add`, `git stash`, or `git commit` against the report file.

## Autonomous Mode

When the caller triggers autonomous mode, run **Steps 1–5 first** (resolve mode + scope, dispatch the Opus 4.8 reviewer agent, parse findings, research, **generate and save the report directly to `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/`**). Then, instead of Steps 6–7, execute the following:

### Auto Step A: Fix all "Real issue / Fix" items

1. From the saved report, collect all findings with determination "Real issue" and recommendation "Fix"
2. If there are none, go to Auto Step C (print final summary) — do NOT skip the report
3. Implement each fix one at a time
4. After all fixes are applied, run tests and linter
5. If tests or linter fail, fix the failures and re-run until both pass cleanly

### Auto Step B: Commit and push

1. Stage only the files changed by the fixes (not the report file)
2. Commit with message:
   ```
   fix: address code review findings ({REPORT_LABEL})

   - {one-line summary of each fix}

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   ```
3. Push to a remote branch:
   - **PR mode:** push to the PR's head branch — `git push origin {headRefName}`.
   - **Direct mode:** resolve the current branch first (`CURRENT_BRANCH=$(git branch --show-current)`), then `git push origin $CURRENT_BRANCH`. If the caller's brief made clear there's no intent to push (e.g., a read-only review of files in an unrelated repo, or an explicit "just review, don't push" instruction), skip the push and note in the summary that fixes were committed locally only.

### Auto Step C: Print final summary

The report is already saved durably at `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/{REPORT_LABEL}-CODEX-REVIEW-{ITERATION}.md` — no stash step is needed.

1. Print the saved report path on its own line.
2. Print a summary of all findings and fixes applied.
3. Do NOT run `git add`, `git stash`, or `git commit` against the report file.

## Auto Mode Safeguards

- If a fix attempt fails tests/linter **3 times**, skip that fix, note it in the report, and continue with the remaining fixes
- Do NOT re-run the reviewer agent in a poll loop (unlike PR review comments, these findings don't change after fixing) — unless a caller like `ticket-driver` explicitly invokes this skill a second time as a separate "final pass" on a later diff, which is a distinct, intentional invocation, not a poll

## References

- **Report template** — [references/report-template.md](references/report-template.md)
- **Determination criteria** — [references/determination-criteria.md](references/determination-criteria.md)
