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
