# Rule F — Under-Review PR-approval auto-transition (full detail)

Used by `jira-sprint-manager` Step 2.5. The summary + flowchart live in SKILL.md; this file holds the per-step PR enumeration, the stakeholder-trigger keyword list, the routing logic, and the failure modes.

## Trigger

The response contains at least ONE ticket whose `fields.status.name == "Under review"` (case-sensitive — the Jira workflow uses lowercase `review`).

Rule F evaluates each Under-Review ticket independently. Tickets Rule E just transitioned into Under Review during the SAME run are also evaluated (E → F chain — see SKILL.md "Interaction order across rules").

## Per-ticket handling

1. **Determine the target repo.** Match the ticket's `description` + `summary` text (case-insensitive) against the known-repo list from Rule D step 4:
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

   First match wins (more specific names listed first). If none appear in the text, **default to `webapp-react-trident`**.

   The ticket text used for repo detection is whatever was fetched in the Step-2 JQL response (`fields.description` + `fields.summary`). If Rule E already fetched comments earlier in the same run, the fetched text is fine — Rule F does NOT need to re-fetch.

2. **Enumerate open PRs** by ticket-key branch:

   ```
   gh pr list --repo boatsgroup/<repo> --head <TICKET-KEY> --state open --json url,number,title,isDraft,reviewDecision
   ```

   `reviewDecision` values from GitHub:
   - `APPROVED` — all required reviews have approved.
   - `CHANGES_REQUESTED` — at least one reviewer requested changes.
   - `REVIEW_REQUIRED` — needs review but nobody has approved yet.
   - `null` — no review has been requested (e.g., branch protection doesn't require reviews).

   Capture every PR's `url`, `number`, `title`, `isDraft`, `reviewDecision`. Sort by `number` ASC for stable output.

3. **Apply the approval gate.** Proceed to step 4 ONLY when BOTH conditions hold:
   - `PR_COUNT >= 1` (at least one open PR was found), AND
   - Every open PR has `reviewDecision == "APPROVED"`.

   Drafts count toward the gate too — a draft PR with `reviewDecision == "APPROVED"` is treated as approved (rare, but defensible since the operator explicitly approved a draft). If you want to exclude drafts in the future, add a `&& !isDraft` clause.

   **When the gate does NOT pass**, handle each case differently — do NOT skip silently:

   - **`gh pr list` returned an error (non-zero exit):** print one terminal warning line. No `actionsTaken` entry, no REMINDERS entry (PR state is unknown so no actionable reminder is possible). The next run retries.

   - **No open PRs found (`PR_COUNT == 0`):** append a REMINDERS entry:
     ```
     <TICKET-KEY> is Under Review — no open PRs found in <repo>. Check that the PR was opened against the correct branch.
     ```
     No `actionsTaken` entry. The ticket stays in Under Review.

   - **Open PRs found but not all APPROVED** (any PR has `reviewDecision != "APPROVED"` — includes `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or `null`): append a REMINDERS entry listing every unapproved PR URL:
     ```
     <TICKET-KEY> needs PR approvals to move to PROD READY: <url1>, <url2> (reviewDecision: <status1>, <status2>)
     ```
     No `actionsTaken` entry. The ticket stays in Under Review.

4. **Scan for stakeholder triggers.** Match the ticket's `description` + `summary` text (case-insensitive) against this list of trigger phrases:

   | Phrase | Match rule |
   |---|---|
   | `GA event` | case-insensitive substring |
   | `GA events` | case-insensitive substring |
   | `google analytics` | case-insensitive substring |
   | `stakeholder approval` | case-insensitive substring |
   | `stakeholder review required` | case-insensitive substring |
   | `stakeholder sign-off` | case-insensitive substring (matches `sign-off` and `signoff` — strip the hyphen before comparing) |

   The match list is **GA-specific keywords + explicit stakeholder phrases only**. Iterable / Salesforce / other event-system mentions do NOT trigger the stakeholder route — Rule F treats those as ordinary release work that goes through standard QA → prod ready. If you want to extend the list, edit this section.

   Set `STAKEHOLDER_REQUIRED = true` if ANY phrase matches.

5. **Determine the target transition and execute it.**

   ### 5a. `STAKEHOLDER_REQUIRED == true` → Stakeholder Review

   1. Look up the `Stakeholder Review` transition via `mcp__atlassian__getTransitionsForJiraIssue`. Find the transition whose `to.name == "Stakeholder Review"` (case-sensitive). If no exact match, fall back to a case-insensitive substring match on `"stakeholder review"`.

      On the Trident workflow this is currently transition id `171` (verified 2026-05-14), but always lookup at runtime.

   2. Execute `mcp__atlassian__transitionJiraIssue` with the captured id.

   3. On success: update in-memory `status.name = "Stakeholder Review"` (so Step 3 sorting puts the ticket in priority bucket 4). Append to `actionsTaken`:

      ```
      Moved to Stakeholder Review after all PRs APPROVED (<N> PR(s)): <url1>, <url2>, …. Trigger keywords matched: <comma-separated-list>.
      ```

   ### 5b. `STAKEHOLDER_REQUIRED == false` → Resolved - QA Complete (PROD READY)

   1. Look up the `Resolved - QA Complete` transition. Find the transition whose `to.name == "Resolved - QA Complete"` (case-sensitive). If no exact match, fall back to a case-insensitive substring match on `"resolved - qa complete"`.

      On the Trident workflow this is currently transition id `221` (verified 2026-05-14), but always lookup at runtime. Note: there is also a non-global "QA Complete" transition (id `31`) with the same `to` status; either id works, but the global `221` is the preferred match because it works from every source status.

   2. Execute `mcp__atlassian__transitionJiraIssue` with the captured id.

   3. On success: update in-memory `status.name = "Resolved - QA Complete"` (so Step 3 sorting puts the ticket in priority bucket 3 / PROD READY). Append to `actionsTaken`:

      ```
      Moved to Resolved - QA Complete (PROD READY) after all PRs APPROVED (<N> PR(s)): <url1>, <url2>, ….
      ```

   4. **Back-edge chain into Rule C (interactive mode only).** After the transition lands, immediately re-invoke Rule C's per-ticket evaluation on this ticket. The chain runs Rule C's full decision tree (pre-flight open-PR lookup, then path 3a / 3b / 3c / 3d). Rule C's appended `actionsTaken` entries stack additively on top of Rule F's entry from step 3. A Rule-C failure does NOT roll back Rule F's transition — the ticket stays in PROD READY and Rule C's outcome (reminder, skip, or partial deploy) is appended as the next entry.

      In **autonomous mode** the chain is BROKEN — skip step 4 entirely. Rule C is skipped in autonomous mode (its lane-moving path 3c requires the 3-option approval question), so the just-moved ticket waits for the next interactive run before the merge plan surfaces.

      The Stakeholder Review path (5a) does NOT chain — those tickets are blocked on a stakeholder, not on a merge.

## Failure modes

- **`gh pr list` fails** (non-zero exit) → print one terminal warning line; no `actionsTaken` or REMINDERS entry. Rule F is best-effort — a `gh` outage shouldn't pollute the report with reminders. The next run retries.
- **Gate fails — no open PRs** → append REMINDERS entry (see step 3). No `actionsTaken` entry. This is actionable: the operator should verify the PR was opened.
- **Gate fails — PRs not all APPROVED** → append REMINDERS entry listing unapproved PRs with their `reviewDecision` status (see step 3). No `actionsTaken` entry. This is the expected steady state until reviewers approve.
- **`getTransitionsForJiraIssue` errors** → append `"Move failed: could not fetch transitions: <error>"` to `actionsTaken`. Print one terminal warning.
- **No matching transition available** (workflow has been edited) → append `"Move failed: no '<target>' transition available on this ticket"` (where `<target>` is `Stakeholder Review` or `Resolved - QA Complete`). Print one terminal warning. The ticket stays in Under Review.
- **`transitionJiraIssue` errors** → append `"Move failed: <verbatim error>"`. Status stays as Under Review.

## Per-ticket question contract

Rule F **never asks a question** — it is fully autonomous on the gate. The operator's override is the manual Jira UI (set the status by hand before the next run).

## Cross-rule notes

- **E → F chain (same run):** Rule E moves a Testing ticket into Under Review on Q1=Yes. Rule F then evaluates that ticket. If all open PRs are already approved AND the stakeholder gate sends it further, both transitions land in the same run and the ticket's `actionsTaken` shows two stacked entries (rule-firing order: E entry first, F entry second). This is rare but valid (e.g., a hotfix PR pre-approved before QA Pass).
- **F → C back-edge chain (same run, interactive mode only):** when Rule F moves a ticket to `Resolved - QA Complete` (path 5b above), Rule F immediately re-invokes Rule C's per-ticket evaluation on that just-moved ticket (see step 4 of section 5b). This is the workflow's only **back-edge** chain — Rule C ran at position 3 in the forward sweep and did NOT see this ticket because it was still in Under Review at that point; the back-edge bridges that gap so the merge plan surfaces in the same run instead of waiting a full cycle. The chain is BROKEN in autonomous mode (Rule C is skipped there). The Stakeholder Review path (5a) does NOT chain.
- **E → F → C cascade (same run):** if both forward chains happen on the same ticket — Rule E moves Testing → Under Review, then Rule F moves Under Review → PROD READY, then the back-edge fires Rule C — the ticket's `actionsTaken` can show three stacked entries in one run. Theoretically rare (it requires the PR to be already approved AND the deployment to be already cleanable).
- **F and Rules A/B/D are mutually exclusive** by board column.
