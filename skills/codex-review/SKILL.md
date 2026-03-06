---
name: codex-review
description: Runs Codex CLI peer review against the current branch via a PR URL, generates a structured markdown report classifying each finding as "Real issue (fix)" or "Not a real issue", and offers to apply fixes. Supports autonomous mode for auto-fixing. Use when the user asks for a codex review, codex code review, AI peer review of their branch, or wants a second opinion from Codex on their changes. Takes a GitHub PR URL as input.
---

# Codex Review

Run OpenAI Codex CLI peer review against the current branch using a GitHub PR URL to derive the target branch and ticket name. Produce a structured markdown report with actionable determinations. Optionally fix issues and git stash the report.

## Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Interactive** (default) | User provides a PR URL without saying "autonomous" | Generates report, asks before fixing |
| **Autonomous** | User says "autonomous", "auto-fix", or "auto mode" | Fixes all "Real issue / Fix" items, commits, pushes, git stashes report |

Determine the mode from the user's message. If unclear, default to **Interactive**.

## Critical Rules

- In **Interactive** mode: NEVER make changes without explicit user approval
- In **Autonomous** mode: Only auto-fix issues determined as "Real issue" with recommendation "Fix" — skip "Leave as is" items
- ALWAYS research the actual codebase before making a determination on each Codex finding
- Save the report to `dynamic-app/pr-reviews/` before applying any fixes
- ALWAYS dispatch Codex via the `/codex-peer-review` command — do NOT call `codex` CLI directly

## Workflow

### Step 1: Parse PR URL and extract metadata

Extract `owner`, `repo`, and `pr_number` from the input URL.

**Supported formats:**
- `https://github.com/{owner}/{repo}/pull/{number}`
- `{owner}/{repo}#{number}`

Fetch PR metadata:
```bash
gh pr view {number} --repo {owner}/{repo} --json title,number,url,headRefName,baseRefName,author
```

From the response, extract:
- **`baseRefName`** — the PR's target branch (e.g., `main`). This is the base for the Codex review.
- **`headRefName`** — the PR's source branch (e.g., `TRIDENT-822`). This is the current branch.
- **Ticket number** — extract from the PR title (convention: title starts with `TICKET-123:` or `[TICKET-123]`). Use this for naming the report file.

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

### Step 2: Run Codex peer review

Dispatch to the `/codex-peer-review` command with the target branch:

```
/codex-peer-review --base {baseRefName}
```

This runs the full Codex peer review workflow (via the `codex-peer-reviewer` subagent) against the PR's target branch and returns synthesized findings.

Capture the full Codex output for analysis.

### Step 3: Parse Codex findings

Extract each distinct finding from the Codex output. For each finding, identify:
- **File and line** referenced
- **Category** (bug, security, performance, style, design, etc.)
- **Codex's concern** (what it flagged)
- **Codex's suggestion** (what it recommends)

### Step 4: Research each finding against the codebase

For each Codex finding:

1. Read the file referenced at the relevant lines
2. Understand the context — why the code is written this way
3. Check related files, patterns, and tests in the codebase
4. Make a determination — see [references/determination-criteria.md](references/determination-criteria.md)

**Determination must be one of:**

| Determination | Meaning |
|---------------|---------|
| **Not a real issue** | Codex's concern is unfounded, already handled, or a style preference that doesn't match this project's conventions. |
| **Real issue** | The concern is valid. Assess size (S/M/L), risk (S/M/L), and recommend "Fix" or "Leave as is". |

### Step 5: Generate the report

Create a markdown file following the template in [references/report-template.md](references/report-template.md).

**File naming convention:**
```
{TICKET-NUMBER}-CODEX-REVIEW-{ITERATION}.md
```

- Use the ticket number extracted from the PR title in Step 1 (e.g., `TRIDENT-822`)
- Iteration starts at `1`. If `{TICKET}-CODEX-REVIEW-1.md` exists in `dynamic-app/pr-reviews/`, use `2`, and so on
- If no ticket number is found, use the PR number: `PR-{number}-CODEX-REVIEW-{ITERATION}.md`
- **Save location:** `dynamic-app/pr-reviews/` (create the directory if it doesn't exist)

### Step 6: Present results and offer fixes (Interactive mode)

After saving the report:

1. Display a summary table (total findings, real issues, not real issues, fix vs leave-as-is)
2. If ANY real issues with recommendation "Fix" were found, ask the user:
   > "I found {N} fixable issues. Would you like me to fix any of them?"
3. List each fixable issue with its size/risk so the user can choose

### Step 7: Apply fixes (if requested)

When the user requests fixes:

1. Implement the selected fixes one at a time
2. After ALL fixes are applied, run the project's test suite and linter
3. If any tests or lint checks fail, determine if caused by the fix or pre-existing, and fix accordingly
4. Re-run tests and linter until all pass
5. Summarize what was fixed and confirm passing status

### Step 8: Git stash the report

After fixes are applied (or if no fixes requested), git stash the report file:

1. Stage the report file:
   ```bash
   git add dynamic-app/pr-reviews/{TICKET-NUMBER}-CODEX-REVIEW-*.md
   ```
2. Git stash with a descriptive message:
   ```bash
   git stash push -m "Codex review report: {TICKET-NUMBER}" -- dynamic-app/pr-reviews/
   ```
3. Print: `"Git stashed report. Retrieve with: git stash pop"`

## Autonomous Mode

When the user triggers autonomous mode, run **Steps 1–5 first** (parse PR URL, run Codex via `/codex-peer-review --base {baseRefName}`, parse findings, research, **generate and save the report to `dynamic-app/pr-reviews/`**). Then, instead of Steps 6–7, execute the following:

### Auto Step A: Fix all "Real issue / Fix" items

1. From the saved report, collect all findings with determination "Real issue" and recommendation "Fix"
2. If there are none, go to Auto Step C (git stash report and print final summary) — do NOT skip the report
3. Implement each fix one at a time
4. After all fixes are applied, run tests and linter
5. If tests or linter fail, fix the failures and re-run until both pass cleanly

### Auto Step B: Commit and push

1. Stage only the files changed by the fixes (not the report file)
2. Commit with message:
   ```
   fix: address Codex review findings ({TICKET-NUMBER})

   - {one-line summary of each fix}

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   ```
3. Push to the PR's head branch:
   ```bash
   git push origin {headRefName}
   ```

### Auto Step C: Git stash report

1. Stage the report file:
   ```bash
   git add dynamic-app/pr-reviews/{TICKET-NUMBER}-CODEX-REVIEW-*.md
   ```
2. Git stash with a descriptive message:
   ```bash
   git stash push -m "Codex review report: {TICKET-NUMBER}" -- dynamic-app/pr-reviews/
   ```
3. Print summary: `"Git stashed report. Retrieve with: git stash pop"`
4. Print final summary of all findings and fixes applied

## Auto Mode Safeguards

- If a fix attempt fails tests/linter **3 times**, skip that fix, note it in the report, and continue with the remaining fixes
- Do NOT re-run Codex in a poll loop (unlike PR review comments, Codex findings don't change after fixing)

## References

- **Report template** — [references/report-template.md](references/report-template.md)
- **Determination criteria** — [references/determination-criteria.md](references/determination-criteria.md)
