# Rule E — Testing-lane QA-pass verification (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step Jira fetches, the marker-scan rule, the transition logic, the PR-discovery via `gh`, and the failure modes.

## Trigger

The response contains at least ONE ticket whose `fields.status.name` is in:
- `Resolved - Ready for QA`
- `Resolved - Ready for AQA`

(These are the two TESTING-column statuses on board 391.)

## Per-Testing-ticket handling (apply in board order — top of the TESTING lane first)

1. **Fetch the ticket's comments, description, and summary.** Use `mcp__atlassian__getJiraIssue` with:
   - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
   - `issueIdOrKey`: the ticket key
   - `fields`: `["comment", "description", "summary"]`
   - `responseContentFormat`: `"markdown"`

   If the result exceeds the inline token cap, the harness saves it to disk — use `grep` on the saved file to extract the comment-scan signal (same pattern as Rule B / Rule D).

2. **Scan for the QA-pass marker.** Match against the body text of each comment in `fields.comment.comments[]`.

   **Match rule:** a comment counts as a QA-pass marker if its body (after trimming leading whitespace) **starts with** the case-insensitive prefix `qa pass`. Examples that MATCH:
   - `QA Pass`
   - `QA Pass — verified all AC items on stage`
   - `qa pass ✅`
   - `QA PASS\nDetails:\n- AC1 ✓`

   Examples that DO NOT match:
   - `Live QA Pass …` (begins with `Live`, not `QA Pass` — Rule B handles this marker)
   - `Note: QA Pass came in last week` (`QA Pass` is not at the start of the body)
   - `Failed QA — see notes` (no `qa pass` prefix at all)

   This start-of-body rule is what keeps Rule E and Rule B's `live qa pass` substring scan from overlapping.

   Set `QA_PASS_FOUND = true` if any comment matches, otherwise `QA_PASS_FOUND = false`.

3. **Branch on `QA_PASS_FOUND`:**

   ### 3a. `QA_PASS_FOUND == false`

   Skip this ticket — no question, no action, no `actionsTaken` entry. The next run picks up after QA posts the marker comment.

   ### 3b. `QA_PASS_FOUND == true`

   Append a yes/no question to the in-memory `QUESTIONS` list:

   ```
   <TICKET-KEY> is in Testing and a "QA Pass" comment was found. Has QA been completed and should we move it to Under Review? (yes/no)
   ```

   Do NOT transition the ticket yet. Do NOT add a REMINDERS entry yet. Both are deferred to the question-application step.

## Apply the answer (during Step 6 / question-collection phase)

### 4a. Q1 `yes` answer — transition + PR enumeration + optional Slack post

1. **Look up the `Under review` transition** via `mcp__atlassian__getTransitionsForJiraIssue` with `cloudId` and `issueIdOrKey`. Find the transition whose `to.name == "Under review"` (case-sensitive). If no exact match, fall back to a case-insensitive substring match on `"under review"`.

   On the Trident workflow this is currently transition id `201` (verified 2026-05-14), but rules always lookup at runtime — never hard-code the id, because workflow edits can renumber transitions.

2. **Execute the transition** via `mcp__atlassian__transitionJiraIssue` with the captured id.

   - On error: append to `actionsTaken`: `"Move failed: <verbatim error>"`. Do NOT run the PR enumeration step. Print one terminal warning line.

3. **Determine the target repo** for `gh pr list`. Match the ticket's `description` + `summary` text (case-insensitive) against the known-repo list from Rule D step 4 (in priority order — more specific names first):
   - `portal-react-boattrader`
   - `webapp-react-trident`
   - `api-node-boats`
   - `api-node-boattrader`
   - `lambda-node-trident-700credit`
   - `lambda-node-trident-advertised-rates`
   - `lambda-node-trident-portal-lead`
   - `pp-algorithm`
   - `configd`

   First match wins. If none appear in the text, **default to `webapp-react-trident`**.

4. **Enumerate open PRs** by ticket-key branch:

   ```
   gh pr list --repo boatsgroup/<repo> --head <TICKET-KEY> --state open --json url,number,title,isDraft,reviewDecision
   ```

   The `--head` filter matches PRs whose source-branch name is exactly `<TICKET-KEY>` (e.g., `TRIDENT-904`). The convention on this account is to name the impl branch after the ticket, so this typically returns 0 or 1 PR.

   - On exit code 0 with a non-empty array: capture each PR's `url`, `number`, `title`, `isDraft`, `reviewDecision`. Sort by `number` ASC so the order is stable across runs.
   - On exit code 0 with an empty array: no open PR for this branch — go to branch **5c** below.
   - On non-zero exit: capture the stderr text — go to branch **5d** below.

5. **Branch on PR-enumeration result.** Exactly one of 5a / 5b / 5c / 5d applies per ticket:

   ### 5a. PRs found AND operator says "Yes, post to Slack" (Q2 = yes)

   Q2 is the follow-up yes/no question that fires only when step 4 found ≥1 open PR:

   ```
   PR(s) found for <TICKET-KEY>: <url1>, <url2>, … — post a review request as you to #poseidon-finance? (yes/no)
   ```

   On **Q2 = yes**:

   1. **Send the Slack message** via `mcp__claude_ai_Slack__slack_send_message`:
      - `channel_id`: `C07S51UAS6P` (the `#poseidon-finance` channel id, verified 2026-05-14). If you need to re-verify, run `mcp__claude_ai_Slack__slack_search_channels` with query `poseidon-finance` and cache the result for this run. Note the channel-name match may also return `#finance-poseidon-pm-em` (different channel) — always pick the one whose name is `poseidon-finance` exactly.
      - `message`: the message body, with literal `\n` line breaks between elements, in EXACTLY this format (one PR URL per line; do NOT collapse to one line):
        ```
        <!subteam^S07UBA3B2T0> please review for <TICKET-KEY>
        <PR-URL-1>
        <PR-URL-2-if-applicable>
        ```

        **CRITICAL — Slack group-mention syntax.** Use the literal `<!subteam^S07UBA3B2T0>` token (no `@` prefix, no display-name) — Slack will render this as the highlighted `@finance-dev` group ping AND notify every member of the group. Plain `@finance-dev` text does NOT trigger a group mention; it renders as inert plain text and nobody gets notified (verified 2026-05-14 — an earlier run posted plain `@finance-dev` and the group did not get pinged).

        `S07UBA3B2T0` is the subteam ID for the `finance-dev` user group, verified by sampling existing channel messages on 2026-05-14. **If the group is renamed or recreated in the future** and this ID stops working, re-discover it by reading recent #poseidon-finance messages via `mcp__claude_ai_Slack__slack_read_channel` and searching the raw `text` for a `<!subteam^XXXXXX>` token in a known group-mention message (e.g., a daily "Good morning @finance-dev" post). Then update this reference file with the new ID.

        Optional explicit display-name form `<!subteam^S07UBA3B2T0|@finance-dev>` is also accepted by Slack and renders identically — both forms work. Prefer the bare form for terseness.
      - DO NOT post in a thread (`thread_ts` left unset) — the channel-level visibility is the point.

      Capture the response `message_ts` and `message_link` for the audit trail.

      - On Slack error: append `"Slack post FAILED: <verbatim error>; falling back to PR-approval reminder"` to a terminal warning, then fall through to branch 5b (post the REMINDERS line instead so the operator still has actionable PR URLs).

   2. **Post a Jira comment** via `mcp__atlassian__addCommentToJiraIssue`:
      - `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
      - `issueIdOrKey`: the ticket key
      - `commentBody`: `"PR is pending review — request for review has been made in #poseidon-finance."`
      - `contentFormat`: `"markdown"`

      - On Jira-comment error: append `"Jira PR-pending comment failed: <verbatim error>"` to the action summary, but do NOT undo the Slack post (it's already public). The Slack message itself is the canonical audit trail.

   3. **Do NOT add a PR-approval REMINDERS line.** The Slack post replaces the reminder — the operator does not need both. (This is the user's contract: "reminder does not need to be given if user chose for you to post to slack".)

   4. **Append to `actionsTaken`** (one entry):
      ```
      Moved to Under Review, posted PR-review request to #poseidon-finance (Slack ts: <ts>), and added Jira "PR pending review" comment.
      ```

   ### 5b. PRs found AND operator says "No, just remind me" (Q2 = no)

   Append exactly one REMINDERS line listing every PR URL, separated by `, ` (comma + space):

   ```
   <TICKET-KEY>: Get PR approvals for the following PR(s): <url1>, <url2>, …
   ```

   If any PR has `isDraft == true`, append the marker `(DRAFT)` immediately after its URL. If `reviewDecision == "APPROVED"`, append `(APPROVED — ready to merge)` for visibility (the operator may want to advance straight to Prod Ready).

   Append to `actionsTaken` (one entry):
   ```
   Moved to Under Review and posted PR-approval reminder (<N> PR(s)); operator declined Slack post.
   ```

   ### 5c. No PRs found — skip Q2

   When step 4 returned an empty array, **do not ask Q2** (there are no PR URLs to post). Append a warning REMINDERS line so the operator can investigate:

   ```
   <TICKET-KEY>: Moved to Under Review but no open PRs were found in boatsgroup/<repo> with head branch <TICKET-KEY>. Please verify the PR exists / branch naming, then chase approvals manually.
   ```

   Append to `actionsTaken`:
   ```
   Moved to Under Review; no open PRs found by branch — flagged for manual check.
   ```

   ### 5d. `gh pr list` failed — skip Q2

   When step 4 exited non-zero, **do not ask Q2** (we don't know what to post). Append a REMINDERS line that mentions the failure but does NOT block the transition (which already landed):

   ```
   <TICKET-KEY>: Moved to Under Review, but PR enumeration failed (`gh pr list … --head <TICKET-KEY>` exited <code>). Please list open PRs manually and chase approvals.
   ```

   Append to `actionsTaken`:
   ```
   Moved to Under Review; PR enumeration failed — flagged for manual check.
   ```

### 4b. Q1 `no` answer — leave as-is

- No transition. No `editJiraIssue`. No Q2 fired. No REMINDERS entry. No `actionsTaken` entry.
- The next run will re-evaluate; if the QA Pass marker is still on the ticket, Q1 fires again.

## Failure modes

- **Comments fetch fails** → append to `actionsTaken`: `"QA verification skipped — Jira comment fetch failed: <error>"`. Do not queue any question.
- **No `Under review` transition available** (workflow has been edited) → append `"Move failed: no 'Under review' transition available on this ticket"`. Print one terminal warning. The PR-enumeration step and Q2 are skipped.
- **Transition call errors** → append `"Move failed: <verbatim error>"`. PR-enumeration and Q2 skipped.
- **`gh pr list` errors** → see branch 5d above; the transition already landed so the rule still records the move and falls back to a manual-check reminder. Q2 is NOT asked.
- **Slack channel lookup fails** (search returns no match for `poseidon-finance`) → log the failure, fall through to branch 5b (post the PR-approval reminder instead).
- **Slack post errors** → log the verbatim error, fall through to branch 5b. Do NOT post the Jira "pending review" comment (the Slack post is its prerequisite).
- **Jira `addCommentToJiraIssue` errors** (after a successful Slack post) → append a parenthetical `"… (Jira comment failed: <verbatim error>)"` to the `actionsTaken` summary. Do NOT undo the Slack post.

## Per-ticket question contract

Rule E asks **up to TWO questions per ticket per run**: Q1 (QA-complete → transition) and, on Q1 = Yes with ≥1 open PR found, Q2 (Slack post vs. reminder). Q2 NEVER fires when Q1 = No, when the transition failed, when no PRs were found, or when `gh pr list` failed.

The same ticket can re-fire on subsequent runs as long as the QA-pass marker remains and the ticket is still in TESTING. Once the ticket transitions out of TESTING (e.g., to Under Review via Q1=Yes), Rule E no longer evaluates it.

## Cross-rule notes

- Rule E does NOT chain into Rule C. Rule E transitions tickets to `Under review` (priority 5), which is one column away from PROD READY (priority 3), but Rule C only fires on `Resolved - QA Complete` / `Pending Release Candidate` — never on `Under review`.
- Rule E is independent of Rules A, B, D. A ticket in TESTING cannot simultaneously be New / In Progress / Live / PROD READY, so cross-rule collisions are structurally impossible.
