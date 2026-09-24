---
name: jira-sprint-todo-loop
description: Scans the operator's TO DO-column tickets on the Trident BG board (391), filters to the ones genuinely ready to start early (not flagged, no unfinished dependency, has ticket-creator's "Implementation Ready" comment marker), then for each qualifying ticket resolves its repos from ticket-creator's "Repos Involved" comment and mass-launches a backgrounded `/ticket-driver <TICKET> TODO-MODE` session per repo — each in its own new git worktree, named `<TICKET> - <CODE_NAME>` in the agent view. This is how implementation gets started on TO DO tickets ahead of sprint pickup, in bulk, unattended. Any repo `ticket-creator` tagged `(new)` in its Repos Involved comment (doesn't exist yet) is bootstrapped first — local directory created, `create-boatsgroup-repo` skill invoked to create it on GitHub, initial README pushed as the first commit to `main` — before the normal worktree-creation flow runs against it. Each run publishes a short results summary (counts + launched ticket keys) as a new entry in a shared Claude Code Artifact — the Jira Sprint Loops Activity Log, also used by `jira-sprint-manager` — before exiting (an earlier Slack-notification attempt was abandoned when an org-side approval gate never let it post reliably from a looped session, and a later local-file version was superseded when the log moved to this artifact). Use when the operator asks to run jira-sprint-todo-loop, kick off ready TODO tickets, start implementation early on backlog tickets, or bulk-launch TODO-MODE ticket-driver runs. Does NOT generate the daily sprint report or run jira-sprint-manager's six lane-transition rules (that's `jira-sprint-manager`) and does NOT implement anything itself (that's `ticket-driver`, which this skill only dispatches).
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
- **Known-repo list** (for validating names parsed out of comments): `portal-react-boattrader`, `portal-nextjs-platform`, `webapp-react-trident`, `api-node-boats`, `api-node-boattrader`, `boatsdotcom`, `lambda-node-trident-700credit`, `lambda-node-trident-advertised-rates`, `lambda-node-trident-portal-lead`, `lambda-node-trident-partner-lender`, `lambda-node-trident-services`, `pp-algorithm`, `configd`, `terraform-stack-trident`.

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

1. Parse the **Repos Involved** comment (`This ticket will involve changes in these repos: <repo1>, <repo2>, ...`) — same marker `ticket-creator` posts and `jira-sprint-manager` Rule D already parses, including its trailing `(new)` tag on any repo that doesn't exist yet (e.g. `lambda-node-trident-loan-recovery (new)`). No comment → skip this ticket with a clear note; never guess repos from ticket text.
2. Check the ticket itself for a `Ticket Driver Implementation Started` or `Completed` comment — if present, skip it (something's already running or done; don't waste a worktree/session launch when `ticket-driver`'s own Guard would refuse anyway).
2.5. For each repo tagged `(new)` whose directory doesn't exist yet at `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`: create the directory, invoke the `create-boatsgroup-repo` skill (wait for it to return the created repo's URL), then push an initial `README.md` as the first commit to `main` — see [references/worktree-and-launch.md](references/worktree-and-launch.md) "Bootstrap any repo tagged (new)" for the exact commands and failure handling. Once this lands, the repo is treated exactly like any pre-existing one for the rest of Step 3.
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
  `<specific reason>` is always one of: `flagged`; `depends on <DEP-KEY>, not yet implemented`; `no Implementation Ready marker`; `qualifies but no Repos Involved comment found`; `already has a Ticket Driver Implementation Started/Completed comment`; `repo <repo> tagged (new) but automated repo creation failed: <error>`; `repo <repo> tagged (new), created on GitHub, but first-commit push failed: <error> — resolve manually, then re-run`.

Every ticket gets exactly one of these two lines — never zero, never both, never a vaguer third shape. A ticket with a per-repo failure partway through Step 3 (e.g. one of two repos failed `worktree add`) still counts as "launched" for this line if at least one repo succeeded — the partial failure was already surfaced live during Step 3's commentary, not swallowed, just not repeated here.

**Immediately after the per-ticket disposition lines, before the final timestamp line — publish a short summary of this run to the shared Activity artifact.** (Two earlier versions of this step used other channels: a Slack post — abandoned 2026-08-10 after an org-side approval gate on `mcp__claude_ai_Slack__slack_send_message` never let it post reliably from a looped session — and a local markdown file at `~/.claude/jira-sprint-loops/activity.md` — superseded 2026-08-11 by the Claude Code Artifact this step now publishes to, using the exact same URL `jira-sprint-manager` also writes to.) Keep the logged summary short — counts and launched ticket keys only, not the full per-ticket reasoning already printed to the terminal:
```
jira-sprint-todo-loop: <L> launched, <S> skipped
Launched: <TICKET1> (<repo1>, <repo2>), <TICKET2> (<repo>)
```
- If `L == 0`, omit the `Launched:` line entirely (just `jira-sprint-todo-loop: 0 launched, <S> skipped`).
- If `S == 0`, still include `jira-sprint-todo-loop: <L> launched, 0 skipped`.
- This is a summary, not a duplicate of Step 4's per-ticket report — never list skip reasons here; the terminal/report already has that detail.

**How to publish it — Activity log (shared Claude Code Artifact, also used by `jira-sprint-manager`):**

**Artifact URL (fixed — same one `jira-sprint-manager` publishes to):**
```
https://claude.ai/code/artifact/bac6ed28-75cd-447e-a432-de42f8f3f07d
```

**Local mirror file:** `~/.claude/jira-sprint-loops/activity.html` — read, edit, and republish this file; it's the only source of truth for the artifact's current content. (The earlier `~/.claude/jira-sprint-loops/activity.md` file is now a frozen archive — its final content was copied into the artifact as seed history on 2026-08-11 and is no longer updated by either skill.)

1. `date "+%Y-%m-%d %H:%M"` (standalone Bash) → `TIMESTAMP`. Never print a literal placeholder — always the real command output (see the note on the final timestamp line below; the same rule applies here).
2. **Read** `~/.claude/jira-sprint-loops/activity.html` with the Read tool. It should always exist (seeded 2026-08-11) — if it's genuinely missing, print one warning line and skip publishing this run rather than guessing at replacement content.
3. **Build the new entry block:**
   ```html
   <article class="entry">
     <div class="entry-head">
       <span class="tag todoloop">jira-sprint-todo-loop</span>
       <span class="timestamp"><TIMESTAMP></span>
     </div>
     <div class="entry-body">
       <p class="logline">jira-sprint-todo-loop: <L> launched, <S> skipped</p>
       <p class="logline">Launched: <TICKET1> (<repo1>, <repo2>), <TICKET2> (<repo>)</p>
     </div>
   </article>
   ```
   (Omit the second `<p class="logline">Launched: …</p>` line entirely when `L == 0`, same rule as the terminal summary above.)
4. **Insert it as the first child of `<div class="entries">`** — directly after that opening tag, before any existing `<article class="entry">`. The artifact is newest-first; never append at the end.
5. **Bump the entry count** — find `<span><N> entries</span>` in the `.meta-strip` block and increment `N` by 1.
6. **Write** the updated file back to `~/.claude/jira-sprint-loops/activity.html` with the Write tool — never shell redirection.
7. **Publish it** — call the `Artifact` tool with `file_path: ~/.claude/jira-sprint-loops/activity.html`, `url` set to the fixed artifact URL above, and `favicon: 📋` (identical every time).

`jira-sprint-manager` uses the identical mechanism with its own entry template — see that skill's own SKILL.md for its exact entry content.

**The very last line printed, after the activity-log entry is written and immediately before the skill exits:**
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
