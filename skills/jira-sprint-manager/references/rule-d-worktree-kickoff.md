# Rule D — In-Progress ticket implementation/research kickoff (worktree + Claude session) — full detail

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the comment scan, repo detection, worktree path computation, and the two phase paths (6a implementation, 6b research).

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
   /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<repo>
   ```
   (Confirmed via `ls ~/BOATS-GROUP-PROJECTS-GITHUB/` — every repo in the list above lives at that path on this workstation.) If the resolved path does not exist, append to `actionsTaken`: `"Implementation kickoff skipped — repo <repo> not found at <path>"` and move on.

5. **Compute both per-ticket worktree paths** (both branches in step 6 need these — the impl path is used when the marker was found, the research path when it wasn't):
   ```
   IMPL_PATH     = /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>
   RESEARCH_PATH = /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>-research
   ```
   Examples for `TRIDENT-904` (`webapp-react-trident`):
   - `IMPL_PATH = /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904`
   - `RESEARCH_PATH = /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-904-research`

   (Note: both naming conventions are distinct from the legacy `<repo>-worktree-<N>` numbered worktrees and the shared `<repo>-worktree-research` scratch worktree. The per-ticket worktrees are dedicated to one ticket each, with separate branches for the research vs. implementation phases.)

6. **Branch on `MARKER_FOUND` to choose the worktree phase.**

### 6a. `MARKER_FOUND == true` (implementation phase) — operate on `IMPL_PATH` with branch `<TICKET-KEY>`

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

3. **Open a new Claude session in the worktree** via the helper script at `/Users/fabianodesouza/.claude/skills/jira-sprint-manager/open-claude-session.sh`:
   ```
   /Users/fabianodesouza/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     <IMPL_PATH> \
     --prompt "/ticket-driver <TICKET-KEY>"
   ```
   The script opens a new iTerm2 tab (in the existing iTerm2 window if one is open; Terminal.app fallback if iTerm2 isn't installed) in the worktree and starts a fresh `claude` with the slash command pre-submitted, so the new session immediately invokes `ticket-driver` for the ticket.

   If the script's exit code is non-zero, append to `actionsTaken`: `"Worktree created at <IMPL_PATH> but open-claude-session failed: exit <code>"` and continue with the rest of the workflow. The worktree is preserved either way.

4. On success: append to `actionsTaken`: `"Created worktree at <IMPL_PATH> and opened a new Claude session with /ticket-driver <TICKET-KEY>"`.

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
   /Users/fabianodesouza/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     <RESEARCH_PATH> \
     --prompt "/ticket-creator"
   ```
   The new session starts in the research worktree with `/ticket-creator` pre-submitted. The operator drives research from there and ultimately uses ticket-creator's output to refine the existing Jira ticket.

   If the script's exit code is non-zero, append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"` and continue with the rest of the workflow. The worktree is preserved either way.

4. On success: append to `actionsTaken`: `"Created research worktree at <RESEARCH_PATH> and opened a new Claude session with /ticket-creator"`.

## Failure modes summary

- Comments fetch fails → append to `actionsTaken`: `"Implementation kickoff skipped — Jira comment fetch failed: <error>"` (the same error path covers both phases; the phase is reflected in the worktree path mentioned in subsequent actions).
- Repo path not found → append to `actionsTaken`: `"Implementation kickoff skipped — repo <repo> not found at <path>"`.
- **Implementation phase (6a):**
  - Worktree creation fails → append to `actionsTaken`: `"Implementation kickoff skipped — worktree creation failed: <error>"`.
  - Worktree created but open-claude-session script fails → append to `actionsTaken`: `"Worktree created at <IMPL_PATH> but open-claude-session failed: exit <code>"`.
- **Research phase (6b):**
  - Worktree creation fails → append to `actionsTaken`: `"Research kickoff skipped — worktree creation failed: <error>"`.
  - Worktree created but open-claude-session script fails → append to `actionsTaken`: `"Research worktree created at <RESEARCH_PATH> but open-claude-session failed: exit <code>"`.

Rule D never blocks on `AskUserQuestion` — the comment match (or absence thereof) IS the operator's signal. If the operator wants to override (e.g., not have a worktree auto-created), they should pre-create the worktree manually OR hold off on putting the ticket in In Progress until they're ready for the skill to act.
