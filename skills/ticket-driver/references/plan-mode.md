# PLAN-MODE (for SprintLoop)

**If `PLAN-MODE` is specified in the arguments**, this skill operates differently. It only creates the plan and context files — it does NOT execute any code changes, git operations, or implementation.

When PLAN-MODE is detected, follow ONLY the workflow in this file. Use the **Planning blueprint** and **Output format** sections in [planning-phase.md](planning-phase.md) for producing and presenting the plan, but ignore the git-handling, execution, and post-executor sections (those live in [planning-phase.md](planning-phase.md) git section and [execution.md](execution.md) — not used in PLAN-MODE). Only write `plan.md` and `context.md` AFTER the user confirms "no further changes."

Run bookkeeping (Step 0 start timestamp + Step 0a sessions.md logging from SKILL.md) STILL applies in PLAN-MODE.

**Required arguments:** `PLAN-MODE <SPRINT_NAME> <TICKET_NAME>`
**Examples:**
- `/ticket-driver PLAN-MODE sprint_1 TRIDENT-802` — fetches Jira data from `TRIDENT-802`, saves to `TRIDENT-802/`
- `/ticket-driver PLAN-MODE test_sprint TRIDENT-802-TEST` — fetches Jira data from `TRIDENT-802`, saves to `TRIDENT-802-TEST/`
- `/ticket-driver PLAN-MODE test_sprint TRIDENT-802-TEST-2` — fetches Jira data from `TRIDENT-802`, saves to `TRIDENT-802-TEST-2/`

## Ticket Name Resolution

The `<TICKET_NAME>` argument is used as-is for **everything** (branch name, save directory, PR title prefix, etc.) **except** Jira lookups. For Jira API calls, strip any `-TEST` or `-TEST-<N>` suffix (where N is any number) to get the base Jira ticket key:
- `TRIDENT-802` → Jira lookup: `TRIDENT-802`
- `TRIDENT-802-TEST` → Jira lookup: `TRIDENT-802`
- `TRIDENT-802-TEST-2` → Jira lookup: `TRIDENT-802`
- `TRIDENT-802-TEST-15` → Jira lookup: `TRIDENT-802`

This allows rerunning test sprints against the same Jira ticket with different `-TEST-<N>` suffixes to create separate branches and save directories.

## ⚠️ SEMANTIC VERSIONING IN PLAN-MODE

The "Critical rules → Semantic versioning" section in SKILL.md applies equally to PLAN-MODE. If the plan will modify ANY files under `dynamic-app/`, the plan.md checklist **MUST** include semantic versioning tasks (update `internal-version.json`, update `package.json` version, run `npm install`).

## ⚠️ TDD IN PLAN-MODE

The "Critical rules → TDD-first" section in SKILL.md applies equally to PLAN-MODE. The plan.md checklist **MUST** order test-writing tasks BEFORE their corresponding implementation tasks. A plan that lists implementation before tests is a **planning error** and must be corrected before presenting.

## PLAN-MODE Workflow

1. **Collect inputs** — Same as standard mode: fetch from Jira, accept manual inputs/overrides (see [planning-phase.md](planning-phase.md)).
2. **Check for ticket dependencies** — Read `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/sprintStatus.json` and find the current ticket's entry. If the ticket's `baseBranch` field is not `main`, it depends on another ticket (the `baseBranch` value is the dependency ticket name):
   - Read `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<DEPENDENCY_TICKET>/context.md` to understand the prerequisite work (what that ticket implements, its design decisions, key files it modifies)
   - Read `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<DEPENDENCY_TICKET>/plan.md` to understand the planned changes (what code will exist when the dependency is complete)
   - Use this dependency context when producing the plan — the current ticket's implementation will build on top of the dependency ticket's changes
   - If `sprintStatus.json` does not exist or the ticket is not found in it, **STOP immediately** and warn the user: "Cannot proceed — `sprintStatus.json` not found or ticket not listed. Please run the sprint setup script first to initialize the sprint configuration." Do NOT continue with planning.
3. **Skip ALL git operations** — No branch setup, no checkout, no push.
4. **Read prior E2E learnings** — Read `~/.claude/memory/E2E/<projectDir>/learnings.md` (see [e2e.md](e2e.md) for how to derive `<projectDir>`). If the file exists, factor any relevant entries into the plan and the **E2E Test Plan**. If it doesn't exist, proceed.
5. **Produce the plan using the "Planning blueprint" section in [planning-phase.md](planning-phase.md)** — Follow the same rigorous planning process as standard mode (HIGH LEVEL PLAN, Summary, Acceptance Criteria → Test Mapping, Design Choice, Task Breakdown, Commands). Present the full plan to the user. If dependency context was loaded in step 2, incorporate it into the plan — reference the dependency ticket's changes and explain how the current ticket builds on them.
6. **Plan review loop** — Same as standard mode: present the plan and ask for changes. Repeat until the user confirms "no further changes."
7. **Skip ALL execution** — No code changes, no tests, no implementation.
8. **Save `plan.md`** — Distill the finalized plan into a checklist and write to:
   `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<TICKET_NAME>/plan.md`
   where `<TICKET_NAME>` is the full ticket name as passed (including any `-TEST-<N>` suffix).

   The plan.md must be a **flat checklist of tasks** formatted for the SprintLoop executor to follow. Each task should be a clear, actionable instruction. Example:
   ```markdown
   # <JIRA_TICKET_NUMBER> - Execution Plan

   - [ ] Write unit tests for the new validation logic in `src/utils/validation.test.ts`
   - [ ] Implement the validation function in `src/utils/validation.ts`
   - [ ] Update `BorrowerAddressStep.tsx` to use the new validation function
   - [ ] Run lint: `npm run lint`
   - [ ] Run tests: `CI=true npm test -- --coverage`
   - [ ] Run code-review-specialist subagent and address any issues — only fix issues in code modified/added by this branch, do not fix preexisting issues in the codebase
   - [ ] Run production-code-validator subagent and address any issues — only fix issues in code modified/added by this branch, do not fix preexisting issues in the codebase
   - [ ] Commit all changes, push to remote, and create PR
   - [ ] Wait 20 minutes for review bots to post comments: `sleep 1200`
   - [ ] Run `/review-pr-comments` with the PR URL in autonomous mode to auto-fix reviewer feedback
   - [ ] Run `/codex-review` with the PR URL in autonomous mode to auto-fix Codex findings
   - [ ] E2E test using Playwright CLI — see `~/.claude/skills/ticket-driver/references/e2e.md` for the snapshot-then-act loop. Check `playwright-cli --help` for available commands. Use the URL, what to test, and what to capture from the **E2E Test Plan** in context.md. **Drive the funnel manually with `playwright-cli` snapshot → click/fill → snapshot — do NOT rely on any bundled funnel-driving scripts (`*-flow.sh` wrappers); UIs drift faster than scripts get maintained.** On failure, run a fix-and-retry loop (max 5 iterations: investigate → fix code → commit/push → re-run same test). If still failing after 5 iterations, write `E2ETEST-Report.md` at the project root with status, what's failing, what was tried each iteration, and suggested next steps. *(Omit this checklist item entirely if the operator opted out of E2E testing — the **E2E Test Plan** section in context.md will say "Skipped by operator.")*
   - [ ] **On E2E pass: post "QA Pass" Jira comment** via `mcp__atlassian__addCommentToJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey is the resolved Jira key, contentFormat `markdown`). Title the comment exactly **`# QA Pass (Automated E2E Execution) ✅`**. Use the structured format from `~/.claude/skills/ticket-driver/references/qa-pass-comment-template.md` (Run metadata, What was tested, What was verified — AC table, Evidence — milestone 1 dataLayer/proof, Evidence — milestone 2, Evidence — direct smoke test if applicable, Code review iterations table, Local artifacts, Notes). **Skip this step entirely if (a) E2E failed (an `E2ETEST-Report.md` exists at project root), OR (b) the operator opted out of E2E during planning — there is no proof to attach.**
   - [ ] On success: transition Jira ticket to "Ready for QA", assign to Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`), and log the operator-provided hours (see **Jira Finalization** section in context.md) via `mcp__atlassian__addWorklogToJiraIssue`. **Skip the entire finalization (transition + assign + log) if (a) E2E failed after 5 iterations (an `E2ETEST-Report.md` was written), OR (b) the ticket's current status is not "In Progress" — re-fetch the ticket status before mutating; if it's already "Ready for QA" or anywhere else past In Progress, print a skip message and continue to Done.**
   ```

9. **Save `context.md`** — Write the full ticket context to:
   `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<TICKET_NAME>/context.md`
   (same `<TICKET_NAME>` directory as step 8)

   This file will be read by **another LLM session** (the SprintLoop executor) that has no knowledge of this conversation. Include everything that session needs to understand and execute the plan:

   ```markdown
   # <JIRA_TICKET_NUMBER> - Context

   ## Ticket Summary
   <ticket name and short description>

   ## User Story
   <user story if available>

   ## Acceptance Criteria
   <full acceptance criteria>

   ## Technical Documentation
   <any documentation from the ticket>

   ## Dependency Context
   <If the ticket depends on another ticket (baseBranch != main), summarize the dependency ticket's work here: what it implements, which files it modifies, its design decisions, and any interfaces or patterns it introduces that the current ticket will use. If no dependency, write "None — this ticket branches from main.">

   ## Design Decisions
   <design choices made during planning and why>

   ## Key Files
   <list of files that will be modified or created, with brief rationale>

   ## Constraints
   <any constraints discussed>

   ## E2E Test Plan
   <Captured from the human operator during planning (after the 3-item proposal-and-confirm flow). If the operator opted out, write exactly: "Skipped by operator." (and the executor will skip the E2E test step). Otherwise, write the three confirmed items verbatim:

   1. **URL to use:** <confirmed URL>
   2. **How to deploy** (stage-trident only — production deployment is FORBIDDEN): <confirmed command>
   3. **How to verify passing:** <confirmed pass/fail rule + evidence to capture>

   The executor MUST drive the funnel manually using the snapshot-then-act loop (see `~/.claude/skills/ticket-driver/references/e2e.md`) and MUST NOT invoke any bundled funnel-driving scripts (`*-flow.sh` wrappers or similar).

   The executor MAY update item 3 mid-execution if the agreed verification approach demonstrably fails, but MUST document both the original and the alternate (with a one-line rationale) in the post-test report. URL and deploy command MUST NOT be changed without operator approval — stop and ask if either needs to change.>

   ## Jira Finalization
   - **Hours to log on success:** <value provided by operator during planning, e.g., 2.5>
   - **Transition to:** Ready for QA
   - **Assignee:** Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`)
   - **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - **Skip conditions (skip transition + assign + worklog if ANY of these is true):**
     1. E2E failed after 5 iterations (`E2ETEST-Report.md` exists at project root).
     2. The ticket's current status is **not** "In Progress" at finalization time. Re-fetch status via `mcp__atlassian__getJiraIssue` (`fields: ["status"]`) immediately before any mutation. If `fields.status.name !== "In Progress"`, print a skip message naming the current status and continue to Done — this prevents re-runs on already-finalized tickets from regressing state.

   ## Session Notes
   <any important context from the planning conversation with the user that the executor needs to know — e.g., user preferences, clarifications, edge cases discussed, things to watch out for>
   ```

10. **Done — confirm files + report elapsed time** — Confirm `plan.md` and `context.md` were saved. Compute total elapsed time per the same procedure as standard mode's final summary (read `/tmp/ticket-driver-start-<TICKET>.timestamp`, fresh `date +%s`, format as `Xh Ym`). Present a one-line summary:

    ```
    PLAN-MODE complete — <TICKET>
    Saved: plan.md, context.md (in ~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<TICKET_NAME>/)
    Total elapsed: <Xh Ym>
    ```

    Then delete the timestamp file (`rm /tmp/ticket-driver-start-<TICKET>.timestamp`) and exit. Do NOT proceed to implementation.
