---
name: jira-sprint-manager-pickup-ticket
description: Force-picks up ONE specific, operator-named TO DO-column Jira ticket into In Progress, plus its full kickoff (worktree + backgrounded /ticket-driver session, or the SPIKE-close question), regardless of how many other tickets the operator already has In Progress. Takes one required argument, the ticket key (e.g. TRIDENT-928, invoked as `/jira-sprint-manager-pickup-ticket TRIDENT-928`). Unlike jira-sprint-manager's own Rule A (which only fires when the operator has ZERO In Progress tickets and picks whichever ticket is top-of-rank itself), this skill targets exactly the ticket key given, on demand, even while other tickets are already In Progress — the whole point is jumping a specific ticket ahead of that gate. Still enforces the same eligibility bar Rule A/Rule D would: the ticket must currently be in the TO DO column (New/Backlog/Reopened), must NOT be flagged (customfield_10091), and must already carry ticket-creator's "Implementation Ready" comment marker (ticket research completed / research completed / implementation ready / ready for implementation) — if ANY of these fail, the ticket is left completely untouched and every failing reason is reported back to the operator, nothing is moved or guessed at. On a passing ticket: transitions it to In Progress, auto-classifies its Ticket Type if unset (same as Rule A), then chains straight into Rule D's kickoff for that ticket (worktree + backgrounded, auto-closing /ticket-driver session for a normal ticket, or the Under-Review/hours question pair for a SPIKE) — the same outcome a full jira-sprint-manager run would have produced for this ticket, just without needing the zero-In-Progress trigger or a full board sweep. Use when the operator asks to pick up, jump the queue for, force-start, or immediately kick off a specific TO DO ticket ahead of schedule while already working something else, or runs `/jira-sprint-manager-pickup-ticket <TICKET-KEY>`. Does NOT run jira-sprint-manager's other rules, does NOT generate the daily sprint report, and does NOT relax or skip the flag/marker eligibility checks under any circumstance — a failing ticket is reported, never forced through.
---

# jira-sprint-manager: force-pickup a specific TO DO ticket

Moves exactly one operator-named ticket from TO DO straight into In Progress plus its full kickoff, bypassing `jira-sprint-manager` Rule A's "only when I have zero In Progress tickets" trigger — for the case where the operator explicitly wants to start a particular ticket right now, on top of whatever else is already In Progress. The eligibility bar is NOT relaxed to make this possible: the same flag/marker checks Rule A and Rule D already apply still gate this ticket, exactly as strictly. This skill only removes the "nothing else in progress" trigger condition, nothing else.

This is a thin orchestrator over the SAME mechanics `jira-sprint-manager`'s Rule A and Rule D already use — see [jira-sprint-manager/references/rule-a-kickoff.md](../jira-sprint-manager/references/rule-a-kickoff.md) and [jira-sprint-manager/references/rule-d-worktree-kickoff.md](../jira-sprint-manager/references/rule-d-worktree-kickoff.md), both loaded and followed directly below rather than re-derived from scratch.

## Fixed configuration

- **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
- **TO DO column statuses:** `New`, `Backlog`, `Reopened`
- **Flagged field:** `customfield_10091` (never the short name `flagged` — see rule-a-kickoff.md's "Flagged detection" for the 2026-05-20 incident this pins against)
- **Ticket Type field:** `customfield_10188`
- **Base projects dir:** `~/BOATS-GROUP-PROJECTS-GITHUB`

## Input

One required argument: the **ticket key** (e.g. `TRIDENT-928`). If missing from the invocation, ask for it before doing anything else.

## Workflow

### Step 1 — Fetch the ticket

`mcp__atlassian__getJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`, `issueIdOrKey: <TICKET-KEY>`, `fields: ["status", "summary", "description", "comment", "customfield_10091", "customfield_10188"]`.

If the fetch fails, report the verbatim error and stop — no mutation.

### Step 2 — Eligibility gate (ALL must pass; collect every failing reason, don't short-circuit)

1. **TO DO column** — `fields.status.name` (case-insensitive) is one of `New`, `Backlog`, `Reopened`. If not: reason = `not in the TO DO column (current status: "<status>")`.
2. **Not flagged** — `fields.customfield_10091` is empty/null/missing (see "Flagged detection" in rule-a-kickoff.md for the exact non-empty/empty shapes). If flagged: reason = `flagged (impediment) — clear the flag first if this is now actionable`.
3. **Has the Implementation Ready marker** — scan `fields.comment`'s bodies (flattened text, case-insensitive) for any of `ticket research completed` / `research completed` / `implementation ready` / `ready for implementation` (same match `jira-sprint-manager` Rule D and `jira-sprint-todo-loop` both already use). If none match: reason = `no Implementation Ready marker — research isn't complete yet`.

**If any reason was collected**, print exactly:

```
jira-sprint-manager-pickup-ticket: <TICKET-KEY> was NOT moved — it doesn't meet the criteria:
  - <reason 1>
  - <reason 2 if any>
  - <reason 3 if any>
No changes made.
```

Stop here. Nothing else in this workflow runs — no transition, no worktree, no session.

**If zero reasons were collected**, continue to Step 3.

### Step 3 — Transition to In Progress

Follow **rule-a-kickoff.md's "Steps to perform the transition"** (steps 4–6 of that section — the candidate is already chosen, it's `<TICKET-KEY>`, so skip that file's own candidate-selection steps 1–3, which don't apply here):

1. `mcp__atlassian__getTransitionsForJiraIssue` (cloudId above, issueIdOrKey `<TICKET-KEY>`). Find the transition whose `to.name` is `"In Progress"` (case-sensitive first, then a case-insensitive `"in progress"` fallback).
2. **No match** → print `jira-sprint-manager-pickup-ticket: <TICKET-KEY> passed eligibility but no "In Progress" transition is available from its current state — move it manually in Jira. No changes made.` Stop — do not proceed to Ticket Type classification or Rule D's kickoff, since the ticket isn't actually In Progress.
3. **Match found** → `mcp__atlassian__transitionJiraIssue` with that transition's `id`. On failure, report the verbatim error and stop, same as above (nothing else runs). On success, update the in-memory `fields.status.name` to `"In Progress"` and continue.

### Step 4 — Ticket Type auto-classification

Follow **rule-a-kickoff.md's "Ticket Type auto-classification"** section exactly (SPIKE → Research `10514`, bug/tech-debt → M&S `10343`, else → Feature `10342`; never overwrites an already-set value). Runs immediately after Step 3's successful transition, on this same ticket.

### Step 5 — Chain into Rule D's kickoff for this ticket

Gate 2's step 3 already guarantees `MARKER_FOUND = true` for this ticket, and Step 3 above just landed the `In Progress` transition cleanly (no `"Move failed"`, no `Rule-D-SKIP` — those two terminal-skip exceptions in rule-d-worktree-kickoff.md's step 1 exist for jira-sprint-manager's own Rule A → Rule D chain and don't apply to a fresh, successful transition from this skill).

Follow **rule-d-worktree-kickoff.md starting at its step 2** (re-fetching/re-scanning comments there is fine and harmless — it'll just reconfirm what Step 2 above already found) through the rest of its numbered steps for this one ticket, including:

- Step 3.5's Repos Involved comment scan and step 4's `TARGET_REPOS` resolution (implementation-phase branch, since `MARKER_FOUND = true`).
- Step 5.6's `SESSION_NAME` computation (`<TICKET-KEY>-<SEGMENT>` per repo).
- Step 6's branch on `IS_SPIKE` (summary contains `SPIKE`, case-insensitive):
  - **`IS_SPIKE == false`** → **6a** — one worktree + one backgrounded, auto-closing `/ticket-driver <TICKET-KEY>` session per repo in `TARGET_REPOS`.
  - **`IS_SPIKE == true`** → **6a-spike** — no worktree; queue **Q1** (move to Under review?) and, if yes, **Q2** (hours), exactly as documented there.
- Any new-repo bootstrap (a repo tagged `(new)` in the Repos Involved comment) per that file's own procedure.

Capture whatever `actionsTaken`-equivalent outcome lines that section produces (worktree(s) created / reminder / Q1+Q2 result) for the Step 6 summary below.

### Step 6 — Print the summary

```
jira-sprint-manager-pickup-ticket: <TICKET-KEY> picked up (was "<original status>")

Moved to In Progress.
Ticket Type: <set to Research|M&S|Feature (was unset) | left as-is (already set) | set failed: <error>>

Kickoff:
  <repo1>: worktree created at <IMPL_PATH>, backgrounded session '<TICKET-KEY>-<SEGMENT>' opened (auto-closes on background handoff)
  <repo2>: ...
  (or, for a SPIKE) Asked Q1/Q2 — <outcome>
  (or) No repos resolved — <reason from rule-d-worktree-kickoff.md's own fallback/ask-operator handling>

<TICKET-KEY> is now in progress alongside whatever else you're already working on.
```

## Failure modes

- **Ticket fetch fails (Step 1)** → report verbatim error, stop. No mutation.
- **Any eligibility gate fails (Step 2)** → report every failing reason, stop. No mutation of any kind — this is the operator's explicit "just tell me, don't force it" contract for this skill.
- **No "In Progress" transition available, or the transition call itself fails (Step 3)** → report verbatim, stop. No Ticket Type write, no Rule D kickoff.
- **Ticket Type write fails (Step 4)** → report verbatim, continue anyway — this is a data-hygiene nice-to-have, not a gate (matches rule-a-kickoff.md's own failure handling for this step).
- **A repo's worktree/session-open fails inside Step 5** → non-fatal for that repo, per rule-d-worktree-kickoff.md's own per-repo failure handling; continue with the rest and report it in the summary.

## Bash safety rules

- NEVER use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution (`$(...)`, `${...}`).
- NEVER use `&&`, `;`, or `||` to chain commands — split into separate Bash calls.
- Use absolute paths everywhere; never use `cd`.
