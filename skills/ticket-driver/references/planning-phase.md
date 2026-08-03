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

### Step 1: Fetch ticket details AND comments (needed for ARTIFACT-mode detection)

Use `mcp__atlassian__getJiraIssue` with:
- `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
- `issueIdOrKey`: the **resolved Jira key** (e.g., if ticket name is `TRIDENT-655-TEST-2`, use `TRIDENT-655`)
- `fields`: include `"comment"` alongside the standard fields (title, description, status, etc.) — the comment list is required for the ARTIFACT-mode check below, not optional.

### Step 1.5: Check for ARTIFACT mode (ALWAYS run this before Step 2 — see "ARTIFACT mode" below)

Scan the comments returned in Step 1 for the artifact marker. **If found, skip Steps 2–3 entirely** — go straight to the "ARTIFACT mode" section below, which replaces the rest of intake. **If not found**, proceed to Step 2 as normal (this is the existing, unchanged Jira-fields path).

### Step 2: Fetch Acceptance Criteria (skipped in ARTIFACT mode)

Run `/fetch-jira-acceptance-criteria` with the **resolved Jira key** (e.g., `TRIDENT-655`). This skill handles the custom field lookup, ADF parsing, and fallback logic. If the custom field is empty, fall back to parsing the description body for an "Acceptance Criteria" section.

### Step 3: Extract all inputs (skipped in ARTIFACT mode)

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

## ARTIFACT mode

**Why this exists:** some tickets are created and owned by a PO, and editing the Jira ticket's own Description/AC fields isn't practical (process, permissions, or the PO's workflow doesn't want engineering edits landing there). ARTIFACT mode lets the ticket content live on a separate artifact page that mirrors what the Jira ticket would otherwise contain, while the Jira ticket itself stays untouched and continues to drive the normal workflow (status, assignee, worklog, comments).

### Detection (runs automatically — never a CLI flag, never asked about)

In Step 1.5, scan every comment body on the ticket (fetched in Step 1) for a **case-insensitive substring match** on `ticket driver artifact:`. The match does not need to be a prefix or the whole comment — it can appear anywhere in the comment body.

- **Zero matching comments** → ARTIFACT mode is OFF. Proceed to Step 2 (existing Jira-fields path) as if this section didn't exist.
- **One or more matching comments** → ARTIFACT mode is ON. If more than one comment matches, use the **most recently created** one (by the comment's `created` timestamp) — this lets the operator supersede an old artifact link by posting a newer comment, no cleanup required. Extract the URL immediately following the matched phrase (the first `http(s)://` token after the colon).

Example matching comment bodies (all are valid matches):
```
Ticket Driver Artifact: https://claude.ai/artifacts/abc123
ticket driver artifact: https://claude.ai/artifacts/abc123
FYI — Ticket Driver Artifact: https://claude.ai/artifacts/abc123 (updated 7/6)
```

### Fetching and parsing the artifact (ONLY when ARTIFACT mode is ON)

1. **Fetch the artifact page** via `WebFetch` on the extracted URL.
2. **On fetch failure** (404, access denied, any error) — **STOP. Do NOT fall back to the Jira ticket's own fields.** Falling back would silently reintroduce the exact staleness problem ARTIFACT mode exists to avoid, without the operator necessarily noticing a fallback happened. Report clearly:
   ```
   ✗ ARTIFACT mode detected (comment from <date>) but the URL failed to fetch:
     <url> → <error>

   Not falling back to Jira ticket fields — that would silently reintroduce
   the staleness this mode exists to avoid.

   Fix the artifact link (edit or delete the marker comment), then re-run.
   ```
   Then stop — do not proceed to planning.
3. **On fetch success, parse the artifact's content by heading**, expecting the exact same section headings `/ticket-creator` produces (this is the shared contract between the two skills — an operator can take ticket-creator's output and publish it as the artifact verbatim instead of pasting it into Jira):
   - `## Story` → **User Story**
   - `## Description` → **Description**
   - `## Technical Details` → **Documentation** (this is ARTIFACT mode's equivalent of the Jira-fields path's "Documentation" section — same downstream field, different source heading, because it mirrors ticket-creator's naming rather than legacy Jira ticket conventions)
   - `## Testing Methodology` → carried into the plan's Task Breakdown / Commands sections where relevant, same as any other testing guidance the operator provides
   - `## Acceptance Criteria` → **Acceptance criteria** (replaces Step 2's `/fetch-jira-acceptance-criteria` call entirely — do not call that skill in ARTIFACT mode)
   - `## Deployment Notes` → **Constraints** (deployment/environment constraints feed the same downstream field manual-mode "Constraints" would)
   - `## Rollback Steps` → **Constraints** (append alongside Deployment Notes if both are present)

   A heading that's missing or empty in the artifact is simply absent downstream (same as an optional Jira field being empty) — do not invent content to fill a gap. If something load-bearing is missing (e.g. no Acceptance Criteria section at all), ask the operator one crisp clarifying question per the existing Guardrails rule — do not guess.

4. **Exclusivity (HARD RULE):** in ARTIFACT mode, the artifact is the **sole** source for Story/Description/Technical Details/Testing Methodology/Acceptance Criteria/Deployment Notes/Rollback Steps.
   - **Do NOT** merge in the Jira ticket's own Description/AC fields — ignore them entirely for content purposes even though they were fetched in Step 1.
   - **Do NOT** solicit or merge manual inputs for this content either — the "Option 1 / Option 2" choice in "What to ask the operator" below is skipped entirely in ARTIFACT mode.
   - This is a deliberate divergence from the standard Jira+Manual merge rules ("Input merging rules" below) — ARTIFACT mode replaces that entire section, it does not participate in it.
5. **Ticket name, branch, PR, Jira lifecycle mechanics are UNCHANGED.** ARTIFACT mode only changes where descriptive content comes from. The Jira ticket number still drives branch naming, PR title, status transitions, worklog hours, the QA Pass comment, and session logging exactly as in Standard mode (see "Scope" note — nothing about the ticket's lifecycle changes, only its content source).
6. **Output format / Data Source label:** render as `Artifact (<url>)` instead of `Jira` / `Manual` / `Jira + Manual overrides` (see "Output format" below).

---

## What to ask the operator

**Skip this "Option 1 / Option 2" choice entirely if ARTIFACT mode is ON** (detected in Step 1.5) — the content source is already fully resolved (the artifact), there is nothing to ask. Jump straight to "Jira finalization on success" and the "E2E Test Plan" prompts below, which still apply unchanged in ARTIFACT mode (they're operational planning questions, unrelated to where the ticket's descriptive content comes from).

**Otherwise (ARTIFACT mode OFF), first ask if the user wants to provide a Jira ticket number OR manual inputs:**

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
- This value is used after the E2E test passes (or after the rest of the flow completes when E2E is skipped) to: (a) in standard mode, transition the ticket to **"Ready for QA"** — **skipped in TODO-MODE**, (b) assign the ticket to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`), (c) log the hours as a worklog entry via `mcp__atlassian__addWorklogToJiraIssue`. (b) and (c) run in both modes.

### E2E Test Plan (ALWAYS draft + confirm during the planning phase, before the plan review loop)

- First, ask: **"Do you want to include an E2E test (Playwright CLI) as the final step? (yes/no — default: yes)"**
- **If the user says no / skip / no E2E:** do NOT continue with the proposal. Omit the E2E Test Plan section from the plan output, omit the E2E task from the HIGH LEVEL PLAN and Task Breakdown, and omit the E2E checklist item from the PLAN-MODE plan.md. Note in the plan output: "E2E test: skipped by operator."
- **If the user says yes (or default):** **draft a 3-item proposal first**, using your understanding of the ticket's changes (which funnel/flow they touch, which events/UI they affect) plus any relevant entry from `~/.claude/memory/E2E/<projectDir>/learnings.md` (already read in step 4 of the workflow). Present all 3 items together as a single proposal and ask the user to **confirm or update each one**. Format the proposal exactly like this:

  ```
  ### Proposed E2E Test Plan — please confirm or update each item

  1. **URL(s) to use:**
     - URL 1: <proposed URL>
       (e.g., for the Combined funnel: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true)
     - URL 2 (only if this ticket's E2E scenario genuinely needs a second, independent starting point — e.g. testing two separate funnel entry points in the same run — omit entirely if there's only one): <proposed URL>

  2. **How to deploy** (**stage-trident only — production deployment is FORBIDDEN**): <proposed command>
     (e.g., to deploy hosting + the modified functions:
     `firebase --project stage-trident deploy --only hosting:dynamic-app,functions:lendAPIWebhook,functions:getLendAPIApprovalData`)

  3. **How to verify passing:** <proposed verification approach with concrete pass/fail rule + evidence>
     (e.g., "After completing the funnel through the Submitted tab, run `playwright-cli eval \"() => JSON.stringify(window.dataLayer || [])\"` and confirm the `lead_submitted` and `application_submitted` entries each contain `approval_odds: <number>` and `approval_outcome: <string>`. Capture full dataLayer JSON + final-page screenshot.")
  ```

  **URL confirmation is explicit, not a rubber stamp (MANDATORY — this is the single most common source of a wasted E2E run, so treat it accordingly):** after presenting the proposal above, if the operator's reply confirms the overall plan without specifically addressing item 1, **do not treat that as URL confirmation.** Follow up with a direct, dedicated question naming every URL verbatim, e.g.: *"Before I proceed — please double-check this specific URL is correct (domain, product/listing ID, query params): `<URL>`. Reply with the exact corrected URL if not, or 'confirmed' if it is."* Ask this once per URL if there's more than one. Do not start execution until every URL in the plan has an explicit, URL-specific confirmation on record — a general "looks good" to the 3-item block is not sufficient by itself for this one item, precisely because a wrong URL invalidates the entire E2E run without failing loudly (the test may still "pass" against the wrong page).

- **Drafting heuristics — use ticket understanding to populate each item:**
  - **URL(s)** — derive from the ticket's funnel scope (Combined, FullApp, Prequal, Internal). Default to the QA stage URL with `prodTesting=true` when the ticket affects a LendAPI funnel. Check `~/.claude/memory/E2E/<projectDir>/learnings.md` for known-good URLs and known-blocked domains. **Identify every distinct starting point the E2E scenario actually needs** — most tickets need exactly one URL, but if the ticket's scope spans more than one independent funnel entry point (e.g., a shared component change that must be verified on both Combined and FullApp), propose one numbered URL per entry point rather than picking just one and hoping it's representative.
  - **Deploy command** — propose the minimum stage-only command that covers the modified surface: hosting if `dynamic-app/` changed, function names from `functions/src/index.ts` if backend changed, both if both. **Always prefix with `--project stage-trident`** to make the safety guarantee explicit. **Never propose a command that targets `trident-funding` or omits `--project`.**
  - **How to verify passing** — must combine a **pass/fail rule** (specific DOM text, specific GA event payload, specific final URL, absence of specific console errors) with the **evidence to capture** (dataLayer JSON dump, screenshot, console log, network request). Tailor to what the ticket changed: GA-event tickets capture `window.dataLayer`; UI tickets capture screenshots; backend tickets capture network responses or function-output console logs.

- **Capture the confirmed/updated answers verbatim** — including every explicitly-confirmed URL — and store them as the **E2E Test Plan** section in the plan output. The execution phase uses these for the snapshot-then-act loop.

- **Mid-execution updates to "How to verify passing" are allowed but must be documented:** During execution, the executor may discover that the agreed verification approach doesn't work as expected (e.g., the dataLayer is on a child iframe instead of the parent, the expected console log is gated behind a feature flag, the screenshot target re-renders mid-capture). The executor MAY switch to a different verification approach IF AND ONLY IF:
  1. It first attempted the agreed approach and observed a concrete failure (not a guess that something else would be easier).
  2. The new approach successfully validated the same pass/fail intent (i.e., still proved the AC is met).
  3. The post-test report (whether success report or `E2ETEST-Report.md`) documents BOTH the originally-agreed verification approach AND the alternate that was used, with a one-line "why the original didn't work."

  Mid-execution updates to **any confirmed URL** or the **Deploy command** are NOT allowed without operator approval — those are safety-critical (wrong URL = invalid test, wrong deploy command = potential production touch). Stop and ask if either needs to change.

### Input merging rules

**Does not apply in ARTIFACT mode** — see "ARTIFACT mode → Exclusivity" above. These rules govern only the Jira-fields path (ARTIFACT mode OFF).

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
  4. Run `/codex-review` with the PR URL in autonomous mode — **pre-clean pass** (runs first, synchronously within this session via an independent Opus 4.8 subagent review — no waiting on external bots; pre-empts Bugbot findings → fewer review-pr-comments iterations)
  5. Run `/review-pr-comments` with the PR URL in autonomous mode to auto-fix reviewer feedback (terminal convergence loop among the auto-pushers)
  6. Run `/codex-review` with the PR URL in autonomous mode again — **final pass** on the now-final diff (auto-fix + push any remaining real issues; any late Bugbot comment from this push is reaped by `jira-sprint-manager` Rule C's pre-merge gate — do NOT loop back to review-pr-comments)
  7. E2E test using Playwright CLI — drive the funnel manually with snapshot → click/fill → snapshot (do NOT rely on bundled flow scripts; see [e2e.md](e2e.md)). Check `playwright-cli --help` for available commands. Use the URL, test items, and capture criteria collected during planning. **NEVER ask the operator how to proceed with the E2E step** — the plan-review loop already authorized "run E2E + allow up to 5 deploys with `--fix-and-retry`". Do not use `AskUserQuestion` or numbered-option prompts here; do not pause for deploy approval (the plan-review confirmation IS the explicit approval; stage-only safety guards inside `e2e-test-jira-ticket` are the binding check). **Omit this step entirely if the operator opted out of E2E testing during planning.**
  8. **On E2E pass: post "QA Pass" Jira comment** via `mcp__atlassian__addCommentToJiraIssue` using the structured format from [qa-pass-comment-template.md](qa-pass-comment-template.md). Title: `# QA Pass (Automated E2E Execution) ✅`. **Skip if E2E failed (`E2ETEST-Report.md` exists) or E2E was opted-out during planning** — there is no proof to attach.
  9. **Jira finalization (only on success — E2E passed, or E2E skipped during planning):** assign to Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`), log the hours collected during planning via `mcp__atlassian__addWorklogToJiraIssue`, and post a `Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>` marker comment (the `Ticket Driver Implementation Completed (<REPO_NAME>)` prefix, repo name included, is what a future run's pre-run Guard step checks for to avoid re-running on this ticket **for this same repo** — the same Guard also checks for a `Ticket Driver Implementation Started (<REPO_NAME>): <timestamp>` comment that this run itself posted right before execution began; a marker for a different repo on the same ticket never blocks this one). **Standard mode also transitions** the ticket to "Ready for QA" — **TODO-MODE does NOT transition it** (the ticket is expected to still be in a TODO-column status the whole time; that mode's whole point is finishing the work ahead of the ticket being picked up). **Skip the entire finalization (transition + assign + log + marker comment) if (a) E2E failed after 5 iterations** (an `E2ETEST-Report.md` was written), **OR (b, standard mode only) the ticket's current Jira status is not "In Progress"** (re-fetch via `mcp__atlassian__getJiraIssue` immediately before mutating; this prevents re-runs on already-finalized tickets from regressing state — TODO-MODE skips this particular check since "not In Progress" is its expected, normal state, not a re-run signal). On skip, print a clear message naming the reason and continue.

  **Review-ordering rationale (codex-review → review → codex-review):** `/codex-review` (an independent Opus 4.8 subagent review that runs synchronously within this session — no Codex CLI involved despite the name; see its SKILL.md) *produces* Bugbot work when it pushes; `/review-pr-comments` is the only *consumer* of Bugbot/human PR threads. So `/codex-review` runs first (pre-clean, fewer Bugbot comments → fewer review iterations), `/review-pr-comments` runs in the middle as the loop-until-clean convergence step, and a final `/codex-review` pass gives the last correctness word on the final diff. The final push's possible late bot comment is caught downstream by `jira-sprint-manager` Rule C's unresolved-thread merge gate — so ticket-driver does not loop back.

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
    9. Run /codex-review with PR URL in autonomous mode (pre-clean pass)
    10. Run /review-pr-comments with PR URL in autonomous mode
    11. Run /codex-review with PR URL in autonomous mode (final pass on the final diff)
    12. E2E test using Playwright CLI (URL, what to test, captures from planning)
    13. On E2E pass: post "QA Pass (Automated E2E Execution) ✅" Jira comment with structured evidence (skip if E2E failed or opted out)
    14. On success: assign to Fabiano Desouza, log <hours> hours, post "Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>" marker comment (repo-scoped); standard mode also transitions to "Ready for QA" if Jira status is "In Progress" (otherwise skip finalization — re-runs on already-finalized tickets are a no-op); TODO-MODE always skips the transition (ticket is expected to still be outside "In Progress")
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
- **Codex Review — pre-clean pass**: Run `/codex-review` (independent Opus 4.8 subagent review, runs synchronously within this session — no Codex CLI involved) with the PR URL in autonomous mode to auto-fix its findings FIRST; pre-empts Bugbot findings so the next step runs fewer iterations
- **Review PR Comments**: Run `/review-pr-comments` with the PR URL in autonomous mode to auto-fix any reviewer feedback (terminal convergence loop)
- **Codex Review — final pass**: Run `/codex-review` with the PR URL in autonomous mode again — final correctness pass on the now-final diff; auto-fix + push any remaining real issues. Any late Bugbot comment from this push is reaped by `jira-sprint-manager` Rule C's pre-merge gate; do NOT loop back to review-pr-comments.
- **E2E Test (Playwright CLI)** *(omit this task entirely if the operator opted out of E2E testing during planning)*: Run an E2E test using Playwright CLI. **Drive the funnel manually with `playwright-cli` snapshot → click/fill → snapshot — do NOT rely on any bundled funnel-driving scripts (`*-flow.sh` wrappers); UIs drift faster than scripts get maintained. See [e2e.md](e2e.md) for the loop.** Check `playwright-cli --help` for available commands. Use the **E2E Test Plan** captured during planning (URL, what to test, what to capture). **On failure, run a fix-and-retry loop (max 5 iterations): investigate → fix code → commit/push → re-run the same E2E test.** If still failing after 5 iterations, write `E2ETEST-Report.md` at the project root with status, what's failing, what was tried each iteration, and suggested next steps.
- **QA Pass Jira comment (only on E2E pass)**: Post a structured comment to the Jira ticket via `mcp__atlassian__addCommentToJiraIssue` with title **`# QA Pass (Automated E2E Execution) ✅`** and the format defined in [qa-pass-comment-template.md](qa-pass-comment-template.md). The comment must include: run metadata (PR, branch, app version verified live, run date), what was tested (test URL, deploy command, tabs traversed), what was verified (AC-by-AC pass table), evidence (milestone dataLayer JSONs, direct smoke-test responses where applicable, screenshot paths), code-review iterations table (Cursor/Codex findings + fix commit SHAs), local artifacts list, and notes on anything surprising (e.g., funnel-specific quirks). **Skip if (a) E2E failed (`E2ETEST-Report.md` exists at project root), OR (b) operator opted out of E2E during planning** — there is no proof to attach.
- **Jira finalization on success**: Assign to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`), log **<HOURS>** hours via `mcp__atlassian__addWorklogToJiraIssue` (where `<HOURS>` is the value the operator provided during planning), and post a `Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>` marker comment (the `Ticket Driver Implementation Completed (<REPO_NAME>)` prefix, repo name included, is machine-matched by a future run's pre-run Guard check for that same repo — a `Ticket Driver Implementation Started (<REPO_NAME>): <timestamp>` comment was already posted right before execution began, for the same Guard to catch a concurrent run on the same repo even before this one finishes; a different repo on the same ticket is never blocked by either marker). **Standard mode also transitions** the ticket to **"Ready for QA"**; **TODO-MODE does not** — it leaves the ticket's status untouched so it's ready to transition the moment it's actually picked up later. **Skip the entire finalization (transition + assign + log + marker comment) if (a) E2E failed after 5 iterations** (an `E2ETEST-Report.md` was written), **OR (b, standard mode only) the ticket's current Jira status is not "In Progress"** — re-fetch via `mcp__atlassian__getJiraIssue` immediately before mutating; if it's already past finalization (e.g., re-running on a ticket already at "Ready for QA"), print a clear skip message and continue. (TODO-MODE never applies this particular check — being outside "In Progress" is its normal, expected state.) Run this even when E2E was skipped during planning.

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
- **Data Source**: [Jira | Manual | Jira + Manual overrides | Artifact (\<url\>)]
- **TODO-MODE**: [Yes — will NOT transition to "Ready for QA" on completion | No]
- **HIGH LEVEL PLAN** (concise task list for quick review — no ticket details)
- **Summary** (including user story if provided)
- **Technical Documentation** (if provided)
- **Acceptance Criteria → Tests**
- **Design Choice**
- **Task Breakdown (TDD-first)**
- **Commands (per tool permissions)**
- **Constraints** (if any)
- **E2E Test Plan** (3 confirmed items: 1) URL to use, 2) How to deploy [stage-trident only — production FORBIDDEN], 3) How to verify passing [pass/fail rule + evidence to capture] — drafted by the agent, then confirmed/updated by the operator; OR "Skipped by operator." if opted out)
- **Jira Finalization** (Hours to log on success — captured from the operator during planning. Assignee: Fabiano Desouza. Transition target: "Ready for QA" in standard mode — omit/mark "not transitioned (TODO-MODE)" when TODO-MODE is active. Posts a `Ticket Driver Implementation Started (<REPO_NAME>): <timestamp>` comment right before execution begins, and a `Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>` comment on successful finalization — both regardless of mode, both scoped to this run's own repo.)
- **Plan Review Loop Prompt** (repeat until "no further changes")
