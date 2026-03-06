---
name: review-pr-comments
description: Reviews GitHub PR comments and review threads, identifying resolved and unresolved feedback. Fetches PR review threads via GitHub GraphQL API, researches the codebase to assess each unresolved comment, and generates a markdown review report. Supports an autonomous mode that auto-fixes real issues, commits, pushes, and polls for new comments in a loop. Use when the user asks to review PR comments, check PR feedback, address PR review comments, triage PR threads, analyze review feedback, or autonomously fix PR comments on a pull request. Does NOT create new reviews or submit approvals — only reads, analyzes, and optionally fixes.
---

# Review PR Comments

Analyze all review comments on a GitHub PR, research unresolved issues against the codebase, and produce a structured markdown report with actionable determinations.

## Modes

This skill operates in two modes:

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Interactive** (default) | User provides a PR URL without saying "autonomous" | Generates report, asks before fixing |
| **Autonomous** | User says "autonomous", "auto-fix", or "auto mode" | Fixes all "Real issue / Fix" items, commits, pushes, then polls for new comments |

**WAIT argument (Autonomous mode only):** If the user includes `WAIT` in their message (e.g., "autonomous WAIT", "auto-fix WAIT"), sleep 20 minutes before starting to give review bots (e.g., Cursor bot) time to post their comments. See **Auto Step 0** below.

Determine the mode from the user's message. If unclear, default to **Interactive**.

## Critical Rules

- In **Interactive** mode: NEVER make changes without explicit user approval
- In **Autonomous** mode: Only auto-fix issues determined as "Real issue" with recommendation "Fix" — still skip "Leave as is" items
- ALWAYS use the GraphQL API to fetch review threads (REST API lacks resolved status)
- ALWAYS research the actual codebase before making a determination on unresolved comments
- Save the report before applying any fixes
- **NEVER use GitHub emoji shortcodes** like `:white_check_mark:` — they only render on GitHub. Always use the actual Unicode emoji character `✅` directly in the markdown
- **NEVER use `$(...)` or `${...}` command substitution in Bash commands** — these trigger security permission prompts that block autonomous execution. Instead, inline all values directly into the command. Specifically:
  - Do NOT write queries to temp files and use `$(cat /tmp/...)` — inline the GraphQL query directly in the `gh api graphql -f query='...'` command as shown in [references/graphql-queries.md](references/graphql-queries.md)
  - Do NOT use `$(git branch --show-current)` — run the command separately, read the output, then use the value directly in subsequent commands
- **NEVER use `cd ... &&` or `cd ... ;` compound commands** — these trigger security permission prompts ("bare repository attacks") that BLOCK autonomous execution. This is a hard constraint, not a suggestion. Instead:
  - For git commands: use `git -C <path>` (e.g., `git -C /path/to/repo add file.txt`) OR run `git add <relative-path>` directly (git resolves paths from the repo root)
  - For non-git commands: run each command as a separate Bash call with absolute paths
  - **NEVER write:** `cd /some/path && git add file.txt` — this WILL trigger a permission prompt and halt autonomous mode
- **NEVER use pipes (`|`) or output redirection (`>`, `>>`) in Bash commands** — these create compound commands that trigger permission prompts. Run commands standalone and let Claude Code capture the full output. Specifically:
  - Do NOT write: `CI=true npx react-scripts test ... | tail -30` — run the test command by itself
  - Do NOT write: `command > file.txt` or `command 2>&1 | grep ...` — run the command standalone

## Workflow

### Step 1: Parse the PR URL

Extract `owner`, `repo`, and `pr_number` from the input URL.

**Supported formats:**
- `https://github.com/{owner}/{repo}/pull/{number}`
- `{owner}/{repo}#{number}`

### Step 2: Fetch PR metadata

```bash
gh pr view {number} --repo {owner}/{repo} --json title,number,url,headRefName,baseRefName,author
```

Extract the **ticket number** from the PR title. Convention: the title starts with `TICKET-123:` or `[TICKET-123]`. Use this to name the output file.

### Step 3: Fetch review threads (two-phase GraphQL)

Use the **two-phase query strategy** from [references/graphql-queries.md](references/graphql-queries.md) to minimize context usage:

**Phase 1 — Metadata only (no comment bodies):**
- Fetch all threads with: `id`, `isResolved`, `isOutdated`, `path`, `line`, `resolvedBy`, first comment author
- This is a lightweight query (~5KB vs ~67KB for full bodies)
- Paginate if `hasNextPage` is true

**Phase 2 — Full bodies for unresolved threads only:**
- Collect `id` values of all unresolved threads from Phase 1
- Use the batched `node` query to fetch full comment bodies ONLY for those threads
- Skip Phase 2 entirely if all threads are resolved

**CRITICAL:** Do NOT fetch comment bodies for resolved threads. Resolved threads only need `path`, `line`, and `resolvedBy` for the report summary line. Bot review comments are often 3–4KB each and will rapidly fill context if fetched unnecessarily.

### Step 4: Categorize threads

Sort all threads from Phase 1 into two groups:

1. **Resolved threads** — `isResolved: true` (summarize from metadata only — path, line, resolvedBy)
2. **Unresolved threads** — `isResolved: false` (full comment bodies available from Phase 2)

### Step 5: Research unresolved comments

For each unresolved thread:

1. Read the file referenced in the comment (`path` field) at the relevant lines
2. Understand the reviewer's concern by analyzing the comment body and diff context
3. Research the broader codebase if needed (e.g., check related files, patterns, tests)
4. Make a determination — see [references/determination-criteria.md](references/determination-criteria.md)

**Determination must be one of:**

| Determination | Meaning |
|---------------|---------|
| **Not a real issue** | The reviewer's concern is unfounded or already handled. Provide a response comment to paste in the PR. |
| **Real issue** | The concern is valid. Assess size (S/M/L), risk (S/M/L), and recommend fix or leave-as-is. If leaving as is, provide a response comment to paste. |

### Step 6: Generate the report

Create a markdown file following the template in [references/report-template.md](references/report-template.md).

**File naming convention:**
```
{TICKET-NUMBER}-PR-REVIEW-{ITERATION}.md
```

- Extract the ticket number from the PR title (e.g., `TRIDENT-825`)
- Iteration starts at `1`. If `{TICKET}-PR-REVIEW-1.md` exists, use `2`, and so on
- If no ticket number is found, use the PR number: `PR-{number}-REVIEW-{ITERATION}.md`
- Save in `dynamic-app/pr-reviews/` (create the directory if it doesn't exist)

### Step 7: Present results and offer fixes

After saving the report:

1. Display a summary table of all threads (resolved count, unresolved count, determinations)
2. If ANY real issues were found (even if recommending leave-as-is), ask the user:
   > "I found {N} real issues. Would you like me to fix any of them?"
3. List each real issue with its size/risk so the user can choose which to fix

### Step 8: Apply fixes (if requested)

When the user requests fixes:

1. Implement the selected fixes one at a time
2. After ALL fixes are applied, run the project's test suite and linter:
   - Run tests (e.g., `npm test`, `yarn test`, or the project's test command)
   - Run linter (e.g., `npm run lint`, `yarn lint`, or the project's lint command)
3. If any tests or lint checks fail:
   - Determine if the failure is caused by the fix or was pre-existing
   - Fix any failures introduced by the changes
   - Re-run tests and linter until all pass
4. Do NOT consider fixes complete until both tests and linter pass cleanly
5. Summarize what was fixed and confirm the passing status of tests and linter

## Autonomous Mode

### Auto Step 0: Initial wait (only if WAIT argument is present)

If the user included `WAIT` in their message, sleep 20 minutes before doing anything else — this gives review bots time to post their comments on the PR.

1. Output as plain text (NOT via Bash `echo`): "WAIT requested. Sleeping 20 minutes to allow review bots to post comments..."
2. Sleep using the Bash tool with ONLY `sleep 1200` as the command — no `echo`, no `&&`, no `$(...)`:
   ```
   Bash(command="sleep 1200", timeout=1500000)
   ```
3. After the sleep completes, proceed to Steps 1–6 below.

If `WAIT` is NOT present, skip this step entirely.

### Steps 1–6: Fetch, categorize, research, report

Run **Steps 1–6** (parse URL, fetch metadata, fetch threads, categorize, research, **generate and save the report to `dynamic-app/pr-reviews/`**). Then, instead of Steps 7–8, execute the following loop:

### Auto Step A: Fix all "Real issue / Fix" items

1. From the saved report, collect all unresolved threads with determination "Real issue" and recommendation "Fix"
2. If there are none, go to Auto Step D (stash reports and print final summary) — do NOT skip the report
3. Implement each fix one at a time
4. After all fixes are applied, run tests and linter (same as Step 8)
5. If tests or linter fail, fix the failures and re-run until both pass cleanly

### Auto Step B: Commit and push

1. Stage only the files changed by the fixes (not the report file). **Stage each file as a separate Bash call using `git add <file>` — NEVER use `cd <path> && git add`:**
   ```bash
   git add path/to/file1.tsx
   git add path/to/file2.ts
   ```
2. Commit with message:
   ```
   fix: address PR review comments ({TICKET-NUMBER})

   - {one-line summary of each fix}

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   ```
3. Push to the PR's head branch:
   ```bash
   git push origin {headRefName}
   ```

### Auto Step C: Poll loop

1. Output the status line as plain text (NOT via Bash `echo`): "Fixes pushed. Sleeping 20 minutes before checking for new comments..."
2. Sleep for 20 minutes using the Bash tool with ONLY `sleep 1200` as the command — no `echo`, no `&&`, no `$(...)`:
   ```
   Bash(command="sleep 1200", timeout=1500000)
   ```
3. Re-run Steps 3–6 (fetch threads, categorize, research, generate a new report with incremented iteration number)
4. Check: are there any NEW unresolved threads with determination "Real issue" and recommendation "Fix"?
   - **Yes** → Go to Auto Step A (fix, test, commit, push, poll again)
   - **No** → Go to Auto Step D (git stash reports and print final summary)

### Auto Mode Safeguards

- Maximum **5 iterations** of the poll loop to prevent infinite runs. After 5 iterations, go to Auto Step D (git stash reports), then notify the user.
- If a fix attempt fails tests/linter **3 times**, skip that fix, note it in the report, and continue with the remaining fixes.
- On each iteration, only process threads that were NOT present in the previous iteration's report (avoid re-fixing already-addressed threads).
- Print a status line before each sleep using plain text output (NOT a Bash command): `[Iteration {N}/5] Waiting 20 minutes...` — do NOT use `$(date ...)` or any shell substitution to compute the time

### Auto Step D: Git stash reports on completion

When the autonomous loop ends (no more fixable issues or max iterations reached), **git stash** all report files so they don't pollute the working tree or get accidentally committed:

1. Stage only the report files:
   ```bash
   git add dynamic-app/pr-reviews/{TICKET-NUMBER}-PR-REVIEW-*.md
   ```
2. Git stash them with a descriptive message:
   ```bash
   git stash push -m "PR review reports: {TICKET-NUMBER}" -- dynamic-app/pr-reviews/
   ```
3. Print a summary: `"Git stashed {N} report(s). Retrieve with: git stash pop"`
4. Do NOT commit the report files — they are for local reference only. The git stash preserves them without cluttering the branch.

## Output Format Summary

```
## Resolved Comments (N)
- ✅ Brief summary of each resolved thread

## Unresolved Comments (N)

### [Thread title / file:line]
- **Determination:** Not a real issue | Real issue
- **Reviewer:** @username
- **File:** path/to/file.ts:42
- **Comment:** [reviewer's comment]
- **Analysis:** [your research findings]
- **Size/Risk:** S/M/L (real issues only)
- **Recommendation:** Fix | Leave as is
- **Suggested response:** [comment to paste in PR]
```

## References

- **GraphQL queries** — [references/graphql-queries.md](references/graphql-queries.md)
- **Determination criteria** — [references/determination-criteria.md](references/determination-criteria.md)
- **Report template** — [references/report-template.md](references/report-template.md)
