# QA Pass comment template (Jira comment posted after E2E pass)

When the E2E test passes (no `E2ETEST-Report.md` at project root) and the operator did not opt out of E2E during planning, post a structured comment to the Jira ticket via `mcp__atlassian__addCommentToJiraIssue` with `contentFormat: "markdown"`. The title is **always exactly** `# QA Pass (Automated E2E Execution) ✅`.

## Required structure

The comment body MUST include the following sections, in this order. Tailor each section to the ticket — do not include placeholders or generic descriptions where specific facts are available.

```markdown
# QA Pass (Automated E2E Execution) ✅

**PR:** <PR URL from the executor result>
**Branch:** `<head branch name>`
**Stage app version verified live:** `<Dynamic App Version: x.y.z>` (read from page console after deploy)
**Run date:** YYYY-MM-DD

---

## What was tested

<1–3 sentence summary of the funnel/feature exercised, the user persona used, the deliberate path chosen (happy path / no-hit / decline), and how it was driven (manual playwright-cli snapshot-then-act, no bundled scripts).>

**Test URL:**

```
<the URL passed to e2e-test-jira-ticket --url=…>
```

**Deploy command (stage-trident only — production deployment forbidden):**

```
<the command passed to e2e-test-jira-ticket --deploy=…>
```

**Tabs traversed (N steps):**

1. <tab name + key inputs/picks>
2. <tab name + key inputs/picks>
…
N. <final tab — typically the verification milestone>

---

## What was verified

| AC | Verification | Result |
| --- | --- | --- |
| AC 1 | <restate AC 1 verbatim or paraphrased + how it was verified> | ✅ Pass / ❌ Fail / 🔁 Substituted |
| AC 2 | … | … |
…
| AC N | … | … |

For any AC verified by mocked unit/integration tests rather than live E2E (e.g., the "fields missing → omit" branch when the sandbox always populates fields), say so explicitly in the verification cell — do not pretend live E2E covered it.

---

## Evidence — Milestone 1: <event name> on `<tab name>`

<1–2 sentence description of how this evidence was captured (e.g., `playwright-cli eval`, network response inspection, console log capture).>

```json
<the actual captured payload — full JSON for dataLayer events, response body for backend smoke tests, etc.>
```

<1-line summary of what this proves about the AC.>

---

## Evidence — Milestone 2: <event name> on `<tab name>`

<same shape as milestone 1>

```json
<captured payload>
```

<what it proves>

---

## Evidence — Direct <component> smoke test (optional)

<Include this section ONLY if the ticket added a new backend endpoint, function, or API surface that was smoke-tested directly (e.g., curl). Show the command and the response.>

```
$ curl -s "<URL>"

<response body>
```

<what the smoke test confirms about the source-of-truth behavior.>

---

## Code review iterations (all addressed before E2E)

<Table of every Cursor + Codex finding addressed during the autonomous review loop, with the fix commit SHA. Even if there were zero findings, include the table with a single "0 findings" row so the reviewer sees that the review loop ran.>

| # | Severity | Issue | Fix Commit |
| --- | --- | --- | --- |
| 1 | <Low / Medium / High> (<reviewer source: Cursor / Codex>) | <one-line issue summary> | `<short SHA>` |
…

---

## Local artifacts captured (operator workstation)

* `<path>` — <what it is>
* `<path>` — <what it is>
…

---

## Notes

* <Anything surprising or counterintuitive discovered during the run — e.g., a no-hit user that still produced approval data, a deploy gotcha, an iframe quirk.>
* <Architectural confirmations that resulted from this run — e.g., "the X ref design works as intended end-to-end".>
* <Any verification substitutions that occurred — both the originally-agreed approach AND the alternate, with one-line rationale.>

🤖 Verified by automated E2E orchestrator (ticket-driver → e2e-test-jira-ticket skill chain)
```

## Section presence rules

- **Required sections (always include):** Title, run metadata, "What was tested", "What was verified" (AC table), at least one "Evidence — Milestone" section, "Code review iterations", "Local artifacts captured", "Notes", trailing footer.
- **Optional sections:** "Direct smoke test" (only when applicable to the ticket scope), additional "Evidence — Milestone N" sections (one per milestone the operator agreed to in the verify rule).
- **Code review table — zero-findings case:** Still include the table with a single row noting "0 findings — clean review loop". Do not omit the table.
- **Verification substitutions:** If the operator-approved verify rule was substituted mid-execution (per the verification-substitution rule), the Notes section MUST document BOTH the originally-agreed approach AND the alternate used, with a one-line rationale. The "What was verified" AC table cell uses 🔁 Substituted as the result marker.

## Style rules

- Use markdown tables, not bullet lists, for the AC verification matrix and the code-review iterations matrix.
- Use fenced ```json blocks for dataLayer / response-body evidence. Always pretty-print (2-space indent).
- Use fenced plain blocks for shell commands and curl invocations.
- Quote inline values with backticks (event names, tab names, file paths, status names).
- Bold key facts inside cells (e.g., **Both fields propagated correctly**); avoid bold on entire sentences.
- Keep "Notes" focused on what a reviewer needs to know to either approve quickly or know where to look — not a transcript of the run.

## Posting rules

- `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f`
- `issueIdOrKey`: the **resolved** Jira key (strip any `-TEST` / `-TEST-<N>` suffix from the ticket name)
- `contentFormat`: `markdown`
- After posting, confirm to the operator: `"Posted QA Pass comment to <TICKET>: <comment URL from the API response>"`. The URL form is `https://boats-group.atlassian.net/browse/<TICKET>?focusedCommentId=<id>`.
- The operator can reference an example of a well-formatted QA Pass comment: TRIDENT-879 comment id `390021` (posted 2026-05-08).
