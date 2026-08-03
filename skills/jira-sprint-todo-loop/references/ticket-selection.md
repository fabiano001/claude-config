# Ticket selection (Step 2 detail)

All three gates below must pass for a ticket to proceed to Step 3. Evaluate all three even after one fails, if cheap to do — the report in SKILL.md Step 4 should name every reason a ticket was excluded, not just the first one hit, though a single stated reason is acceptable if evaluating further gates requires an extra fetch that would otherwise be wasted.

## Gate 1 — Not flagged

`fields.customfield_10091` — treat as flagged if it's an array with `length > 0`, a non-empty string, or a non-null object with a truthy property. Treat as unflagged if missing, `null`, `[]`, or `""`. This is the exact same rule `jira-sprint-manager/references/rule-a-kickoff.md` documents under "Flagged detection" — reuse it verbatim, don't reinvent it.

## Gate 2 — No unfinished dependency

### Dependency link type — verified against the live instance

Confirmed via `mcp__atlassian__getIssueLinkTypes` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`): this Jira instance has exactly **one** link type capable of expressing "this ticket is waiting on another one" — **`Blocks`** (id `10000`, `outward: "blocks"`, `inward: "is blocked by"`). There is **no** separate `Depends`/`Depends on` type configured here (the full list also includes `AgileTest`, `AgileTest Defect`, `Cloners`, `Discovery - Connected`, `Duplicate`, `Polaris datapoint work item link`, `Polaris merge work item link`, `Polaris work item link`, `Post-Incident Reviews`, `Problem/Incident`, `Relates`, `Work item split` — none of those express a dependency relationship). So: a dependency, on this instance, is always expressed as a `Blocks` link.

**Re-discovery fallback (only if this ever stops matching):** if a ticket's `issuelinks` ever show a link type other than `Blocks` that plausibly means "waiting on" (e.g. a Jira admin adds a dedicated `Depends` type later), re-run `getIssueLinkTypes` and update this section — don't silently start ignoring a real dependency because it doesn't match the single hardcoded name above.

### Reading the direction correctly

Each entry in `fields.issuelinks` has a `type: {name, inward, outward}` and EITHER an `outwardIssue` OR an `inwardIssue` field (never both) — whichever is populated tells you which phrase is "active" from THIS ticket's point of view:

- `outwardIssue` populated → the relationship reads "**this ticket** `<type.outward>` **outwardIssue**" — for `Blocks`, "this ticket **blocks** outwardIssue" (this ticket is the blocker; says nothing about whether THIS ticket is ready).
- `inwardIssue` populated → the relationship reads "**this ticket** `<type.inward>` **inwardIssue**" — for `Blocks`, "this ticket **is blocked by** inwardIssue" (this ticket is the one waiting — `inwardIssue` is the dependency).

So concretely: **collect a dependency whenever a ticket has a `Blocks`-type link with `inwardIssue` populated** — that `inwardIssue` is the ticket this one is blocked by. A `Blocks`-type link with `outwardIssue` populated instead means this ticket blocks someone else, which is irrelevant to this ticket's own readiness — do not treat it as a dependency.

### Judging whether a dependency is "implemented"

For each dependency key collected above, fetch it (`mcp__atlassian__getJiraIssue`, `fields: ["status", "comment"]`) and judge, in this order:

1. **Primary signal:** its comments contain `Ticket Driver Implementation Completed` (case-insensitive substring — the exact marker `ticket-driver` posts on successful finalization, in any mode). Present → **implemented**.
2. **Fallback signal** (covers tickets implemented before this marker convention existed, or implemented by hand): its `status.name` has progressed to anything **other than** a TO DO status (`New`/`Backlog`/`Reopened`) or `In Progress` — i.e. `Resolved - Ready for QA`/`Resolved - Ready for AQA`, `Under review`, `Stakeholder Review`, `Resolved - QA Complete`/`Pending Release Candidate`, `Live`, `Done`, `Closed`. Present → **implemented**.
3. **Neither** → **not implemented**. The dependent ticket fails Gate 2 — exclude it this run, note which dependency it's waiting on (by key) in the final report. This is a normal, expected outcome, not an error.

If a ticket has **zero** dependency links pointing the waiting direction, Gate 2 passes trivially — most tickets will be in this bucket.

**A ticket can have more than one dependency.** All of them must be implemented for Gate 2 to pass; report the first not-yet-implemented one you find (no need to enumerate every unfinished dependency if there are several — one is sufficient reason to exclude).

## Gate 3 — Has the Implementation Ready marker

Scan `fields.comment` for any comment whose body (trimmed, case-insensitive) contains any of: `ticket research completed`, `research completed`, `implementation ready`, `ready for implementation`. This is the exact multi-phrase match `jira-sprint-manager` Rule D already uses to detect the marker `ticket-creator` posts — reuse it as-is; do not narrow it to a single phrase, since existing tickets in this project may have been created before the wording was fully standardized.

## Worked example

Ticket `TRIDENT-960`: not flagged, has the Implementation Ready marker, and has one issue link — type `Blocks` (`outward: "blocks"` / `inward: "is blocked by"`), with `inwardIssue` populated pointing at `TRIDENT-954`. Since `inwardIssue` is populated, the active phrase is the inward one: "TRIDENT-960 is blocked by TRIDENT-954" → `TRIDENT-954` is a dependency. Fetching `TRIDENT-954`: no `Ticket Driver Implementation Completed` comment, but `status.name == "Resolved - Ready for QA"` → fallback signal fires → implemented. Gate 2 passes. `TRIDENT-960` proceeds to Step 3, and per `references/worktree-and-launch.md`, its worktree creation will need to check whether `TRIDENT-954`'s branch has actually landed in `main` yet before picking a base branch.
