# Rule D — In-Progress ticket implementation/research kickoff (worktree + Claude session) + SPIKE-close — full detail

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the comment scan, repo detection, worktree path computation, SPIKE detection, and the three phase paths (6a implementation, 6b research, 6a-spike spike-close).

## Trigger

The response contains at least ONE ticket whose `fields.status.name == "In Progress"`. Rule D evaluates each such ticket; the inner trigger (comment match) gates whether any action runs.

## Per-In-Progress-ticket handling (apply in board order — top of the IN PROGRESS lane first)

1. **Chain with Rule A (additive default).** Rule D explicitly chains with Rule A on tickets that Rule A just moved into In Progress this run via its classic candidate walk — that ticket's `actionsTaken` already carries `"Moved to In Progress"` from Rule A, and Rule D will append its own outcome on top (typically the research-branch outcome, since a freshly-kicked-off ticket has no implementation-ready marker yet). **Two exceptions (both terminal skips), check both:**
   - If Rule A appended a `"Move failed: …"` entry for this ticket (the transition didn't actually land), the ticket is NOT really In Progress in Jira — Rule D MUST skip it. Detect by scanning `actionsTaken` for an entry starting with `"Move failed"`.
   - If Rule A marked this ticket `Rule-D-SKIP` (its Step 0 — the TODO-MODE priority check, see `rule-a-kickoff.md` — determined this ticket's implementation is already underway or done via `ticket-driver TODO-MODE`, and transitioned it for that reason), Rule D MUST also skip it — even though the transition DID land this time. There's no worktree to create and no session to launch; `actionsTaken` will show `"Moved to In Progress — TODO-MODE implementation already underway, no worktree/session needed"` for this ticket instead of the plain `"Moved to In Progress"`, which is the detectable signal.

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

3.5. **Scan comment bodies for the repos-involved marker.** `/ticket-creator` always posts a comment of this exact shape as part of ticket generation (see its "Repos Involved (Add as a comment)" section):

   ```
   This ticket will involve changes in these repos: <repo1>, <repo2>, …
   ```

   Match case-insensitively against the trimmed start of each comment body: `this ticket will involve changes in these repos:`. If **zero** comments match, `REPOS_FROM_COMMENT = []` (ticket predates this convention, or was created manually outside `/ticket-creator` — fall through to the legacy text-scan logic in step 4). If **one or more** match, take the **most recently created** matching comment (a later comment may supersede an earlier one if the ticket's scope was revised) and parse everything after the colon as a comma-separated list:
   - Trim whitespace from each entry.
   - Match each, case-insensitively, against the known-repo list from step 4 below.
   - Entries that match (case-insensitively) are normalized to the list's canonical casing/hyphenation.
   - Entries that do NOT match any known repo are dropped and recorded: append `"Repos-comment listed unrecognized repo '<name>' for <TICKET-KEY> — skipped"` to `actionsTaken`. Do not invent a disk path for an unrecognized name.

   The surviving, deduped, normalized list is `REPOS_FROM_COMMENT`. This can still end up empty (e.g., every entry was unrecognized) — treat that identically to "zero comments matched" for step 4's purposes.

4. **Determine the target repo(s).** `REPOS_FROM_COMMENT` (step 3.5) is checked FIRST in both phases — it's the authoritative signal because `/ticket-creator` derived it from the actual clarification interview, not from fuzzy text-matching against prose. The legacy logic below is the fallback for tickets that predate the convention or were created outside `/ticket-creator`. The phase-specific logic (which still applies whenever `REPOS_FROM_COMMENT` is empty) differs depending on whether `MARKER_FOUND` is true (implementation phase) or false (research phase):

   **Known-repo list** (checked case-insensitively, in priority order — more specific names first):
   - `portal-react-boattrader`
   - `webapp-react-trident`
   - `api-node-boats`
   - `api-node-boattrader`
   - `lambda-node-trident-700credit`
   - `lambda-node-trident-advertised-rates`
   - `lambda-node-trident-portal-lead`
   - `lambda-node-trident-partner-lender`
   - `pp-algorithm`
   - `configd`
   - `terraform-stack-trident`

   The repo's base path on disk is `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`.

   ### 4a. When `MARKER_FOUND == false` (research phase) — single repo
   **If `REPOS_FROM_COMMENT` (step 3.5) is non-empty**, use its first entry as the repo — research always runs in one primary worktree, even when the comment already names multiple implementation-phase repos. Set `TARGET_REPOS = [REPOS_FROM_COMMENT[0]]` and skip the rest of this sub-step.

   Otherwise (legacy fallback): match the ticket's `description` + `summary` text against the known-repo list. The **first** match wins. If none appear, default to `webapp-react-trident`. Set `TARGET_REPOS = [<single repo>]`.

   ### 4b. When `MARKER_FOUND == true` (implementation phase) — multi-repo scan
   **If `REPOS_FROM_COMMENT` (step 3.5) is non-empty**, use it directly: `TARGET_REPOS = REPOS_FROM_COMMENT`. Skip the Documentation/Technical-Details scan AND the ask-operator fallback below entirely — the comment is the authoritative source of scope precisely because it was captured during `/ticket-creator`'s clarification interview, not inferred from prose after the fact. Proceed straight to the disk-path existence check at the end of this sub-step.

   Otherwise (legacy fallback — ticket predates the repos-comment convention, or every entry in the comment was unrecognized): research is complete and we are about to create implementation worktrees. At this point we want to be precise about which repos will actually receive code changes, because creating a spurious worktree in the wrong repo is noise. Scan in this priority order:

   1. **Scan the `Documentation` and `Technical Details` (or `Technical Detail`) sections of the ticket description first.** These sections are the most authoritative source of implementation scope. Collect ALL known-repo names that appear there — this may yield more than one (e.g., both `webapp-react-trident` and `api-node-boattrader` mentioned for a cross-service feature).

   2. **If no repos were found in those sections**, fall back to scanning the full description + summary (same as the research-phase logic) and take **all** matches (not just the first).

   3. **If still no repos found**, and the ticket gives no clear signal:
      - If running **interactively**, use `AskUserQuestion` with the message: `"<TICKET-KEY>: I couldn't determine which repo(s) this ticket targets from the description. Which repo(s) should I create implementation worktrees in? (comma-separated, e.g. webapp-react-trident, api-node-boattrader)"`. Use the operator's answer verbatim, matching each entry against the known-repo list. If an entry doesn't match any known repo, note it in `actionsTaken` and skip creating a worktree for it.
      - If running **autonomously** (autonomous mode — though Rule D is normally skipped there), default to `webapp-react-trident` and note the fallback.

   **Disk-path existence check (applies regardless of which path above set `TARGET_REPOS`** — the `REPOS_FROM_COMMENT` shortcut, or the legacy 3-step scan): remove duplicates, then for each repo in `TARGET_REPOS`, if its resolved path (`~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`) does not exist on disk, append `"Implementation kickoff skipped for <repo> — not found at <path>"` to `actionsTaken` and remove it from `TARGET_REPOS`. If `TARGET_REPOS` is empty after removals, halt Rule D for this ticket.

5. **Compute worktree paths.**

   **Research phase (MARKER_FOUND == false) — single path:**
   ```
   RESEARCH_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>-research
   ```
   Example for `TRIDENT-904` (`webapp-react-trident`):
   - `RESEARCH_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904-research`

   **Implementation phase (MARKER_FOUND == true) — one path per repo in TARGET_REPOS:**
   ```
   IMPL_PATH(<repo>) = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>
   ```
   Examples for `TRIDENT-904` targeting `webapp-react-trident` + `api-node-boattrader`:
   - `~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904`
   - `~/BOATS-GROUP-PROJECTS-GITHUB/api-node-boattrader-TRIDENT-904`

   (These naming conventions are distinct from the legacy `<repo>-worktree-<N>` numbered worktrees. Per-ticket worktrees are dedicated to one ticket each.)

5.5. **Detect SPIKE.** A ticket is treated as a SPIKE if its `fields.summary` (already fetched in step 2) contains the substring `SPIKE` case-insensitively. On the Trident board, spike tickets follow the convention `FINANCE | SPIKE | <topic>` (e.g., `FINANCE | SPIKE | Medalion Bank connection`), so a case-insensitive substring match on `SPIKE` is sufficient. Set `IS_SPIKE = true` if the substring is present, otherwise `IS_SPIKE = false`.

5.6. **Compute `SESSION_NAME` for every `open-claude-session.sh` call that opens a NEW session in this rule** (i.e. every call below that passes `--prompt` without `--resume` — resumed sessions in Rule B/C already carry the name they were given here at creation and don't need it re-passed). Format: `<TICKET-KEY>-<SEGMENT>`.

   - **If `IS_SPIKE == true`:** `SEGMENT = "SPIKE"`, regardless of repo. (A spike only ever reaches the research phase below — 6a-spike never creates a worktree or session, so `SEGMENT` for a spike is always `SPIKE`, never a repo code.)
   - **Otherwise, `SEGMENT` is derived from the repo this specific worktree/session is for** (the research phase's single repo, or — in the implementation-phase loop — the current repo in `TARGET_REPOS`), per this table:

     | Repo | SEGMENT |
     |---|---|
     | `webapp-react-trident` | `WEBAPP` |
     | `portal-react-boattrader` | `PRBT` |
     | `lambda-node-trident-700credit`, `lambda-node-trident-advertised-rates`, `lambda-node-trident-portal-lead`, `lambda-node-trident-partner-lender` (any repo name containing `lambda`) | `LAMBDA` |
     | anything else (`api-node-boats`, `api-node-boattrader`, `pp-algorithm`, `configd`, `terraform-stack-trident`, or an unrecognized repo) | the repo's own name, spelled out verbatim (e.g. `api-node-boats`) |

   Examples: `TRIDENT-904-WEBAPP` (research or impl session in `webapp-react-trident`), `TRIDENT-912-LAMBDA` (impl session in `lambda-node-trident-700credit`), `TRIDENT-930-SPIKE` (a spike's research session, whatever repo it happens to run in), `TRIDENT-940-pp-algorithm` (impl session in a repo with no dedicated abbreviation).

   In the **implementation-phase loop (6a)**, `SESSION_NAME` is recomputed per repo on each iteration — each repo's session gets its own name, since `TARGET_REPOS` can contain more than one repo for the same ticket.

   **Why this matters:** SPIKE tickets are research-only — the artifact IS the ticket-creator output (typically a refined description in Jira + supporting notes). There is no implementation phase, no PR, no QA cycle. Once research is complete (impl-ready marker on the ticket), the ticket moves straight from In Progress → Under review (skipping Testing) and the operator logs the hours spent on research.

   The research phase (step 6b) is identical for SPIKE and non-SPIKE tickets; only the marker-found branch differs.

6. **Branch on `MARKER_FOUND` and `IS_SPIKE` to choose the phase:**
   - `MARKER_FOUND == false` → **6b (research phase)** — same flow for SPIKE and non-SPIKE.
   - `MARKER_FOUND == true` AND `IS_SPIKE == false` → **6a (implementation phase)** — create the impl worktree + open a backgrounded `/ticket-driver` session.
   - `MARKER_FOUND == true` AND `IS_SPIKE == true` → **6a-spike (spike-close phase)** — no worktree, no impl session; queue Q1 + Q2 to ask the operator about transitioning to Under review + logging hours.

### 6a. `MARKER_FOUND == true` AND `IS_SPIKE == false` (implementation phase) — one worktree per repo in TARGET_REPOS

Apply the following sub-steps **for EACH repo in `TARGET_REPOS`** in order. Track outcomes per repo; a failure on one repo does not stop processing the others.

Let `IMPL_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>` for the current repo.

**6a-i. If `IMPL_PATH` EXISTS** (`test -d <IMPL_PATH>`):
- Append to `actionsTaken`: `"Reminded u to complete implementation under existing worktree <IMPL_PATH> (<repo>)"`.
- Append to `REMINDERS`: `"<TICKET-KEY> [<repo>]: Complete implementation under existing worktree at <IMPL_PATH>."`
- Do NOT create or open anything for this repo. Move to the next repo in TARGET_REPOS.

**6a-ii. If `IMPL_PATH` DOES NOT EXIST**, create it and open a Claude session:

1. **Discover branch state** for `<TICKET-KEY>` in this repo's main-repo path (`~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`):
   - `git -C <main repo path> fetch --prune origin <TICKET-KEY>` (standalone Bash). May exit non-zero if the ref doesn't exist on the remote — capture the exit code, don't abort.
   - `git -C <main repo path> rev-parse --verify --quiet refs/heads/<TICKET-KEY>` → `LOCAL_HAS_BRANCH` (true if exit 0).
   - `git -C <main repo path> ls-remote --exit-code --heads origin <TICKET-KEY>` → `REMOTE_HAS_BRANCH` (true if exit 0).

2. **Create the worktree** with the correct branch wiring:
   - `LOCAL_HAS_BRANCH=true` → `git -C <main repo path> worktree add <IMPL_PATH> <TICKET-KEY>` (reuse the existing local branch).
   - `LOCAL_HAS_BRANCH=false`, `REMOTE_HAS_BRANCH=true` → `git -C <main repo path> worktree add <IMPL_PATH> -b <TICKET-KEY> --track origin/<TICKET-KEY>` (create local tracking branch).
   - Both false → `git -C <main repo path> worktree add <IMPL_PATH> -b <TICKET-KEY> origin/main` (new branch off main).

   If the `worktree add` command fails for any reason (refs in use, permission denied, conflicting path), append to `actionsTaken`: `"Implementation kickoff skipped for <repo> — worktree creation failed: <verbatim error>"`. Print one terminal warning line. Move to the next repo in TARGET_REPOS.

3. **Open a new Claude session in the worktree** via the helper script at `~/.claude/skills/jira-sprint-manager/open-claude-session.sh`, with the prompt prefixed by `/background` so the session moves into the background-agent view immediately instead of sitting as a foreground interactive tab, and `--session-name` set per step 5.6 (for the current repo in this loop iteration):
   ```
   ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     <IMPL_PATH> \
     --prompt "/background /ticket-driver <TICKET-KEY>" \
     --session-name "<TICKET-KEY>-<SEGMENT>"
   ```
   The script opens a new iTerm2 tab (in the existing iTerm2 window if one is open; Terminal.app fallback if iTerm2 isn't installed) in the worktree and starts a fresh `claude --name "<TICKET-KEY>-<SEGMENT>"` with `/background /ticket-driver <TICKET-KEY>` pre-submitted as the first message. `/background` moves that session into the background-agent view before `ticket-driver` starts running — the operator is still expected to be around and can still see it, respond to any permission prompts, and monitor progress there (e.g. via the agents list, now pre-named instead of showing a generic/AI-guessed title); it just isn't left occupying the one foreground tab, so the operator can keep working elsewhere while it runs.

   If the script's exit code is non-zero, append to `actionsTaken`: `"Worktree created at <IMPL_PATH> (<repo>) but open-claude-session failed: exit <code>"`. The worktree is preserved. Move to the next repo.

4. On success for this repo: append to `actionsTaken`: `"Created worktree at <IMPL_PATH> (<repo>) and opened a backgrounded Claude session named '<TICKET-KEY>-<SEGMENT>' with prompt: /background /ticket-driver <TICKET-KEY>"` — the literal prompt string, verbatim, not a paraphrase (see SKILL.md's rule on this, right after the Action-stacking model paragraph). **Also print this exact prompt string in your terminal response at the time you make the call** — don't wait for the report file to be the only place it appears.

**After all repos have been processed**, append a single consolidated summary line to `actionsTaken` listing every created, pre-existing, and failed worktree so the operator has a full picture at a glance:

```
Implementation kickoff summary for <TICKET-KEY>:
  created:    <repo1> → <IMPL_PATH1>, <repo2> → <IMPL_PATH2>
  pre-existing (reminded): <repo3> → <IMPL_PATH3>
  failed:     <repo4> → <error>
  (N iTerm2 tab(s) opened)
```

Omit any category that has zero entries. If only one repo was involved, this summary line is optional (the per-repo entry above is sufficient).

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

3. **Open a new Claude session in the research worktree** via the helper script — **the launched command depends on `IS_SPIKE`:**

   Both branches pass `--session-name "<TICKET-KEY>-<SEGMENT>"` per step 5.6 — `<SEGMENT>` is `SPIKE` on the SPIKE branch (always) and the repo-derived code on the non-SPIKE branch.

   - **Non-SPIKE (`IS_SPIKE == false`):**
     ```
     ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
       <RESEARCH_PATH> \
       --prompt "/background /ticket-creator" \
       --session-name "<TICKET-KEY>-<SEGMENT>"
     ```
     The `/background` prefix moves the session into the background-agent view immediately, same as Rule D's implementation-phase kickoff (6a) — the operator is still expected to be reachable, not unattended. The new session starts in the research worktree with `/ticket-creator` pre-submitted, pre-named `<TICKET-KEY>-<SEGMENT>` in the agent view. The operator drives research from there and ultimately uses ticket-creator's output to refine the existing Jira ticket.

   - **SPIKE (`IS_SPIKE == true`):**
     ```
     ~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
       <RESEARCH_PATH> \
       --prompt "/background /research SPIKE" \
       --session-name "<TICKET-KEY>-SPIKE"
     ```
     The `/background` prefix moves the session into the background-agent view immediately, same as Rule D's implementation-phase kickoff (6a) — the operator is still expected to be reachable, not unattended (see the note on 6a's kickoff for why this isn't "fire and forget"). `/research`'s own SPIKE mode (see its SKILL.md) recognizes the literal argument `SPIKE`, asks the operator **"What would you like me to research?"**, and treats their answer as the actual research topic for the rest of its normal workflow. A spike's research now runs through `/research`, not `/ticket-creator`.

   If the script's exit code is non-zero (either branch), append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"` and continue with the rest of the workflow. The worktree is preserved either way.

4. On success, append to `actionsTaken`:
   - Non-SPIKE: `"Created research worktree at <RESEARCH_PATH> and opened a backgrounded Claude session named '<TICKET-KEY>-<SEGMENT>' with prompt: /background /ticket-creator"`.
   - SPIKE: `"Created research worktree at <RESEARCH_PATH> and opened a backgrounded Claude session named '<TICKET-KEY>-SPIKE' with prompt: /background /research SPIKE"`.

   Both are the literal, verbatim prompt string passed to `--prompt` — not a paraphrase. **Also print the exact prompt string in your terminal response at the time you make the call**, same as the implementation-phase kickoff above — don't leave it only in the report file.

5. **If `IS_SPIKE == true`, log this worktree to `~/.claude/memory/sessions.md`** — same file, same entry format, and same insertion rules `ticket-creation` (in `ticket-creator`) and `ticket-driver` already use for their own bookkeeping. This exists because a SPIKE's entire lifecycle can consist of just this one research worktree — 6a-spike (the spike-close phase) never creates a worktree or opens a session, and (unlike `/ticket-creator`) `/research` never logs itself to `sessions.md` at all under any circumstance — it only logs to its own `~/.claude/memory/research/index.md`. So this step is the ONLY place a spike's research worktree ever gets recorded in `sessions.md`. Non-spike tickets aren't logged here — their research worktree still gets recorded once, later, when the spawned `/ticket-creator` session reaches its own Step 5 logging.

   1. **Get the current Claude session ID** — Run `ls -t ~/.claude/projects/` (standalone Bash, no pipes) to find the most-recently-modified project subdirectory. Then run `ls -t ~/.claude/projects/<that-subdir>/`; the first `.jsonl` filename (minus the `.jsonl` extension) is the current session UUID. **This is jira-sprint-manager's OWN running session** — the newly spawned session in the worktree doesn't have a UUID yet (its `claude` process hasn't started), so there is nothing else to log here.
   2. **Repo/dir** — the basename of `RESEARCH_PATH` (already computed earlier in this rule) — e.g. `webapp-react-trident-TRIDENT-950-research`. No need to `git rev-parse`; jira-sprint-manager isn't running from inside that worktree.
   3. **Date** — Run `date +%Y-%m-%d` (standalone Bash).
   4. **Read** `~/.claude/memory/sessions.md` with the Read tool. If it doesn't exist, treat existing content as empty.
   5. **Check for an existing entry for this ticket** — look for a line matching `# <TICKET-KEY>` exactly OR `# <TICKET-KEY> (...)`, same matching rule `ticket-creator`/`ticket-driver` use (match on the ticket key only).
      - **Header exists:** idempotency check — if the section already contains a `## jira-sprint-manager (spike research worktree)` subentry whose `session id:` matches the current UUID, SKIP the insertion (print `"Session already logged for <TICKET-KEY>; skipping."`) and continue. Otherwise insert a new H2 subentry immediately after the H1 line and its trailing blank line, BEFORE any existing H2 subentries (newest-first ordering).
      - **Header does NOT exist:** PREFIX a brand-new ticket entry at the very top of the file.
   6. **Entry format** (exactly this shape — no extra fields):
      ```markdown
      # <TICKET-KEY>

      ## jira-sprint-manager (spike research worktree)
      - session id: <uuid>
      - repo/dir: <RESEARCH_PATH basename>
      - date: YYYY-MM-DD
      ```
      When inserting as a subentry under an existing ticket header, omit the H1 line and the blank line above the H2 — just the `## jira-sprint-manager (spike research worktree)` block plus its trailing blank line.
   7. **Write** the updated file using the Write tool. **NEVER** use shell redirection (`>`, `>>`) or `echo`.

   If any sub-step errors out, print one line explaining what failed and continue — do not block the rest of Rule D on this.

## Failure modes summary

- Comments fetch fails → append to `actionsTaken`: `"Implementation kickoff skipped — Jira comment fetch failed: <error>"` (the same error path covers all three phases; the phase is reflected in the worktree path mentioned in subsequent actions, or in the lack of one for spike-close). This also means `REPOS_FROM_COMMENT` can never be computed, so repo determination falls all the way through to the legacy text-scan/ask-operator logic if the rule proceeds at all.
- **Repos-comment has an unrecognized entry** (step 3.5) → append `"Repos-comment listed unrecognized repo '<name>' for <TICKET-KEY> — skipped"` to `actionsTaken` and drop that entry from `REPOS_FROM_COMMENT`. The other, recognized entries are still used. If ALL entries are unrecognized, `REPOS_FROM_COMMENT` is empty and step 4 falls through to the legacy scan for that ticket.
- Repo path not found → append `"Implementation kickoff skipped for <repo> — not found at <path>"` to `actionsTaken` and remove it from `TARGET_REPOS`. If `TARGET_REPOS` becomes empty, halt Rule D for this ticket. (For SPIKE tickets the repo isn't strictly needed since no worktree is created, but the repo-not-found check still runs in step 4 before the SPIKE-detection branch — treat the skip as a deliberate guard rather than a bug.) This check runs whether `TARGET_REPOS` came from `REPOS_FROM_COMMENT` or the legacy scan.
- **Repo ambiguity (implementation phase only, interactive, and only reached when `REPOS_FROM_COMMENT` is empty)** — if the scan in step 4b yields no repos and no default is appropriate, `AskUserQuestion` is used exactly once per ticket to ask which repos apply. If the operator's answer names a repo not in the known-repo list, append `"Unrecognised repo <name> from operator — skipped"` to `actionsTaken` and omit it.
- **Implementation phase (6a) — per-repo failure is non-fatal:**
  - Worktree creation fails for one repo → append `"Implementation kickoff skipped for <repo> — worktree creation failed: <error>"` and move to the next repo. The other repos are still processed.
  - Worktree created but open-claude-session script fails → append `"Worktree created at <IMPL_PATH> (<repo>) but open-claude-session failed: exit <code>"` and move to the next repo. The worktree is preserved.
  - ALL repos failed → the consolidated summary reflects all failures; `actionsTaken` records each individually.
- **Spike-close phase (6a-spike):**
  - Transition to `Under review` errors → append `"Spike-close failed: transition to Under review errored: <error>"`; worklog step is skipped (do not log time on a ticket whose status didn't change).
  - Transition succeeds but `addWorklogToJiraIssue` errors → append `"Spike-close partial: transitioned to Under review but worklog failed: <error>. Please log <hours> manually."`; also append a REMINDERS line so the operator catches the dangling worklog.
- **Research phase (6b):**
  - Worktree creation fails → append to `actionsTaken`: `"Research kickoff skipped — worktree creation failed: <error>"`.
  - Worktree created but open-claude-session script fails → append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"`.
  - SPIKE ticket, worktree created, but the `sessions.md` logging (6b-ii step 5) errors out → print one terminal warning line and continue; do NOT roll back or retry the worktree/session creation over this. The worktree and its spawned session are already valid without the log entry — the log entry is bookkeeping, not a correctness gate.

Rule D's research phase never blocks on `AskUserQuestion` — the comment match (or absence thereof) IS the operator's signal. The **implementation phase** has one legitimate ask: when the multi-repo scan (step 4b) yields no results and no default is safe, `AskUserQuestion` is called once to confirm which repos apply. The **spike-close phase** queues Q1 (yes/no) and, on Q1=Yes, Q2 (hours). All questions are answered in Step 6 of the parent SKILL.md workflow.

If the operator wants to override (e.g., not have a worktree auto-created for a non-spike ticket, or hold a spike at In Progress without transitioning), they should pre-create the worktree manually OR hold off on putting the ticket in In Progress until they're ready for the skill to act, OR (for spikes) answer Q1=No when prompted.
