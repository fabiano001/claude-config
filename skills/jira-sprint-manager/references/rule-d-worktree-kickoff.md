# Rule D — In-Progress ticket implementation/research kickoff (worktree + Claude session) + SPIKE-close — full detail

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the comment scan, repo detection, worktree path computation, SPIKE detection, and the three phase paths (6a implementation, 6b research, 6a-spike spike-close).

## Trigger

The response contains at least ONE ticket whose `fields.status.name == "In Progress"`. Rule D evaluates each such ticket; the inner trigger (comment match) gates whether any action runs.

## Per-In-Progress-ticket handling (apply in board order — top of the IN PROGRESS lane first)

1. **Chain with Rule A (additive default).** Rule D explicitly chains with Rule A on tickets that Rule A just moved into In Progress this run — that ticket's `actionsTaken` already carries `"Moved to In Progress"` from Rule A, and Rule D will append its own outcome on top (typically the research-branch outcome, since a freshly-kicked-off ticket has no implementation-ready marker yet). **Exception (terminal skip):** if Rule A appended a `"Move failed: …"` entry for this ticket (the transition didn't actually land), the ticket is NOT really In Progress in Jira — Rule D MUST skip it in that case. Detect by scanning `actionsTaken` for an entry starting with `"Move failed"`.

2. **Fetch the ticket's comments.** Use `mcp__atlassian__getJiraIssue` with:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `fields`: `["comment", "description", "summary"]`

   (`description` and `summary` are also fetched here because step 4 uses them to detect the target repo.)

3. **Scan comment bodies for an implementation-ready marker.** Match any of these substrings case-insensitively against the flattened text of each comment body:
   - `ticket research completed`
   - `research completed`
   - `implementation ready`
   - `ready for implementation`

   Set `MARKER_FOUND = true` if any comment matches, otherwise `MARKER_FOUND = false`. **Do NOT early-out** — step 6 branches on this flag to choose between the implementation worktree path (marker found) and the research worktree path (marker not found). Both branches need the repo + paths computed in steps 4–5.

4. **Determine the target repo.** Match the ticket's `description` + `summary` text (case-insensitive) against this known-repo list (in priority order — more specific names first):
   - `portal-react-boattrader`
   - `webapp-react-trident`
   - `api-node-boats`
   - `api-node-boattrader`
   - `lambda-node-trident-700credit`
   - `lambda-node-trident-advertised-rates`
   - `lambda-node-trident-portal-lead`
   - `pp-algorithm`
   - `configd`

   The first repo name that appears in the ticket text wins. If none appear, **default to `webapp-react-trident`** (most TRIDENT-board tickets target it).

   The repo's main-repo absolute path is:
   ```
   ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>
   ```
   (Confirmed via `ls ~/BOATS-GROUP-PROJECTS-GITHUB/` — every repo in the list above lives at that path on this workstation.) If the resolved path does not exist, append to `actionsTaken`: `"Implementation kickoff skipped — repo <repo> not found at <path>"` and move on.

5. **Compute both per-ticket worktree paths** (both branches in step 6 need these — the impl path is used when the marker was found, the research path when it wasn't):
   ```
   IMPL_PATH     = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>
   RESEARCH_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>-research
   ```
   Examples for `TRIDENT-904` (`webapp-react-trident`):
   - `IMPL_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904`
   - `RESEARCH_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904-research`

   (Note: both naming conventions are distinct from the legacy `<repo>-worktree-<N>` numbered worktrees and the shared `<repo>-worktree-research` scratch worktree. The per-ticket worktrees are dedicated to one ticket each, with separate branches for the research vs. implementation phases.)

5.5. **Detect SPIKE.** A ticket is treated as a SPIKE if its `fields.summary` (already fetched in step 2) contains the substring `SPIKE` case-insensitively. On the Trident board, spike tickets follow the convention `FINANCE | SPIKE | <topic>` (e.g., `FINANCE | SPIKE | Medalion Bank connection`), so a case-insensitive substring match on `SPIKE` is sufficient. Set `IS_SPIKE = true` if the substring is present, otherwise `IS_SPIKE = false`.

   **Why this matters:** SPIKE tickets are research-only — the artifact IS the ticket-creator output (typically a refined description in Jira + supporting notes). There is no implementation phase, no PR, no QA cycle. Once research is complete (impl-ready marker on the ticket), the ticket moves straight from In Progress → Under review (skipping Testing) and the operator logs the hours spent on research.

   The research phase (step 6b) is identical for SPIKE and non-SPIKE tickets; only the marker-found branch differs.

6. **Branch on `MARKER_FOUND` and `IS_SPIKE` to choose the phase:**
   - `MARKER_FOUND == false` → **6b (research phase)** — same flow for SPIKE and non-SPIKE.
   - `MARKER_FOUND == true` AND `IS_SPIKE == false` → **6a (implementation phase)** — create the impl worktree + open `/ticket-driver`.
   - `MARKER_FOUND == true` AND `IS_SPIKE == true` → **6a-spike (spike-close phase)** — no worktree, no impl session; queue Q1 + Q2 to ask the operator about transitioning to Under review + logging hours.

### 6a. `MARKER_FOUND == true` AND `IS_SPIKE == false` (implementation phase) — operate on `IMPL_PATH` with branch `<TICKET-KEY>`

**6a-i. If `IMPL_PATH` EXISTS** (`test -d <IMPL_PATH>`):
- Append to `actionsTaken`: `"Reminded u to complete implementation under existing worktree <IMPL_PATH>"`.
- Append to `REMINDERS`: `"<TICKET-KEY>: Complete implementation under existing worktree at <IMPL_PATH>."`
- Do NOT create or open anything.

**6a-ii. If `IMPL_PATH` DOES NOT EXIST**, create it and open a Claude session:

1. **Discover branch state** for `<TICKET-KEY>`:
   - `git -C <main repo path> fetch --prune origin <TICKET-KEY>` (standalone Bash). May exit non-zero if the ref doesn't exist on the remote — capture the exit code, don't abort the rule.
   - `git -C <main repo path> rev-parse --verify --quiet refs/heads/<TICKET-KEY>` → `LOCAL_HAS_BRANCH` (true if exit 0).
   - `git -C <main repo path> ls-remote --exit-code --heads origin <TICKET-KEY>` → `REMOTE_HAS_BRANCH` (true if exit 0).

2. **Create the worktree** with the correct branch wiring:
   - `LOCAL_HAS_BRANCH=true` → `git -C <main repo path> worktree add <IMPL_PATH> <TICKET-KEY>` (reuse the existing local branch).
   - `LOCAL_HAS_BRANCH=false`, `REMOTE_HAS_BRANCH=true` → `git -C <main repo path> worktree add <IMPL_PATH> -b <TICKET-KEY> --track origin/<TICKET-KEY>` (create local tracking branch).
   - Both false → `git -C <main repo path> worktree add <IMPL_PATH> -b <TICKET-KEY> origin/main` (new branch off main).

   If the `worktree add` command fails for any reason (refs in use, permission denied, conflicting path), append to `actionsTaken`: `"Implementation kickoff skipped — worktree creation failed: <verbatim error>"` and stop the rule for this ticket. Print one terminal warning line.

3. **Open a new Claude session in the worktree** via the helper script at `~/.claude/skills/jira-sprint-manager/open-claude-session.sh`:
   ```
   ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     <IMPL_PATH> \
     --prompt "/ticket-driver <TICKET-KEY>"
   ```
   The script opens a new iTerm2 tab (in the existing iTerm2 window if one is open; Terminal.app fallback if iTerm2 isn't installed) in the worktree and starts a fresh `claude` with the slash command pre-submitted, so the new session immediately invokes `ticket-driver` for the ticket.

   If the script's exit code is non-zero, append to `actionsTaken`: `"Worktree created at <IMPL_PATH> but open-claude-session failed: exit <code>"` and continue with the rest of the workflow. The worktree is preserved either way.

4. On success: append to `actionsTaken`: `"Created worktree at <IMPL_PATH> and opened a new Claude session with /ticket-driver <TICKET-KEY>"`.

### 6a-spike. `MARKER_FOUND == true` AND `IS_SPIKE == true` (spike-close phase) — no worktree, no impl session

The research deliverable is complete. There is no code to implement and no testing cycle — the next state in the lifecycle is Under Review (skipping the Testing column), where stakeholders can read the research output and either close the ticket or spawn follow-up impl tickets.

**Do NOT create the impl worktree, do NOT call `open-claude-session.sh`, do NOT open `/ticket-driver`.** The research worktree (if it still exists on disk) is preserved as-is for the operator's reference; the spike-close phase only acts on Jira.

**Step 1 — Queue Q1 (yes/no) — move to Under review.**

Append a yes/no question to `QUESTIONS`:

```
<TICKET-KEY> is a SPIKE and research is complete (impl-ready marker found in comments). Ready to move it to Under Review and log hours? (Spikes skip the Testing column — the research IS the deliverable.) (yes/no)
```

**Step 2 — Apply Q1 answer (during Step 6 / question-collection in SKILL.md).**

- **Q1 = `no`** → do nothing. No transition, no worklog, no REMINDERS entry, no `actionsTaken` entry. The next run will re-fire Q1 as long as the ticket stays in In Progress with the impl-ready marker still present.

- **Q1 = `yes`** → proceed to step 3 (queue Q2 for hours).

**Step 3 — Queue Q2 (hours to log).**

Q2 fires ONLY when Q1 was yes. Use `AskUserQuestion` with 4 preset options + the automatic "Other" escape for custom values:

| Option label | Maps to `timeSpent` |
|---|---|
| `2h` | `"2h"` |
| `4h` | `"4h"` |
| `8h` | `"8h"` |
| `16h` | `"16h"` |
| Other (free text) | operator-typed string — pass through to `timeSpent` after trimming; if missing the trailing `h`/`d`/`m`/`w`, append `h` |

Question text:

```
How many hours to log on <TICKET-KEY>? Pick a preset or use Other to type your own (e.g., "5h", "1.5h", "1d"). Jira time syntax accepted.
```

**Step 4 — Apply Q2 answer (still during Step 6).**

1. **Look up the `Under review` transition** via `mcp__atlassian__getTransitionsForJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f` and `issueIdOrKey: <TICKET-KEY>`. Find the transition whose `to.name == "Under review"` (case-sensitive). On the Trident workflow this is currently transition id `201` (verified 2026-05-14, same id Rule E uses), but always look up at runtime — never hard-code.

2. **Execute the transition** via `mcp__atlassian__transitionJiraIssue`:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `transition`: `{ "id": "<captured id>" }`

   On error: append to `actionsTaken`: `"Spike-close failed: transition to Under review errored: <verbatim error>"`. Do NOT proceed to the worklog step (don't log time on a ticket whose status didn't change). Print one terminal warning line.

3. **Log the worklog** via `mcp__atlassian__addWorklogToJiraIssue`:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `timeSpent`: the Q2 answer (e.g., `"2h"`, `"4h"`, `"5h"`, `"1d"`)
   - `comment`: `"Spike research complete — logged via jira-sprint-manager Rule D spike-close."` (markdown content format)

   On error: append to `actionsTaken`: `"Spike-close partial: transitioned to Under review but worklog failed: <verbatim error>. Please log <hours> manually."`. The transition already landed, so status stays as `Under review`. Also append to `REMINDERS`: `"<TICKET-KEY>: Worklog of <hours> failed to land — log it manually in Jira."`.

4. **On full success** (both transition and worklog landed):
   - Update in-memory `fields.status.name = "Under review"` so Step 3 sorting puts the ticket in priority bucket 5 (UNDER REVIEW).
   - Append to `actionsTaken`: `"Spike moved to Under Review (transition id <id>) and logged <hours> via addWorklogToJiraIssue. Testing column intentionally skipped — research IS the deliverable for spike tickets."`.
   - No REMINDERS entry — the operator's next step (stakeholder review) is on the board, not in this report.

**Per-ticket question contract:** Rule D's spike-close phase asks up to TWO questions per ticket per run (Q1 + optional Q2). Q2 NEVER fires when Q1 = No. Both questions block in Step 6 only when the runtime is interactive; in the non-interactive runtime path (see SKILL.md's "Non-interactive runtime" note) the queue is left unanswered and the ticket stays put.

**Cross-rule note (chain):** Rule D's spike-close phase moves a ticket to `Under review`. Rule F (Under-Review PR-approval auto-transition) is the next rule in the run order — so a SPIKE ticket that just transitioned via 6a-spike will be evaluated by Rule F in the same run. However, SPIKE tickets typically have NO open PR (the deliverable is research notes, not code), so Rule F's "no open PR" gate fails silently and Rule F takes no action. If a SPIKE ticket DOES happen to have an approved PR (rare — e.g., a research spike that also produced a tiny config patch), Rule F will advance it further. That cross-rule chain is intentional and safe.

### 6b. `MARKER_FOUND == false` (research phase still in progress) — operate on `RESEARCH_PATH` with branch `<TICKET-KEY>-research`

The research worktree uses a **separate branch** named `<TICKET-KEY>-research` so research commits stay isolated from any implementation branch the operator may later create at `<TICKET-KEY>`. The two worktrees can coexist on disk and represent two phases of the same ticket.

**6b-i. If `RESEARCH_PATH` EXISTS** (`test -d <RESEARCH_PATH>`):
- Append to `actionsTaken`: `"Reminded u to complete ticket research under existing worktree <RESEARCH_PATH>"`.
- Append to `REMINDERS`: `"<TICKET-KEY>: Please complete ticket research under existing worktree at <RESEARCH_PATH>."`
- Do NOT create or open anything. **Exit the rule for this ticket** — once the operator finishes research and posts an implementation-ready comment, the next run will route to 6a.

**6b-ii. If `RESEARCH_PATH` DOES NOT EXIST**, create it and open a Claude session:

1. **Discover branch state** for `<TICKET-KEY>-research`:
   - `git -C <main repo path> fetch --prune origin <TICKET-KEY>-research` (standalone Bash). May exit non-zero if the ref doesn't exist on the remote — capture the exit code, don't abort the rule.
   - `git -C <main repo path> rev-parse --verify --quiet refs/heads/<TICKET-KEY>-research` → `LOCAL_HAS_RESEARCH_BRANCH`.
   - `git -C <main repo path> ls-remote --exit-code --heads origin <TICKET-KEY>-research` → `REMOTE_HAS_RESEARCH_BRANCH`.

2. **Create the worktree** with the correct branch wiring (same 3-case logic as 6a-ii.2 but for the `-research` branch):
   - `LOCAL_HAS_RESEARCH_BRANCH=true` → `git -C <main repo path> worktree add <RESEARCH_PATH> <TICKET-KEY>-research`.
   - `LOCAL_HAS_RESEARCH_BRANCH=false`, `REMOTE_HAS_RESEARCH_BRANCH=true` → `git -C <main repo path> worktree add <RESEARCH_PATH> -b <TICKET-KEY>-research --track origin/<TICKET-KEY>-research`.
   - Both false → `git -C <main repo path> worktree add <RESEARCH_PATH> -b <TICKET-KEY>-research origin/main`.

   If the `worktree add` command fails, append to `actionsTaken`: `"Research kickoff skipped — worktree creation failed: <verbatim error>"` and stop the rule for this ticket. Print one terminal warning line.

3. **Open a new Claude session in the research worktree** via the helper script:
   ```
   ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     <RESEARCH_PATH> \
     --prompt "/ticket-creator"
   ```
   The new session starts in the research worktree with `/ticket-creator` pre-submitted. The operator drives research from there and ultimately uses ticket-creator's output to refine the existing Jira ticket.

   If the script's exit code is non-zero, append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"` and continue with the rest of the workflow. The worktree is preserved either way.

4. On success: append to `actionsTaken`: `"Created research worktree at <RESEARCH_PATH> and opened a new Claude session with /ticket-creator"`.

## Failure modes summary

- Comments fetch fails → append to `actionsTaken`: `"Implementation kickoff skipped — Jira comment fetch failed: <error>"` (the same error path covers all three phases; the phase is reflected in the worktree path mentioned in subsequent actions, or in the lack of one for spike-close).
- Repo path not found → append to `actionsTaken`: `"Implementation kickoff skipped — repo <repo> not found at <path>"`. (For SPIKE tickets the repo isn't strictly needed since no worktree is created, but the repo-not-found check still runs in step 4 because it precedes the SPIKE-detection branch in step 5.5 — treat the skip as a deliberate guard rather than a bug.)
- **Implementation phase (6a):**
  - Worktree creation fails → append to `actionsTaken`: `"Implementation kickoff skipped — worktree creation failed: <error>"`.
  - Worktree created but open-claude-session script fails → append to `actionsTaken`: `"Worktree created at <IMPL_PATH> but open-claude-session failed: exit <code>"`.
- **Spike-close phase (6a-spike):**
  - Transition to `Under review` errors → append `"Spike-close failed: transition to Under review errored: <error>"`; worklog step is skipped (do not log time on a ticket whose status didn't change).
  - Transition succeeds but `addWorklogToJiraIssue` errors → append `"Spike-close partial: transitioned to Under review but worklog failed: <error>. Please log <hours> manually."`; also append a REMINDERS line so the operator catches the dangling worklog.
- **Research phase (6b):**
  - Worktree creation fails → append to `actionsTaken`: `"Research kickoff skipped — worktree creation failed: <error>"`.
  - Worktree created but open-claude-session script fails → append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"`.

Rule D's research and implementation phases never block on `AskUserQuestion` — the comment match (or absence thereof) IS the operator's signal for those. The **spike-close phase** is the lone exception — it queues Q1 (yes/no) and, on Q1=Yes, Q2 (hours). Both are answered in Step 6 of the parent SKILL.md workflow.

If the operator wants to override (e.g., not have a worktree auto-created for a non-spike ticket, or hold a spike at In Progress without transitioning), they should pre-create the worktree manually OR hold off on putting the ticket in In Progress until they're ready for the skill to act, OR (for spikes) answer Q1=No when prompted.
