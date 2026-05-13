# Rule B — Live-ticket follow-up (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step Jira fetches, the Live QA pre-check, the stakeholder-response heuristic, and the close-question handling.

## Trigger

The response contains at least ONE ticket whose `fields.status.name == "Live"`.

## Per-Live-ticket handling (apply in board order — top of the Live lane first)

1. **Fetch the ticket's comments.** Use `mcp__atlassian__getJiraIssue` with:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `fields`: `["comment"]`

   The same comment fetch serves both the Live QA pre-check (step 2) and the stakeholder check (step 3). If the result is too large for direct context, save-to-file is acceptable — the structure under `fields.comment.comments[]` exposes `body` (ADF or markdown depending on `responseContentFormat`) and `created` for each comment.

2. **Live QA pre-check — has Live QA been performed?**

   Before checking for a stakeholder review marker, determine whether Live QA has already happened on this ticket. Scan all comment bodies (case-insensitive) for the substring `live qa pass`. This matches:
   - **Automated Live QA** — the `e2e-test-jira-ticket` skill's Mode 3 posts a comment titled `# LIVE QA Pass ✅` after a successful live-qa run.
   - **Manual Live QA** — comments the operator posts that begin with phrases like `Live QA Pass`, `LIVE QA passed`, or similar variants. The case-insensitive `live qa pass` substring catches both.

   Set `LIVE_QA_DONE = true` if any comment matches, otherwise `LIVE_QA_DONE = false`.

   **Branch on `LIVE_QA_DONE`:**

   ### 2a. If `LIVE_QA_DONE == true`

   Skip the Live QA pre-check question — Live QA is already on record. Proceed to step 3 (stakeholder check).

   ### 2b. If `LIVE_QA_DONE == false`

   Append a yes/no question to the `QUESTIONS` list:

   ```
   <TICKET-KEY> is in Live but no Live QA Pass comment was found in the ticket history. Would you like to run automated Live QA via /e2e-test-jira-ticket --live-qa in the implementation session? (yes/no)
   ```

   **Apply the answer (during Step 6 / question-collection phase):**

   - **`yes` answer** → kick off automated Live QA in the resumed implementation session:

     1. **Read `~/.claude/memory/sessions.md`** with the Read tool. Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` (key followed by a parenthetical). If no matching heading is found, fall through to the no-session fallback below.

     2. **Find the topmost `## ticket-driver` subentry** in that ticket's section (newest-first ordering). Capture two fields from the bullets under it:
        - `session id: <uuid>` → `IMPL_SESSION_ID`
        - `repo/dir: <basename>` → `IMPL_REPO_DIR`

        Compute the absolute path as `/Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<IMPL_REPO_DIR>`.

        **No-session fallback:** if either (a) the ticket heading doesn't exist in sessions.md, (b) the section has no `## ticket-driver` subentry, or (c) the resolved absolute path doesn't exist on disk (`test -d` fails), SKIP the resume and:
        - Append to `actionsTaken`: `"Live QA kickoff skipped — no prior ticket-driver session found in sessions.md. Please run /e2e-test-jira-ticket <TICKET-KEY> --live-qa manually."`.
        - Append to `REMINDERS`: `"<TICKET-KEY>: Live QA needed but no implementation session was logged. Please run /e2e-test-jira-ticket <TICKET-KEY> --live-qa manually in your working worktree."`.
        - Skip the rest of Rule B for this ticket this run.

     3. **Open a new Claude session resuming the implementation session** via the helper script:
        ```
        /Users/fabianodesouza/.claude/skills/jira-sprint-manager/open-claude-session.sh \
          /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<IMPL_REPO_DIR> \
          --resume <IMPL_SESSION_ID> \
          --prompt "/e2e-test-jira-ticket <TICKET-KEY> --live-qa"
        ```
        The script opens a new iTerm2 tab (in the existing iTerm2 window if one is open; Terminal.app fallback if iTerm2 isn't installed) in the implementation worktree, runs `claude --resume <IMPL_SESSION_ID>` so the prior transcript is loaded, and immediately submits `/e2e-test-jira-ticket <TICKET-KEY> --live-qa` so the live-qa flow starts.

        If the script's exit code is non-zero:
        - Append to `actionsTaken`: `"Live QA kickoff failed — attempted to resume session <IMPL_SESSION_ID> in <IMPL_REPO_DIR> but open-claude-session exited <code>. Run /e2e-test-jira-ticket <TICKET-KEY> --live-qa manually."`.
        - Append to `REMINDERS`: similar message.
        - Skip the rest of Rule B for this ticket.

     4. **On success:** the implementation session is now driving Live QA in a separate iTerm2 tab. Append to `actionsTaken`: `"Live QA kicked off — resumed implementation session <IMPL_SESSION_ID> in <IMPL_REPO_DIR> with /e2e-test-jira-ticket <TICKET-KEY> --live-qa."`. Append to `REMINDERS`: `"<TICKET-KEY>: Live QA running in resumed session in <IMPL_REPO_DIR> — watch that iTerm2 tab for progress. The next run will see the Live QA Pass comment and re-evaluate."`.

     5. **Skip the rest of Rule B for this ticket this run** — the auto-resumed session handles Live QA; on the next run, the Live QA Pass marker will be present and Rule B will route to the stakeholder check (step 3).

   - **`no` answer** → operator opted out of automated Live QA. Skip the rest of Rule B for this ticket too — without Live QA proof, the stakeholder/close question doesn't make sense. Append to `actionsTaken`: `"Live QA skipped — operator declined; ticket remains in Live without Live QA verification on record."`. Append to `REMINDERS`: `"<TICKET-KEY>: Live QA needed but operator declined auto-run. Run /e2e-test-jira-ticket <TICKET-KEY> --live-qa manually if you want validation on record before closing."`.

3. **Stakeholder-review check** (only reached when `LIVE_QA_DONE == true`).

   Scan all comment bodies for a stakeholder-review pending marker. Match any of these substrings case-insensitively against the comment body text:
   - `pending stakeholder review`
   - `pending stakeholder` (partial — covers variants like "pending stakeholder sign-off")
   - `stakeholder review` (broader fallback, in case the wording is "stakeholder review pending" or similar)
   - `awaiting stakeholder`

   Find the **most recent** comment whose body contains ANY of these substrings. Capture its `created` timestamp as `T_PENDING`. If no comment matches, `T_PENDING = null`.

4. **If `T_PENDING` is not null, check whether the stakeholder has since responded.**

   Scan all comments with `created > T_PENDING`. A comment counts as "the stakeholder's response" if it is authored by **someone OTHER than the operator** (`author.accountId != "5a6765563c7f1842c3d7b806"`). This heuristic works because the pending-review request is always posted by the operator tagging the stakeholder; any subsequent non-operator comment is almost always the tagged stakeholder replying.

   - If at least one non-operator comment exists with `created > T_PENDING` → `STAKEHOLDER_PENDING = false` (stakeholder has reviewed; ticket is no longer gated). Capture the responder's display name and the timestamp for the audit trail.
   - If only operator comments exist after `T_PENDING` (or no comments at all after it) → `STAKEHOLDER_PENDING = true` (still gated; the stakeholder hasn't replied).

   If `T_PENDING == null` (no pending-review mention in any comment), set `STAKEHOLDER_PENDING = false`.

5. **Branch on the stakeholder check result:**

   **5a. If `STAKEHOLDER_PENDING == true`** (pending-review mention found AND no non-operator response after it):
   - Append `"Reminded u to follow up with stakeholder"` to the ticket's `actionsTaken` list.
   - Append a line to the in-memory `REMINDERS` list: `"<TICKET-KEY>: Follow up with stakeholder — comment in the ticket flagged a pending stakeholder review and there has been no response yet."`
   - Do NOT prompt the user. Do NOT transition the ticket. The reminder is the action.

   **5b. If `STAKEHOLDER_PENDING == false`** (either no pending-review mention, OR a stakeholder has since responded):
   - Append a question to the in-memory `QUESTIONS` list. The question text differs slightly so the operator sees the actual reason:
     - **No pending-review mention found:** `"<TICKET-KEY> is in Live with no pending stakeholder review mentioned in the comments — are we ready to close it? (yes/no)"`
     - **Pending-review mention but stakeholder has since responded:** `"<TICKET-KEY> is in Live and stakeholder <name> responded on <YYYY-MM-DD> after the pending-review request — are we ready to close it? (yes/no)"`
   - Do NOT append to `actionsTaken` yet — it stays empty until the operator answers (then either an action string is pushed or the list remains empty).
   - Do NOT transition or assign the ticket yet.

6. **After Rule B has scanned every Live ticket** — the global Step 6 in SKILL.md prints the Reminders / Questions sections and collects yes/no answers via `AskUserQuestion`. Rule B does NOT need to do the printing itself — only contribute to `REMINDERS` and `QUESTIONS`.

7. **Apply the close-question answers** (only if a step-5b question was queued) — happens during Step 6 of SKILL.md:
   - **`yes` answer** → close the ticket:
     1. Look up the transition ID for `Closed` via `mcp__atlassian__getTransitionsForJiraIssue`. Pick the transition whose `to.name == "Closed"` (case-sensitive). If no exact match, fall back to a case-insensitive substring match on `"closed"`.
     2. Execute `mcp__atlassian__transitionJiraIssue` with the captured ID.
     3. Assign the ticket back to the operator (Fabiano Desouza) via `mcp__atlassian__editJiraIssue`:
        - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
        - `issueIdOrKey`: the ticket key
        - `fields`: `{ "assignee": { "accountId": "5a6765563c7f1842c3d7b806" } }`
     4. Update the in-memory ticket: set `fields.status.name` to `"Closed"` and append `"Moved to Closed and assigned back to me"` to `actionsTaken`.
     5. The Step 3 sort places the ticket in priority bucket `1` (DONE column — `Closed` is already in the priority table alongside `Done` and `Cancelled`).
   - **`no` answer** (or any non-yes answer) → leave the ticket as-is:
     - Leave `actionsTaken` empty for this ticket (the operator chose not to close — no action to record).
     - Do NOT transition. Do NOT reassign.

## Failure modes

### Live QA kickoff (step 2b)
- No `## ticket-driver` entry in sessions.md for this ticket → manual-fallback action appended; operator runs `/e2e-test-jira-ticket --live-qa` themselves.
- `open-claude-session.sh` exits non-zero → kickoff-failed action appended; operator runs the slash command manually.

### Close transition (step 7)
- If `getTransitionsForJiraIssue` or `transitionJiraIssue` errors, append `"Close failed: <verbatim error>"` to `actionsTaken` and keep the original status. Print one terminal warning line.
- If the transition succeeded but the assign call failed, append `"Moved to Closed but assign failed: <verbatim error>"` to `actionsTaken`. Status stays as `Closed` (the transition already landed).

## Per-ticket question contract

Rule B asks **at most ONE question per ticket per run**. The order is:
- Live QA pre-check question (step 2b) takes precedence if Live QA hasn't happened.
- If Live QA has happened (step 2a), the stakeholder-close question (step 5b) may fire if the stakeholder check warrants it.

A ticket can never be in a state where both questions fire in the same run — by construction, step 2b skips the rest of Rule B for the ticket.
