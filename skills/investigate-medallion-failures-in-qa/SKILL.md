---
name: investigate-medallion-failures-in-qa
description: Investigates recent unprocessed Medallion partner-lender submission-failure alerts (message title `*Partner Loan Submission Failure*`, from `lambda-node-trident-partner-lender`'s `_buildFailureAlert`) posted to the QA Slack channel #finance-qa-alerts — the exact QA counterpart of `investigate-medallion-failures`, which covers the prod channel #finance-prod-alerts instead. Scans up to the last 7 days of channel history, identifies Medallion alerts by that message title alone (not by Lender Code, which legitimately reads N/A on poller-level failures), and treats an alert as unprocessed only when it has NEITHER an `:acknowledged:` emoji reaction NOR any thread replies. Groups duplicate/near-duplicate unprocessed alerts (same Error Type + Error Message) into one finding with an occurrence count and time range before reporting — QA traffic has been observed firing the identical alert every 1–2 minutes for hours during an ongoing incident, and reporting each occurrence separately would be pure noise. For each distinct finding it reads the failure type, Error Message, Error Details, and (800-char-truncated) Stack Trace already embedded in the alert itself and classifies the root cause against known patterns (a Salesforce-field-mapping gap, a Salesforce auth/permission error, a generic/opaque HTTP failure, an infra/config problem, or a systemic poller-level failure). Read-only and report-only — it never posts to Slack, reacts with an emoji, or changes code. Use when the operator asks to investigate/triage Medallion failures in QA, check on QA partner-lender submission alerts, or review unacknowledged "Partner Loan Submission Failure" alerts in #finance-qa-alerts. Does NOT touch the prod channel (that's `investigate-medallion-failures`) and does NOT post anything to Slack itself.
---

# Investigate Medallion Failures (QA)

The QA counterpart of `investigate-medallion-failures` — same Medallion partner-lender integration, same alert format, same root-cause taxonomy, but reading `#finance-qa-alerts` instead of `#finance-prod-alerts`, plus one QA-specific adaptation: **duplicate collapsing** (Step 4), since QA has been observed producing the same alert on a tight loop during an ongoing incident (verified live, 2026-08-31 — see **Fixed configuration**). Purely read/report — no Slack mutation, no code changes.

## Fixed configuration

- **Channel:** `#finance-qa-alerts` — `channel_id: C0B5S55SPHS`. Re-discover via `mcp__claude_ai_Slack__slack_search_channels` if this ever 404s.
- **Lookback window:** 7 days (fixed — not an argument).
- **"Ack" reaction name:** `acknowledged` — same convention as the prod skill. An `eyes` reaction does NOT count as acknowledged.
- **How to tell a Medallion alert apart from everything else in this channel:** its message text starts with the bold heading `*Partner Loan Submission Failure* - Salesforce Loan ID: <id>`. In this QA channel the alert's Slack bot displays as **"Partner Loan Submission Monitoring"** (a different app/bot id than the prod channel's shared "Trident Monitoring" identity, confirmed live) — a cosmetic difference, not something to filter on either way. **Filter on message text, never on the author**, same rule as the prod skill.
- **Lender scope:** same as prod — the `*Partner Loan Submission Failure*` title alone is the reliable signal. Do NOT require `Lender Code == MEDALLION`; a poller-level failure's `Lender Code` legitimately reads `N/A`. Treat `Lender Code` as informational, flagging (not dropping) anything other than `MEDALLION`/`N/A`.
- **Known noisy pattern, observed live in this channel (2026-08-31):** `Poller — run failed before any row could be processed` with Error Message `INSUFFICIENT_ACCESS: SOAP API login() requires the Use Any API Auth user permission` fired repeatedly, minutes apart, for an extended stretch — tied to a live Salesforce org/credential migration (`Boatsgroup--skyloanqa` → `boatsgroup--qa`) discussed in the same channel. This is exactly the shape Step 4's dedup exists for: one systemic root cause, not one distinct issue per message.

## Workflow

### Step 1 — Fetch the last 7 days of channel history

1. Compute the lookback boundary: `date -v-7d +%s` (standalone Bash, macOS/BSD `date`) → `OLDEST_TS`.
2. `mcp__claude_ai_Slack__slack_read_channel` with `channel_id: C0B5S55SPHS`, `oldest: <OLDEST_TS>`, `limit: 100`, `response_format: detailed` (needed for the reaction/thread-reply counts used in Step 3).
3. Page with `cursor` if `pagination_info` indicates more messages, until the full 7-day window is covered. **This channel can be high-volume during an incident** (observed: an identical alert every 1–2 minutes for hours) — don't stop paging early just because a page looks repetitive; Step 4 collapses the repetition, but only after all of it has actually been fetched.

### Step 2 — Keep only Medallion alerts

Keep a message only if its text starts with `*Partner Loan Submission Failure*`. Discard everything else without further inspection. Do NOT additionally require `Lender Code == MEDALLION` — see **Fixed configuration**.

### Step 3 — Keep only unprocessed alerts

Unprocessed = **no `acknowledged` reaction AND no thread replies** (either signal alone counts as already handled). Discard everything that fails this check. If nothing survives, stop and report plainly: `No unprocessed Medallion alerts in the last 7 days.`

### Step 4 — Collapse duplicate/near-duplicate alerts (QA-specific — not in the prod skill)

Group the surviving alerts by **(Error Type + Error Message)** — treat two alerts as the same finding if both match exactly, regardless of timestamp or Salesforce Application ID (poller-level failures carry no per-loan identity anyway). For each group, keep:
- The **first** and **last** timestamp in the group (the incident's observed span).
- The **occurrence count**.
- One representative alert's full detail (Error Details, Stack Trace) for Step 6's classification — they're identical across the group by construction.

Proceed to Steps 5–7 once per **group**, not once per raw message. A group of 200 identical poller failures becomes exactly one finding in the final report, not 200.

### Step 5 — Extract the alert's own details

Medallion's alert format (`_buildFailureAlert`) always renders fields in this fixed order — pull out whichever are present, from the group's representative alert (Step 4):
- **Salesforce Application ID** (often `n/a` for poller-level failures)
- **Lender Code** (usually `MEDALLION`; `N/A` on poller-level failures — record it, don't require it)
- **Error Type** — a `failureType` label. Known taxonomy: `Type 1 — Save_Submit failed`, `Type 2 — SF record create failed`, `REFRESH_LAMBDA_ARN not configured...`, `Type 3 — Refresh failed`, `Poller — 3 consecutive refresh failures`, `Poller — run failed before any row could be processed`. If it doesn't match, don't force-fit it — note it as unrecognized and classify from Error Message/Details alone.
- **Lender Application ID** — Medallion's GUID; often `n/a`.
- **Salesforce Lender Submission ID** — conditional.
- **Go to Resubmit** link — points at the QA admin page (`www.qa.boattrader.com/...`); the operator's own fix mechanism, not something this skill acts on.
- **Error Message** — code block, `error.message`.
- **Error Details** — conditional, often a validation-error list.
- **Stack Trace** — truncated to 800 characters. Don't assume it's complete.

### Step 6 — Root-cause investigation has the same hard ceiling as prod

**The raw SOAP envelope Medallion actually received is never logged or persisted anywhere in this integration**, there's **no persisted failure record** beyond the Slack message, and **no environment tag** distinguishing prod from QA in the alert content itself (you already know it's QA because you're reading this channel). So the Slack message's own Error Message/Error Details/Stack Trace is normally the complete available evidence.

**Optional, best-effort deeper dig:** CloudWatch for this Lambda stack (note: **QA and prod are separate Lambda deployments/log groups** — don't pull the prod log group by habit). No established convention in this codebase yet for AWS CloudWatch queries from a skill — if attempted, confirm the QA function/log-group name and AWS profile first, and label anything found this way as supplementary.

### Step 7 — Determine root cause

Classify against the same known patterns as the prod skill:

- **Salesforce-field-mapping gap** — Error Details names a specific missing/invalid field (e.g. "Down payment value is required"). Very likely a mapping gap in `adapters/medallion.js`'s `buildApplicantBlock`, not a data-entry or Medallion-side problem.
- **Salesforce auth/permission error** (e.g. `INSUFFICIENT_ACCESS: SOAP API login() requires the Use Any API Auth user permission`, `INVALID_LOGIN`, expired session) — a Salesforce credential/permission-set problem in the SSM-stored QA config (`/configd/trident/salesforce/*`), not a code bug. **QA in particular is known to go through org/sandbox migrations** (e.g. `Boatsgroup--skyloanqa` → `boatsgroup--qa`, discussed live in this channel) — if the same error is recurring across a long span, suspect the QA credential/permission config needs updating for whichever org is currently active, and say so plainly.
- **Generic/opaque HTTP failure** (e.g. "Request failed with status code 500" with no Error Details) — check where the Stack Trace originates. Could be transient on Medallion's QA/sandbox endpoint or an unhandled exception client-side.
- **Infra/config failure** (e.g. `REFRESH_LAMBDA_ARN not configured`) — a deployment/SSM configuration problem for the QA stack specifically.
- **Poller-level systemic failure** (`Poller — 3 consecutive refresh failures` / `Poller — run failed before any row could be processed`) — not a single-loan issue; the 30-minute poller is failing broadly for QA. If Step 4 collapsed a large, long-running group of these, say so explicitly — a poller failure recurring for hours is itself a signal worth calling out, separate from whatever the underlying error is.
- **`Type 3 — Refresh failed`** — note whether it looks like a Medallion `Get()` call failure or a Salesforce write failure, if determinable; say so if it isn't.
- **Inconclusive** — say exactly what's missing rather than forcing a fit.

### Step 8 — Produce the report

One block per distinct finding (i.e. per group from Step 4, newest-first by last-occurrence timestamp), even if only one:

```markdown
### <Error Type> — <occurrence count>× between <first timestamp> and <last timestamp>
**Root cause:** <2–4 sentences, cites the specific field/error/stage from the representative alert>
**Suggested Slack comment:** "<short, specific, human-toned reply — one or two sentences, written for the whole group if it's a recurring incident (e.g. "Looks like N repeated poller failures from the same cause — ...") rather than as if it were a single one-off>"
```

Print this directly in your response — this skill does not write a file or publish an artifact on its own.

## What this skill never does

- Never posts to Slack, never adds a reaction.
- Never touches the prod channel (`#finance-prod-alerts`) — that's `investigate-medallion-failures`.
- Never calls the actual Medallion API, never resubmits a loan, and never modifies any code — the "Go to Resubmit" link is the operator's own fix path.

## Failure modes

- Channel fetch fails → report the verbatim error, stop.
- Zero Medallion alerts in the window at all → `No Medallion alerts in the last 7 days.`
- Medallion alerts exist but all are already acknowledged/commented → `<N> Medallion alert(s) in the last 7 days, all already handled — nothing to investigate.`
- Error Type doesn't match the known taxonomy → don't force a label; classify from Error Message/Details alone and note the unrecognized type.
- Error Details/Stack Trace insufficient to classify → mark inconclusive, state exactly what's missing.
- A dedup group (Step 4) mixes alerts that are only *superficially* similar (e.g. same Error Type but a materially different Error Message) → don't collapse them; the exact-match rule in Step 4 is deliberately strict for this reason, but double-check before reporting a large group as one finding.
- An optional CloudWatch dig (Step 6) fails or can't be attempted → note it and proceed with the alert's own embedded content.
