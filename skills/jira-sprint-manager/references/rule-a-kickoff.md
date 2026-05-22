# Rule A — Kickoff a New ticket when nothing is In Progress (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step API calls, the flagged-skip behavior, and failure-mode handling.

## Trigger

The fetched ticket list contains ZERO tickets whose `fields.status.name == "In Progress"` AND at least ONE ticket whose `fields.status.name == "New"`.

## Action

Transition the **highest-ranked, NOT-FLAGGED New ticket** (lowest `rank` value among unflagged status=`New` tickets — i.e., the top of the New lane on the board, skipping over any flagged entries) to status `In Progress`. If every New ticket is flagged, the rule exits without acting.

## "Flagged" detection

A New ticket is considered **flagged** (and therefore ineligible for kickoff) when its `fields.customfield_10091` value is non-empty. The Jira "Flagged" field for the boats-group Trident project is a `multicheckboxes` custom field with one allowed value `{"id":"10115","value":"Impediment"}`. When the operator clicks the flag icon on a ticket, the field becomes `[{"value":"Impediment","id":"10115"}]`; an unflagged ticket reports it as `null`, missing, or an empty array.

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

**Why this matters:** the operator uses the flag to mark a New ticket as blocked (e.g., a `Flag added — Blocked by TRIDENT-862` comment is auto-posted by Jira when the flag is set). Auto-moving a blocked ticket into In Progress would (a) trigger Rule D to spawn a research worktree for work that cannot start, and (b) silently hide the blocker because the ticket leaves the New column where the operator can see the flag at a glance.

**Field ID re-discovery procedure:** the JQL request in Step 2 uses the explicit `customfield_10091` field id (pinned for the boats-group Trident project — see above). If the field ever returns unset on tickets you KNOW are flagged in the UI (e.g., a Jira admin migrates the field, or this skill is re-used on a different project/instance), re-discover the canonical id via `mcp__atlassian__getJiraIssueTypeMetaWithFields` (look for a field whose name is "Flagged" or whose schema type is `multicheckboxes` with `Impediment` as the only allowed value) and update both SKILL.md Step 2 and this reference to the new `customfield_<id>`.

## Steps to perform the transition

1. **Build the candidate list.** Filter the fetched issues to `status.name == "New"`, then sort ascending by `rank`. This is the iteration order; the front of the list is the top of the New lane.
2. **Walk the candidate list.** For each candidate in order:
   - **Flag check** — apply the "Flagged detection" rules above. If flagged:
     - Do NOT append anything to this ticket's `actionsTaken` (the report's status column shows it as `New`, which together with the flag icon in Jira tells the story for that ticket entry itself).
     - **DO append** a `REMINDERS` entry: `"<TICKET-KEY> is the top-of-rank New ticket but is flagged (impediment) — not kicked off. Clear the flag or unblock the impediment before next run if it's now actionable."` Surfacing the skip is mandatory because silent skipping is what masked the 2026-05-20 incident (field-resolution bug returned `null` for every ticket and the rule treated the JQL response as authoritative). With REMINDERS on, a field-resolution bug or a stale flag is visible at the next run instead of hidden.
     - Move on to the next candidate.
   - **Unflagged** — this ticket is the kickoff target. Capture its key as `KICKOFF_KEY` and break the loop.
3. **No candidate found.** If the loop exits without picking a `KICKOFF_KEY` (every New ticket was flagged), Rule A exits with no kickoff transition. Every flagged candidate has already produced its `REMINDERS` entry per step 2, so the operator still sees the full list of skipped tickets in the daily report. Rule D's "chain from Rule A" path inherits nothing — Rule D will not move any ticket this run via the chain (it can still fire on tickets that were already In Progress, but the trigger condition requires `≥1 In Progress`, which by definition is false in this run — so Rule D is a no-op too).
4. **Look up the transition ID** with `mcp__atlassian__getTransitionsForJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = `KICKOFF_KEY`). Walk the returned `transitions` array and pick the one whose **target status name** is `"In Progress"` (case-sensitive match on `to.name`). If no exact match, look for a name containing `"in progress"` (case-insensitive) as a fallback. Capture its `id` as `TRANSITION_ID`.
5. **Execute the transition** via `mcp__atlassian__transitionJiraIssue` (cloudId same as above, issueIdOrKey = `KICKOFF_KEY`, transition = `{ id: TRANSITION_ID }`).
6. **Update the in-memory ticket state**: set the kickoff ticket's `fields.status.name` to `"In Progress"` so the subsequent sort (Step 3) places it in the In Progress lane (priority 7) and the report's heading + Current Status bullet both reflect the new state.
7. **Append `"Moved to In Progress"`** to the kickoff ticket's `actionsTaken` list.
8. For every other ticket, leave `actionsTaken` empty (it'll render as `Action Taken: None`).

## Failure modes — terminal for Rule D on this ticket

If Rule A fails to land the In Progress status on the chosen ticket, Rule D MUST skip that ticket, because its precondition "ticket is actually In Progress" is false.

- If `getTransitionsForJiraIssue` returns no matching transition (workflow doesn't expose "In Progress" from the current state), append `"Move failed: no 'In Progress' transition available"` to the kickoff ticket's `actionsTaken` and keep the original status. Mark the ticket as Rule-A-failed for Rule D's skip check. Do NOT abort the report. Do NOT advance to the next candidate — Rule A picks at most one kickoff target per run; "transition unavailable" is a state-machine fault on this ticket, not a reason to flip to a different one.
- If `transitionJiraIssue` returns an error, append `"Move failed: <verbatim error>"` to `actionsTaken` and keep the original status. Mark the ticket as Rule-A-failed for Rule D's skip check. Do NOT abort the report.
- In either failure mode, print one terminal warning line so the operator can investigate.

**Flagged candidates are NOT a failure** — they are a normal, expected skip. Flagged skips do NOT log terminal warnings and do NOT produce `actionsTaken` entries, BUT they DO produce a `REMINDERS` entry per the walk-the-candidate-list step above. The combination of (a) the flag icon visible on the ticket in Jira and (b) the REMINDERS line in the daily report tells the operator "this is intentionally not being touched right now" without hiding it altogether.

**Integrity guardrail — never fabricate state.** The action string (and any user-facing narrative built off Rule A's observation) MUST reflect what was actually observed. NEVER say "flag was cleared" or "ticket is unflagged now" unless `fields.customfield_10091` came back empty on the current fetch. On 2026-05-20 a single inference ("the field is null in the JQL response, so the flag must have been cleared since the 2026-05-13 flag-added comment") caused the skill operator to actively misreport the state of a flagged ticket in the daily report — the underlying cause was the field-resolution bug fixed above, but the narrative would have been wrong even without the bug because the skill never verified the claim. That class of inference is now banned: state claims require state observations.
