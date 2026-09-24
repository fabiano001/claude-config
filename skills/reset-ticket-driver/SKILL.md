---
name: reset-ticket-driver
description: Resets a Jira ticket's /ticket-driver work so it can be picked up completely fresh by jira-sprint-manager Rule D or jira-sprint-todo-loop. Takes one required argument, the ticket key (e.g. TRIDENT-975). Does nothing and exits immediately unless the ticket's current status is in the TO DO column (New/Backlog/Reopened) or In Progress — any other status (Testing, Under Review, Stakeholder Review, PROD READY, Live, Done, Closed, Cancelled) is left completely untouched. For each implementation worktree found on disk at ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY> (one per repo the ticket touched — NOT the ticket-creator research worktree, which is left alone), removes the git worktree (force-removing and warning if uncommitted changes exist), deletes the local <TICKET-KEY> branch, and deletes the remote branch too if it was pushed (skipped with a warning instead if an open PR still references it, to avoid silently closing that PR). Refuses to touch anything at all if a live ticket-driver background session for this ticket is still running (checked via the same claude-agents liveness pattern jira-sprint-manager uses) — tell the operator to close it first. Neutralizes every "Ticket Driver Implementation Started (<repo>): <timestamp>" Jira comment on the ticket by editing its body to a placeholder (Jira's API has no comment-delete tool available here, so this is the closest functional equivalent — it stops ticket-driver's own pre-run Guard from seeing a stale Started marker); leaves any "Ticket Driver Implementation Completed" comment, the Repos Involved comment, and the Implementation Ready marker untouched. Removes only the "## ticket-driver" (and "## ticket-driver (TODO mode)") subentries for this ticket from ~/.claude/memory/sessions.md, leaving ticket-creation/other entries for the same ticket in place; removes the ticket's whole entry if nothing else is left under it. Use when the operator asks to reset, restart, redo, or abandon-and-retry a ticket's /ticket-driver implementation, or wants a stalled/broken run cleared before jira-sprint-manager or jira-sprint-todo-loop picks the ticket up again. Does NOT touch Jira status/transitions, does NOT touch the ticket-creator research worktree or its branch, and refuses to run on a ticket past In Progress. For an In Progress ticket that should go all the way back to the TO DO column (Jira status transition included, research worktree included, plus an open-PR confirmation gate first) use jira-sprint-manager-reset-ticket instead, which calls this skill internally for the implementation-worktree part.
---

# Reset ticket-driver

Wipes out everything `/ticket-driver` created for a ticket — worktree(s), branch(es), the Jira "Started" marker(s), and the `sessions.md` bookkeeping — so the next `jira-sprint-manager` or `jira-sprint-todo-loop` run treats it as if implementation never began. Leaves everything `ticket-creator` did (research worktree, Repos Involved comment, Implementation Ready marker, `## ticket-creation` sessions.md entry) completely alone.

**⚠️ Do not run this while a `ticket-driver` session for this ticket is still open in the background-agent view.** Step 2 checks for exactly this and refuses to proceed if it finds one — but if you already know a session is open, close it first rather than relying on the check.

## Fixed configuration

- **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
- **TO DO column statuses:** `New`, `Backlog`, `Reopened`
- **In Progress status:** `In Progress`
- **Base projects dir:** `~/BOATS-GROUP-PROJECTS-GITHUB`

## Input

One required argument: the **ticket key** (e.g. `TRIDENT-975`). If missing from the invocation, ask for it before doing anything else.

## Workflow

### Step 1 — Fetch the ticket

`mcp__atlassian__getJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`, `issueIdOrKey: <TICKET-KEY>`, `fields: ["status", "comment"]`.

If the fetch fails, report the verbatim error and stop — no mutation.

### Step 2 — Gate on status

Check `fields.status.name` (case-insensitive) against `New`, `Backlog`, `Reopened`, `In Progress`. If it does NOT match one of these, print exactly one line:

```
reset-ticket-driver: <TICKET-KEY> is in "<status>" — only TO DO (New/Backlog/Reopened) or In Progress tickets can be reset. No changes made.
```

Stop here. Nothing else in this workflow runs.

### Step 3 — Find this ticket's ticket-driver worktrees on disk

```
find ~/BOATS-GROUP-PROJECTS-GITHUB -maxdepth 1 -type d -name "*-<TICKET-KEY>"
```

(standalone Bash, end-anchored pattern.) This matches only the implementation worktree naming convention `<repo>-<TICKET-KEY>` — it does **not** match the ticket-creator research worktree (`<repo>-<TICKET-KEY>-research`), which ends in `-research` and is out of scope for this skill.

For each match, derive `<repo>` by stripping the trailing `-<TICKET-KEY>` from the directory's basename (unambiguous — ticket keys are uppercase `PROJECT-NUMBER`, repo names are lowercase-hyphenated, so the suffix can't collide with part of a repo name).

**Zero matches is not an error** — it means `ticket-driver` never actually created a worktree for this ticket (or a prior reset already cleared it). Continue to Step 4 and 5 anyway; a ticket can still have a stale "Started" comment or `sessions.md` entry with no worktree left on disk (e.g. someone deleted it by hand), and this skill should clean those up too, idempotently.

### Step 4 — Live-session safety check (MANDATORY, before touching anything)

1. Read `~/.claude/memory/sessions.md`. Find the block starting with a line matching `# <TICKET-KEY>` exactly OR `# <TICKET-KEY> (...)` (same matching rule `ticket-creator`/`ticket-driver`/`jira-sprint-manager` already use elsewhere).
2. Within that block, collect the `session id:` value from every `## ticket-driver` or `## ticket-driver (TODO mode)` subentry (there can be more than one — one per repo the ticket touched).
3. For each collected session id, run the **live-agent check** ([jira-sprint-manager's references/live-agent-check.md](../jira-sprint-manager/references/live-agent-check.md)): `claude agents --all --json`, does an entry with this `sessionId` carry a `pid`?
4. **If ANY session is live:** STOP THE ENTIRE RESET. Do not remove any worktree, branch, comment, or `sessions.md` entry — not just for that session's repo, all of it. Print:
   ```
   reset-ticket-driver: <TICKET-KEY> has a live ticket-driver session ("<AGENT_NAME>") still running in the background. Close it first (via `claude agents`), then re-run this skill. No changes made.
   ```
5. **If none are live** (or no `## ticket-driver` sessions.md entries exist at all — nothing to check), proceed to Step 5.

### Step 5 — Per-repo cleanup

For each worktree found in Step 3, in order:

1. **Remove the worktree:**
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> worktree remove ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>
   ```
   If this fails because of uncommitted/untracked changes (git's own error names this — "contains modified or untracked files, use --force"), retry with `--force` and print a clear warning naming exactly what was discarded:
   ```
   reset-ticket-driver: <repo>-<TICKET-KEY> had uncommitted changes — force-removed. Anything not committed or pushed is now gone.
   ```
   If it still fails after `--force` (e.g. permission error), report the verbatim error, **skip branch deletion for this repo** (the worktree still exists and may still have the branch checked out), and move to the next repo.

2. **Delete the local branch, if it exists:**
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> rev-parse --verify --quiet refs/heads/<TICKET-KEY>
   ```
   Exit 0 → `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> branch -D <TICKET-KEY>`. Non-zero → nothing to delete locally.

3. **Delete the remote branch, only if it exists AND has no open PR:**
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> ls-remote --exit-code --heads origin <TICKET-KEY>
   ```
   - **Non-zero (not pushed)** → nothing to do remotely.
   - **Exit 0 (pushed)** → check for an open PR first:
     ```
     gh pr list --repo boatsgroup/<repo> --head <TICKET-KEY> --state open --json url,number
     ```
     - **`gh` errors** (network/auth) → do NOT delete the remote branch — we can't verify PR state, and deleting blind risks closing a PR nobody told us about. Report: `"<repo>: could not verify open-PR status (<error>) — remote branch <TICKET-KEY> left in place, delete manually if safe."`
     - **≥1 open PR found** → skip the remote delete. Report: `"<repo>: open PR <url> still references <TICKET-KEY> — remote branch left in place. Close/handle the PR first if you want it fully removed."`
     - **No open PR** → `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> push origin --delete <TICKET-KEY>`.

4. Record this repo's outcome (worktree removed / force-removed / failed; local branch deleted / none; remote branch deleted / skipped-open-PR / skipped-unverifiable / none) for the Step 8 summary.

### Step 6 — Neutralize "Ticket Driver Implementation Started" comments

Using the comments already fetched in Step 1 (no need to re-fetch), scan for any whose body contains the case-insensitive substring `ticket driver implementation started`. There can be more than one (one per repo `ticket-driver` ran in).

**Jira's API has no comment-delete tool available here** — `mcp__atlassian__addCommentToJiraIssue` can only add a new comment or update an existing one's body via `commentId`. Updating is the closest functional equivalent to deletion: for each matching comment, call it with:
- `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
- `issueIdOrKey`: `<TICKET-KEY>`
- `commentId`: the matched comment's id
- `commentBody`: `_[Cleared by /reset-ticket-driver on <today's date, YYYY-MM-DD>]_`
- `contentFormat`: `markdown`

The replacement text must NOT contain the phrase "ticket driver implementation started" in any form — `ticket-driver`'s own pre-run Guard does a case-insensitive substring match across all comments, so leaving that phrase in (even struck through) would still block a fresh run.

**Leave any "Ticket Driver Implementation Completed" comment untouched** — out of scope for this skill (only "Started" markers are neutralized, per how this skill was specified). If one is found, note it in the Step 8 summary as a heads-up — its presence on a TODO/In-Progress ticket is unusual and worth the operator's attention, but this skill does not act on it.

Also leave the **Repos Involved** comment and the **Implementation Ready marker** comment untouched — those belong to `ticket-creator`, not `ticket-driver`.

### Step 7 — Clean `~/.claude/memory/sessions.md`

1. Read the file. If the ticket's `# <TICKET-KEY>` block (same matching rule as Step 4) doesn't exist, this step is a no-op — skip to Step 8.
2. Within that block, remove every `## ticket-driver` or `## ticket-driver (TODO mode)` subentry — its heading line, its bullet lines (`session id:`, `repo/dir:`, `date:`), and the trailing blank line — but leave every OTHER subentry under the same header untouched (`## ticket-creation`, `## jira-sprint-manager (spike research worktree)`, etc.).
3. **If zero subentries remain under the `# <TICKET-KEY>` header after removal**, remove the header block entirely too (no point leaving a bare `# TRIDENT-975` heading with nothing under it).
4. Write the updated file back with the Write tool — **never** shell redirection (`>`, `>>`) or `echo`.

### Step 8 — Print the summary

One report covering everything that happened:

```
reset-ticket-driver: <TICKET-KEY> (was "<status>")

Repos processed: <repo1>, <repo2>, ...
  <repo1>: worktree removed (or force-removed — uncommitted changes discarded), local branch deleted, remote branch deleted
  <repo2>: worktree removed, local branch deleted, remote branch left in place — open PR <url>
  ...

Comments neutralized: <N> "Ticket Driver Implementation Started" comment(s)
  (heads-up: a "Ticket Driver Implementation Completed" comment also exists and was left untouched — verify this ticket's real state)   [only if applicable]

sessions.md: removed <N> ticket-driver subentry/entries for <TICKET-KEY>   (or: "no ticket-driver entries found — nothing to remove")

<TICKET-KEY> is now clear to be picked up fresh by jira-sprint-manager or jira-sprint-todo-loop.
```

If Step 3 found zero worktrees, say so plainly (`No ticket-driver worktrees found on disk for <TICKET-KEY>`) rather than omitting the line.

## Failure modes

- **Ticket fetch fails (Step 1)** → report verbatim error, stop. No mutation.
- **Status gate fails (Step 2)** → report the status, stop. No mutation.
- **A ticket-driver session is live (Step 4)** → report which one, stop entirely. No mutation to ANY repo, comment, or sessions.md, even for repos whose session isn't the live one — this is an all-or-nothing gate, not per-repo.
- **`git worktree remove` fails even with `--force`** → report the verbatim error, skip local+remote branch deletion for that repo only, continue with the rest.
- **`gh pr list` errors** → leave the remote branch in place for that repo, report why, continue with the rest.
- **Jira comment update fails** → report the verbatim error for that specific comment, continue neutralizing any others found, continue to Step 7 regardless.
- **`sessions.md` write fails** → report the verbatim error; the worktree/branch/comment cleanup already completed is not rolled back (this step is bookkeeping, not a correctness gate for the reset itself).

## Bash safety rules

- NEVER use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution (`$(...)`, `${...}`).
- NEVER use `&&`, `;`, or `||` to chain commands — split into separate Bash calls.
- Use absolute paths everywhere; never use `cd`.
- Use the Write tool to write files; never `echo "…" > file`.
- Never `rm -rf` a worktree directory directly — always `git worktree remove` (which also cleans up `.git/worktrees/` metadata that a raw `rm` would leave stale, and matches this environment's hook that blocks mass-delete shell commands outright).
