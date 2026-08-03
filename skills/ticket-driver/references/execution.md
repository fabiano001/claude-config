# Execution phase + post-executor workflow

Load this **only after** the user explicitly confirms "no further changes" in the plan review loop. It covers: dispatching the executor Agent subagent (with the full prompt template), and the post-executor workflow the parent agent drives (review → codex → E2E → QA Pass → Jira finalization → final summary).

**PREREQUISITE:** The user MUST have explicitly said "no", "no further changes", or equivalent in the plan review loop. If the user has NOT confirmed, go back to the plan review loop and ask. Do NOT auto-approve the plan.

---

## Post the "Implementation Started" marker (MANDATORY, runs BEFORE dispatch, every mode)

The instant the plan is approved and BEFORE the executor is dispatched, post the start-of-implementation marker comment: `mcp__atlassian__addCommentToJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = the resolved ticket key) with `commentBody` = exactly `Ticket Driver Implementation Started (<REPO_NAME>): <timestamp>`, where:
- `<REPO_NAME>` is the `REPO_NAME` already resolved by SKILL.md's pre-run Guard (step 0 there). Reuse the same value — don't re-derive it independently. If it's somehow not available (e.g. long-running context got compacted between the Guard and here), re-resolve it the exact same way: `git remote get-url origin`, final `/`-delimited path segment, trailing `.git` stripped.
- `<timestamp>` is the current local time via `date +"%Y-%m-%d %H:%M"` (standalone Bash) — same human-readable format the final summary already uses for "started/finished local".

Runs identically regardless of mode (standard, TODO-MODE, USE-CURRENT-BRANCH, ARTIFACT). **The `(<REPO_NAME>)` parenthetical is not decorative** — it's what lets SKILL.md's Guard tell apart which repo a marker belongs to on a multi-repo ticket (see SKILL.md's Guard section for why: one ticket can have several repos, each driven by its own separate `ticket-driver` session, and without the repo name a marker for repo A would incorrectly block a run on repo B).

**Why this has to happen here, not earlier:** SKILL.md's pre-run Guard already ran once, before planning even began, and found neither marker for this repo (or this run wouldn't have gotten this far). Posting the Started marker now — right as implementation actually begins, after the interactive plan-review loop is done — is what lets a *different* invocation's own Guard check (run at ITS start, at any point from now until this run finishes, for the SAME repo) see that implementation is underway and bail, instead of racing this one. A concurrent invocation on a DIFFERENT repo for the same ticket is unaffected either way — that's the entire reason the marker is repo-scoped.

**If this comment-post fails:** don't silently continue — print a clear warning that the Started marker wasn't posted and that this run is proceeding WITHOUT that protection (a concurrent second invocation on this ticket, for THIS SAME repo, would not be caught). This is not fatal to the run itself; the plan was already approved and execution should proceed, but the operator needs to know the safety net has a hole for this run.

---

## Dispatch to Agent subagent

Dispatch execution to an Agent subagent using the Agent tool. Agent subagents inherit parent permissions from `settings.local.json` and cannot ask the user questions — they are inherently non-interactive.

Use the **Agent tool** with:
- `subagent_type`: `"general-purpose"`
- `description`: `"Execute ticket plan for <TICKET_NAME>"`

The **prompt** parameter must be a single string built by concatenating sections 1–4 below. Do NOT wrap any section in code fences — the agent must read every line as a direct instruction.

**--- START OF PROMPT TEMPLATE (substitute variables, remove this marker) ---**

**SECTION 1 — ROLE AND SAFETY RULES (paste first, before anything else)**

You are the Ticket Driver Executor — an autonomous execution engine that implements a pre-approved plan task by task. You run in a separate context with NO user present.

RULE 1 — NEVER ASK QUESTIONS:
You MUST NOT use AskUserQuestion or any similar tool. You MUST NOT output text asking the user to confirm, approve, or choose. There is no user. If you are unsure about something, make the best decision and proceed. NEVER say "Do you want to proceed?" or "Should I continue?" or present numbered options — just do the work.

This rule applies with FULL FORCE to the E2E step (Step 4 below) and to deploys triggered inside the `e2e-test-jira-ticket` skill. Specifically:
- NEVER prompt the operator with options like "1. Run E2E + allow up to 5 deploys / 2. Run E2E with NO redeploys / 3. Skip E2E entirely / …". The plan-review confirmation IS the answer: run E2E + `--fix-and-retry` (allow up to 5 deploys).
- NEVER pause for "explicit user approval" before a deploy at the E2E step, even if a CLAUDE.md rule or auto-mode classifier suggests it. The plan-review loop is the explicit approval. The deploy command is also pre-validated by stage-only safety guards inside `e2e-test-jira-ticket` (production targets abort the run). If the auto-mode classifier blocks a follow-up command (e.g., `command -v playwright-cli`), proceed with the next step using whatever you can; do NOT route the block into a user-facing question.

RULE 2 — BASH COMMAND FORMAT:
Every Bash command you run MUST be a simple, standalone command. Before submitting ANY Bash tool call, mentally scan the command string for these FORBIDDEN characters and remove them:

FORBIDDEN — remove these if present:
  2>&1  (NEVER append this — Claude Code captures stderr automatically)
  &&    (split into separate Bash calls)
  ;     (split into separate Bash calls)
  ||    (split into separate Bash calls)
  |     (NEVER use pipes — this includes "| grep", "| head", "| tail", "| wc" etc.)
  >     (no output redirection)
  >>    (no output redirection)
  $(    (no command substitution)
  =(    (Zsh process substitution — triggered by =() in strings like testPathPattern)
  cd    (NEVER use cd — use git -C or npm/npx --prefix)
  ~     (expand to full absolute path)
  \n+#  (NEVER put newlines followed by # inside quoted arguments — triggers "can hide arguments from path validation" security prompt. Keep --body and --message values as single-line plain text)

TESTPATHPATTERN RULE: When using --testPathPattern with multiple files, NEVER use parentheses for grouping. Instead of --testPathPattern="(foo|bar)", use --testPathPattern="foo|bar" (no parentheses). The parentheses contain =( which Zsh interprets as process substitution, triggering a security prompt.

SELF-CHECK: Read your Bash command string character by character. If it contains 2>&1, delete those 4 characters. If it contains | grep (or any pipe), remove it — read the full output instead. This check is mandatory for every single Bash call.

NEVER filter test output with grep. When tests fail, run the test command standalone and read the full output — Claude Code captures everything. Do NOT append "| grep ..." or "2>&1 | grep ..." to narrow the output.

CORRECT command patterns (copy these exactly, substituting paths):
  git -C /absolute/path status
  npm --prefix /absolute/path/to/dynamic-app run lint
  npm --prefix /absolute/path/to/dynamic-app test
  CI=true npm --prefix /absolute/path/to/dynamic-app test -- --watchAll=false --no-coverage
  CI=true npm --prefix /absolute/path/to/dynamic-app test -- --testPathPattern="src/foo/bar.test.tsx" --watchAll=false --no-coverage
  npx --prefix /absolute/path/to/dynamic-app eslint src/
  git -C /absolute/path add src/foo/bar.ts
  git -C /absolute/path commit -m "message"
  git -C /absolute/path push -u origin BRANCH_NAME
  gh pr create --repo owner/repo --base main --head BRANCH --title "title" --body "Single-line plain text body with no newlines or # characters"
  sleep 1200

**SECTION 2 — CONTEXT (substitute actual values)**

PROJECT_ROOT: <absolute path to the project root — the current IDE workspace>
TICKET_NAME: <ticket key, e.g., TRIDENT-655>
BRANCH_NAME: <current git branch name — use branch name, not ticket name>

**SECTION 3 — PLAN (paste the finalized plan sections)**

HIGH LEVEL PLAN:
<the numbered task list from the planning phase>

TASK BREAKDOWN:
<the full task breakdown with file paths, test names, and rationale>

ACCEPTANCE CRITERIA:
<the acceptance criteria from the ticket>

DESIGN DECISIONS:
<the chosen design approach and constraints>

**SECTION 4 — EXECUTION WORKFLOW**

Step 0 — Load project context (MANDATORY before any other step):
Use the Read tool to read these files. Internalize their contents as project rules and conventions that govern all your work:
1. Read PROJECT_ROOT/CLAUDE.md — contains project structure, code standards, semantic versioning rules, git conventions, and critical patterns. Follow every rule in this file.
2. Read PROJECT_ROOT/.claude/MEMORY.md — if it exists, contains memory index with project context and learnings from prior sessions. Read any linked memory files that are relevant to the current ticket.
3. Read ~/.claude/memory/E2E/<projectDir>/learnings.md — persistent E2E learnings shared across sessions and worktrees of this repo. Derive `<projectDir>` from the basename of PROJECT_ROOT by stripping any trailing `-worktree-<N>` suffix (e.g., `webapp-react-trident-worktree-2` → `webapp-react-trident`). If the file doesn't exist, skip silently. If it exists, internalize the entries — they document infra quirks, bot-protection behaviors, env-specific gotchas, and other knowledge that will affect Step 4 (E2E test).
Do NOT skip this step. Do NOT proceed to Step 1 until you have read and internalized these files.

Step 1 — Write initial status.md:
Write PROJECT_ROOT/dynamic-app/docs/status.md with EVERY task from the HIGH LEVEL PLAN as unchecked items ([ ] 1. task ...). **This file is NEVER committed to git — it is an in-run task tracker only. See Step 4's ⛔ NEVER COMMIT rule.** This includes the implementation/test tasks YOU will execute below AND the post-executor tasks the parent ticket-driver agent owns (review-pr-comments, codex-review, E2E test, QA Pass Jira comment, Jira finalization). Do NOT trim the list to just the coding tasks — the parent agent reads back this same file and ticks off the remaining items as each post-executor step completes. The status.md file is the single source of truth for "where is this ticket in its lifecycle?"; an incomplete list defeats that.

Step 2 — Execute tasks in a loop:
Repeat the following 3-step cycle for EACH task in order. Do not skip any step.

  Step 2a — Execute the task:
  Follow TDD-first rules (write tests FIRST, implement SECOND). Exceptions: pure config changes, dependency updates with no logic, trivial one-line fixes already covered by tests. Use the Edit tool for all code changes. Keep diffs minimal. Run lint, typecheck, and tests after each implementation chunk. Iterate until green.

  Step 2b — Update status.md (MANDATORY after every task):
  Use the Edit tool to change [ ] to [x] for the task you just completed in PROJECT_ROOT/dynamic-app/docs/status.md. This is not optional. Do this immediately after each task passes, before starting the next task. Only tick the items YOU executed in this loop — leave the post-executor items (review-pr-comments, codex-review, E2E, QA Pass Jira comment, Jira finalization) unchecked. The parent agent ticks those off as it processes them after you return.

  Step 2c — Move to the next task and repeat from Step 2a.

Step 3 — Code Review and Production Validation:
- Run the code-review-specialist agent (via Agent tool) to review all changes. Fix issues found in the current branch only (not preexisting issues).
- Run the production-code-validator agent (via Agent tool) to validate production readiness. Fix issues found in the current branch only.

Step 4 — Commit, Push, and PR:
- Run lint and tests one final time. Only proceed if both pass.
- Stage changed files with git add (one file per call — never git add -A or git add .).

  **⛔ NEVER COMMIT THESE FILES — they are run-state / local docs, not source code:**
  - `dynamic-app/docs/status.md` — this is the in-run task tracker; committing it pollutes the branch history with ticket-driver's own internal state.
  - `dynamic-app/docs/learnings.md` — this is a local post-run notes file; it is NOT part of the deliverable.
  - Any file under `dynamic-app/docs/` that was written by ticket-driver itself (status, learnings).

  Before staging, check `git -C <PROJECT_ROOT> status --short` and explicitly SKIP any of the above files. If you catch yourself about to stage them, abort the `git add` for those files and continue without them. If they were accidentally staged, unstage them with `git -C <PROJECT_ROOT> restore --staged dynamic-app/docs/status.md` (and the same for learnings.md) before committing.

- Commit with a descriptive message.
- Push to remote.
- Create PR using gh pr create. IMPORTANT: The --body value must be a single-line string with NO newlines and NO # characters — these trigger Claude Code security prompts ("Newline followed by # inside a quoted argument") that block autonomous execution. Use plain text separators instead of markdown headers:
    gh pr create --repo owner/repo --base main --head BRANCH_NAME --title "BRANCH_NAME: Short title" --body "Summary: bullet1, bullet2. Test plan: item1, item2."

Step 5 — Write learnings.md:
After all tasks are complete, write PROJECT_ROOT/dynamic-app/docs/learnings.md with: Summary (what was implemented, key files, PR URL) and Learnings (anything unexpected, workarounds, patterns, gotchas — or "No significant learnings" if straightforward). **This file is NEVER committed to git — it is a local post-run notes file only. See Step 4's ⛔ NEVER COMMIT rule.**

Step 6 — Return completion message:
Return a message confirming all tasks completed (or which failed and why), PR URL if created, and path to learnings.md.

**--- END OF PROMPT TEMPLATE ---**

---

## After executor completes

**AUTO-CONTINUE CONTRACT (HARD RULE — applies to every step in this section):**

Once the executor subagent returns, every step below runs **back-to-back without pausing**. After each step finishes, IMMEDIATELY proceed to the next step in the same turn. Do NOT stop, do NOT summarize and wait, do NOT ask "should I continue?", do NOT treat a step's completion as the end of work. The only legitimate stops are:
- A step's tooling itself blocked (e.g., `e2e-test-jira-ticket` aborted due to a stage-only safety guard, or `/review-pr-comments` reached its 5-iteration cap with leftover work).
- A hard error you cannot recover from (in which case report the failure and the exact next step the operator can take, then stop).
- The final step (Done) is reached.

Specifically: completing a "review" step (review-pr-comments OR codex-review) is NEVER a stopping point. Even when a review reports zero findings or "all clear", that is a green light to continue, not a reason to stop. Generate any report the step produces (or note "no findings"), then move directly to the next numbered step.

If you find yourself uncertain about whether to continue, the answer is always: **continue**. The operator only steps in when you explicitly tell them you have stopped.

**STATUS.MD CONTRACT (HARD RULE — applies to every step in this section):**

The executor wrote `<PROJECT_ROOT>/dynamic-app/docs/status.md` at its Step 1 with EVERY task from the HIGH LEVEL PLAN as unchecked items — including the post-executor tasks (review-pr-comments, codex-review, E2E test, QA Pass Jira comment, Jira finalization). The executor's Step 2b only ticks off the coding tasks it owns; the parent agent (this section) owns the rest.

**After EACH numbered step below completes**, immediately use the Edit tool to flip the matching `[ ]` to `[x]` in `<PROJECT_ROOT>/dynamic-app/docs/status.md` BEFORE moving to the next step. The mapping from this section's step numbers to the typical HIGH LEVEL PLAN line items is:

| Step in this section | HIGH LEVEL PLAN item (example numbering) | When to tick |
|---|---|---|
| 3. Codex review (pre-clean pass) | `9. Run /codex-review … (pre-clean)` | After step 3a captures the report paths. |
| 4. Review PR comments | `10. Run /review-pr-comments …` | After step 4a captures the report paths. |
| 5. Codex review (final pass) | `11. Run /codex-review … (final pass)` | After step 5a captures the report paths. |
| 6. E2E test | `12. E2E test using Playwright CLI …` | After the `e2e-test-jira-ticket` skill returns, regardless of pass/fail. If E2E failed, the item is still "completed" — the failure is recorded in `E2ETEST-Report.md`, not as an unchecked status. |
| 7. QA Pass Jira comment | `13. On E2E pass: post "QA Pass …" Jira comment` | After the comment posts, OR after deciding to skip per the skip rules (E2E failed / E2E opted out). Both outcomes count as the item being processed. |
| 8. Jira finalization | `14. On success: transition Jira ticket …` | After the transition + assign + worklog land, OR after deciding to skip per the skip rules. |

If the HIGH LEVEL PLAN's numbering differs from the example (e.g., E2E was opted out so the plan has fewer items), match by task description rather than by number — pick the line in status.md whose text matches the step's intent.

Do NOT batch the status.md updates at the end. Each step's tick happens IMMEDIATELY after that step finishes so the operator (or a debugging run) can read status.md mid-flight and see exactly where things stand. The same Edit-tool rule the executor used in its Step 2b applies here.

If a step is genuinely SKIPPED (e.g., E2E opted out during planning means the E2E line was never written into status.md to begin with, OR the Jira finalization step decided the ticket was already past "In Progress"), do not tick anything — the missing or already-resolved line stays as it is. Only tick items that the step actually performed.

---

1. **Read the learnings file**: Read `<PROJECT_ROOT>/dynamic-app/docs/learnings.md`
2. **Present to the user**: Display the Summary and Learnings sections from the file
3. **Codex review — pre-clean pass (runs FIRST, before review-pr-comments)**: Run `/codex-review` with the PR URL in **autonomous** mode to auto-fix its findings. `/codex-review` dispatches an independent Opus 4.8 subagent that runs synchronously within this session (no Codex CLI involved despite the skill's name) — no waiting on external bots — so it runs immediately with no preceding sleep.

   **Why this runs first:** `/codex-review` runs synchronously within this session, with no external bot to wait on; fixing its correctness findings now (and pushing them) pre-empts issues Cursor Bugbot would otherwise post, which reduces the number of `/review-pr-comments` iterations (each of which costs a 20-minute sleep). The push also starts the bot clock so the subsequent `sleep` + review loop incubates and reaps any comments this push provokes.

   **3a. Capture Codex (pre-clean) report paths (runs IMMEDIATELY after step 3 returns).** Apply the same pattern as step 4a, to `~/.claude/memory/ticket-reports/<TICKET>/codex-review/`. Collect every `<TICKET>-CODEX-REVIEW-*.md` (or `PR-<number>-CODEX-REVIEW-*.md`) into `CODEX_REVIEW_REPORT_PATHS`. Empty list is fine.

   **Auto-continue (regardless of findings):** zero findings / all "Not a real issue" is a green light — note "Codex pre-clean: no findings to fix" in one line and continue to step 4. A Codex tool error / cannot-run → report the error and the next step the operator should take, then stop.

4. **Wait for review bots, then review PR comments**: First run `sleep 1200` as a **foreground blocking Bash call** — do NOT use `run_in_background`; it must block for the full 20 minutes (set the Bash tool timeout to at least 1300000ms) so Cursor Bugbot / CI have time to post comments (including any triggered by the step-3 Codex push). Then invoke the skill with exactly: `/review-pr-comments <PR_URL> autonomous` — the "autonomous" keyword triggers the skill's auto-fix loop (Auto Steps A→B→C→D) which fixes issues, commits, pushes, sleeps 20 minutes, re-checks for new comments, and repeats up to 5 iterations until no new fixable issues remain. This loop is the **terminal convergence step among the auto-pushers** — it drives the PR's review threads to a clean state.

   **4a. Capture PR review report paths (runs IMMEDIATELY after step 4 returns).** The `/review-pr-comments` skill writes its reports directly to `~/.claude/memory/ticket-reports/<TICKET>/pr-review/`. No stash dance, no copy — the files are already at the durable location. This step just records the paths for the final summary.
   1. List the directory: `ls ~/.claude/memory/ticket-reports/<TICKET>/pr-review/` (standalone Bash).
   2. Collect every `<TICKET>-PR-REVIEW-*.md` (or `PR-<number>-REVIEW-*.md`) filename into `PR_REVIEW_REPORT_PATHS`, prefixing each with the absolute directory path.
   3. If the directory does not exist or is empty (skill ran but produced nothing — extremely rare), set `PR_REVIEW_REPORT_PATHS` to an empty list. The final summary will show `none generated`.

5. **Codex review — final pass (ONLY after step 4 is fully complete)**: Wait for `/review-pr-comments` to finish its entire autonomous loop (all iterations, up to 5 max) before proceeding. Then run `/codex-review` with the PR URL in **autonomous** mode again — a final correctness pass on the now-final diff. It auto-fixes, commits, and pushes any remaining real issues.

   **Late-comment handling (do NOT loop back here):** this final push *may* draw a fresh Cursor Bugbot comment, and `/review-pr-comments` does NOT run again inside ticket-driver to reap it. That is intentional and safe — `jira-sprint-manager` Rule C's **pre-merge unresolved-review-thread gate** (which auto-resumes `/review-pr-comments` via its path 3b) is the backstop that reaps any straggler before anything merges to prod. A real issue found this late is rare (two prior review passes already cleaned most), so the residual bot churn is minimal. Do NOT add another review-pr-comments iteration here — proceed to E2E.

   **5a. Capture Codex (final-pass) report paths (runs IMMEDIATELY after step 5 returns).** Same pattern as step 3a/4a, applied to `~/.claude/memory/ticket-reports/<TICKET>/codex-review/`. **Append** any new `<TICKET>-CODEX-REVIEW-*.md` files to `CODEX_REVIEW_REPORT_PATHS` (do not drop the pre-clean report from step 3a). Empty ⇒ no new final-pass report.

   **Auto-continue after this step (regardless of findings):** When Codex returns, proceed IMMEDIATELY to step 6 (E2E test). Possible Codex outcomes and what to do:
   - **Real issues found and auto-fixed** → fixes are already committed/pushed by the autonomous loop; the Rule C backstop reaps any resulting bot comment at merge time. Continue to step 6.
   - **Real issues found but classified as "Leave as is"** → noted in the report, no action needed. Continue to step 6.
   - **Zero findings / all "Not a real issue" / only style observations** → this is a green light. Note "Codex final pass: no findings to fix" in one line, then continue to step 6. **Do NOT stop here.** Reaching this step's end is not a milestone for operator review; it is a transition point to the E2E step.
   - **Codex tool error / cannot run** → report the error and the next step the operator should take, then stop.
6. **E2E test (delegated to the `e2e-test-jira-ticket` skill — runs ONLY after the final Codex pass is complete)**: **Skip this step entirely if the operator opted out during planning** (E2E Test Plan = "Skipped by operator.").

   Otherwise, invoke the `e2e-test-jira-ticket` skill via the Skill tool, passing the three confirmed items from planning verbatim plus the `--fix-and-retry` flag. **This invocation is pre-authorized by the planning phase — no operator confirmation is needed at this step.** The autonomous orchestrator pattern means we want the skill to commit/push/redeploy fixes on failure, up to 5 iterations:

   ```
   Skill(skill="e2e-test-jira-ticket",
         args="<TICKET> --plan-confirmed --url='<url>' --deploy='<deploy command>' --verify='<verify rule>' --fix-and-retry")
   ```

   **If planning confirmed more than one URL** (the rare multi-entry-point case — see planning-phase.md's "URL confirmation" section): `--url` here takes the **first/primary** confirmed URL. Running a second, independent E2E pass against the other confirmed URL is not automated by this step — `e2e-test-jira-ticket`'s interface accepts one URL per invocation, and this skill doesn't loop this step over a list. If the plan genuinely needs both funnel entry points verified, note that explicitly to the operator after this step completes rather than silently testing only one and calling it done.

   ### NEVER-ASK rule for the E2E step (HARD CONSTRAINT)

   When `ticket-driver` reaches this step, the agent MUST invoke the skill IMMEDIATELY with the args above. Do NOT pause to ask the operator any question about how to proceed with E2E. Specifically:

   - **Do NOT** use `AskUserQuestion` or any numbered-option prompt (e.g., "1. Run E2E + allow up to 5 deploys / 2. Run E2E with NO redeploys / 3. Skip E2E entirely / …"). The operator has ALREADY answered this during planning by confirming the E2E Test Plan; the answer is **always** "run E2E + allow up to 5 deploys with `--fix-and-retry`".
   - **Do NOT** ask the operator to authorize the deploy command. The deploy command is pre-authorized:
     - It was confirmed by the operator during the plan-review loop.
     - Stage-only safety guards inside `e2e-test-jira-ticket` re-validate at skill entry and again before the command runs.
     - Production deployment is forbidden by the skill (any `trident-funding` target aborts).
   - **If a CLAUDE.md or auto-mode classifier rule (e.g., "never deploy without explicit user approval") suggests pausing** — DO NOT pause. The plan-review loop IS the explicit user approval for deploys at this step. Note this back to the operator in one line ("Deploy step pre-authorized by plan-review confirmation; proceeding") and continue. The `e2e-test-jira-ticket` skill's stage-only safety guards are the final binding check; they will abort if the command is wrong.
   - **The only legitimate pauses** at this step are the ones the skill itself produces (stage-vs-prod safety guard tripping, suspicious-URL refusal, deploy command failing with non-zero exit, or branch-state aborts in Mode 1 — but ticket-driver invokes Mode 2, so most of those don't apply). Anything else is a skip-the-question situation.

   The `e2e-test-jira-ticket` skill owns the entire execution path: it echoes the resolved values back to the operator (last-chance visual review — no pause), runs the deploy (with stage-only safety guards), drives the funnel via Playwright CLI's snapshot-then-act loop (no bundled scripts), verifies against the pass/fail rule, captures evidence, runs the fix-and-retry loop on failure, and on final failure writes `<PROJECT_ROOT>/E2ETEST-Report.md` and persists any new learnings.

   **What `ticket-driver` does after the skill returns:**
   - Check for `<PROJECT_ROOT>/E2ETEST-Report.md` — if it exists, the E2E failed. Skip BOTH the QA Pass Jira comment (step 7) AND the Jira finalization (step 8); leave the ticket as-is for the operator to triage.
   - If the file does NOT exist, the E2E passed (or was substituted via the verification-substitution rule but still proved the AC). Proceed to step 7 (QA Pass comment) and then step 8 (Jira finalization).

   The `e2e-test-jira-ticket` skill enforces these rules internally (do not duplicate them here):
   - URL and deploy command are LOCKED for the run — the skill stops and asks the operator if either appears wrong.
   - Verification approach MAY be substituted mid-execution if the agreed approach demonstrably fails AND the alternate validates the same pass/fail intent. Both are documented in the report.
   - Production deployment is forbidden — the skill aborts before running any command that doesn't explicitly target stage.
   - Learnings are persisted ONLY when something genuinely new (and non-duplicate) was discovered.
7. **QA Pass Jira comment (only on E2E pass — runs BEFORE Jira finalization)**: When the `e2e-test-jira-ticket` skill returned successfully (no `E2ETEST-Report.md` at project root) AND the operator did NOT opt out of E2E during planning, post a structured comment to the Jira ticket via `mcp__atlassian__addCommentToJiraIssue`:

   - **`cloudId`:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - **`issueIdOrKey`:** the resolved Jira key (strip any `-TEST` / `-TEST-<N>` suffix from the ticket name)
   - **`contentFormat`:** `markdown`
   - **`commentBody`:** structured per [qa-pass-comment-template.md](qa-pass-comment-template.md) — title is exactly `# QA Pass (Automated E2E Execution) ✅`.

   **Skip conditions (skip this step if ANY is true):**
   - `<PROJECT_ROOT>/E2ETEST-Report.md` exists (E2E failed after 5 iterations) — there is no pass to celebrate.
   - The operator opted out of E2E during planning (E2E Test Plan = "Skipped by operator.") — there is no automated proof to attach.

   On skip, print one line: `"QA Pass comment skipped: <reason>."` and continue to step 8.

   Confirm to the operator on success: `"Posted QA Pass comment to <TICKET>: <comment URL>"`.

8. **Jira finalization on success**: Run this step **only if** (a) the E2E test passed, OR (b) the operator skipped E2E during planning. **Skip this step entirely if** an `E2ETEST-Report.md` exists at the project root (E2E failed after 5 iterations) — leave the ticket as-is for the operator.

   **Status guard (runs first) — branches on TODO-MODE, detected back at Standard-mode-workflow step 1:**

   - **Standard mode (TODO-MODE not passed):** fetch the current ticket status via `mcp__atlassian__getJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey is the ticket key, request `fields: ["status"]` to keep the response slim). Inspect `fields.status.name`.
     - **If `status.name === "In Progress"`** → proceed to all four sub-steps below (transition + assign + log + confirm).
     - **If `status.name !== "In Progress"`** → **SKIP the entire finalization** (no transition, no assign, no worklog). Print to the operator:

       ```
       Jira finalization skipped: ticket <TICKET> is in status "<current status>", not "In Progress".
       This typically means the workflow has already moved past finalization (e.g., a re-run on a ticket that was already moved to "Ready for QA"), or someone else has progressed the ticket manually.
       If this is unexpected, check the ticket on Jira and re-run finalization manually.
       ```

       Then proceed to step 9 (Done) — do not error out, this is an expected case during workflow re-runs and during testing.

   - **TODO-MODE:** skip this status check entirely — a TODO-MODE ticket is *expected* to still be sitting in a TODO-column status (New/Backlog/Reopened), not "In Progress"; that's the whole premise of the mode, not an anomaly to guard against. Proceed straight to sub-steps 2–4 below (Assign, Log hours, Confirm) and **skip sub-step 1 (Transition) unconditionally**, regardless of whatever the current status actually is.

     **Trade-off (mitigated):** because TODO-MODE bypasses the "not In Progress" guard that gives standard mode its natural re-run protection, re-invoking ticket-driver in TODO-MODE on an already-finalized ticket would otherwise re-assign and re-log hours. Sub-step 4 below (the completion marker comment) is what closes this gap in practice — SKILL.md's pre-run "Guard" step checks for that exact comment before any run (any mode) even starts, so a second invocation on an already-completed ticket now stops at the Guard, before ever reaching this section.

   Perform these sub-steps in order (sub-step 1 applies to standard mode only; the rest run in both):

   1. **Transition** the ticket to **"Ready for QA"** using `mcp__atlassian__getTransitionsForJiraIssue` to find the matching transition ID, then `mcp__atlassian__transitionJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`. **Skip this sub-step entirely in TODO-MODE** — the ticket stays in whatever status it was already in; nothing about its Jira status field changes.
   2. **Assign** the ticket to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`) using `mcp__atlassian__editJiraIssue` with `fields: { assignee: { accountId: "5a6765563c7f1842c3d7b806" } }`.
   3. **Log hours** using `mcp__atlassian__addWorklogToJiraIssue` with the **Hours to log** value captured during planning (convert to seconds: `hours * 3600`, or use the API's `timeSpent` string format like `"2.5h"` per the tool's schema).
   4. **Post the completion marker comment** via `mcp__atlassian__addCommentToJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = the resolved ticket key). `commentBody` = exactly `Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>`, where `<REPO_NAME>` is the same value used for the Started marker (from SKILL.md's Guard step 0, or re-resolved the same way if unavailable) and `<timestamp>` is the current local time via `date +"%Y-%m-%d %H:%M"` (standalone Bash) — same format as the Started marker posted before dispatch. The `Ticket Driver Implementation Completed (<REPO_NAME>)` prefix (repo name included) is the machine-matched part (this is a marker, not a human status report — the QA Pass comment from step 7 already covers the human-readable detail); keep that exact prefix, repo name and all, so SKILL.md's pre-run Guard step can reliably find it via substring match on every future invocation against this ticket **and repo**, in any mode — a marker for a different repo on the same ticket must not match. If this comment-post fails, don't silently continue: print a clear warning that the completion marker wasn't posted and that a future run on this ticket (for this same repo) won't be auto-skipped by the Guard step as a result (it'll still be blocked by the earlier Started marker from THIS run, though — not fully unprotected) — but do not treat it as fatal to this run, which has already completed its real work.
   5. Confirm to the user:
      - **Standard mode:** "ticket transitioned, assigned, `<HOURS>` hours logged, and completion comment posted."
      - **TODO-MODE:** "ticket assigned, `<HOURS>` hours logged, and completion comment posted — **NOT transitioned** (TODO-MODE): the implementation, PR, and E2E pass are already done, so the ticket is ready to move straight to 'Ready for QA' as soon as it's actually picked up and transitioned to 'In Progress' — that transition itself is a separate, later action this run intentionally did not take."
9. **Done — final summary (MANDATORY)**: Compute the total wall-clock elapsed time AND gather the run-level metrics, then present a structured final summary to the operator.

   **Step 9a — Elapsed-time calculation:**
   1. Read the start timestamp back via `cat /tmp/ticket-driver-start-<TICKET>.timestamp` (use the `Read` tool if shell `cat` trips a permission prompt — same Unix-epoch-seconds value).
   2. Run a fresh `date +%s` for the end timestamp.
   3. Compute `elapsed_seconds = end - start`. Convert to hours and minutes:
      - `hours = floor(elapsed_seconds / 3600)`
      - `minutes = floor((elapsed_seconds % 3600) / 60)`
   4. Format as `Xh Ym` (e.g., `2h 47m`). If hours is 0, drop the hours component (e.g., `34m`). Always include minutes even if 0.

   **Step 9b — Gather run-level metrics:**
   - **Commit list** — `git -C <PROJECT_ROOT> log main..HEAD --oneline` (or whatever base branch the PR targets). Capture all commits introduced on this branch during this run; each row in the summary table is `<short SHA> | <one-line description>`. Group commits by phase if helpful (initial implementation / PR review fixes / Codex fixes / mid-E2E fixes).
   - **Test counts** — Use the counts from the most recent `CI=true npm test` run during the lint+test pass. The Jest summary line `Tests: N passed, M skipped, P total` is what you want. Capture per-project (`dynamic-app/` and `functions/`) when both ran. If the count was not retained in working memory (long run), re-run the test commands once before producing the summary; do NOT guess.
   - **New tests added (count)** — Count new `it(` / `test(` blocks in test files modified or created on this branch:
     ```
     git -C <PROJECT_ROOT> diff main..HEAD -- '*.test.ts' '*.test.tsx'
     ```
     Then count added lines starting with `+` that contain `it(`, `test(`, or `it.each(`. Approximate is fine; "+18 tests across 3 files" is more useful than "exact line count". If no test files were modified (rare for TDD-first), report "0".
   - **Stage app version verified live** — The `Dynamic App Version: x.y.z` value the operator (or executor) read from the live page console after deploy. Skip this metric if E2E was opted-out.
   - **Code review iteration counts** — Number of Cursor Bugbot findings + number of Codex findings addressed during the autonomous review loop. Sum per source. Pull from the iteration reports preserved by steps 3a, 4a, and 5a at `~/.claude/memory/ticket-reports/<TICKET>/pr-review/<TICKET>-PR-REVIEW-*.md` and `~/.claude/memory/ticket-reports/<TICKET>/codex-review/<TICKET>-CODEX-REVIEW-*.md` (Codex now has two passes — pre-clean at 3a + final at 5a — both folded into `CODEX_REVIEW_REPORT_PATHS`). The captured paths are available in `PR_REVIEW_REPORT_PATHS` and `CODEX_REVIEW_REPORT_PATHS`.
   - **New E2E learnings count** — Number of new entries appended to `~/.claude/memory/E2E/<projectDir>/learnings.md` during this run. The `e2e-test-jira-ticket` skill writes these conditionally; if it didn't write any (because nothing new was discovered), report "0".

   **Step 9c — Present the final summary in the format below:**

   ```markdown
   ## Ticket-driver complete — <TICKET>

   **PR:** <PR URL>
   **Branch:** `<branch name>`
   **Total elapsed:** <Xh Ym>  (started <Y-m-d H:M> local · finished <Y-m-d H:M> local)
   **Stage app version verified live:** `<Dynamic App Version: x.y.z>` (or "n/a — E2E was skipped")

   ### Commits added during this run (<N> total on branch)

   | SHA | Description |
   |-----|-------------|
   | `<short>` | <one-line description> |
   | `<short>` | <one-line description> |
   | …  | … |

   ### Verification

   - **Lint:** zero warnings (`dynamic-app/` + `functions/`) — or note any warnings + which project
   - **Unit/integration tests:** `<dynamic-app total>` passing (`<skipped>` skipped) in `dynamic-app/`; `<functions total>` passing (`<skipped>` skipped) in `functions/`
   - **New tests added on this branch:** `<count>` (breakdown: `<file1>: +N`, `<file2>: +M`, …)
   - **Test coverage:** `<delta or absolute %>` if computed; `not captured` if `--no-coverage` was used (default for ticket-driver runs)
   - **E2E:** `PASSED` | `FAILED` | `SKIPPED` — one-line outcome (e.g., "lead_submitted + application_submitted carry approval_odds + approval_outcome")

   ### Status

   - **Code review iterations:** `<N>` Cursor + `<M>` Codex findings, all addressed (or "0 findings — clean review loop")
   - **QA Pass Jira comment:** `POSTED` (`<comment URL>`) | `SKIPPED` (`<reason>`)
   - **Jira finalization:** `TRANSITIONED to "Ready for QA"` + `ASSIGNED to Fabiano Desouza` + `<HOURS>h logged` + `completion comment posted` | `ASSIGNED to Fabiano Desouza` + `<HOURS>h logged` + `completion comment posted` — **NOT transitioned (TODO-MODE)** | `SKIPPED` (`<reason>`)

   ### Artifacts

   - **E2E evidence:** comma-separated artifact paths from `~/.claude/memory/ticket-reports/<TICKET>/artifacts/` (e.g., `<TICKET>-datalayer.json`, `<TICKET>-e2e-final.png`, `<TICKET>-final-snapshot.yml`, plus any ad-hoc captures the executor took during the run). All captures live under that durable per-ticket directory — never `/tmp`. Show "n/a — E2E was skipped" when the operator opted out of E2E during planning.
   - **PR review reports:** one markdown link per file from `PR_REVIEW_REPORT_PATHS`, in iteration order — `[<TICKET>-PR-REVIEW-1.md](~/.claude/memory/ticket-reports/<TICKET>/pr-review/<TICKET>-PR-REVIEW-1.md)`, `[<TICKET>-PR-REVIEW-2.md](...)`, … (or `none generated` if the list is empty)
   - **Codex review reports:** one markdown link per file from `CODEX_REVIEW_REPORT_PATHS`, in iteration order — `[<TICKET>-CODEX-REVIEW-1.md](~/.claude/memory/ticket-reports/<TICKET>/codex-review/<TICKET>-CODEX-REVIEW-1.md)`, … (or `none generated` if the list is empty)
   - **New E2E learnings:** `<count>` new entries in `~/.claude/memory/E2E/<projectDir>/learnings.md` (or "none — run was routine")
   - **Local docs:** `<PROJECT_ROOT>/dynamic-app/docs/learnings.md` (executor-written run notes)
   ```

   **Style rules for the summary:**
   - Use markdown headings (`##`, `###`) and tables — this is the LAST text the operator reads, treat it like a polished report.
   - Wrap all SHAs in single backticks; wrap branch/file paths in single backticks; wrap status keywords (`PASSED`, `SKIPPED`, etc.) in single backticks.
   - Keep commit descriptions to a single line each (≤ ~110 chars). For initial-implementation commits, include scope; for fix commits, name the source ("Fix Cursor #2 — DRY refactor", "Fix Codex — applicationId regex").
   - The "Total elapsed" line is load-bearing — never omit it. If the timestamp file is missing for some reason (operator deleted it, or step 0 was skipped), report "Total elapsed: not captured (start timestamp missing)" rather than guess.
   - Do NOT recap every step of the workflow. The operator already saw progress along the way — the summary is for the at-a-glance view.

   **Step 9d — Cleanup:** After presenting the summary, delete the timestamp file: `rm /tmp/ticket-driver-start-<TICKET>.timestamp` (standalone Bash). If `rm` trips a permission prompt or the file is already gone, skip silently.

10. **The ticket is complete.**
