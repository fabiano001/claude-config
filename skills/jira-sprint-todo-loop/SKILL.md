---
name: jira-sprint-todo-loop
description: Scans the operator's TO DO-column tickets on the Trident BG board (391), filters to the ones genuinely ready to start early (not flagged, no unfinished dependency, has ticket-creator's "Implementation Ready" comment marker), then for each qualifying ticket resolves its repos from ticket-creator's "Repos Involved" comment and mass-launches a backgrounded `/ticket-driver <TICKET> TODO-MODE` session per repo — each in its own new git worktree, named `<TICKET> - <CODE_NAME>` in the agent view. This is how implementation gets started on TO DO tickets ahead of sprint pickup, in bulk, unattended. Each run posts a short results summary (counts + launched ticket keys) to the `#fabi-jira-sprint-manager` Slack channel before exiting. Use when the operator asks to run jira-sprint-todo-loop, kick off ready TODO tickets, start implementation early on backlog tickets, or bulk-launch TODO-MODE ticket-driver runs. Does NOT generate the daily sprint report or run jira-sprint-manager's six lane-transition rules (that's `jira-sprint-manager`) and does NOT implement anything itself (that's `ticket-driver`, which this skill only dispatches).
---

# Jira Sprint TODO Loop

## What this is (and isn't)

A batch dispatcher. It never writes code, never talks to `git` beyond creating worktrees and checking merge state, and never touches Jira status transitions. Its entire job: find TO DO tickets that are genuinely unblocked and ready, then hand each one's implementation off to `/ticket-driver ... TODO-MODE` in its own backgrounded session — one per repo the ticket touches. Everything after dispatch belongs to `ticket-driver`, not this skill.

**Dependency link type — verified against the live instance:** the only issue-link type on this Jira instance capable of expressing "this ticket is waiting on another one" is **`Blocks`** (id `10000`, `outward: "blocks"`, `inward: "is blocked by"`) — confirmed via `mcp__atlassian__getIssueLinkTypes`. There is no separate `Depends`/`Depends on` type configured here. Step 2 keys on this directly (an `issuelinks` entry with `type.name === "Blocks"` and `inwardIssue` populated) rather than a generic pattern match — see [references/ticket-selection.md](references/ticket-selection.md) "Dependency link type" for the exact directionality and a re-discovery fallback in case this instance's link types ever change.

## Fixed configuration (do NOT prompt for these — reused verbatim from `jira-sprint-manager`, same Jira instance)

- **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
- **Project key:** `TRIDENT` — **Board:** `391` (Trident BG)
- **Assignee accountId:** `5a6765563c7f1842c3d7b806` (Fabiano Desouza)
- **TO DO column statuses:** `New`, `Backlog`, `Reopened` (same set `jira-sprint-manager`'s status-priority table uses)
- **Flagged field:** `customfield_10091` — non-empty means flagged. **Never use the short name `flagged`** — on this instance it silently resolves to `null` for every ticket (the exact incident that's documented in `jira-sprint-manager/references/rule-a-kickoff.md`). Re-discovery procedure if this ever stops matching real flags: `mcp__atlassian__getJiraIssueTypeMetaWithFields`, look for a field named "Flagged" / schema `multicheckboxes` with `Impediment` as its only option.
- **Known-repo list** (for validating names parsed out of comments): `portal-react-boattrader`, `webapp-react-trident`, `api-node-boats`, `api-node-boattrader`, `lambda-node-trident-700credit`, `lambda-node-trident-advertised-rates`, `lambda-node-trident-portal-lead`, `lambda-node-trident-partner-lender`, `pp-algorithm`, `configd`, `terraform-stack-trident`.

## Workflow

### Step 1 — Fetch every TO DO ticket assigned to the operator

```
mcp__atlassian__searchJiraIssuesUsingJql
  cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f
  jql: sprint in openSprints() AND project = TRIDENT AND assignee = "5a6765563c7f1842c3d7b806" AND status in ("New","Backlog","Reopened") ORDER BY rank ASC
  fields: ["summary", "status", "customfield_10091", "comment", "issuelinks"]
  limit: 100 (paginate if isLast is false)
```

Rank order = board order, same convention `jira-sprint-manager` uses everywhere. Every ticket returned here gets a disposition line in the final report (Step 4) — qualifying and launched, or excluded with a named reason. Nothing fetched here is ever silently dropped from that report.

### Step 2 — Filter to tickets that are actually ready

Apply all three gates below to every fetched ticket. All three must pass. **Full detail, exact matching logic, and the dependency link-type discovery procedure — load [references/ticket-selection.md](references/ticket-selection.md).**

1. **Not flagged** — `customfield_10091` is empty/null/missing.
2. **No unfinished dependency** — no issue-link pointing at another ticket this one is waiting on, UNLESS that other ticket's implementation is already done (checked via `ticket-driver`'s own `Ticket Driver Implementation Completed` comment marker, or a status-based fallback for older tickets).
3. **Has the Implementation Ready marker** — a comment matching any of `ticket research completed` / `research completed` / `implementation ready` / `ready for implementation` (case-insensitive substring), the same marker/matching convention `jira-sprint-manager` Rule D already scans for.

### Step 3 — Resolve repos and launch, per qualifying ticket

**Full detail, exact commands, and the dependency-aware base-branch override — load [references/worktree-and-launch.md](references/worktree-and-launch.md).**

1. Parse the **Repos Involved** comment (`This ticket will involve changes in these repos: <repo1>, <repo2>, ...`) — same marker `ticket-creator` posts and `jira-sprint-manager` Rule D already parses. No comment → skip this ticket with a clear note; never guess repos from ticket text.
2. Check the ticket itself for a `Ticket Driver Implementation Started` or `Completed` comment — if present, skip it (something's already running or done; don't waste a worktree/session launch when `ticket-driver`'s own Guard would refuse anyway).
3. For each resolved repo: create `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>` (skip + remind if it already exists), then launch:
   ```
   ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY> \
     --prompt "/background /ticket-driver <TICKET-KEY> TODO-MODE" \
     --session-name "<TICKET-KEY> - <CODE_NAME>"
   ```
   `<CODE_NAME>` = `WEBAPP` for `webapp-react-trident`, `PRBT` for `portal-react-boattrader`, `LAMBDA` for any repo name containing "lambda", `TERRAFORM` for any repo name containing "terraform" (e.g. `terraform-stack-trident` → `TERRAFORM`), otherwise the repo's own literal name — based on the mapping `jira-sprint-manager` uses for its own session naming, extended here with the `TERRAFORM` case (that extension is specific to this skill — `jira-sprint-manager` itself hasn't been updated to match).

   **Note the two deliberate corrections versus an informally-phrased request this skill might get invoked from:** the prompt is `/background /ticket-driver ... TODO-MODE` — `/background` is mandatory (no other mechanism backgrounds a session; see below), and `TODO-MODE` is the literal token `ticket-driver` actually checks for (bare `TODO` does nothing). The session name uses `" - "` (space-dash-space), not a bare hyphen.

### Step 4 — Exit immediately after dispatching, with exactly one line per ticket

**This skill does not wait for any `ticket-driver` run.** Its job ends the moment every repo for every qualifying ticket has had a worktree created and a backgrounded session launched (or already had one running) — it identifies tickets, spawns the necessary `ticket-driver` sessions in the background, and exits. It never polls a launched session, never checks back on its progress, and never blocks on anything past the launch call itself.

**The richer per-repo detail** (worktree path, session name, new-tab-vs-focused-existing-tab) belongs to the running commentary printed live during Step 3, as each repo is processed — that's where an operator watching the run in real time sees the detail. It is NOT part of the final report.

**The final report, printed right before exiting, is exactly one line per ticket fetched in Step 1** — every ticket, no exceptions, in the same rank order as Step 1. Each line is one of exactly two shapes:

- **Qualified and at least one repo got a `ticket-driver` session (new or already running for that ticket):**
  ```
  <TICKET-KEY>: ticket-driver launched in TODO-MODE (<repo1>, <repo2>, ...)
  ```
- **Anything else** — failed a gate in Step 2, or passed all three gates but wasn't actually launched for an operational reason (no parseable Repos Involved comment, or already had its own Started/Completed marker):
  ```
  <TICKET-KEY>: Didn't match ticket-driver TODO-MODE launching criteria because <specific reason>
  ```
  `<specific reason>` is always one of: `flagged`; `depends on <DEP-KEY>, not yet implemented`; `no Implementation Ready marker`; `qualifies but no Repos Involved comment found`; `already has a Ticket Driver Implementation Started/Completed comment`.

Every ticket gets exactly one of these two lines — never zero, never both, never a vaguer third shape. A ticket with a per-repo failure partway through Step 3 (e.g. one of two repos failed `worktree add`) still counts as "launched" for this line if at least one repo succeeded — the partial failure was already surfaced live during Step 3's commentary, not swallowed, just not repeated here.

**Immediately after the per-ticket disposition lines, before the final timestamp line — post a short Slack summary of this run.** Send one message via `mcp__claude_ai_Slack__slack_send_message` (`channel_id: "C0BMTSBK048"` — the `#fabi-jira-sprint-manager` channel, same one `jira-sprint-manager` itself posts to). Keep it very short — counts and launched ticket keys only, not the full per-ticket reasoning from the terminal report:
```
jira-sprint-todo-loop: <L> launched, <S> skipped
Launched: <TICKET1> (<repo1>, <repo2>), <TICKET2> (<repo>)
```
- If `L == 0`, omit the `Launched:` line entirely (just `jira-sprint-todo-loop: 0 launched, <S> skipped`).
- If `S == 0`, still print `jira-sprint-todo-loop: <L> launched, 0 skipped`.
- This is a summary, not a duplicate of Step 4's per-ticket report — never list skip reasons here; the terminal/report already has that detail.
- **If the Slack send fails** (bad channel id, auth error, network error): print one warning line and continue anyway — a failed notification must never block the run from finishing or printing its final timestamp line.

**The very last line printed, after the Slack summary and immediately before the skill exits:**
```
jira-sprint-todo-loop run completed at <timestamp>
```
`<timestamp>` MUST be a real, resolved value — run `date "+%Y-%m-%d %H:%M"` (standalone Bash call, right before printing this line) and substitute its actual output. **Never print the literal string `<timestamp>` or any other placeholder/bracketed text in its place** — if you catch yourself about to write something like `2026-07-29 [current time]`, that's the bug this note exists to prevent; run the command and use its real output instead.

## Gotchas

- **`/background` is not optional.** Every launched prompt must literally start with `/background ` or the new session lands in the ordinary foreground view instead of the agent view — this is the same rule `jira-sprint-manager` and `launch-pr-review-agent` already follow, not something specific to this skill.
- **This skill launches sessions; it never waits for them.** Once a session is opened (or an existing tab is focused because the worktree already existed), move on to the next repo/ticket immediately — do not poll or block on the launched `ticket-driver` run's progress.
- **No automatic retry of excluded tickets.** A ticket excluded this run (flagged, dependency not ready, etc.) is simply skipped — re-run `jira-sprint-todo-loop` later once the blocking condition clears; this skill does not remember or re-check excluded tickets on its own.

## Failure & fallback

- Step 1's JQL fails twice → stop, report the verbatim error. Do not guess at ticket state from a prior run's memory.
- A per-ticket or per-repo failure (bad comment format, worktree creation error, launch script non-zero exit) is **never fatal to the whole run** — report it live during Step 3 against that one ticket/repo, fold it into that ticket's one-line disposition in Step 4, and continue with the rest.
