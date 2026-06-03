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

As of `codex-peer-review` plugin v2.0.0 the default mode is **blind-debate** (symmetric two-AI review with per-issue debate). The verdict comes back as a structured markdown block with sections `### Critical`, `### Important`, `### Contested`, `### Dismissed`, and `### Style notes` — not as free-form findings. Steps 3 and 4 of this skill consume that structure directly.

**Prerequisites (fail fast if missing):**

1. `~/.codex/config.toml` must contain `[profiles.peer-review]`. If absent, surface this to the user and stop: `Run /codex-peer-review init before requesting a codex review.`
2. `jq` must be on `$PATH`. If absent: `Install jq before requesting a codex review (brew install jq).`

**Capture the Codex model used.** As of plugin v2.0.0 the review model is selected by the Codex profile, NOT by the user's global `model = "..."` line in `~/.codex/config.toml`. Determine `CODEX_MODEL` in this priority order:

1. **Profile model (preferred).** Read `~/.codex/config.toml` and extract the `model` value from the `[profiles.peer-review]` block. This is the authoritative source — it's the model the peer review actually used.
2. **Stdout header fallback.** If the profile lookup fails, parse a `model: <name>` line from any captured Codex stdout (older invocation patterns include it).
3. **Last resort.** If both fail, record `CODEX_MODEL` as `unknown (CLI default)`.

Save the resolved value for inclusion in the report header (Step 5) and the user-facing summary (Step 6).

### Step 3: Parse Codex findings

The plugin returns a structured verdict. Extract each finding under each section header. For each finding, capture:
- **File and line** (from the `` `file:line` `` prefix in the bullet)
- **Section** (`Critical` | `Important` | `Contested` | `Dismissed` | `Style notes`)
- **Claim** (the short sentence after the dash)
- **Evidence** (the `Evidence:` sub-bullet)
- **Source** (the `Source:` sub-bullet — `both`, `claude`, or `codex`)
- For `Contested` entries also capture `Claude's view`, `Codex's view`, and `Recommendation`

### Step 4: Research each finding against the codebase

For each Codex finding:

1. Read the file referenced at the relevant lines
2. Understand the context — why the code is written this way
3. Check related files, patterns, and tests in the codebase
4. Apply the verdict mapping below to translate the plugin's section into this skill's determination

**Verdict mapping (plugin v2.0.0 → this skill's determination):**

| Plugin section | Determination | Default recommendation | Notes |
|----------------|---------------|------------------------|-------|
| `### Critical` | **Real issue** | **Fix** | Severity high/critical, both AIs (or one with strong evidence) accepted during debate. Size/risk usually M–L. |
| `### Important` | **Real issue** | **Fix** | Severity medium, accepted. Assess size (S/M/L) and risk (S/M/L); recommend `Fix` unless your codebase research shows it would cause regressions. |
| `### Contested` | **Real issue** | **Leave as is** | Both AIs held position after the debate cap. Surface both views to the user; do not auto-fix in autonomous mode. |
| `### Dismissed` | **Not a real issue** | — | Raised but withdrawn during debate. Informational only. |
| `### Style notes` | **Not a real issue** | — | Bypassed debate entirely (style severity never converges through debate). Informational only. |

After mapping, you may still **override** the recommendation if codebase research shows otherwise (e.g., a `Critical` flagged on intentional code that an existing test already validates — downgrade to "Leave as is" with a justification). Record the override reasoning in the report's per-finding analysis.

See [references/determination-criteria.md](references/determination-criteria.md) for size/risk heuristics.

### Step 5: Generate the report

Create a markdown file following the template in [references/report-template.md](references/report-template.md).

**File naming convention:**
```
{TICKET-NUMBER}-CODEX-REVIEW-{ITERATION}.md
```

- Use the ticket number extracted from the PR title in Step 1 (e.g., `TRIDENT-822`)
- Iteration starts at `1`. If `{TICKET}-CODEX-REVIEW-1.md` exists in the save directory, use `2`, and so on
- If no ticket number is found, use the PR number: `PR-{number}-CODEX-REVIEW-{ITERATION}.md`
- **Save directly to** `~/.claude/memory/ticket-reports/{TICKET-NUMBER}/codex-review/` (create the directory with `mkdir -p` if it doesn't exist). This is durable storage that survives worktree cleanup and lives outside any project tree — no stash step is needed because the file is never written into the working tree in the first place.

### Step 6: Present results and offer fixes (Interactive mode)

After saving the report:

1. Display a header line: `**Codex model:** {CODEX_MODEL}` so the user knows which OpenAI model produced the findings
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

After fixes are applied (or if no fixes requested), the report is already saved durably at `~/.claude/memory/ticket-reports/{TICKET-NUMBER}/codex-review/{TICKET-NUMBER}-CODEX-REVIEW-{ITERATION}.md` from Step 5 — there is nothing to stash because the file was never written inside the project tree. Print one line confirming the saved path. Do NOT run `git add`, `git stash`, or `git commit` against the report file.

## Autonomous Mode

When the user triggers autonomous mode, run **Steps 1–5 first** (parse PR URL, run Codex via `/codex-peer-review --base {baseRefName}`, parse findings, research, **generate and save the report directly to `~/.claude/memory/ticket-reports/{TICKET-NUMBER}/codex-review/`**). Then, instead of Steps 6–7, execute the following:

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
   fix: address Codex review findings ({TICKET-NUMBER})

   - {one-line summary of each fix}

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   ```
3. Push to the PR's head branch:
   ```bash
   git push origin {headRefName}
   ```

### Auto Step C: Print final summary

The report is already saved durably at `~/.claude/memory/ticket-reports/{TICKET-NUMBER}/codex-review/{TICKET-NUMBER}-CODEX-REVIEW-{ITERATION}.md` — no stash step is needed.

1. Print the saved report path on its own line.
2. Print a summary of all findings and fixes applied.
3. Do NOT run `git add`, `git stash`, or `git commit` against the report file.

## Auto Mode Safeguards

- If a fix attempt fails tests/linter **3 times**, skip that fix, note it in the report, and continue with the remaining fixes
- Do NOT re-run Codex in a poll loop (unlike PR review comments, Codex findings don't change after fixing)

## References

- **Report template** — [references/report-template.md](references/report-template.md)
- **Determination criteria** — [references/determination-criteria.md](references/determination-criteria.md)
