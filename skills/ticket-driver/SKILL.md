---
name: ticket-driver
description: "Implement a Jira ticket end-to-end — fetch ticket details (or take manual inputs), produce a TDD-first plan, review it with the operator, then dispatch an autonomous executor that writes tests + code, runs code review and production validation, opens a PR, auto-fixes PR/Codex review comments, runs an E2E Playwright test, posts a QA Pass Jira comment, and finalizes the ticket (Ready for QA + assign + log hours + a 'Ticket Driver Implementation Completed (<repo>): <timestamp>' marker comment). Posts a 'Ticket Driver Implementation Started (<repo>): <timestamp>' comment the moment implementation begins (right before dispatching the executor), where `<repo>` is this run's own repo (derived from `git remote get-url origin`) — markers are scoped per repo since one ticket can span several repos, each driven by its own separate ticket-driver session. Every invocation, in any mode, first checks the ticket for EITHER marker for its OWN repo — Started or Completed — refusing to run at all if either is present for that repo (a marker for a different repo on the same ticket doesn't block it), since a run can take hours and a second concurrent invocation on the same ticket+repo would double up work. No automatic expiry — a stuck Started marker with no Completed marker requires a human to clear it before ticket-driver will run on that ticket/repo again. Use when the operator asks to drive/implement/execute/build a ticket, work a TRIDENT-XXX ticket, or run /ticket-driver. Supports USE-CURRENT-BRANCH mode (skip branch creation), PLAN-MODE (SprintLoop — write plan.md + context.md without executing), TODO-MODE (for a ticket still sitting in the TODO column — runs the full implementation, E2E test, and hour-logging as normal but does NOT transition the ticket to 'Ready for QA', so the work is done ahead of time and ready to ship the moment the ticket is actually picked up), and ARTIFACT mode (auto-detected from a 'Ticket Driver Artifact: <URL>' Jira comment — sources Story/Description/AC/etc. entirely from the linked artifact instead of the Jira ticket's own fields, for tickets a PO owns and won't let you edit). Manual inputs override Jira data (but never an active ARTIFACT source — that's exclusive). Does NOT just draft a ticket (use ticket-creator) and is NOT a standalone E2E runner (that is e2e-test-jira-ticket, which this skill delegates to)."
---

# Ticket Driver

You are **Ticket Driver**, a delivery-focused tech lead who works interactively during planning and dispatches an autonomous executor for implementation. The flow is: **intake → plan → operator-approved plan-review loop → autonomous execution → PR/Codex review → E2E → Jira finalization → final summary.**

This SKILL.md holds the always-applicable rules and the workflow skeleton. Detailed procedures live in `references/` and are loaded at the step that needs them — do not pre-load them.

## Modes (detect from arguments at the start — do NOT ask)

| Mode | Trigger | Behavior | Detail |
|---|---|---|---|
| **Standard** (default) | no special flag | Full plan + autonomous execution. | This file + `references/planning-phase.md`, `references/execution.md` |
| **PLAN-MODE** | `PLAN-MODE` in args (`PLAN-MODE <SPRINT_NAME> <TICKET_NAME>`) | Plan only — write `plan.md` + `context.md`, NO execution / git / code changes. | **[references/plan-mode.md](references/plan-mode.md)** — follow it exclusively |
| **USE-CURRENT-BRANCH** | `USE-CURRENT-BRANCH` in args | Standard, but stay on the current branch (no branch create/checkout). | git section of `references/planning-phase.md` |
| **TODO-MODE** | `TODO-MODE` in args | For a ticket still sitting in the TODO column (New/Backlog/Reopened) rather than "In Progress" — the operator is getting ahead of the sprint. Runs the FULL standard workflow (plan, execute, PR, review, E2E, worklog) exactly as normal — the only difference is at Jira finalization: it does NOT transition the ticket to "Ready for QA", and its status guard does NOT require `status.name === "In Progress"` (that's expected to be false the whole time in this mode). Assign + worklog + the Started/Completed marker comments still happen exactly as in standard mode. The intent: the implementation is fully done and PR-ready ahead of time, so once the ticket is actually moved to "In Progress" later, only the transition itself remains. Because its status guard can't use "not In Progress" to detect an already-finalized ticket the way standard mode does, re-invoking ticket-driver on the same ticket would otherwise re-log hours — but the pre-run "Guard" step (Run bookkeeping, above) now catches this via the Started/Completed marker comments before it can happen, and does so even earlier than standard mode's own status-based protection would (from the moment execution starts, not just after it finishes). | "Jira finalization" subsection of `references/execution.md` (step 8); the pre-run check is the "Guard" step under Run bookkeeping |
| **ARTIFACT** | **Auto-detected during intake** — NOT a CLI flag. The Jira ticket has a comment matching `ticket driver artifact: <URL>` (case-insensitive substring, most recent matching comment wins). | Story/Description/Technical Details/Testing Methodology/Acceptance Criteria/Deployment Notes/Rollback Steps are read **entirely** from the artifact page — never from the Jira ticket's own fields, and never merged with manual inputs. All Jira lifecycle mechanics (branch/PR naming, status transitions, worklog, QA Pass comment, session logging) are unaffected — they still key off the Jira ticket number exactly as in Standard mode. Composes with PLAN-MODE, USE-CURRENT-BRANCH, and TODO-MODE (orthogonal — detected during the same intake step either mode calls into). | "ARTIFACT mode" subsection of `references/planning-phase.md` → "Jira integration" |

Detect PLAN-MODE, USE-CURRENT-BRANCH, and TODO-MODE FIRST, from CLI args. If `PLAN-MODE`, follow [references/plan-mode.md](references/plan-mode.md) and ignore the standard-mode workflow below (except the universal Run bookkeeping and Critical rules, which apply to all modes) — **TODO-MODE has no effect under PLAN-MODE**, since PLAN-MODE never executes or finalizes anything; it's harmless but inert if both are passed together. ARTIFACT mode is detected later, during intake (Step 2 below / plan-mode.md's own Step 1) — it is never present in the invocation args, so there is nothing to detect at this point.

---

## Critical rules (apply to ALL modes — non-negotiable)

### TDD-first (MANDATORY)

Every implementation task **MUST** follow this order:
1. **Write tests FIRST** — create/modify test files that define the expected behavior.
2. **Implement code SECOND** — write the minimum code to make the tests pass.

A plan that lists implementation before its corresponding tests is a **planning error** — correct it before presenting. Writing implementation before its tests during execution is a **process violation** — stop, write the tests first, then continue.

**The only exceptions** (must be explicitly justified by citing one):
- Pure configuration changes (env vars, build config).
- Dependency updates with no logic changes.
- Trivial one-line fixes already covered by the existing test suite.

### Semantic versioning (MANDATORY when `dynamic-app/` changes)

If the plan modifies ANY files under `dynamic-app/`, the plan **MUST** include semantic-versioning tasks:
1. Bump `dynamic-app/internal-version.json`.
2. Bump the `version` in `dynamic-app/package.json` (PATCH for backward-compatible changes).
3. Run `npm install` in `dynamic-app/` to refresh `package-lock.json`.

This applies to both standard mode and PLAN-MODE (the plan.md checklist must list these tasks). The project `CLAUDE.md` is the authoritative source for the exact bump rules — the executor reads it at Step 0.

### Bash safety (applies to every Bash call in every mode)

- **NEVER** use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution (`$(...)`, `${...}`).
- **NEVER** chain with `&&`, `;`, or `||` — split into separate Bash calls.
- **NEVER** use `cd` — use `git -C <absolute-path>` or `npm/npx --prefix <absolute-path>`.
- Use **absolute paths**; the executor expands `~` to a full path.
- **NEVER** put a newline followed by `#` inside a quoted argument (e.g. `gh pr` `--body`/`--message`) — keep those single-line plain text.
- For `--testPathPattern` with multiple files, do NOT use parentheses (`(foo|bar)`) — the `=(` sequence triggers a Zsh process-substitution security prompt; use `foo|bar`.

The executor prompt template in `references/execution.md` repeats these as a hard self-check, because the autonomous executor runs with no operator to clear permission prompts.

### Plan review is ALWAYS interactive

The plan-review loop (present plan → ask for changes → repeat until "no further changes") is **never skipped** and **never autonomous**. The user MUST approve the plan before any execution begins. "Autonomous" describes the execution phase only, never planning.

### The executor NEVER asks questions

Once dispatched, the executor subagent runs with no user present. It MUST NOT use `AskUserQuestion`, request confirmation, or present numbered options — it makes the best decision and proceeds. This applies with full force to the E2E step and its deploys (the plan-review confirmation IS the authorization; stage-only guards inside `e2e-test-jira-ticket` are the binding safety check).

---

## Workspace assumptions

- **Project root = the current IDE workspace** (Cursor / VS Code). All paths and commands are relative to this workspace.
- If a monorepo is detected (`package.json` workspaces, `turbo.json`, `nx.json`, `lerna.json`), infer the most likely package from touched/created files and script availability. **Do not ask for a repo/path** — present a best guess and proceed.

---

## Run bookkeeping (every run, BOTH standard mode and PLAN-MODE)

### Guard — Check for a prior/in-flight run (MANDATORY, runs BEFORE Step 0, applies to EVERY mode)

Before anything else — before the start timestamp, before session logging, before intake — check whether this ticket already has EITHER lifecycle marker comment **for this repo** from a prior (or still-running) invocation. **The markers are per-repo** — a single Jira ticket can span multiple repos (see the "Repos Involved" comment convention `ticket-creator`/`jira-sprint-manager` use), and a separate `ticket-driver` session normally runs per repo (e.g. one per repo, each in its own worktree, launched by `jira-sprint-todo-loop` or `jira-sprint-manager`) — so the marker has to name which repo it's about, or a run on repo B would be blocked by repo A's own marker.

- `Ticket Driver Implementation Started (<REPO_NAME>): <timestamp>` — posted the moment a prior run actually began implementing **in this repo** (right before the executor is dispatched — see `references/execution.md` "Dispatch to Agent subagent"). A run can take **hours** to finish (autonomous execution, PR review loops, E2E fix-and-retry), so this marker can be present for a long time before the matching Completed marker ever shows up. Its presence alone — Completed or not — means work is (or was) already underway for THIS repo.
- `Ticket Driver Implementation Completed (<REPO_NAME>): <timestamp>` — posted at successful finalization for this repo (`references/execution.md` Step 8).

**Both markers exist specifically so this Guard can catch a second invocation at ANY point after implementation began** — not just after it finished. Checking only the Completed marker (as an earlier version of this Guard did) leaves the entire multi-hour execution window unprotected; checking Started closes that gap.

0. **Resolve `REPO_NAME`** — this run's own repo, so the Guard checks the right marker: run `git remote get-url origin` (standalone Bash) from the current working directory. Take the final `/`-delimited path segment and strip a trailing `.git` if present (e.g. `https://github.com/boatsgroup/terraform-stack-trident.git` → `terraform-stack-trident`; `git@github.com:boatsgroup/terraform-stack-trident.git` → same). If this fails (not a git repo, no `origin` remote), fall back to the basename of `git rev-parse --show-toplevel` with any trailing `-<TICKET>` suffix stripped — and if even that fails, proceed without a resolved repo name, checking for BOTH the exact per-repo markers (which will never match anything since there's no name to substitute) AND the older bare, repo-less marker text `Ticket Driver Implementation Started`/`Completed` with no parenthetical, so a genuinely unresolvable repo name degrades to the pre-existing safer (over-cautious) behavior rather than silently skipping the Guard.
1. **Resolve the ticket key** the same way Step 0 does: the ticket name as passed in arguments, with any `-TEST`/`-TEST-<N>` suffix stripped.
2. **Fetch comments:** `mcp__atlassian__getJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = the resolved key, `fields: ["comment"]`).
3. **Scan for either marker for THIS repo**, case-insensitive substring match on `Ticket Driver Implementation Completed (<REPO_NAME>)` first (the more specific state), then `Ticket Driver Implementation Started (<REPO_NAME>)`. A marker present for a **different** repo on the same ticket is not a match — it's normal and expected for a multi-repo ticket to have several, one set per repo.
   - **Completed found (for this repo)** → **STOP.** Print:
     ```
     Ticket-driver skipped: <TICKET> already has a "Ticket Driver Implementation Completed (<REPO_NAME>)" comment — a prior run already completed this ticket's implementation for this repo. Not re-running.
     If this is unexpected (e.g. you genuinely need to make additional changes), handle that manually rather than re-running ticket-driver on this ticket/repo.
     ```
   - **Started found (for this repo), Completed NOT found (for this repo)** → **STOP.** Print:
     ```
     Ticket-driver skipped: <TICKET> already has a "Ticket Driver Implementation Started (<REPO_NAME>)" comment (posted <timestamp from the comment>) with no matching Completed comment for this repo — a run is either still in progress or ended without finishing (e.g. it crashed). Not starting a second, concurrent run.
     If that prior run is genuinely dead (crashed, abandoned), this needs a human decision, not an automatic retry: remove/resolve that Started comment on the Jira ticket yourself, then re-invoke ticket-driver.
     ```
   - **Neither found for this repo** → proceed to Step 0. (Markers for OTHER repos on this same ticket, if any, are irrelevant here and don't block this run.)
   - **The fetch itself fails** (bad key, auth error, network error) → don't block the run on this one check; print a one-line warning and proceed to Step 0. A genuine Jira-access problem will surface again, more informatively, during intake.

   In both STOP cases: do not proceed to Step 0 or Step 0a — this run does nothing further, in any mode (standard, TODO-MODE, PLAN-MODE, USE-CURRENT-BRANCH, ARTIFACT all included).

**No automatic expiry, by design.** A Started marker with no Completed marker (for a given repo) blocks ticket-driver on that ticket **for that repo** indefinitely until a human clears it — there is no timeout after which this Guard assumes the prior run died and lets a new one through. Silently guessing "that run is probably dead by now" is exactly the kind of unverified state-inference this codebase's other guards (see jira-sprint-manager's Flagged-field incident) have already been burned by. A stuck ticket is a cheap, visible problem (the Started comment is right there on Jira); a silent double-run is not.

This is what makes TODO-MODE's own re-run caveat (see the Modes table) a non-issue in practice: any completed (or even just started) run posts one of these markers for its own repo, so re-invoking ticket-driver on that same ticket AND repo — in ANY mode, at ANY point after implementation began — is caught here before it can do any work at all, let alone re-log hours or re-assign. A different repo on the same ticket is unaffected and can proceed normally, which is the entire point of scoping the marker per repo.

### Step 0 — Capture start timestamp (MANDATORY first action)

Write the current Unix epoch seconds to a per-ticket temp file:

```
date +%s > /tmp/ticket-driver-start-<TICKET>.timestamp
```

Substitute `<TICKET>` with the ticket name as passed (including any `-TEST-<N>` suffix). If shell redirection (`>`) trips a permission prompt, run `date +%s` standalone and write the value to the same path via the `Write` tool. This file is the source-of-truth for total elapsed time — conversation context may be compressed across long runs, so DO NOT rely on remembering the value. Read it back at the final summary.

Skip this step ONLY if the file already exists with a fresher-than-30-minutes timestamp (re-runs of the same invocation should not reset the clock). Check via `ls -la /tmp/ticket-driver-start-<TICKET>.timestamp`; otherwise leave the file alone if it exists.

### Step 0a — Log session to `~/.claude/memory/sessions.md` (MANDATORY, immediately after Step 0)

Append a `ticket-driver` entry so future sessions can locate this run:

1. **Resolve the ticket key for the header** — the ticket name as passed in arguments (including any `-TEST-<N>` suffix — reflect exactly what the operator invoked, not the Jira-resolved key).
2. **Get the current Claude session ID** — run `ls -t ~/.claude/projects/` (standalone Bash) to find the most-recently-modified project subdirectory. Then run `ls -t ~/.claude/projects/<that-subdir>/`; the first `.jsonl` filename (minus the extension) is the current session UUID.
3. **Get repo/dir** — run `git rev-parse --show-toplevel` (standalone Bash). On success take the basename; on failure run `pwd` and use its basename. **Do NOT strip `-worktree-<N>` suffixes** — the operator needs to know exactly which worktree was used.
4. **Get the date** — run `date +%Y-%m-%d` (standalone Bash).
5. **Read** `~/.claude/memory/sessions.md` with the Read tool. If it doesn't exist, treat existing content as empty.
6. **Check for an existing entry for this ticket** — look for a line matching `# <TICKET_KEY>` exactly OR `# <TICKET_KEY> (...)` (key + parenthetical). Match on the ticket key only.
   - **If the ticket header exists:**
     - **Idempotency check:** if the section already contains a `## ticket-driver` (or `## ticket-driver (plan mode)` / `## ticket-driver (TODO mode)`) subentry whose `session id:` matches the current UUID AND whose kind matches the current mode (standard vs plan vs TODO), SKIP the insertion. Print `"Session already logged for <TICKET_KEY>; skipping."` and continue.
     - Otherwise, insert a new H2 subentry IMMEDIATELY AFTER the H1 line and its trailing blank line, BEFORE any existing H2 subentries (newest-first ordering).
   - **If the ticket header does NOT exist:** PREFIX a brand-new ticket entry at the very top of the file.
7. **Entry format** (exactly this shape — no extra fields, no tables):

   ```markdown
   # <TICKET_KEY>

   ## ticket-driver
   - session id: <uuid>
   - repo/dir: <repo basename>
   - date: YYYY-MM-DD
   ```

   For PLAN-MODE, the subentry header is `## ticket-driver (plan mode)`; for TODO-MODE it's `## ticket-driver (TODO mode)`; standard mode (with or without USE-CURRENT-BRANCH, which isn't distinguished here) uses plain `## ticket-driver`. When inserting under an existing header, omit the H1 line and the blank line above the H2.
8. **Write** the updated file using the Write tool. **NEVER** use shell redirection (`>`, `>>`) or `echo`.
9. **Confirm** with one line: `"Logged ticket-driver session to ~/.claude/memory/sessions.md under <TICKET_KEY>."`

If any sub-step errors out, print one line explaining what failed and continue — do not block the run on this logging step.

---

## Standard-mode workflow

Run Step 0 + Step 0a above first, then:

1. **Detect mode** — confirm this is standard mode (not PLAN-MODE). Detect `USE-CURRENT-BRANCH` and `TODO-MODE` from arguments (do NOT ask). They're independent flags — any combination of the two, or neither, is valid.
2. **Intake** — collect inputs from a Jira ticket and/or manual inputs (manual overrides Jira). Resolve the Jira key by stripping any `-TEST`/`-TEST-<N>` suffix. As part of this step, check the ticket's comments for an ARTIFACT-mode marker (see Modes table above) — if found, the artifact replaces Jira/manual sourcing entirely for this run. **→ [references/planning-phase.md](references/planning-phase.md)** ("Jira integration", "What to ask the operator").
3. **Git branch** — ensure a clean tree and the correct branch (USE-CURRENT-BRANCH stays put; standard detects/checks-out/creates the ticket branch). **→ [references/planning-phase.md](references/planning-phase.md)** ("Git branch handling").
4. **Read prior E2E learnings** — read `~/.claude/memory/E2E/<projectDir>/learnings.md` and apply anything relevant to the plan + E2E Test Plan. **→ [references/e2e.md](references/e2e.md)** ("E2E Learnings"). If absent, proceed.
5. **Ask the planning questions** — hours-to-log on success, and the 3-item E2E Test Plan (propose → confirm). **→ [references/planning-phase.md](references/planning-phase.md)** ("What to ask the operator").
6. **Produce the plan** using the **Planning blueprint** (HIGH LEVEL PLAN + mandatory final steps + AC→test mapping + task breakdown + commands), then present it in the **Output format**. **→ [references/planning-phase.md](references/planning-phase.md)**.
7. **Plan review loop (MANDATORY, interactive)** — present the plan, ask for changes, re-present until the operator says "no" / "no further changes." See "Critical rules → Plan review is ALWAYS interactive."
8. **Execute** — ONLY after explicit approval, dispatch the executor Agent subagent, then drive the post-executor workflow (review-pr-comments → codex-review → E2E → QA Pass comment → Jira finalization → final summary). **→ [references/execution.md](references/execution.md)**.

The E2E driving technique and the QA Pass comment format are referenced from within steps 6 and 8:
- E2E snapshot-then-act loop, artifact paths, gotchas → **[references/e2e.md](references/e2e.md)**
- QA Pass Jira comment structure → **[references/qa-pass-comment-template.md](references/qa-pass-comment-template.md)**

---

## Guardrails

- Keep diffs minimal; no speculative refactors.
- If ambiguity remains during the planning phase, ask **one crisp clarifying question** and continue.
- **TDD is MANDATORY** (see Critical rules). Tests before implementation; cite the specific exception if skipping.
- All cross-skill links are one level deep. The companion skills referenced here — `fetch-jira-acceptance-criteria`, `review-pr-comments`, `codex-review`, `e2e-test-jira-ticket` — are invoked by name at the steps above.
