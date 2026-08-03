# Rule A — Kickoff when nothing is In Progress (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step API calls, the flagged-skip behavior, and failure-mode handling.

**No operator question anywhere in this rule — by design, permanently.** An earlier version of this rule had a second path ("Path 2") that offered to pick up additional TO DO tickets via `AskUserQuestion`. That has been removed entirely, on explicit instruction: there is no longer any mechanism in Rule A that asks the operator whether to bring more tickets into In Progress, and none should be re-added. Rule A now has exactly one trigger and, within it, exactly one priority-ordered decision: check for a TODO-MODE-started ticket first, then fall back to the classic walk. Both are plain, no-question transitions.

## Trigger

The fetched ticket list contains ZERO tickets whose `fields.status.name == "In Progress"` AND at least ONE ticket anywhere in the TO DO column (`fields.status.name` in `New`, `Backlog`, or `Reopened` — see SKILL.md Step 3's status-priority table). This is broader than just "≥1 New" because Step 0 below needs to see the whole TO DO column, not only `New`; when nothing in the broader set actually qualifies, the rule still ends up doing nothing, same as before.

## Step 0 — TODO-MODE priority check (runs FIRST, before the classic candidate walk)

**Why this exists:** `jira-sprint-todo-loop` (and an operator running `ticket-driver ... TODO-MODE` by hand) can start — or even finish — a ticket's implementation while the ticket is still sitting in the TODO column, ahead of the sprint formally picking it up. Once that's happened, the Jira status should catch up to reality: the ticket should move to `In Progress`, but there is nothing left for Rule D to kick off (the worktree already exists, `ticket-driver` is already running or done there). This step recognizes that case and handles it as a pure status transition, distinct from a fresh kickoff.

1. **Build the candidate list.** Filter the fetched issues to `status.name` in `New`, `Backlog`, or `Reopened` (the full TO DO column), sorted ascending by `rank`.
2. **Walk the candidate list in rank order.** For each candidate:
   - **Flag check** — apply the "Flagged detection" rules below. If flagged, append the same kind of `REMINDERS` entry as the classic walk does (see below) and move to the next candidate. A flagged ticket is never auto-promoted by this step, even if it happens to have a TODO-MODE marker (e.g. it started before being flagged) — the flag guard takes priority.
   - **Marker check** — fetch/reuse this ticket's comments (already fetched in Step 2 of the main workflow) and scan for a **bare prefix match**, case-insensitive: `Ticket Driver Implementation Started (` or `Ticket Driver Implementation Completed (`. Unlike `ticket-driver`'s own per-repo Guard check, this scan does NOT care which specific repo is named in the parenthetical — ANY repo's marker (Started or Completed) is sufficient, since the point here is just "is implementation underway or done for this ticket, in at least one repo." If a match is found, this ticket is the target — capture its key as `KICKOFF_KEY` and break the loop.
   - No match on this candidate → move to the next.
3. **No candidate found.** If the loop exits without picking a `KICKOFF_KEY`, this step does nothing — fall through to the classic candidate walk below (unchanged behavior from before this step existed).
4. **Found — transition it.** Run the same transition mechanics as "Steps to perform the transition" below (`getTransitionsForJiraIssue` + `transitionJiraIssue`), but on success append a **different** action string: `"Moved to In Progress — TODO-MODE implementation already underway, no worktree/session needed"`. Then run "Ticket Type auto-classification" (below) exactly as the classic walk does.
5. **Mark the ticket `Rule-D-SKIP`** (a new, distinct in-memory marker — NOT `Rule-A-failed`). This is the critical difference from a normal kickoff: the transition genuinely succeeded (the ticket really is `In Progress` in Jira now), but Rule D must still skip it, because there's no worktree to create and no session to launch — `jira-sprint-todo-loop`/`ticket-driver TODO-MODE` already did that work. Rule D's own "Chain with Rule A" check (see `rule-d-worktree-kickoff.md` and SKILL.md's Rule D section) must treat `Rule-D-SKIP` as a second terminal condition alongside the existing `"Move failed: …"` check.
6. **Stop.** Whether this step found a target or not, Rule A picks at most one kickoff target per run — if Step 0 already picked one, the classic candidate walk never runs this cycle.

**Failure handling for this step** is identical to "Failure modes" below (a failed `getTransitionsForJiraIssue`/`transitionJiraIssue` call marks the ticket `Rule-A-failed`, not `Rule-D-SKIP` — a failed transition means the ticket ISN'T actually In Progress, so Rule D's normal "Move failed" skip check applies, not the TODO-MODE one).

### Worked example

TO DO column (rank order): `TRIDENT-980` (New, no marker), `TRIDENT-975` (Backlog, flagged), `TRIDENT-987` (Reopened, has a `Ticket Driver Implementation Started (terraform-stack-trident): 2026-07-29 11:06` comment from a `jira-sprint-todo-loop` launch two days ago, unflagged). Step 0 walks rank order: `TRIDENT-980` has no marker, skip. `TRIDENT-975` is flagged, append `REMINDERS`, skip. `TRIDENT-987` matches the marker prefix → `KICKOFF_KEY = TRIDENT-987`. Transition to `In Progress` succeeds → append `"Moved to In Progress — TODO-MODE implementation already underway, no worktree/session needed"`. Ticket Type is already set (ticket-creator set it at creation) → left as-is. Mark `TRIDENT-987` as `Rule-D-SKIP`. Rule A stops — `TRIDENT-980` was never evaluated by the classic walk this run, even though it would otherwise have been the top-of-New candidate.

## Classic candidate walk (only runs if Step 0 found nothing)

Transition the **highest-ranked, NOT-FLAGGED New ticket** (lowest `rank` value among unflagged status=`New` tickets — i.e., the top of the New lane on the board, skipping over any flagged entries) to status `In Progress`. If every New ticket is flagged, the rule exits without acting.

## "Flagged" detection

A ticket is considered **flagged** (and therefore ineligible for kickoff, in either Step 0 or the classic walk) when its `fields.customfield_10091` value is non-empty. The Jira "Flagged" field for the boats-group Trident project is a `multicheckboxes` custom field with one allowed value `{"id":"10115","value":"Impediment"}`. When the operator clicks the flag icon on a ticket, the field becomes `[{"value":"Impediment","id":"10115"}]`; an unflagged ticket reports it as `null`, missing, or an empty array.

**Pinned field id — DO NOT use the short name `flagged`.** This Jira REST API instance does NOT resolve the short-name `flagged` to `customfield_10091` — the short name returns `null` for every ticket and silently bypasses the flag guard. The field id was pinned to `customfield_10091` on 2026-05-20 after a production incident where Rule A kicked an actively-flagged ticket (TRIDENT-869, flag added 2026-05-13 by the operator) into In Progress because the JQL fetch used `flagged` instead of the canonical id. The skill MUST use the explicit `customfield_10091` field id from now on.

Treat any of the following as **flagged**:
- `fields.customfield_10091` is an array with `length > 0`.
- `fields.customfield_10091` is a non-empty string (some instances coerce to a string representation).
- `fields.customfield_10091` is a non-null object with at least one truthy property (rare; defensive only).

Treat any of the following as **unflagged**:
- `fields.customfield_10091` is missing/undefined.
- `fields.customfield_10091` is `null`.
- `fields.customfield_10091` is an empty array `[]`.
- `fields.customfield_10091` is an empty string.

**Why this matters:** the operator uses the flag to mark a ticket as blocked (e.g., a `Flag added — Blocked by TRIDENT-862` comment is auto-posted by Jira when the flag is set). Auto-moving a blocked ticket into In Progress would (a) trigger Rule D to spawn a research worktree for work that cannot start (classic walk) or misrepresent a blocked ticket as ready (Step 0), and (b) silently hide the blocker because the ticket leaves the TO DO column where the operator can see the flag at a glance.

**Field ID re-discovery procedure:** the JQL request in Step 2 uses the explicit `customfield_10091` field id (pinned for the boats-group Trident project — see above). If the field ever returns unset on tickets you KNOW are flagged in the UI (e.g., a Jira admin migrates the field, or this skill is re-used on a different project/instance), re-discover the canonical id via `mcp__atlassian__getJiraIssueTypeMetaWithFields` (look for a field whose name is "Flagged" or whose schema type is `multicheckboxes` with `Impediment` as the only allowed value) and update both SKILL.md Step 2 and this reference to the new `customfield_<id>`.

## Ticket Type auto-classification (applies to whichever branch actually transitions a ticket — Step 0 or the classic walk)

Whenever Rule A successfully transitions a ticket to `In Progress`, check whether that ticket's **Ticket Type** field (`customfield_10188`, a single-select custom field) is unset, and if so, set it automatically. **Never overwrite an existing value** — this only fills a gap, it never corrects or reclassifies a value the operator (or `ticket-creator`) already set.

**Field:** `customfield_10188`, name "Ticket Type", schema type `option` (single-select). Verified 2026-07-24 via `mcp__atlassian__getJiraIssueTypeMetaWithFields` (`projectIdOrKey: "TRIDENT"`, `issueTypeId: "10001"`, `requiredFieldsOnly: false`). Allowed values include (among others not relevant here): `Feature` (id `10342`), `M&S` (id `10343`), `Research` (id `10514`).

**Unset check:** `fields.customfield_10188` is `null` or missing. If it already holds any value (including a value not covered by the classification below, e.g. `SEO`, `Design`, `Engineering`), skip — do not touch it.

**Classification (first match wins, in this order):**

1. **`IS_SPIKE == true`** (same detection Rule D already uses: `fields.summary` contains the substring `SPIKE`, case-insensitive) → **`Research`** (id `10514`).
2. **Else, the ticket looks like a bug fix or tech-debt item** — true if EITHER:
   - `fields.issuetype.name == "Bug"` (the project's real, structural Bug issue type — id `10004`; this project has no separate "Tech Debt" issue type, so tech-debt work is filed under Task or Story, which this signal alone won't catch), OR
   - `fields.summary`, case-insensitive, contains any of: `bug`, `bugfix`, `bug fix`, `tech debt`, `techdebt`, `technical debt`, `hotfix`.

   → **`M&S`** (id `10343`).

   **Known limitation — accept it, don't over-engineer a fix:** the bare substring `bug` also matches words like "debug" (e.g. a ticket titled "Debug logging for X" would be misclassified as M&S). This mirrors the same class of simple substring convention Rule D already uses for SPIKE detection. Since this step only ever fills a field that was otherwise blank, a wrong guess costs the operator one manual correction in Jira, not a broken workflow — it does not gate any transition, worktree, or session. Not worth a more elaborate classifier for that trade-off.
3. **Else** → **`Feature`** (id `10342`).

**Apply the edit:** `mcp__atlassian__editJiraIssue` on the just-transitioned ticket, `fields: { "customfield_10188": { "id": "<10514|10343|10342>" } }`.

**On success:** append `"Set Ticket Type to <Research|M&S|Feature> (was unset)"` to that ticket's `actionsTaken`, stacking additively after whichever transition message applied (`"Moved to In Progress"` from the classic walk, or `"Moved to In Progress — TODO-MODE implementation already underway, no worktree/session needed"` from Step 0).

**On failure:** append `"Ticket Type set failed: <verbatim error>"` to `actionsTaken`. This is NOT terminal for anything else — it doesn't block Rule D's chain (for the classic-walk case), doesn't revert the status transition, and doesn't need a REMINDERS entry (it's a data-hygiene nice-to-have, not something that blocks work). Print one terminal warning line.

**Autonomous mode:** this step is a plain field write with no question — it runs in autonomous mode whenever Rule A itself transitions a ticket there, regardless of which branch (Step 0 or the classic walk) did it.

**Field ID re-discovery procedure:** if `customfield_10188` ever comes back as an unrecognized field, or the option ids above stop matching (e.g., a Jira admin edits the picklist), re-discover via `mcp__atlassian__getJiraIssueTypeMetaWithFields` (look for a field named "Ticket Type", schema type `option`) and update this section with the new field id and/or option ids.

## Steps to perform the transition

Shared by both Step 0 (the TODO-MODE priority check) and the classic candidate walk — only the candidate-selection logic and the final action string differ between them.

1. **Build the candidate list.** (Step 0: full TO DO column. Classic walk: `status.name == "New"` only.) Sort ascending by `rank`.
2. **Walk the candidate list.** For each candidate in order:
   - **Flag check** — apply the "Flagged detection" rules above. If flagged:
     - Do NOT append anything to this ticket's `actionsTaken` (the report's status column shows its current TO DO status, which together with the flag icon in Jira tells the story for that ticket entry itself).
     - **DO append** a `REMINDERS` entry: `"<TICKET-KEY> is <top-of-rank New / a TODO-MODE-started> ticket but is flagged (impediment) — not kicked off. Clear the flag or unblock the impediment before next run if it's now actionable."` Surfacing the skip is mandatory because silent skipping is what masked the 2026-05-20 incident (field-resolution bug returned `null` for every ticket and the rule treated the JQL response as authoritative). With REMINDERS on, a field-resolution bug or a stale flag is visible at the next run instead of hidden.
     - Move on to the next candidate.
   - **Unflagged AND (classic walk: this is simply the first one) / (Step 0: this one has the marker)** — this ticket is the kickoff target. Capture its key as `KICKOFF_KEY` and break the loop.
3. **No candidate found.** If the loop exits without picking a `KICKOFF_KEY`, this branch exits with no kickoff transition. Every flagged candidate has already produced its `REMINDERS` entry per step 2, so the operator still sees the full list of skipped tickets in the daily report.
4. **Look up the transition ID** with `mcp__atlassian__getTransitionsForJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = `KICKOFF_KEY`). Walk the returned `transitions` array and pick the one whose **target status name** is `"In Progress"` (case-sensitive match on `to.name`). If no exact match, look for a name containing `"in progress"` (case-insensitive) as a fallback. Capture its `id` as `TRANSITION_ID`.
5. **Execute the transition** via `mcp__atlassian__transitionJiraIssue` (cloudId same as above, issueIdOrKey = `KICKOFF_KEY`, transition = `{ id: TRANSITION_ID }`).
6. **Update the in-memory ticket state**: set the kickoff ticket's `fields.status.name` to `"In Progress"` so the subsequent sort (Step 3) places it in the In Progress lane (priority 7) and the report's heading + Current Status bullet both reflect the new state.
7. **Append the action string** — `"Moved to In Progress"` (classic walk) or `"Moved to In Progress — TODO-MODE implementation already underway, no worktree/session needed"` (Step 0) — to the kickoff ticket's `actionsTaken` list.
7a. **Classify and set Ticket Type if unset** — see "Ticket Type auto-classification" above. Runs immediately after step 7, on the same ticket.
7b. **(Step 0 only) Mark the ticket `Rule-D-SKIP`.** The classic walk does NOT do this — its whole point is to chain into Rule D.
8. For every other ticket, leave `actionsTaken` empty (it'll render as `Action Taken: None`).

## Failure modes — terminal for Rule D on this ticket

If Rule A fails to land the In Progress status on the chosen ticket, Rule D MUST skip that ticket, because its precondition "ticket is actually In Progress" is false. This applies identically whether the failed transition came from Step 0 or the classic walk.

- If `getTransitionsForJiraIssue` returns no matching transition (workflow doesn't expose "In Progress" from the current state), append `"Move failed: no 'In Progress' transition available"` to the kickoff ticket's `actionsTaken` and keep the original status. Mark the ticket as `Rule-A-failed` for Rule D's skip check. Do NOT abort the report. Do NOT advance to the next candidate — Rule A picks at most one kickoff target per run; "transition unavailable" is a state-machine fault on this ticket, not a reason to flip to a different one.
- If `transitionJiraIssue` returns an error, append `"Move failed: <verbatim error>"` to `actionsTaken` and keep the original status. Mark the ticket as `Rule-A-failed` for Rule D's skip check. Do NOT abort the report.
- In either failure mode, print one terminal warning line so the operator can investigate.

**Flagged candidates are NOT a failure** — they are a normal, expected skip. Flagged skips do NOT log terminal warnings and do NOT produce `actionsTaken` entries, BUT they DO produce a `REMINDERS` entry per the walk-the-candidate-list step above. The combination of (a) the flag icon visible on the ticket in Jira and (b) the REMINDERS line in the daily report tells the operator "this is intentionally not being touched right now" without hiding it altogether.

**Integrity guardrail — never fabricate state.** The action string (and any user-facing narrative built off Rule A's observation) MUST reflect what was actually observed. NEVER say "flag was cleared" or "ticket is unflagged now" unless `fields.customfield_10091` came back empty on the current fetch. On 2026-05-20 a single inference ("the field is null in the JQL response, so the flag must have been cleared since the 2026-05-13 flag-added comment") caused the skill operator to actively misreport the state of a flagged ticket in the daily report — the underlying cause was the field-resolution bug fixed above, but the narrative would have been wrong even without the bug because the skill never verified the claim. That class of inference is now banned: state claims require state observations. This guardrail applies identically to Step 0 — never claim a ticket moved to In Progress unless `transitionJiraIssue` actually returned success, and never claim its implementation is "already underway" unless a real marker comment was actually found on it.
