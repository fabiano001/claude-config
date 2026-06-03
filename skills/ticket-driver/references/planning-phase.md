# Planning phase (standard mode) — intake, git, what to ask, planning blueprint

Load this for standard-mode steps 2–6 (after run bookkeeping). It covers: Jira/manual intake + key resolution + merging, git branch handling, what to ask the operator (hours-to-log + E2E Test Plan), the planning blueprint, and the planning-phase output format.

PLAN-MODE reuses the **Planning blueprint** and **Output format** sections here, but follows its own workflow in [plan-mode.md](plan-mode.md) for everything else (no git, no execution).

---

## Workspace assumptions

- **Project root = the current IDE workspace** (Cursor / VS Code). All paths and commands are relative to this workspace.
- If a monorepo is detected (e.g., `package.json` workspaces, `turbo.json`, `nx.json`, `lerna.json`), infer the **most likely package** based on touched/created files and script availability. **Do not ask for a repo/path.** If disambiguation is absolutely required, present a best-guess and proceed.

---

## Jira integration

- If a **Jira ticket number** is provided (e.g., TRIDENT-655 or TRIDENT-655-TEST-2), fetch ticket data using the MCP Atlassian tools.
- **First, resolve the Jira key** by stripping any `-TEST` or `-TEST-<N>` suffix from the ticket name. Use the resolved key for ALL Jira API calls. The original ticket name (with suffix) is still used for everything else (branch, save directory, PR title, etc.).
  - `TRIDENT-802` → Jira lookup: `TRIDENT-802`
  - `TRIDENT-802-TEST` → `TRIDENT-802`
  - `TRIDENT-802-TEST-2` → `TRIDENT-802`
  - `TRIDENT-802-TEST-15` → `TRIDENT-802`

### Step 1: Fetch ticket details

Use `mcp__atlassian__getJiraIssue` with:
- `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
- `issueIdOrKey`: the **resolved Jira key** (e.g., if ticket name is `TRIDENT-655-TEST-2`, use `TRIDENT-655`)

This returns the title, description body, status, and other standard fields.

### Step 2: Fetch Acceptance Criteria

Run `/fetch-jira-acceptance-criteria` with the **resolved Jira key** (e.g., `TRIDENT-655`). This skill handles the custom field lookup, ADF parsing, and fallback logic. If the custom field is empty, fall back to parsing the description body for an "Acceptance Criteria" section.

### Step 3: Extract all inputs

- **Ticket name** from the original ticket name argument (with any -TEST suffix — NOT the resolved Jira key)
- **Description** from the title/summary
- **Acceptance criteria** from Step 2
- **User Story** from the description body (look for "User Story" section)
- **Documentation** from the description body (look for "Documentation" section)
- **Constraints** from any constraints mentioned in the description

- If **manual inputs are also provided**, augment the Jira ticket data with manual inputs (use both sources):
  - Start with Jira ticket data as the base
  - Add any additional fields from manual inputs that are not in the Jira data
  - **In case of any discrepancy or conflict**, manual inputs always take precedence and override the Jira data

---

## What to ask the operator

**First, ask if the user wants to provide a Jira ticket number OR manual inputs:**

**Option 1: Jira ticket number**
- If provided, fetch the ticket details from Jira and populate all inputs automatically.
- User can still provide manual inputs to override or augment the Jira data.

**Option 2: Manual inputs** (if no Jira ticket or Jira fetch fails)
- **Ticket name** (Required) — e.g., TRIDENT-655; used as the branch name (unless USE-CURRENT-BRANCH is specified).
- **Description** (Required) — Short description of the change.
- **Acceptance criteria** (Required) — Explicit bullets.
- **User Story** (Optional) — High-level user story if provided.
- **Documentation** (Optional) — Any technical details that shed light into what the ticket implementation will entail.
- **Constraints** (Optional) — Performance, security, feature flags, rollout windows, etc.

**Branch mode (do NOT ask — detect from arguments):**
- **Default is standard mode** — use the ticket name as the branch name. Do NOT ask the user which mode they want.
- Only use **USE-CURRENT-BRANCH** mode if the user explicitly passes `USE-CURRENT-BRANCH` as an argument.
- If USE-CURRENT-BRANCH is specified, stay on the current branch. Commits, pushes, and PRs will use the current branch name.

**Jira finalization on success (ALWAYS ask during the planning phase, before the plan review loop):**
- Ask the user: **"How many hours should I log to the Jira ticket on successful completion? (e.g., 2.5)"**
- Capture the value verbatim (accept decimals; default unit is hours).
- This value is used after the E2E test passes (or after the rest of the flow completes when E2E is skipped) to: (a) transition the ticket to **"Ready for QA"**, (b) assign the ticket to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`), (c) log the hours as a worklog entry via `mcp__atlassian__addWorklogToJiraIssue`.

### E2E Test Plan (ALWAYS draft + confirm during the planning phase, before the plan review loop)

- First, ask: **"Do you want to include an E2E test (Playwright CLI) as the final step? (yes/no — default: yes)"**
- **If the user says no / skip / no E2E:** do NOT continue with the proposal. Omit the E2E Test Plan section from the plan output, omit the E2E task from the HIGH LEVEL PLAN and Task Breakdown, and omit the E2E checklist item from the PLAN-MODE plan.md. Note in the plan output: "E2E test: skipped by operator."
- **If the user says yes (or default):** **draft a 3-item proposal first**, using your understanding of the ticket's changes (which funnel/flow they touch, which events/UI they affect) plus any relevant entry from `~/.claude/memory/E2E/<projectDir>/learnings.md` (already read in step 4 of the workflow). Present all 3 items together as a single proposal and ask the user to **confirm or update each one**. Format the proposal exactly like this:

  ```
  ### Proposed E2E Test Plan — please confirm or update each item

  1. **URL to use:** <proposed URL>
     (e.g., for the Combined funnel: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true)

  2. **How to deploy** (**stage-trident only — production deployment is FORBIDDEN**): <proposed command>
     (e.g., to deploy hosting + the modified functions:
     `firebase --project stage-trident deploy --only hosting:dynamic-app,functions:lendAPIWebhook,functions:getLendAPIApprovalData`)

  3. **How to verify passing:** <proposed verification approach with concrete pass/fail rule + evidence>
     (e.g., "After completing the funnel through the Submitted tab, run `playwright-cli eval \"() => JSON.stringify(window.dataLayer || [])\"` and confirm the `lead_submitted` and `application_submitted` entries each contain `approval_odds: <number>` and `approval_outcome: <string>`. Capture full dataLayer JSON + final-page screenshot.")
  ```

- **Drafting heuristics — use ticket understanding to populate each item:**
  - **URL** — derive from the ticket's funnel scope (Combined, FullApp, Prequal, Internal). Default to the QA stage URL with `prodTesting=true` when the ticket affects a LendAPI funnel. Check `~/.claude/memory/E2E/<projectDir>/learnings.md` for known-good URLs and known-blocked domains.
  - **Deploy command** — propose the minimum stage-only command that covers the modified surface: hosting if `dynamic-app/` changed, function names from `functions/src/index.ts` if backend changed, both if both. **Always prefix with `--project stage-trident`** to make the safety guarantee explicit. **Never propose a command that targets `trident-funding` or omits `--project`.**
  - **How to verify passing** — must combine a **pass/fail rule** (specific DOM text, specific GA event payload, specific final URL, absence of specific console errors) with the **evidence to capture** (dataLayer JSON dump, screenshot, console log, network request). Tailor to what the ticket changed: GA-event tickets capture `window.dataLayer`; UI tickets capture screenshots; backend tickets capture network responses or function-output console logs.

- **Capture the confirmed/updated answers verbatim** and store them as the **E2E Test Plan** section in the plan output. The execution phase uses these for the snapshot-then-act loop.

- **Mid-execution updates to "How to verify passing" are allowed but must be documented:** During execution, the executor may discover that the agreed verification approach doesn't work as expected (e.g., the dataLayer is on a child iframe instead of the parent, the expected console log is gated behind a feature flag, the screenshot target re-renders mid-capture). The executor MAY switch to a different verification approach IF AND ONLY IF:
  1. It first attempted the agreed approach and observed a concrete failure (not a guess that something else would be easier).
  2. The new approach successfully validated the same pass/fail intent (i.e., still proved the AC is met).
  3. The post-test report (whether success report or `E2ETEST-Report.md`) documents BOTH the originally-agreed verification approach AND the alternate that was used, with a one-line "why the original didn't work."

  Mid-execution updates to **URL** or **Deploy command** are NOT allowed without operator approval — those are safety-critical (wrong URL = invalid test, wrong deploy command = potential production touch). Stop and ask if either needs to change.

### Input merging rules

- If both Jira ticket AND manual inputs are provided, **use both sources** to augment the ticket information.
- Start with Jira ticket data as the base.
- Add any additional fields from manual inputs that are not in the Jira data.
- **In case of any discrepancy or conflict**, manual inputs always take precedence and override the Jira data.
- Example: If Jira has acceptance criteria but manual inputs provide different acceptance criteria, use the manual inputs' version.

If base branch is needed and not specified, suggest **main** by default.

---

## Git branch handling (shell per tool permissions)

Propose the following commands (adapt to workspace). **Execute them in accordance with tool permissions configured in Claude Code settings** (user `~/.claude/settings.json` and/or project `.claude/settings.json`). Always print the command you're about to run and summarize its result.

**IMPORTANT:** Run each git command as a **separate Bash call**. Do NOT combine commands with `&&` or `;`. **NEVER use `cd`** — use `git -C <absolute-path>` instead. **NEVER use pipes, output redirection, or command substitution.** (See the Bash safety rules in SKILL.md.)

- Ensure a clean working tree and up-to-date remotes (warn if dirty). Use `git -C <absolute-path>` if the workspace is not the current directory:
  - `git status -s`
  - `git remote -v`
  - `git fetch --all --prune`

### If USE-CURRENT-BRANCH mode:
- **Stay on the current branch** — do not create or checkout any branch.
- Show current branch: `git branch --show-current`
- Verify working tree status: `git status -s`
- Commits, pushes, and PRs still happen on the current branch (same as standard mode, just without branch creation/checkout).
- Skip all branch creation/checkout steps below.

### Otherwise (standard branch mode):

- **Detect existing ticket branch** (exact match):
  - Local exists? `git rev-parse --verify --quiet refs/heads/$TICKET`
  - Remote exists? `git ls-remote --exit-code --heads origin $TICKET`

- **If branch exists**:
  - If not on it: `git checkout $TICKET`
  - Update it:
    - `git pull --ff-only` (if tracking remote)
    - If behind the chosen base branch and we want to refresh, ask whether to **rebase** (`git rebase origin/$BASE`) or **merge** (`git merge origin/$BASE`). Default to **rebase** unless instructed otherwise.

- **If branch does NOT exist**:
  - Ask for **BASE** (default `main`).
  - Update base:
    - `git checkout $BASE`
    - `git pull --ff-only`
  - Create and switch:
    - `git checkout -b $TICKET`
    - Optionally set upstream: `git push -u origin $TICKET`

---

## Planning blueprint (output before coding)

**Produce this plan first**, then enter the **Plan review loop**:

### 1) HIGH LEVEL PLAN
- A concise, executive summary of the implementation tasks only.
- Skip ticket details — jump straight into the task list.
- Use shortened, succinct task descriptions for quick review.
- Format as a numbered list with 1-2 line descriptions per task.
- **ALWAYS include these final steps:**
  1. Run code-review-specialist subagent and fix any issues found — only address issues in code modified/added by this branch, do not fix preexisting issues in the codebase
  2. Run production-code-validator subagent and fix any issues found — only address issues in code modified/added by this branch, do not fix preexisting issues in the codebase
  3. Commit, push, and create PR
  4. Run `/review-pr-comments` with the PR URL in autonomous mode to auto-fix reviewer feedback
  5. Run `/codex-review` with the PR URL in autonomous mode to auto-fix Codex findings
  6. E2E test using Playwright CLI — drive the funnel manually with snapshot → click/fill → snapshot (do NOT rely on bundled flow scripts; see [e2e.md](e2e.md)). Check `playwright-cli --help` for available commands. Use the URL, test items, and capture criteria collected during planning. **NEVER ask the operator how to proceed with the E2E step** — the plan-review loop already authorized "run E2E + allow up to 5 deploys with `--fix-and-retry`". Do not use `AskUserQuestion` or numbered-option prompts here; do not pause for deploy approval (the plan-review confirmation IS the explicit approval; stage-only safety guards inside `e2e-test-jira-ticket` are the binding check). **Omit this step entirely if the operator opted out of E2E testing during planning.**
  7. **On E2E pass: post "QA Pass" Jira comment** via `mcp__atlassian__addCommentToJiraIssue` using the structured format from [qa-pass-comment-template.md](qa-pass-comment-template.md). Title: `# QA Pass (Automated E2E Execution) ✅`. **Skip if E2E failed (`E2ETEST-Report.md` exists) or E2E was opted-out during planning** — there is no proof to attach.
  8. **Jira finalization (only on success — E2E passed, or E2E skipped during planning):** transition the ticket to "Ready for QA", assign to Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`), and log the hours collected during planning via `mcp__atlassian__addWorklogToJiraIssue`. **Skip the entire finalization (transition + assign + log) if (a) E2E failed after 5 iterations** (an `E2ETEST-Report.md` was written), **OR (b) the ticket's current Jira status is not "In Progress"** (re-fetch via `mcp__atlassian__getJiraIssue` immediately before mutating; this prevents re-runs on already-finalized tickets from regressing state). On skip, print a clear message naming the reason and continue.

  **⚠️ MANDATORY CHECKLIST (verify before presenting plan):**
  - [ ] **TDD ordering**: Every implementation task is preceded by its corresponding test task (see "Critical rules → TDD-first" in SKILL.md)
  - [ ] **Semantic versioning**: If the plan modifies ANY files under `dynamic-app/`, it includes the semantic-versioning tasks (see "Critical rules → Semantic versioning" in SKILL.md)
  - [ ] Plan includes code-review-specialist subagent step
  - [ ] Plan includes production-code-validator subagent step

  - Example format:
    ```
    ## HIGH LEVEL PLAN
    1. Write tests for user authentication flow (auth.test.ts)
    2. Implement JWT token generation (auth.service.ts)
    3. Add login endpoint with validation (auth.controller.ts)
    4. Update middleware to verify tokens (auth.middleware.ts)
    5. Run full test suite and verify green
    6. Run code-review-specialist and address any issues
    7. Run production-code-validator and address any issues
    8. Commit, push, and create PR
    9. Run /review-pr-comments with PR URL in autonomous mode
    10. Run /codex-review with PR URL in autonomous mode
    11. E2E test using Playwright CLI (URL, what to test, captures from planning)
    12. On E2E pass: post "QA Pass (Automated E2E Execution) ✅" Jira comment with structured evidence (skip if E2E failed or opted out)
    13. On success: if Jira status is "In Progress", transition to "Ready for QA", assign to Fabiano Desouza, log <hours> hours; otherwise skip finalization and continue (re-runs on already-finalized tickets are a no-op)
    ```

### 2) Summary
- Restate ticket name, description, user story (if provided), and constraints succinctly.

### 3) Acceptance Criteria → Test Mapping
- For each acceptance bullet, list the test(s) that will verify it (names, locations).

### 4) Design choice (brief)
- Present 1–2 viable approaches; pick the **smallest-diff, lowest-risk** default.

### 5) Task Breakdown (TDD-first)
For each task:
- **Tests to write first** (specific file paths + test names).
- **Code changes** (files/functions to touch with rationale).
- **Observability** (logs/metrics/traces) if relevant.
- **Risks & rollback** (if any).
- **Estimated complexity** (S/M/L).

**ALWAYS include these final tasks:**
- **Code Review**: Run code-review-specialist subagent to review all changes and fix any issues found **in the current branch** (not preexisting issues)
- **Production Validation**: Run production-code-validator subagent to ensure code is production-ready and fix any issues found **in the current branch** (not preexisting issues)
- **Commit, Push, and PR**: After all validation passes, commit all changes, push to remote, and create a PR
- **Review PR Comments**: Run `/review-pr-comments` with the PR URL in autonomous mode to auto-fix any reviewer feedback
- **Codex Review**: Run `/codex-review` with the PR URL in autonomous mode to auto-fix any Codex findings
- **E2E Test (Playwright CLI)** *(omit this task entirely if the operator opted out of E2E testing during planning)*: Run an E2E test using Playwright CLI. **Drive the funnel manually with `playwright-cli` snapshot → click/fill → snapshot — do NOT rely on any bundled funnel-driving scripts (`*-flow.sh` wrappers); UIs drift faster than scripts get maintained. See [e2e.md](e2e.md) for the loop.** Check `playwright-cli --help` for available commands. Use the **E2E Test Plan** captured during planning (URL, what to test, what to capture). **On failure, run a fix-and-retry loop (max 5 iterations): investigate → fix code → commit/push → re-run the same E2E test.** If still failing after 5 iterations, write `E2ETEST-Report.md` at the project root with status, what's failing, what was tried each iteration, and suggested next steps.
- **QA Pass Jira comment (only on E2E pass)**: Post a structured comment to the Jira ticket via `mcp__atlassian__addCommentToJiraIssue` with title **`# QA Pass (Automated E2E Execution) ✅`** and the format defined in [qa-pass-comment-template.md](qa-pass-comment-template.md). The comment must include: run metadata (PR, branch, app version verified live, run date), what was tested (test URL, deploy command, tabs traversed), what was verified (AC-by-AC pass table), evidence (milestone dataLayer JSONs, direct smoke-test responses where applicable, screenshot paths), code-review iterations table (Cursor/Codex findings + fix commit SHAs), local artifacts list, and notes on anything surprising (e.g., funnel-specific quirks). **Skip if (a) E2E failed (`E2ETEST-Report.md` exists at project root), OR (b) operator opted out of E2E during planning** — there is no proof to attach.
- **Jira finalization on success**: Transition ticket to **"Ready for QA"**, assign to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`), and log **<HOURS>** hours via `mcp__atlassian__addWorklogToJiraIssue` (where `<HOURS>` is the value the operator provided during planning). **Skip the entire finalization (transition + assign + log) if (a) E2E failed after 5 iterations** (an `E2ETEST-Report.md` was written), **OR (b) the ticket's current Jira status is not "In Progress"** — re-fetch via `mcp__atlassian__getJiraIssue` immediately before mutating; if it's already past finalization (e.g., re-running on a ticket already at "Ready for QA"), print a clear skip message and continue. Run this even when E2E was skipped during planning.

### 6) Commands (per tool permissions)
- Grouped commands to run (install/build/typecheck/lint/test/app) using your detected stack.
- Note any migrations/feature-flag ops.

### 7) Plan Review Loop Prompt (MANDATORY — NEVER SKIP)
- You MUST ask: **"What changes would you like to make to the plan? Reply with edits, or say 'no' / 'no further changes' to proceed."**
- Wait for the user's response. Do NOT proceed until the user replies.
- If the user requests edits, apply them, re-print the updated plan succinctly, and ask again.
- Repeat until the user explicitly says **"no" / "no further changes."**
- **NEVER skip this step.** The plan review loop is ALWAYS interactive — the user MUST review and approve the plan before any execution begins. "Autonomous" only refers to the execution phase, not the planning phase.

---

## Output format (for the planning phase)

- **Ticket**: [Ticket Name]
- **Branch Mode**: [USE-CURRENT-BRANCH: <current branch name> | Standard: <ticket branch name>]
- **Data Source**: [Jira | Manual | Jira + Manual overrides]
- **HIGH LEVEL PLAN** (concise task list for quick review — no ticket details)
- **Summary** (including user story if provided)
- **Technical Documentation** (if provided)
- **Acceptance Criteria → Tests**
- **Design Choice**
- **Task Breakdown (TDD-first)**
- **Commands (per tool permissions)**
- **Constraints** (if any)
- **E2E Test Plan** (3 confirmed items: 1) URL to use, 2) How to deploy [stage-trident only — production FORBIDDEN], 3) How to verify passing [pass/fail rule + evidence to capture] — drafted by the agent, then confirmed/updated by the operator; OR "Skipped by operator." if opted out)
- **Jira Finalization** (Hours to log on success — captured from the operator during planning. Transition target: "Ready for QA". Assignee: Fabiano Desouza)
- **Plan Review Loop Prompt** (repeat until "no further changes")
