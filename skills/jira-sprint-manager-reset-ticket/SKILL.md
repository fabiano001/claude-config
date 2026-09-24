---
name: jira-sprint-manager-reset-ticket
description: Fully resets an In Progress Jira ticket back to the TO DO column so jira-sprint-manager's own Rule A picks it up completely fresh next run — for a ticket that was kicked off but not really started yet, especially one whose requirements/scope changed since kickoff. Takes one required argument, the ticket key (e.g. TRIDENT-975). Refuses to run on anything except a ticket whose current status is exactly "In Progress" (use reset-ticket-driver directly for a TO-DO-column ticket, since no Jira transition is needed there). First finds every worktree on disk associated with the ticket (implementation AND the ticket-creator research worktree, both repo-<TICKET-KEY> and repo-<TICKET-KEY>-research) and checks each associated repo for an open PR via `gh pr list --head <TICKET-KEY>`. If any open PR exists, STOPS and asks the operator to explicitly confirm before proceeding, reminding them to decline/close the PR themselves first (this skill never touches PRs) — proceeds automatically with no question if none exist. Once cleared, delegates the implementation-worktree/branch/Jira-comment/sessions.md cleanup to the reset-ticket-driver skill, additionally removes the ticket-creator research worktree and its branch (which reset-ticket-driver deliberately leaves alone), and finally transitions the Jira ticket from In Progress back to a TO DO status (Reopened/Backlog/New, whichever the workflow exposes) so the next jira-sprint-manager run treats it as a fresh TO DO candidate. Use when the operator asks to reset, restart, or redo an in-progress ticket back to todo/backlog, wants to "start over" on a ticket whose scope changed after kickoff, or runs `/jira-sprint-manager-reset-ticket`. Does NOT touch the Jira Implementation Ready marker, Repos Involved comment, or ticket description/AC — only reset-ticket-driver's usual scope plus the research worktree and the status transition. Do NOT use on a ticket in Testing/Under Review/Stakeholder Review/PROD READY/Live/Done/Closed/Cancelled, or on a TO-DO-column ticket that just needs worktree cleanup with no status change (use reset-ticket-driver for that).
---

# jira-sprint-manager: reset an in-progress ticket to TO DO

Fully rewinds an **In Progress** ticket so it looks, to `jira-sprint-manager` Rule A and `jira-sprint-todo-loop`, exactly like a ticket that was never kicked off — worktrees gone (implementation AND research), ticket-driver's `sessions.md` bookkeeping gone, Jira status back in the TO DO column. Built for the case where a ticket was kicked off, nothing meaningful landed yet, and the requirements/scope have since changed enough that the operator wants a clean restart rather than patching the existing worktree.

This skill is a thin orchestrator over **[reset-ticket-driver](../reset-ticket-driver/SKILL.md)**, which already does the hard, safety-checked part (live-session gate, worktree/branch removal, "Started" comment neutralization, `sessions.md` cleanup) for the implementation worktree. This skill adds three things reset-ticket-driver deliberately does NOT do: the pre-flight open-PR confirmation gate, cleanup of the research worktree, and the Jira status transition back to TO DO.

## Fixed configuration

- **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`
- **GitHub org:** `boatsgroup`
- **Base projects dir:** `~/BOATS-GROUP-PROJECTS-GITHUB`
- **TO DO column statuses (preference order for the reverse transition):** `Reopened` > `Backlog` > `New`

## Input

One required argument: the **ticket key** (e.g. `TRIDENT-975`). If missing, ask for it before doing anything else.

## Workflow

### Step 1 — Fetch the ticket and gate on status

`mcp__atlassian__getJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`, `issueIdOrKey: <TICKET-KEY>`, `fields: ["status"]`.

If the fetch fails, report the verbatim error and stop — no mutation.

Check `fields.status.name` (case-insensitive) equals exactly `In Progress`. If not:

```
jira-sprint-manager-reset-ticket: <TICKET-KEY> is in "<status>", not In Progress — this skill only resets in-progress tickets.
<If status is New/Backlog/Reopened:> It's already in TO DO. If you just want its worktree(s) cleared, run /reset-ticket-driver <TICKET-KEY> directly — no status transition needed.
```

Stop here. Nothing else runs.

### Step 2 — Find every worktree associated with this ticket

```
find ~/BOATS-GROUP-PROJECTS-GITHUB -maxdepth 1 -type d -name "*-<TICKET-KEY>"
find ~/BOATS-GROUP-PROJECTS-GITHUB -maxdepth 1 -type d -name "*-<TICKET-KEY>-research"
```

(two standalone Bash calls, end-anchored patterns — matches `reset-ticket-driver`'s own convention). From the first, derive each **implementation repo** by stripping the trailing `-<TICKET-KEY>`. From the second, derive each **research repo** by stripping the trailing `-<TICKET-KEY>-research`.

Build `ALL_REPOS` as the deduplicated union of both sets. Zero matches in either is not an error — continue regardless (there may still be Jira comments or a `sessions.md` entry with no worktree left on disk).

### Step 3 — Open-PR check (MANDATORY, before touching anything)

For each repo in `ALL_REPOS`:

```
gh pr list --repo boatsgroup/<repo> --head <TICKET-KEY> --state open --json url,number,title
```

(`--head` is always the plain `<TICKET-KEY>` branch — only `ticket-driver`'s implementation branch is ever opened as a PR; the research worktree's `<TICKET-KEY>-research` branch never is, but checking every repo in `ALL_REPOS` is cheap and avoids assuming that stays true forever.)

Collect every open PR found, across every repo, into `OPEN_PRS` (repo, url, number, title).

**If `gh` itself errors** for a given repo (auth/network), do NOT treat that as "no PR" — treat it as unverifiable and fold it into the same confirmation gate below as if a PR were found, naming the repo and the verification failure explicitly instead of a PR URL.

#### Gate

- **`OPEN_PRS` is empty and every repo verified cleanly** → no question, proceed straight to Step 4.
- **`OPEN_PRS` is non-empty, or any repo was unverifiable** → **STOP and ask the operator**, via `AskUserQuestion`:

  > `<TICKET-KEY>` has an open PR still referencing it:
  > - `<repo>`: `<url>` — "`<title>`"
  > (one line per open PR; for an unverifiable repo instead: `<repo>: could not verify open-PR status (<error>)`)
  >
  > Resetting will remove the local worktree(s) and branch(es) for this ticket, but `reset-ticket-driver` will refuse to delete a remote branch that still has an open PR — that PR will keep pointing at a now-deleted local setup. **Decline or close the PR(s) yourself first if you don't want that** — this skill never touches PRs.
  >
  > Proceed with the reset anyway?

  Options: **"No, stop"** (recommended-first — this is a destructive action on top of unresolved review state) / "Yes, proceed anyway".

  - **"No, stop"** → print `jira-sprint-manager-reset-ticket: stopped at the operator's request — <TICKET-KEY> has open PR(s), nothing was changed.` Stop. No mutation of any kind, including no Jira status transition.
  - **"Yes, proceed anyway"** → continue to Step 4, and carry a note into the Step 7 summary that the operator explicitly confirmed proceeding with open PR(s) referenced above still in place.

### Step 4 — Delegate implementation-worktree cleanup to reset-ticket-driver

Invoke the **reset-ticket-driver** skill with `<TICKET-KEY>` as its argument. Let it run its full workflow (its own ticket fetch, its own live-ticket-driver-session gate, worktree/branch removal, "Ticket Driver Implementation Started" comment neutralization, and its `sessions.md` cleanup of `## ticket-driver` / `## ticket-driver (TODO mode)` subentries).

**Read its own printed summary to determine the outcome:**

- **It reports a live-session abort** (its Step 4: `"...has a live ticket-driver session ... still running ..."`) → this skill MUST also stop here. Do not touch the research worktree and do not transition Jira status — the ticket genuinely still has work in flight, so leaving it exactly as-is (including its In Progress status) is correct. Print: `jira-sprint-manager-reset-ticket: stopped — reset-ticket-driver found a live session for <TICKET-KEY> (see above). Close it first, then re-run this skill.`
- **It reports the status-gate rejection** (its Step 2) → this shouldn't happen here since Step 1 above already confirmed `In Progress`, which reset-ticket-driver also accepts. If it somehow does happen anyway (e.g. the status changed between this skill's Step 1 and this call), stop and report the discrepancy rather than guessing.
- **Otherwise (it completed)** → continue to Step 5, regardless of whether individual repos inside it hit their own non-fatal failures (worktree force-removed, remote branch left in place due to a PR, etc. — those are already reported by reset-ticket-driver's own summary and don't block this skill's remaining steps).

### Step 5 — Remove the research worktree(s)

Skipped entirely if Step 4 aborted.

For each **research repo** found in Step 2 (the `<repo>-<TICKET-KEY>-research` set):

1. **Remove the worktree:**
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> worktree remove ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>-research
   ```
   On failure due to uncommitted/untracked changes, retry with `--force` and print the same kind of warning reset-ticket-driver prints for the implementation worktree: `"<repo>-<TICKET-KEY>-research had uncommitted changes — force-removed. Anything not committed or pushed is now gone."` If it still fails, report the verbatim error, skip branch deletion for this repo, and move to the next.

2. **Delete the local `<TICKET-KEY>-research` branch, if it exists:**
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> rev-parse --verify --quiet refs/heads/<TICKET-KEY>-research
   ```
   Exit 0 → `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> branch -D <TICKET-KEY>-research`. Non-zero → nothing to delete.

3. **Delete the remote `<TICKET-KEY>-research` branch, only if pushed AND no open PR references it** (same caution as reset-ticket-driver, even though a PR against a research branch would be unusual):
   ```
   git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> ls-remote --exit-code --heads origin <TICKET-KEY>-research
   ```
   Non-zero → nothing to do. Exit 0 → `gh pr list --repo boatsgroup/<repo> --head <TICKET-KEY>-research --state open --json url,number` first; if any open PR is found or `gh` errors, leave the remote branch in place and report why; otherwise `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> push origin --delete <TICKET-KEY>-research`.

4. Record this repo's outcome for the Step 7 summary.

**Note — sessions.md is intentionally NOT touched here.** Step 4's delegation only removes `## ticket-driver` subentries; the ticket-creator research worktree may still have a `## ticket-creation` (or similar) subentry in `~/.claude/memory/sessions.md` pointing at the now-deleted `-research` directory. This is deliberate scope: the operator's request was to clear `ticket-driver` bookkeeping specifically, and `ticket-creator`'s own bookkeeping is out of scope for this skill, same as it's out of scope for reset-ticket-driver. A stale `sessions.md` line pointing at a deleted directory is harmless (the next attempt to resume it would just fail loudly) — flag it in the summary rather than silently leaving it unmentioned.

### Step 6 — Transition Jira status back to TO DO

Skipped entirely if Step 4 aborted.

1. `mcp__atlassian__getTransitionsForJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`, `issueIdOrKey: <TICKET-KEY>`.
2. Walk the returned `transitions` array and pick the **first** whose target status name (`to.name`, case-insensitive) matches, **in this preference order**: `Reopened`, then `Backlog`, then `New`. (`Reopened` is preferred when available — this ticket already had work started on it once, which is exactly what "reopened" means; `Backlog`/`New` are fallbacks for workflows that don't expose a distinct Reopened transition from In Progress.)
3. **No match found among the three** → do NOT guess with some other transition. Print the full list of available `to.name` values and: `jira-sprint-manager-reset-ticket: <TICKET-KEY>'s worktree(s)/sessions.md/comments are cleared, but no transition to Reopened/Backlog/New is available from "In Progress" in this workflow — move it to TO DO manually in Jira. Available transitions: <list>.` Continue to Step 7 anyway (the cleanup already happened; only the status transition is incomplete).
4. **Match found** → `mcp__atlassian__transitionJiraIssue` with that transition's `id`. On success, note the exact target status name landed on (it may differ between Reopened/Backlog/New depending on what the workflow exposed). On failure, report the verbatim error — the cleanup already happened either way, only the status transition failed.

### Step 7 — Print the summary

```
jira-sprint-manager-reset-ticket: <TICKET-KEY> (was "In Progress")

Open-PR check: <no open PRs found | operator confirmed proceeding despite open PR(s): <repo>: <url>, ...>

reset-ticket-driver: <paste or paraphrase its own summary outcome — repos processed, comments neutralized, sessions.md ticket-driver entries removed>

Research worktree(s):
  <repo>-<TICKET-KEY>-research: worktree removed (or force-removed), local branch deleted, remote branch deleted (or left in place — reason)
  ... (or: "No research worktree found on disk for <TICKET-KEY>")
  Note: sessions.md may still have a stale ticket-creation entry pointing at the deleted research worktree — not touched by this skill.

Jira status: moved to "<Reopened|Backlog|New>"   (or: "NOT transitioned — no matching transition available, move it manually")

<TICKET-KEY> is now clear to be picked up fresh from TO DO by jira-sprint-manager or jira-sprint-todo-loop.
```

## Failure modes

- **Ticket fetch fails (Step 1)** → report verbatim error, stop. No mutation.
- **Status isn't exactly "In Progress" (Step 1)** → report the status, stop. No mutation.
- **`gh pr list` errors for a repo (Step 3)** → treated as unverifiable, folds into the confirmation gate exactly like a found PR would.
- **Operator declines at the confirmation gate (Step 3)** → stop entirely. No mutation of any kind.
- **reset-ticket-driver aborts on a live session (Step 4)** → stop entirely here too. No research-worktree cleanup, no Jira transition.
- **`git worktree remove` fails even with `--force` (Step 5)** → report the verbatim error, skip branch deletion for that repo only, continue with the rest of Step 5, then continue to Step 6.
- **No Reopened/Backlog/New transition available (Step 6)** → report the available transitions, leave status as-is, continue to Step 7 (cleanup already happened).

## Bash safety rules

- NEVER use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution (`$(...)`, `${...}`).
- NEVER use `&&`, `;`, or `||` to chain commands — split into separate Bash calls.
- Use absolute paths everywhere; never use `cd`.
- Never `rm -rf` a worktree directory directly — always `git worktree remove` (matches `reset-ticket-driver`'s own rule; a raw `rm` leaves `.git/worktrees/` metadata stale and this environment blocks mass-delete shell commands outright).
