---
name: investigate-e2e-monitoring-failures
description: Investigates recent unprocessed alerts from the `funnel-e2e` Cloud Run monitor (the agent-driven E2E synthetic test of the LendAPI Combined / Full App funnels) posted to Slack #finance-prod-alerts, and produces a root-cause report per alert with a suggested short Slack reply. Scans up to the last 7 days of channel history, identifies funnel-e2e alerts specifically by their "Trident Funnel E2E — ..." message title (this channel also carries "An error occurred sending loan application to Salesforce" / "Partner Loan Submission Failure" alerts from a different pipeline, already owned by `triage-finance-prod-alerts`/`fix-prod-submission-error` — never touches those), and treats an alert as unprocessed only when it has NEITHER an `:acknowledged:` emoji reaction NOR any thread replies. For each unprocessed alert it extracts the run id, pulls the matching Cloud Run logs via `gcloud logging read` against the `trident-funding` project's `funnel-e2e` service, views the failure screenshot when its signed URL hasn't expired, and determines whether the true cause is a genuine funnel/product break, a monitor-side infra hiccup (Cloudflare block, SDK error, timeout), or an already-annotated known issue (the LendAPI batch-window false-fail case) needing no further digging. Read-only and report-only — it never posts to Slack, reacts with an emoji, or changes anything. Use when the operator asks to investigate/triage e2e funnel monitoring failures, check on funnel-e2e alerts, find out why the loan-application funnel test is failing, or review unacknowledged "Trident Funnel E2E" Slack alerts. Does NOT handle loan-submission-failure alerts and does NOT post anything to Slack itself.
---

# Investigate E2E Monitoring Failures

Reads unhandled `funnel-e2e` monitor alerts from `#finance-prod-alerts`, digs into the Cloud Run logs and failure screenshot behind each one, and hands back a root-cause report with a ready-to-post (but never auto-posted) Slack reply. Purely read/report — no Slack mutation, no code changes.

## Fixed configuration

- **Channel:** `#finance-prod-alerts` — `channel_id: C095S0JBNTH`. Re-discover via `mcp__claude_ai_Slack__slack_search_channels` if this ever 404s.
- **Lookback window:** 7 days (fixed — this is what "recent" means for this skill; not an argument).
- **GCP project:** `trident-funding`. **Cloud Run service:** `funnel-e2e`.
- **"Ack" reaction name:** `acknowledged` — a custom emoji, verified 2026-08-16 against real reactions already present in this channel (`Reactions: acknowledged (1)`). This is distinct from an `eyes` reaction, which some alerts also carry — `eyes` means someone glanced at it, not that it's acknowledged; do NOT treat `eyes` as satisfying the ack condition. If `acknowledged` ever stops appearing on genuinely-handled alerts, re-verify the real name via `mcp__claude_ai_Slack__slack_get_reactions` on a manually-acknowledged alert before trusting a guess.
- **How to tell a funnel-e2e alert apart from everything else in this channel:** its message text starts with the bold heading `*Trident Funnel E2E — ...*` (observed variants: `FUNNEL FAILED in production`; per the monitor's own design there are also `MONITOR_INFRA_ERROR` and known-issue/green variants — recognize any of them by the same `Trident Funnel E2E` prefix, not just the FAILED wording). Loan-submission alerts in the same channel look completely different (`*An error occurred sending loan application to Salesforce...*`, `*Partner Loan Submission Failure* - Salesforce Loan ID: ...`) and come from the same bot (`Trident Monitoring`), so **filter on message text, never on the author** — author alone doesn't distinguish alert types in this channel.

## Workflow

### Step 1 — Fetch the last 7 days of channel history

1. Compute the lookback boundary: `date -v-7d +%s` (standalone Bash, macOS/BSD `date`) → `OLDEST_TS`.
2. `mcp__claude_ai_Slack__slack_read_channel` with `channel_id: C095S0JBNTH`, `oldest: <OLDEST_TS>`, `limit: 100`, `response_format: detailed` (detailed includes reactions + thread-reply counts inline — needed for Step 3, don't use `concise`).
3. If `pagination_info` indicates more messages, keep paging with `cursor` until you've covered the full 7-day window or run out of pages.

### Step 2 — Keep only funnel-e2e alerts

For each message, keep it only if its text starts with `Trident Funnel E2E`. Discard everything else (loan-submission alerts, any other channel chatter) without further inspection — this skill has no business with them.

### Step 3 — Keep only unprocessed alerts

An alert is **unprocessed** only when BOTH are true (either signal alone counts as already handled — don't re-investigate something a human already reacted to or replied on, even if the reaction wasn't literally `acknowledged`):
- No `acknowledged` reaction (an `eyes` reaction, or no reactions at all, both count as "no ack").
- No thread replies (`Thread: N replies` absent, or effectively N == 0).

Discard every alert that fails this check. If NOTHING survives, stop here and report plainly: `No unprocessed funnel-e2e alerts in the last 7 days.` Do not fabricate a report for zero alerts.

### Step 4 — Fast-path known-issue alerts

The monitor itself renders a known LendAPI batch-window false-fail (05:00–08:00 UTC on Full App) as a green card annotated as a known issue, not a real outage — check the alert text for that annotation (wording like "known issue" / "no action needed") before doing any log/screenshot digging. If it matches: skip straight to the report for this alert with root cause `Known LendAPI daily batch-job window false-fail (05:00–08:00 UTC) — the monitor already classified this as a known issue, no further action needed`, and move to the next alert. Everything else below (Steps 5–8) applies only to alerts that do NOT match this fast path.

### Step 5 — Extract the alert's own details

From the message text, pull out:
- **Title** — the bold first line.
- **Classification** — `FUNNEL_FAILED` or `MONITOR_INFRA_ERROR` (from the attachment's bold prefix).
- **Funnel** — `Combined` or `Full App` (from "LendAPI `<X>` funnel").
- **`runId`** — from the plain `` runId: `<uuid>` `` line. If that line is ever missing, fall back to parsing it out of the embedded "See the Logs" link's `jsonPayload.runId%3D%22<uuid>%22` query param.
- **Blocking step** — from "Blocking step: `*<step>*`" (may be absent on `MONITOR_INFRA_ERROR`).
- **Telemetry** — attempt/turns/wall-time/cost/learnings-hash line (context, not root cause).
- **Screenshot URL**, if present — the second link after "See the Logs", separated by `·`. It's a **signed GCS URL with a 24h TTL** — an alert older than a day will have an already-expired link even though it's still visibly present in the message text. `slack_read_channel`'s preview text can also be truncated on long messages (observed: some lines end in `...`) — if a screenshot link isn't visible in a message you expect one on, don't conclude it's absent; note it as unconfirmed rather than asserting either way.

### Step 6 — Pull the Cloud Run logs

```
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="funnel-e2e" AND jsonPayload.runId="<runId>"' --project=trident-funding --format=json --limit=200 --order=asc
```

(standalone Bash, no pipes.) Read the **entire** returned log set in order, not just the last entry — the actual root cause is usually in the harness's step-by-step control-flow log lines or the agent's own verdict reasoning (`blockingStep`, `reason`, `degraded`/`degradedReason`), not only the terminal `FunnelE2E:COMPLETED` summary. Look specifically for: a Cloudflare-block indicator, an SDK/Anthropic API throw, a config-write failure (these all point to `MONITOR_INFRA_ERROR`, a monitor hiccup — never a real funnel outage even if the Slack card said `FUNNEL_FAILED`-shaped things), versus a specific DOM/selector/validation failure the agent actually hit while driving the real funnel (points to a genuine product break). Also note: Chromium child-process SIGPIPE lines tagged `ERROR` severity by Cloud Run are documented as harmless noise — never treat log *severity* as a root-cause signal, only the actual message content.

If `gcloud logging read` errors or returns nothing for that `runId`, don't fabricate a root cause from the Slack message alone — say so explicitly in that alert's report and mark the finding lower-confidence.

### Step 7 — View the failure screenshot, if available

If Step 5 found a screenshot URL: fetch it (`WebFetch` on the exact signed URL). A 403 or signature-expired response means the 24h TTL has lapsed — note that plainly, it's not an error worth digging into. If no screenshot link was ever in the message (screenshot signing can silently fail server-side, or a `MONITOR_INFRA_ERROR` that aborted before the agent ran never produces one at all), say plainly that no screenshot is available — never guess what it might have shown.

### Step 8 — Determine root cause

Synthesize the alert's own stated reason + the full Cloud Run log detail + the screenshot (if viewable) into one clear, specific, evidence-cited root cause. Classify it as one of:
- **Genuine funnel/product break** — something on the real site changed or broke (cite the exact selector/step/error).
- **Monitor-side infra hiccup** — Cloudflare block, SDK error, timeout, config-write failure (cite the exact evidence; explicitly note this is NOT a real funnel outage).
- **Known/benign** — matches a documented benign pattern (the batch-window case from Step 4, or SIGPIPE-style noise) — cite why.
- **Inconclusive** — logs and/or screenshot didn't give enough to be sure. Say exactly what's missing (expired screenshot, sparse/missing logs, ambiguous verdict) rather than guessing at a cause.

### Step 9 — Produce the report

One block per unprocessed alert found (newest first), even if only one:

```markdown
### <alert title> — <funnel>, <FUNNEL_FAILED|MONITOR_INFRA_ERROR>, <timestamp>
**Root cause:** <2–4 sentences, cites the specific evidence from logs/screenshot/message>
**Suggested Slack comment:** "<short, specific, human-toned reply — one or two sentences>"
```

Print this directly in your response — this skill does not write a file or publish an artifact on its own. If the operator wants the report persisted somewhere, that's a separate follow-up ask.

## What this skill never does

- Never posts to Slack (no `slack_send_message`, no thread reply) — the "suggested comment" is for the operator to review and post themselves.
- Never adds a reaction (no `slack_add_reaction`) — acknowledging is the operator's call, not this skill's.
- Never touches loan-submission-failure alerts in the same channel — that's `triage-finance-prod-alerts` / `fix-prod-submission-error`'s job.
- Never modifies the `funnel-e2e` service, its Firestore learnings docs, or any code.

## Failure modes

- Channel fetch fails → report the verbatim error, stop.
- Zero funnel-e2e alerts in the window at all → `No funnel-e2e alerts in the last 7 days.`
- Funnel-e2e alerts exist but all are already acknowledged/commented → `<N> funnel-e2e alert(s) in the last 7 days, all already handled — nothing to investigate.`
- `gcloud logging read` fails or returns nothing for a `runId` → note it in that alert's report, still produce a best-effort root cause from the Slack message content alone, flagged lower-confidence.
- Screenshot link expired or absent → say so plainly; never guess at screenshot content.
- `gcloud` not authenticated for `trident-funding` → report the verbatim auth error; do not silently skip the logs step without saying why.
