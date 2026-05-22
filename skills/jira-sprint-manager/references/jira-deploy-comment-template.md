# Jira deploy-success comment template (Rule C)

Posted to the Jira ticket via `mcp__atlassian__addCommentToJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, `contentFormat: "markdown"`) when Rule C's "Yes — execute plan as proposed" path completes successfully.

## Body

```markdown
# Production deploy via merge-to-main 🚀

**Run date:** <YYYY-MM-DD HH:MM local>
**Driven by:** jira-sprint-manager (Rule C, operator-approved)

- **Merged PR:** <PR URL>
- **Merge commit:** `<short SHA>`
- **Slack notification:** posted to `#merge-requests` (<message URL>)
- **CICD runs:** <comma-separated run URLs with conclusions>
- **Functions reported on:** <funcName list with per-function status, or "N/A — no GCP function deploy in notes">
- **Branch cleanup:** <"auto-deleted by repo's delete_branch_on_merge setting" | "deleted explicitly by skill — repo's auto-delete is off" | "skipped — already gone before check">
- **Jira finalization:** <"Transitioned to Live, assigned to Fabiano Desouza" | "Skipped — deploy not fully successful" | "Skipped — transition unavailable from <status>" | "Transitioned to Live but assign failed: …">
```

## Field-substitution rules

- `<YYYY-MM-DD HH:MM local>` — operator's local time from `date "+%Y-%m-%d %H:%M %Z"` at the time of the comment post.
- `<PR URL>` — full URL from `gh pr view`'s `url` field (e.g., `https://github.com/boatsgroup/webapp-react-trident/pull/251`).
- `<short SHA>` — first 8 chars of the merge commit SHA from `gh pr view --json mergeCommit`.
- `<message URL>` — Slack permalink from `slack_send_message`'s response (`message_link` field).
- `<CICD runs>` — one row per watched run in the form `<workflowName> — <URL> (conclusion: <success|failure|cancelled|timed_out|skipped>; <Nm><Ns>)`.
- `<funcName list with per-function status>` — one bullet per function in the deployment notes, e.g., `\`sendCustomEventToIterable\` — ✅ Deployed by CICD (\`firebase --project trident-funding deploy --only functions:sendCustomEventToIterable\` ran successfully on us-central1, \`Successful update operation\` confirmed in run log)`.

## Edited-plan variant

When the operator chose "Yes — but with an updated plan", append one extra line above the bullets:

```
**Plan was operator-edited.** The operator updated the proposed plan before approving.
```

So a Rule C run that went through the edited-plan path posts:

```markdown
# Production deploy via merge-to-main 🚀

**Run date:** <YYYY-MM-DD HH:MM local>
**Driven by:** jira-sprint-manager (Rule C, operator-approved)
**Plan was operator-edited.** The operator updated the proposed plan before approving.

- **Merged PR:** <PR URL>
- … (same bullets as the standard template)
```

## Partial-deploy template (Rule C — finalization gate failed because CICD missed function(s))

Posted when the merge + CICD watch succeeded but `gh run view --log` shows one or more functions listed in the deployment notes were NOT deployed (typically because CICD's `changedFunctions.sh` heuristic didn't include them). The ticket stays in PROD READY; Rule C's path 3d will re-check on the next run.

**Critical:** the comment MUST end with the machine-readable structured marker (fenced JSON block) so future runs' path 3d can parse pending functions deterministically.

```markdown
# Deploy status — PARTIAL (<func1>[, <func2>] NOT deployed)

**Merged:** <PR URL> (merge commit `<short SHA>`)
**Merge timestamp:** <ISO 8601 from `gh pr view --json mergedAt`>
**Slack notice:** posted to #merge-requests (<message URL>)

## CICD outcome

- **<workflow name>** (run <runId>) — conclusion: `success`
  - `<job1>` job: <outcome summary>
  - `<job2>` job: SUCCESS overall, BUT steps "Setup Firebase" and "Deploy Changed Functions" were **skipped**

## ⚠️ Gap — manual function deploy required

<2–3 sentences explaining WHY CICD skipped: e.g., `changedFunctions.sh --main` heuristic, fallback rule key mismatch, etc.>

As a result, **`<func1>`[, `<func2>`] was NOT deployed to production by CICD**.

## Action required (operator must run manually)

```
npx firebase --project trident-funding deploy --only functions:<func1>[,<func2>]
```

The jira-sprint-manager skill is NOT authorized to run `firebase deploy …` directly — this is by design (safety contract: all prod deploys flow through CICD; the skill reports gaps but never auto-deploys).

## Finalization status

Ticket has NOT been transitioned to Live because the deploy gate requires every listed function to be deployed by CICD. Status stays at `Resolved - QA Complete` (PROD READY). After running the manual function deploy above, the next `/jira-sprint-manager` run will detect the new `updateTime` via `gcloud functions describe` and automatically finalize the ticket (transition + assign + RESOLVED comment).

🤖 Posted by jira-sprint-manager Rule C (PROD READY deploy) — partial-success report

```jira-sprint-manager-state
{
  "jira-sprint-manager:partial-deploy": {
    "pending_functions": ["<func1>", "<func2>"],
    "merge_commit": "<full merge commit SHA>",
    "merged_at": "<ISO 8601 — same as merge timestamp above>",
    "ticket_key": "<TICKET-KEY>",
    "repo": "<repo basename>"
  }
}
```
```

**Why the structured marker is mandatory:**

Future jira-sprint-manager runs scan for this fenced block (lang `jira-sprint-manager-state`, or any unlabeled JSON block containing `"jira-sprint-manager:partial-deploy"`) to know which functions are still pending. Without it, the path-3d logic falls back to parsing the heading parenthetical, which is fragile (multi-function lists, special characters in function names, etc.). The fenced JSON is the authoritative source of truth.

## Resolved-post-merge template (Rule C path 3d — every pending function now confirmed deployed)

Posted when path 3d's gcloud check confirms every previously-pending function has `updateTime > merged_at`. This comment supersedes the PARTIAL marker; the ticket is transitioned to Live alongside the comment.

```markdown
# Deploy status — RESOLVED ✅

The partial-deploy gap reported earlier has been closed — every previously-pending function has been deployed to production. Ticket transitioned to **Live** and assigned to Fabiano Desouza.

**Verified by:** jira-sprint-manager Rule C path 3d (post-merge recovery)
**Verified at:** <ISO 8601 local time of this run>

## Functions confirmed deployed

| Function | updateTime (post-deploy) | merged_at (gap-start) | Δ |
|---|---|---|---|
| `<func1>` | <ISO 8601> | <ISO 8601> | <e.g., +2h 15m> |
| `<func2>` | <ISO 8601> | <ISO 8601> | <e.g., +30m> |

## Source of the partial-deploy state

This run resolved the partial-deploy state captured in the prior PARTIAL comment (<link or "see comments above">). Original gap: CICD's `changedFunctions.sh` heuristic missed the function in the diff; operator ran `npx firebase --project trident-funding deploy --only functions:<funcs>` manually to close the gap.

## Lifecycle status

- **Prior status:** `Resolved - QA Complete` (PROD READY)
- **New status:** `Live`
- **Assignee:** Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`)

🤖 Posted by jira-sprint-manager Rule C path 3d — post-merge recovery resolution
```

## Resolved-post-merge template (fallback variant — gcloud check unavailable)

Used by Rule C path 3d **Step 4c** when the `gcloud functions describe` check was blocked (auto-mode classifier denial, `gcloud` not authenticated, region mismatch — any `CLASSIFIER_BLOCKED` or `UNKNOWN` outcome that would otherwise halt verification) AND a qualifying post-merge operator-confirmation comment was found in the ticket history. Verification path is recorded as `fallback` so the audit trail accurately reflects that `updateTime` was NOT directly verified — the operator's word stood in for it.

```markdown
# Deploy status — RESOLVED ✅ (fallback verification)

The partial-deploy gap reported earlier has been closed based on an **operator confirmation comment** posted to this ticket after the merge. Ticket transitioned to **Live** and assigned to Fabiano Desouza.

**Verification path: fallback — gcloud check unavailable.** The standard `gcloud functions describe` updateTime check could not be run during this jira-sprint-manager run (typical causes: auto-mode classifier denial, `gcloud` not authenticated locally, function in a non-default region). The skill instead matched a post-merge operator comment that explicitly names every previously-pending function — see "Source comment" below — and treated it as authoritative.

**Verified at:** <ISO 8601 local time of this run>

## Functions covered by the operator comment

| Function | merged_at (gap-start) | Confirmation comment timestamp |
|---|---|---|
| `<func1>` | <ISO 8601> | <ISO 8601> |
| `<func2>` | <ISO 8601> | <ISO 8601> |

## Source comment

> <verbatim snippet of the operator comment that satisfied the fallback gate, truncated to ~240 chars if longer>

— <comment author display name> at <ISO 8601>

## Audit-trail note

If the operator did NOT actually run the manual deploy, the prod functions are still on the pre-merge code and this ticket has been wrongly transitioned to Live. The fallback gate is conservative on staleness (requires a post-`merged_at` timestamp + every pending function name present in the comment body), but is NOT a substitute for the `updateTime` check. Re-running `/jira-sprint-manager` after the gcloud blocker is lifted will re-verify via gcloud if the ticket re-enters PROD READY for any reason.

## Lifecycle status

- **Prior status:** `Resolved - QA Complete` (PROD READY)
- **New status:** `Live`
- **Assignee:** Fabiano Desouza (`accountId: 5a6765563c7f1842c3d7b806`)

🤖 Posted by jira-sprint-manager Rule C path 3d — post-merge recovery resolution (fallback variant)
```
