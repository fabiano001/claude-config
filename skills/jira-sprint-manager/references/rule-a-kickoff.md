# Rule A — Kickoff a New ticket when nothing is In Progress (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step API calls and failure-mode handling.

## Trigger

The fetched ticket list contains ZERO tickets whose `fields.status.name == "In Progress"` AND at least ONE ticket whose `fields.status.name == "New"`.

## Action

Transition the **highest-ranked New ticket** (the one with the lowest `rank` value among status=`New` tickets — i.e., the one sitting at the TOP of the New lane on the board) to status `In Progress`.

## Steps to perform the transition

1. Identify the target ticket: filter the fetched list to `status.name == "New"`, then pick the entry with the smallest `rank`. Capture its key as `KICKOFF_KEY`.
2. Look up the transition ID with `mcp__atlassian__getTransitionsForJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey = `KICKOFF_KEY`). Walk the returned `transitions` array and pick the one whose **target status name** is `"In Progress"` (case-sensitive match on `to.name`). If no exact match, look for a name containing `"in progress"` (case-insensitive) as a fallback. Capture its `id` as `TRANSITION_ID`.
3. Execute the transition via `mcp__atlassian__transitionJiraIssue` (cloudId same as above, issueIdOrKey = `KICKOFF_KEY`, transition = `{ id: TRANSITION_ID }`).
4. **Update the in-memory ticket state**: set the kickoff ticket's `fields.status.name` to `"In Progress"` so the subsequent sort (Step 3) places it in the In Progress lane (priority 7) and the report's heading + Current Status bullet both reflect the new state.
5. Append `"Moved to In Progress"` to the kickoff ticket's `actionsTaken` list.
6. For every other ticket, leave `actionsTaken` empty (it'll render as `Action Taken: None`).

## Failure modes — terminal for Rule D on this ticket

If Rule A fails to land the In Progress status, Rule D MUST skip this ticket, because its precondition "ticket is actually In Progress" is false.

- If `getTransitionsForJiraIssue` returns no matching transition (workflow doesn't expose "In Progress" from the current state), append `"Move failed: no 'In Progress' transition available"` to the kickoff ticket's `actionsTaken` and keep the original status. Mark the ticket as Rule-A-failed for Rule D's skip check. Do NOT abort the report.
- If `transitionJiraIssue` returns an error, append `"Move failed: <verbatim error>"` to `actionsTaken` and keep the original status. Mark the ticket as Rule-A-failed for Rule D's skip check. Do NOT abort the report.
- In either failure mode, print one terminal warning line so the operator can investigate.
