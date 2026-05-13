# Rule C — Prod-ready ticket deployment (operator-gated, CICD-driven) — full detail

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the pre-flight checks, plan-build logic, three exclusive routing paths, plan-execution steps, finalization, and failure modes.

## Trigger

The response contains at least ONE ticket whose `fields.status.name` is one of `Resolved - QA Complete`, `Pending Release Candidate`, or `OLD-Pending Release Candidate` (all map to the PROD READY board column in the priority table).

## ⚠️ Safety contract — production deploys flow through CICD, NEVER through this skill directly

Rule C's job is to **merge the ticket branch to `main`** and **let CICD deploy production**. The skill is **NOT authorized** to run any `firebase deploy …` command, any `npx firebase --project trident-funding` command, or any other direct prod-deploy command. The only production-affecting action the skill takes is the merge to `main`; CICD picks up from there.

If CICD fails to deploy a GCP function that the deployment notes called out, the skill's response is to **REPORT** the failure to the operator — not to attempt a manual fallback deploy. The operator must run any manual function deploys themselves.

The operator MUST explicitly approve the plan via the 3-option question below before the merge happens. Without explicit approval, the skill takes ZERO mutating action and `actionsTaken` carries a "Deploy skipped" message naming the reason.

## Per-prod-ready-ticket handling (apply in board order — top of the PROD READY lane first)

1. **Fetch deployment instructions.** Use `mcp__atlassian__getJiraIssue` with:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `fields`: `["customfield_10313", "description", "summary"]`

   `customfield_10313` is the "Deployment Notes" custom field in the boats-group Jira (verified via `getJiraIssueTypeMetaWithFields`). If that field is null or empty, fall back to scanning `fields.description` for a "Deployment Notes", "Deployment", or "Prod" section heading and parse the content beneath it.

   **If neither source yields anything actionable** (no merge instruction, no functions list), append to `actionsTaken`: `"Deploy skipped — no deployment notes found"` and skip the rest of Rule C for this ticket. Print one terminal warning line.

2. **Determine the target repo.** Same logic as Rule D step 4 — scan the deployment notes (and `description` + `summary` as a fallback) for known repo names from the priority list; default to `webapp-react-trident`. The merge happens on this repo's main branch.

   Repo path: `/Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<repo>`. If it doesn't exist on disk, append to `actionsTaken`: `"Deploy skipped — repo <repo> not found at <path>"` and skip.

3. **Parse the deployment notes and build the plan.** Read deployment notes line by line; the standard boats-group pattern (also emitted by the `ticket-creator` skill) is:

   ```
   **Prod**
   - Merge TRIDENT-XXX branch of `<repo>` with main
   - Deploy GCP functions       ← OPTIONAL block; present only when the ticket modifies GCP functions
     - Ensure that the `<funcName>` GCP function was deployed by the CICD GitHub workflow
       - If not manually deploy it from terminal
         `npx firebase --project trident-funding deploy --only functions:<funcName>`
   ```

   Translate this into a 3-or-4-step plan:

### Pre-flight — Verify the PR is mergeable BEFORE building the plan (ALWAYS runs, gates everything else)

1. Look up the open PR: `gh -R boatsgroup/<repo> pr list --head <TICKET-KEY> --state open --json number,url,headRefName,title --limit 1`. If no open PR is found, halt and append to `actionsTaken`: `"Deploy skipped — no open PR found for branch <TICKET-KEY>"`. Stop processing Rule C for this ticket.

2. Fetch the PR's mergeability state and check status: `gh -R boatsgroup/<repo> pr view <PR_NUMBER> --json mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft`.

   Inspect the fields:
   - **`isDraft == true`** → not mergeable: PR is a draft.
   - **`mergeable != "MERGEABLE"`** (e.g., `"CONFLICTING"`) → not mergeable: there are merge conflicts.
   - **`mergeStateStatus`**:
     - `"CLEAN"` → mergeable, all required checks passing, ready to merge.
     - `"UNSTABLE"` → checks are failing or pending; do NOT merge.
     - `"BEHIND"` → the head branch is behind main and the repo requires it to be up to date.
     - `"BLOCKED"` → required reviews missing OR required checks failing.
     - `"DIRTY"` → merge conflicts.
     - `"DRAFT"` → draft PR (same as `isDraft`).
     - `"UNKNOWN"` → GitHub is still computing; retry once after 5 seconds; if still UNKNOWN, treat as not-mergeable for safety.
   - **`reviewDecision`**:
     - `"APPROVED"` → reviews satisfied.
     - `"CHANGES_REQUESTED"` → blocking review comment; not mergeable.
     - `"REVIEW_REQUIRED"` → required reviewers haven't approved yet; not mergeable.

   Combine into a single mergeable boolean: `MERGEABLE = (mergeable == "MERGEABLE") AND (mergeStateStatus == "CLEAN") AND (isDraft == false) AND (reviewDecision in [null, "APPROVED"])`. ANY violation flips this to false.

3. **Additionally — check for unresolved review-thread comments** (soft requirement: not part of the repo's branch-protection gate, but the operator wants these resolved before deploy).

   Use GitHub's GraphQL API via `gh api`:
   ```
   gh api graphql -F prNumber=<PR_NUMBER> -F repoOwner=boatsgroup -F repoName=<repo> -f query='
   query($repoOwner: String!, $repoName: String!, $prNumber: Int!) {
     repository(owner: $repoOwner, name: $repoName) {
       pullRequest(number: $prNumber) {
         reviewThreads(first: 100) {
           totalCount
           nodes {
             id
             isResolved
             path
             line
             comments(first: 1) {
               nodes { author { login } bodyText }
             }
           }
         }
       }
     }
   }'
   ```

   From the response, count `nodes` where `isResolved == false`. Capture as `UNRESOLVED_COUNT` (number) and `UNRESOLVED_THREADS` (the unresolved thread metadata for the reminder text).

### Branch on the combined state — three exclusive paths

**Path 3a — Hard-requirement failure** (`MERGEABLE == false`):

Collect the failure reasons and the required operator actions:
- For each failing/pending check from `statusCheckRollup`, capture the check name and its `conclusion` / `state`. Use `gh -R boatsgroup/<repo> pr checks <PR_NUMBER>` for a more reader-friendly list if `statusCheckRollup` is empty.
- For `reviewDecision == "CHANGES_REQUESTED"` → "address the blocking review comments and request a re-review".
- For `reviewDecision == "REVIEW_REQUIRED"` → "request review from the required reviewers and wait for approval".
- For `mergeStateStatus == "BEHIND"` → "update the head branch from main (`gh pr update-branch <PR_NUMBER>` or merge/rebase main into the branch)".
- For `mergeStateStatus == "DIRTY"` / `mergeable == "CONFLICTING"` → "resolve merge conflicts on the head branch and push".
- For `isDraft == true` → "mark the PR as ready for review (currently draft)".
- If `UNRESOLVED_COUNT > 0`, also append `"<N> unresolved review-thread comments"` to the required-action list — those will need to be addressed alongside the CI/conflict fixes.

Then **do NOT build a merge plan and do NOT ask the operator any question for this ticket. Do NOT auto-resume any session** (the hard-requirement failures are the operator's primary blocker — the session should be opened by the operator after those are fixed). Instead:
- Append to `actionsTaken`: `"Merge skipped — PR #<N> not mergeable. Failing checks: <name1>, <name2>, …. Required action: <action1>; <action2>; …. Resolve and re-run."`. Truncate the failing-checks list to the first 5 names + `"…and N more"` if longer.
- Append to `REMINDERS`: `"<TICKET-KEY>: PR #<N> (<PR URL>) is not mergeable. Please resolve before next run. Failing: <names>. Required action: <actions>."`.
- Print one terminal warning line. Skip the rest of Rule C for this ticket.

**Path 3b — Soft failure, unresolved comments only** (`MERGEABLE == true` AND `UNRESOLVED_COUNT > 0`):

Repo-side branch protection allows the merge, but the operator's policy is to clear review-thread comments first. Auto-resume the implementation session to run `/review-pr-comments` autonomously:

1. **Read `~/.claude/memory/sessions.md`** with the Read tool. Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` (key followed by a parenthetical). If no matching heading is found, fall through to the no-session fallback below.

2. **Find the topmost `## ticket-driver` subentry** in that ticket's section. (Sessions.md is newest-first within each ticket, so the topmost `## ticket-driver` is the most recent implementation session.) Capture two fields from the bullets under it:
   - `session id: <uuid>` → `IMPL_SESSION_ID`
   - `repo/dir: <basename>` → `IMPL_REPO_DIR`

   The repo/dir is a basename (e.g., `webapp-react-trident-worktree-2`); compute the absolute path as `/Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<IMPL_REPO_DIR>`.

   **No-session fallback:** if either (a) the ticket heading doesn't exist in sessions.md, (b) the section has no `## ticket-driver` subentry, or (c) the resolved absolute path doesn't exist on disk (`test -d` fails), then SKIP the auto-resume and:
   - Append to `actionsTaken`: `"Merge skipped — PR #<N> has <UNRESOLVED_COUNT> unresolved review comments; no prior ticket-driver session found in sessions.md. Please run /review-pr-comments <PR URL> autonomous manually."`.
   - Append to `REMINDERS`: `"<TICKET-KEY>: PR #<N> (<PR URL>) has <UNRESOLVED_COUNT> unresolved review comments. No implementation session was logged; please run /review-pr-comments manually in your working worktree."`.
   - Skip the rest of Rule C for this ticket.

3. **Open a new Claude session resuming the implementation session** via the helper script:
   ```
   /Users/fabianodesouza/.claude/skills/jira-sprint-manager/open-claude-session.sh \
     /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/<IMPL_REPO_DIR> \
     --resume <IMPL_SESSION_ID> \
     --prompt "/review-pr-comments <PR URL> autonomous"
   ```
   The script opens a new iTerm2 tab (in the existing iTerm2 window if one is open; Terminal.app fallback if iTerm2 isn't installed) in the implementation worktree, runs `claude --resume <IMPL_SESSION_ID>` so the prior transcript is loaded, and immediately submits `/review-pr-comments <PR URL> autonomous` so the autonomous fix loop starts.

   If the script's exit code is non-zero:
   - Append to `actionsTaken`: `"Merge skipped — PR #<N> has <UNRESOLVED_COUNT> unresolved review comments. Attempted to auto-resume session <IMPL_SESSION_ID> in <IMPL_REPO_DIR> but open-claude-session failed: exit <code>. Run /review-pr-comments <PR URL> autonomous manually."`.
   - Append to `REMINDERS`: similar message.
   - Skip the rest of Rule C for this ticket.

4. **On success:** the implementation session is now driving the autonomous review-comments loop in a separate iTerm2 tab. Append to `actionsTaken`: `"Merge skipped — PR #<N> has <UNRESOLVED_COUNT> unresolved review comments. Resumed implementation session <IMPL_SESSION_ID> in <IMPL_REPO_DIR> with /review-pr-comments <PR URL> autonomous."`. Append to `REMINDERS`: `"<TICKET-KEY>: PR #<N> has <UNRESOLVED_COUNT> unresolved review comments — your implementation session was resumed in <IMPL_REPO_DIR> with /review-pr-comments autonomous. Watch that iTerm2 tab for progress; the next run will re-evaluate once the comments are resolved."`.

5. **Do NOT build a merge plan and do NOT ask the operator any question for this ticket** — the auto-resume IS the action. The operator monitors the new iTerm2 tab; the next `/jira-sprint-manager` run will re-check the PR (presumably with `UNRESOLVED_COUNT == 0` after the autonomous loop has resolved the threads) and either auto-resume again (if more comments arrived) or fall through to the merge-plan path.

**Path 3c — Fully clean** (`MERGEABLE == true` AND `UNRESOLVED_COUNT == 0`):

Proceed to build the numbered plan below using the PR's URL + number. The plan asks the 3-option deploy question as before.

## Plan steps (only present when MERGEABLE and UNRESOLVED_COUNT == 0)

### Step 1 — Merge ticket branch to main (ALWAYS present when MERGEABLE)

```
gh -R boatsgroup/<repo> pr merge <PR_NUMBER> --squash
```

The merge strategy (`--squash` vs `--merge` vs `--rebase`) follows the repo's default per `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`. Squash is the default convention for boats-group repos; only fall back to a different strategy if squash is disabled.

**⚠️ Do NOT pass `--delete-branch` here.** Boats-group repos have `delete_branch_on_merge: true` set on the repo, which makes GitHub auto-delete the head branch after a successful merge. Adding `--delete-branch` to the same `gh pr merge` call has been observed to produce a **duplicate `pr_merge` activity entry** on `main` (verified for TRIDENT-876 on 2026-05-13 — the gh-CLI merge with `--delete-branch` registered two identical `pr_merge` events; historic UI-driven merges register only one). That duplicate fires a second `push` webhook → a second `Main Branch Deploy` run → both runs race to deploy the same function and the loser fails. Step 5 below handles the rare case where the branch *isn't* auto-deleted.

### Step 2 — Post Slack notification to `#merge-requests` (ALWAYS present when MERGEABLE)

- Find the channel ID: `mcp__claude_ai_Slack__slack_search_channels` with query `"merge-requests"`. Pick the result whose name is exactly `merge-requests`.
- Post the message via `mcp__claude_ai_Slack__slack_send_message`. Message text (past tense — the merge has already landed by the time this fires):
  ```
  Merged <PR URL> for <TICKET-KEY>
  ```
  where `<PR URL>` is the URL returned by the pre-flight PR lookup.
- Add a green check-mark reaction (`✅`) to the message. If the Slack MCP server exposes a reaction-add tool, use it on the message's `ts` (timestamp) returned by `slack_send_message`. If no reaction-add tool is available, fall back to prepending `✅` to the message text itself (so it reads `✅ Merged <PR URL> for <TICKET-KEY>`) — and include a one-line note in the run log: "Slack reaction tool not available; included ✅ inline in message text."
- The message is posted **as the operator** (Fabiano Desouza) — Slack OAuth is already wired through the MCP server, so messages naturally appear under the operator's account.

### Step 3 — Wait for CICD to complete on the merge commit (ALWAYS present)

- Capture the merge commit SHA from step 1's output (squash merges produce a new commit on `main`).
- List GitHub Actions runs for that SHA: `gh -R boatsgroup/<repo> run list --commit <SHA> --json databaseId,name,status,conclusion,headSha --limit 20`.
- For each in-progress or queued run, watch it to completion: `gh -R boatsgroup/<repo> run watch <runId> --exit-status`. Allow up to **30 minutes per run** (CICD function-deploy jobs are typically 10–15 minutes; padding for cold starts).
- Capture each run's final `conclusion` (`success`, `failure`, `cancelled`, `timed_out`, `skipped`).

### Step 4 — Verify CICD deployed the GCP functions (CONDITIONAL)

Present ONLY IF the deployment notes contain a "Deploy GCP functions" section listing one or more `<funcName>` entries.

- For each function named in the deployment notes, search the completed CICD runs' logs for a deploy line referencing that function:
  `gh -R boatsgroup/<repo> run view <runId> --log` and look for `Deploying function "<funcName>"` (or the equivalent Firebase deploy phrasing).
- For each `<funcName>`, classify the outcome:
  - **Deployed by CICD** — a successful deploy line was found in the log of a run whose conclusion is `success`.
  - **Not deployed by CICD** — no deploy line found, OR the deploy line is in a run that failed/was cancelled/was skipped.
- **Reporting (NO auto-deploy fallback — the skill is NOT authorized to manually deploy):**
  - If every function in the notes was Deployed by CICD: append to `actionsTaken`: `"Merged to main; CICD deployed all functions: <funcName>, …"`.
  - If one or more functions were NOT Deployed by CICD: append to `actionsTaken`: `"Merged to main; ⚠️ No CICD function deploy happened for: <funcName>, …. You must manually deploy them yourself. The skill is NOT authorized to deploy them on your behalf."`. Print the same warning to the terminal so it's visible at run time, NOT just in the saved report.

Step 4 is OMITTED entirely when deployment notes do not include a "Deploy GCP functions" subsection (e.g., dynamic-app-only tickets — CICD's hosting deploy is the whole story).

### Step 5 — Defensive branch-cleanup check (ALWAYS present, runs LAST)

Most boats-group repos have `delete_branch_on_merge: true`, so the head branch is auto-deleted by GitHub immediately after the merge. This step is a safety net for any repo where that setting is OFF (or for the rare case the auto-delete fails). Run AFTER step 3/4 so any cleanup of the ticket branch can't interfere with the CICD watch.

1. **Check whether the head branch still exists on the remote:**
   ```
   gh api /repos/boatsgroup/<repo>/branches/<TICKET-KEY>
   ```
   - HTTP 200 → branch survived; proceed to delete it.
   - HTTP 404 → branch already deleted (the normal case for boats-group repos); skip deletion. Log one line: `"Branch <TICKET-KEY> already deleted by repo's delete_branch_on_merge setting; nothing to clean up."`.
   - Any other status → log and skip; don't block the rest of the workflow on a transient API hiccup.

2. **If the branch exists, delete it explicitly:**
   ```
   gh api -X DELETE /repos/boatsgroup/<repo>/git/refs/heads/<TICKET-KEY>
   ```
   This is a single API call that's distinct from the merge — it should NOT register a second `pr_merge` activity event (the bug observed in step 1 only occurs when `--delete-branch` is bundled into the `gh pr merge` call itself).

   On 204 (success): log `"Branch <TICKET-KEY> deleted post-deploy."`.
   On any error: log and continue — the branch can be cleaned up manually if needed.

## Plan presentation + 3-option question

(This step runs ONLY when the pre-flight mergeability check passed. Unmergeable PRs are handled via the reminder path described in 3a above and never reach this step.)

Print the full plan to the terminal under a `## Deploy plan — <TICKET-KEY> (PRODUCTION via merge-to-main)` heading. Number each step exactly as in the plan above and show the parsed values (PR URL, merge command, Slack channel, list of `<funcName>`s if applicable). Include a one-line pre-flight summary directly under the heading: `PR pre-flight: mergeStateStatus=CLEAN, reviewDecision=APPROVED (or N/A), unresolved review threads=0` — so the operator can see at a glance that all three pre-flight checks (mergeability, reviews, unresolved comments) passed.

Then append a 3-option question to `QUESTIONS`:

Question text:
```
<TICKET-KEY> is in PROD READY and PR #<N> is mergeable. Should I handle the production deployment via merge-to-main? The plan above lists every action I will take: merge the PR, post to #merge-requests, wait for CICD, and report on function deploys. I will NOT run any firebase deploy commands directly.
```

Options (exactly these, in this order):
- **`Yes — execute plan as proposed`** — the skill runs every step in the printed plan.
- **`Yes — but with an updated plan`** — the skill prompts for edits (free-text follow-up), re-renders the plan, then asks ONE yes/no confirmation before executing.
- **`No — I'll do it myself`** — the skill takes no action.

## Apply the answer (during Step 6 / question-collection phase in SKILL.md)

### `Yes — execute plan as proposed`

1. Run each step in order via separate tool calls. Capture exit codes / responses.
2. **Step 1 (merge) failure** → halt; append to `actionsTaken`: `"Merge failed: <verbatim error>"`. Print one terminal warning. Subsequent steps do NOT run (no Slack notification for a merge that didn't happen).
3. **Step 2 (Slack) failure** → record as a soft warning but do NOT halt; the merge already happened. Append to `actionsTaken`: `"Merged to main; Slack post failed: <error>"`. Continue to step 3.
4. **Step 3 (CICD watch) timeout/failure** → record as a hard report, do NOT halt; the merge already happened and CICD owns the deploy now. Append to `actionsTaken`: `"Merged to main; CICD watch ended with conclusion <conclusion> after <minutes>m"`. Continue to step 4 (if applicable).
5. **Step 4 (function-deploy verification)** → run only if the deployment notes named functions. Outcome appended per the rules in Step 4 above.
6. **Step 5 (defensive branch-cleanup check)** → always runs. The outcome is informational only — does NOT change `actionsTaken` unless the branch was actually deleted by this skill (rare case): in that case append `"Cleaned up surviving head branch <TICKET-KEY>"` so the operator sees the rule did unexpected work.
7. **Jira finalization (transition to Live + assign to operator)** — runs ONLY when the deploy is fully successful. The gate is **strict** to avoid prematurely marking a ticket as Live when the deploy didn't actually finish:

   **All of these must be true:**
   - The merge in Step 1 succeeded (`actionsTaken` does NOT contain a `"Merge failed"` entry).
   - At least one CICD run was watched in Step 3 AND every watched run's `conclusion == "success"` (no `failure`, `cancelled`, `timed_out`, or `skipped`).
   - If Step 4 ran (because the deployment notes named functions), every listed function was classified `Deployed by CICD`. If ANY function was `Not deployed by CICD`, halt finalization — the operator needs to deploy manually first.

   **If the gate passes:**
   1. Look up the transition ID for `Live` via `mcp__atlassian__getTransitionsForJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey is the ticket key). Pick the transition whose `to.name == "Live"` (case-sensitive). If no exact match, fall back to a case-insensitive substring match on `"live"`. If still no match, halt finalization with `"Finalization skipped — no 'Live' transition available from current status"` appended to `actionsTaken`; do NOT abort the rest of the workflow.
   2. Execute the transition via `mcp__atlassian__transitionJiraIssue` with the captured ID.
   3. Assign the ticket to **Fabiano Desouza** (`accountId: 5a6765563c7f1842c3d7b806`) via `mcp__atlassian__editJiraIssue` with `fields: { "assignee": { "accountId": "5a6765563c7f1842c3d7b806" } }`.
   4. Update the in-memory ticket: set `fields.status.name` to `"Live"` so the Step 3 sort places it in priority bucket `2` (LIVE column) and the rendered report's heading + Current Status bullet reflect the new state.
   5. Append to `actionsTaken`: `"Transitioned to Live and assigned to Fabiano Desouza"`.

   **Failure modes (soft — record and continue):**
   - `getTransitionsForJiraIssue` or `transitionJiraIssue` errors → append `"Transition to Live failed: <verbatim error>"` to `actionsTaken`. Continue.
   - Transition succeeded but `editJiraIssue` (assign) errors → append `"Transitioned to Live but assign failed: <verbatim error>"` to `actionsTaken`. Status stays at `Live`.

   **If the gate fails** (deploy wasn't fully successful), do NOT transition or assign. Append `"Finalization skipped — deploy was not fully successful (see prior actions for cause)"` to `actionsTaken` so the report explains why the ticket stayed in PROD READY.

8. On overall success: post a Jira comment to the ticket via `mcp__atlassian__addCommentToJiraIssue` documenting what happened. See [jira-deploy-comment-template.md](jira-deploy-comment-template.md) for the comment body template.

### `Yes — but with an updated plan`

1. Ask a free-text follow-up: `"Provide your edits to the plan. You can paste the full revised plan, or describe changes line-by-line; I'll re-render and confirm before executing."`
2. Apply the edits, re-render the plan, ask one final yes/no confirmation. On `yes`, proceed with the same execution sequence; on `no`, treat as option 3.
3. On success: same Jira comment as option 1, plus a "Plan was operator-edited" note in the body.

### `No — I'll do it myself`

- Append to `actionsTaken`: `"Deploy skipped — operator declined"`. No merge, no Slack post, no CICD watch. No Jira comment.

## Non-interactive runtime (scheduled daily run)

The skill cannot block on `AskUserQuestion`. If `QUESTIONS` contains a Rule C entry AND the runtime is non-interactive:
- Print the plan to the run log.
- Append to `actionsTaken`: `"Deploy skipped — awaiting operator approval (non-interactive run)"`.
- Do NOT execute any step. Do NOT post any Jira comment.

## Hard constraint — the skill must NEVER

- Run `firebase deploy …`, `npx firebase deploy …`, or any direct deploy command.
- Pass `--project trident-funding` to any command other than read-only inspections (e.g., listing past runs is fine; deploying is not).
- "Helpfully" auto-deploy a function that CICD missed. The skill REPORTS the gap; the operator deploys.

If a future maintainer edits this rule to add a fallback `firebase deploy` step, that's a regression — revert the change.

## Failure modes (in addition to per-step halts above)

- Jira fetch fails twice (initial fetch in step 1): append to `actionsTaken`: `"Deploy skipped — Jira fetch failed: <error>"`. Continue with the rest of the workflow.
- No open PR for the ticket branch (pre-flight 1 failure): append to `actionsTaken`: `"Deploy skipped — no open PR found for branch <TICKET-KEY>"`.
- **PR not mergeable** (pre-flight path 3a — failing checks, blocked reviews, conflicts, draft, etc.): append the verbose "Merge skipped — PR #<N> not mergeable. Failing checks: …. Required action: …. Resolve and re-run." action per path 3a above, plus the matching REMINDERS entry. **No question is asked** for this ticket; the operator's next move is to resolve the blockers and let the next run pick the ticket up again.
- **PR has unresolved review comments only** (pre-flight path 3b — branch protection allows merge but operator wants threads resolved first): append the "Merge skipped — PR #<N> has <UNRESOLVED_COUNT> unresolved review comments. Resumed implementation session …" action per path 3b above. **No question is asked**; the auto-resumed session handles the review-comment loop autonomously.
- **Unresolved comments path can't find the implementation session** (no-session fallback in path 3b step 2): append the manual-fallback action; the operator runs `/review-pr-comments` themselves.
- `gh` CLI not available / unauthenticated: append to `actionsTaken`: `"Deploy skipped — gh CLI unavailable or unauthenticated"`.
- GraphQL query for review threads fails: treat `UNRESOLVED_COUNT` as `0` (don't block a legitimate deploy on a query failure), append a one-line warning to the terminal: `"Could not fetch review threads for PR #<N>; proceeding without unresolved-comment check."`. Continue to path 3c (clean merge plan).
- Slack MCP unavailable: per Apply-the-answer step 5.3 above, continue but record the warning.
