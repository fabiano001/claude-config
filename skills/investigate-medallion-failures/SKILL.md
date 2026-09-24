---
name: investigate-medallion-failures
description: Investigates recent unprocessed Medallion partner-lender submission-failure alerts (message title `*Partner Loan Submission Failure*`, from `lambda-node-trident-partner-lender`'s `_buildFailureAlert`) posted to Slack #finance-prod-alerts, and produces a root-cause report per alert with a suggested short Slack reply. Scans up to the last 7 days of channel history, identifies Medallion alerts specifically by that message title alone — not by Lender Code, which legitimately reads N/A on poller-level failures (this channel also carries "An error occurred sending loan application to Salesforce" LendAPI alerts and "Trident Funnel E2E" monitor alerts, owned respectively by `triage-finance-prod-alerts`/`fix-prod-submission-error` and `investigate-e2e-monitoring-failures` — never touches those) — and treats an alert as unprocessed only when it has NEITHER an `:acknowledged:` emoji reaction NOR any thread replies. For each unprocessed alert it reads the failure type, Error Message, Error Details, and (800-char-truncated) Stack Trace already embedded in the alert itself — the raw SOAP request Medallion actually received is never logged or persisted anywhere, so the alert's own content is normally the complete evidence available — and classifies the root cause against known patterns (a Salesforce-field-mapping gap in `adapters/medallion.js`, a Salesforce auth/permission error, a generic/opaque HTTP failure, an infra/config problem, or a systemic poller-level failure affecting multiple loans). Read-only and report-only — it never posts to Slack, reacts with an emoji, or changes code. Use when the operator asks to investigate/triage Medallion failures, check on partner-lender submission alerts, find out why a Medallion loan submission failed, or review unacknowledged "Partner Loan Submission Failure" Slack alerts. Does NOT handle LendAPI/webapp loan-submission alerts or funnel-e2e monitor alerts, and does NOT post anything to Slack itself.
---

# Investigate Medallion Failures

Reads unhandled Medallion partner-lender submission-failure alerts from `#finance-prod-alerts`, classifies each one's root cause against this integration's known failure patterns, and hands back a report with a ready-to-post (but never auto-posted) Slack reply. Purely read/report — no Slack mutation, no code changes. Structurally mirrors its sibling `investigate-e2e-monitoring-failures`, adapted for a different alert source that carries far more diagnostic detail inline (see **Step 6**).

## Fixed configuration

- **Channel:** `#finance-prod-alerts` — `channel_id: C095S0JBNTH` (same channel `investigate-e2e-monitoring-failures` and `triage-finance-prod-alerts` already use). Re-discover via `mcp__claude_ai_Slack__slack_search_channels` if this ever 404s.
- **Lookback window:** 7 days (fixed — not an argument).
- **"Ack" reaction name:** `acknowledged` — same custom emoji convention verified for this channel in `investigate-e2e-monitoring-failures`. An `eyes` reaction does NOT count as acknowledged.
- **How to tell a Medallion alert apart from everything else in this channel:** its message text starts with the bold heading `*Partner Loan Submission Failure* - Salesforce Loan ID: <id>`, sourced from `lambda-node-trident-partner-lender/handlers/submitHandler.js`'s `_buildFailureAlert` (Slack `username: 'Partner Loan Submission Monitoring'`, red attachment). This channel also carries two unrelated alert families — `*An error occurred sending loan application to Salesforce...*` (LendAPI/webapp submission failures, owned by `triage-finance-prod-alerts`/`fix-prod-submission-error`) and `*Trident Funnel E2E — ...*` (the funnel monitor, owned by `investigate-e2e-monitoring-failures`) — and all of them, including Medallion's, can render under the same displayed bot identity in a channel read. **Filter on message text, never on the author.**
- **Lender scope:** the `*Partner Loan Submission Failure*` title alone is the reliable signal — **do not additionally require `Lender Code == MEDALLION`.** A poller-level failure (`Poller — run failed before any row could be processed`) fires before any row/lender is even identified, so its `Lender Code` field legitimately reads `N/A` even though, today, Medallion is the only registered adapter and the failure is unambiguously about this integration (verified live: 2026-08-31, `#finance-qa-alerts`). Only one lender adapter (`MEDALLION`) is registered in `adapters/index.js` today — but the registry is explicitly generic (a second lender could be added without other code changes) — so treat `Lender Code` as informational: note it in the report, and flag (don't silently drop) any alert whose `Lender Code` is populated with something other than `MEDALLION`/`N/A`, since that would mean a second lender adapter has been added and this skill's scope needs revisiting.

## Workflow

### Step 1 — Fetch the last 7 days of channel history

1. Compute the lookback boundary: `date -v-7d +%s` (standalone Bash, macOS/BSD `date`) → `OLDEST_TS`.
2. `mcp__claude_ai_Slack__slack_read_channel` with `channel_id: C095S0JBNTH`, `oldest: <OLDEST_TS>`, `limit: 100`, `response_format: detailed` (needed for the reaction/thread-reply counts used in Step 3).
3. Page with `cursor` if `pagination_info` indicates more messages, until the full 7-day window is covered.

### Step 2 — Keep only Medallion alerts

Keep a message only if its text starts with `*Partner Loan Submission Failure*`. Discard everything else (LendAPI/webapp alerts, funnel-e2e alerts, unrelated channel chatter) without further inspection. Do NOT additionally require `Lender Code == MEDALLION` here — see **Fixed configuration** above for why (poller-level failures legitimately carry `N/A`).

### Step 3 — Keep only unprocessed alerts

Unprocessed = **no `acknowledged` reaction AND no thread replies** (either signal alone counts as already handled — same rule `investigate-e2e-monitoring-failures` uses). Discard everything that fails this check. If nothing survives, stop and report plainly: `No unprocessed Medallion alerts in the last 7 days.`

### Step 4 — Extract the alert's own details

Medallion's alert format (`_buildFailureAlert`) always renders fields in this fixed order — pull out whichever are present:
- **Salesforce Application ID**
- **Lender Code** (usually `MEDALLION`; `N/A` on poller-level failures per **Fixed configuration** — record it, don't require it)
- **Error Type** — a `failureType` label. The known taxonomy (verified against source, not exhaustive if it's grown since): `Type 1 — Save_Submit failed`, `Type 2 — SF record create failed`, `REFRESH_LAMBDA_ARN not configured...`, `Type 3 — Refresh failed`, `Poller — 3 consecutive refresh failures`, `Poller — run failed before any row could be processed`. If the label doesn't match any of these, don't force-fit it — note it as an unrecognized type and classify root cause from the Error Message/Details alone.
- **Lender Application ID** — Medallion's GUID; often `n/a` when `Save_Submit` itself never succeeded.
- **Salesforce Lender Submission ID** — conditional, only present past the `Save_Submit` stage.
- **Go to Resubmit** link — points at `PartnerLoansAdmin.tsx`; this is the operator's actual fix mechanism, not something this skill acts on.
- **Error Message** — code block, `error.message`.
- **Error Details** — conditional, `error.statusMessage`/`error.errorDetails` — Medallion's raw SOAP fault content, often a validation-error list (e.g. `{"string":["Down payment value is required."]}`).
- **Stack Trace** — `error.stack`, **truncated to 800 characters** by the alert itself. Don't assume the visible trace is complete.

### Step 5 — Root-cause investigation has a hard ceiling here — know it before digging

Unlike `investigate-e2e-monitoring-failures` (which almost always needs an external Cloud Run log pull), **the raw SOAP envelope Medallion actually received is never logged or persisted anywhere in this integration** — it's a local variable in `adapter.submit()`, gone the moment the call returns. There is also **no persisted failure record** beyond the Slack message itself, and **no environment tag** (prod and QA alerts look identical). So for the large majority of alerts, **the Slack message's own Error Message/Error Details/Stack Trace already IS the complete available evidence** — there usually isn't a deeper log to go pull.

**Optional, best-effort deeper dig (only if the alert's own content is genuinely insufficient):** CloudWatch carries this Lambda stack's logs and `Trident/PartnerLender` metrics, which could hold the *untruncated* stack trace or surrounding execution context for that invocation's timestamp. There's no established convention in this codebase yet for querying AWS CloudWatch Logs from a skill (unlike the GCP `gcloud logging read` pattern `investigate-e2e-monitoring-failures` uses) — if you attempt it, treat it as exploratory (e.g. `aws logs filter-log-events --log-group-name /aws/lambda/<partner-lender-submit-function-name> --start-time <ms> --end-time <ms>`), confirm the function/log-group name and AWS profile/credentials are actually available first, and clearly label anything found this way as supplementary, not required.

### Step 6 — Determine root cause

Classify against these known patterns (verified against this integration's own research and code):

- **Salesforce-field-mapping gap (by far the most common cause)** — Error Details names a **specific missing/invalid field** (e.g. "Down payment value is required", "Applicant Years Retired missing or invalid", "Applicant Street Address Monthly Housing Payment missing"). This integration forwards only a small subset of the Salesforce data it has to Medallion at all, and several fields it does map are either hardcoded (`loan_term=144`, `residence_status=Own`, `residence_years=0`) or misrouted (mobile phone sent under `<phone_home>` instead of Medallion's `<phone_cell>`) or omitted entirely (the `<employment>`/income block is permanently blank pending `TRIDENT-972`). Name the exact field the error cites and state plainly that it's very likely a mapping gap in `adapters/medallion.js`'s `buildApplicantBlock` — not a Medallion-side or data-entry problem.
- **Generic/opaque HTTP failure** (e.g. "Request failed with status code 500" with no Error Details) — check where the Stack Trace originates (e.g. `Object.submit (/var/task/adapters/medallion.js:NNN)`) to identify which call failed. Could be a transient Medallion-side issue or an unhandled exception client-side. Medallion is known to have at least one confirmed, reproducible server-side bug (`Update_Loan`'s `NullReferenceException`) — but that's specific to the `Update_Loan` operation, not `Save_Submit`; don't attribute to it without matching evidence (same operation name in the Error Message/Stack Trace).
- **Infra/config failure** (e.g. `REFRESH_LAMBDA_ARN not configured`) — a deployment/SSM configuration problem, not a data-mapping bug. Flag for whoever owns the Lambda's deployment, not a code fix in the adapter.
- **Salesforce auth/permission error** (e.g. `INSUFFICIENT_ACCESS: SOAP API login() requires the Use Any API Auth user permission`, `INVALID_LOGIN`, an expired session) — a Salesforce credential or permission-set problem, not a code or field-mapping bug. These Lambdas read Salesforce credentials from SSM (`/configd/trident/salesforce/*`); this class of error means the configured integration user's permission set doesn't allow SOAP API access, or the credential itself is stale (e.g. after a Salesforce org/sandbox migration). Flag for whoever owns Salesforce access/SSM config for that environment.
- **Poller-level systemic failure** (`Poller — 3 consecutive refresh failures` / `Poller — run failed before any row could be processed`) — this is NOT a single-loan issue; it means the 30-minute poller (which refreshes every non-terminal submission across all registered lenders) is failing broadly, most likely a Medallion API outage or a Salesforce/SSM connectivity problem. Say so explicitly rather than treating it like a per-loan field bug.
- **`Type 3 — Refresh failed`** — if determinable from the Error Message/Stack Trace, note whether it looks like a Medallion `Get(application_id)` call failure or a Salesforce `updateSubmissionRecord` write failure (the code internally tags these via `e.stage` even though the alert label doesn't show it) — if it's genuinely not determinable from the alert text alone, say so rather than guessing which stage failed.
- **Inconclusive** — the Error Message/Details/Stack Trace don't cite anything specific enough to classify. Say exactly what's missing rather than forcing a fit into one of the categories above.

### Step 7 — Produce the report

One block per unprocessed alert found (newest first), even if only one:

```markdown
### <Salesforce Application ID> — <Error Type>, <timestamp>
**Root cause:** <2–4 sentences, cites the specific field/error/stage from the alert>
**Suggested Slack comment:** "<short, specific, human-toned reply — one or two sentences>"
```

Print this directly in your response — this skill does not write a file or publish an artifact on its own.

## What this skill never does

- Never posts to Slack (no `slack_send_message`, no thread reply) — the "suggested comment" is for the operator to review and post themselves.
- Never adds a reaction (no `slack_add_reaction`).
- Never touches LendAPI/webapp loan-submission alerts or funnel-e2e monitor alerts in the same channel — those belong to `triage-finance-prod-alerts`/`fix-prod-submission-error` and `investigate-e2e-monitoring-failures` respectively.
- Never calls the actual Medallion API, never resubmits a loan, and never modifies `adapters/medallion.js` or any other code — the "Go to Resubmit" link in each alert is the operator's own fix path, not something this skill acts on.

## Failure modes

- Channel fetch fails → report the verbatim error, stop.
- Zero Medallion alerts in the window at all → `No Medallion alerts in the last 7 days.`
- Medallion alerts exist but all are already acknowledged/commented → `<N> Medallion alert(s) in the last 7 days, all already handled — nothing to investigate.`
- Error Type doesn't match the known 6-string taxonomy → don't force a label; classify from Error Message/Details alone and note the unrecognized type plainly (the taxonomy may have grown since it was last verified).
- Error Details/Stack Trace insufficient to classify → mark that alert's finding as inconclusive and state exactly what's missing, rather than guessing.
- An optional CloudWatch dig (Step 5) fails or can't be attempted (no AWS credentials/profile available) → note it and proceed with the alert's own embedded content, which is the normal/expected evidence source for this integration anyway.
