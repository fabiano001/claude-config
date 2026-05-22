# Slack message recipe

After resolving a Salesforce-submission failure, output a one-line message in this format for the user to copy/paste into Slack:

```
<Error>. <Fix method>. ✅
```

## Rules

- **Name the field** so a co-worker scanning the channel can diagnose without opening Firestore. Use the schema name from the loan doc, not the Salesforce field name (i.e. `borrower DOB`, not `Birthdate`).
- **Show the before → after** when the value-change is short enough to fit. For long values (addresses, names) just say "corrected".
- **Keep it terse** — Fabiano prefers concise. One sentence per part.
- **End with the green check** `✅` to signal closed/done.
- **Don't include the loan id** — Slack threads have separate identifiers; the channel context is "Salesforce failures" so the loan id is just noise.

## Examples by error class

### Malformed DOB
```
Malformed borrower DOB (02/16/1 → 02/16/1965). Updated in Firestore. Resubmitted. ✅
```

### Malformed CoBorrower DOB
```
Malformed coborrower DOB. Updated in Firestore. Resubmitted. ✅
```

### Transient row lock
```
SF row lock (UNABLE_TO_LOCK_ROW). Waited 5min, resubmitted. ✅
```

### Other FIELD_INTEGRITY_EXCEPTION (manual operator fix before the skill resubmitted)
```
Bad mailing-address state code. Corrected in Firestore. Resubmitted. ✅
```

### Intentional skip — test loan in prod (no resubmit)

When the loan envelope trips the test-loan smell signals in `known-fixes.md` and the operator chooses **Skip**, that is still a closed-out action — the team should see it so nobody else picks it up. Use the same recipe shape with the decision in place of a fix:

```
<Classification>. Skipped — not resubmitting. ✅
```

Examples:
```
Test loan in prod (Test/111-11-1111/$15M financed, unknown source 301478). Skipped — not resubmitting. ✅
```
```
Test loan in prod (lastName "Test", all-1s SSN). Skipped — not resubmitting. ✅
```

The `✅` still applies — the green check signals "the operator has handled this," not "Salesforce now has the record."

## When to NOT post the message

Distinguish **operator-decided skip** (still post a message) from **skill-halted-due-to-uncertainty** (no message). The green check stands for "this is closed out," so it's safe to use when the operator made an explicit call — even "skip and leave alone." It is **not** safe when the skill bailed because it couldn't classify the error or verify success.

Suppress the Slack message when:
- GCP log verification didn't return `SubmitApp:SUCCESS` after a resubmit attempt.
- A new failure email lands in the verify window.
- The error class isn't in `known-fixes.md` AND the operator hasn't chosen a path.
- Anything else where the team should investigate before considering it closed.

In those cases, the report's third section should read:

```markdown
## Slack Message for <loan-id> Resubmission Fix
(none — verification did not pass; manual investigation needed)
```

In **auto mode**, suppression applies to the auto-post (Step 9b) too — do NOT post a Slack message in `#finance-prod-alerts` for any of the suppression conditions above. The team's "go investigate" signal is the absence of a `✅` reply on the alert thread.

## Delivery channel and threading (auto mode — Step 9b)

In auto mode, the skill auto-posts the resolution message to `#finance-prod-alerts` as a **threaded reply** to the original alert (the integration-posted message that announced the loan-submission failure). Threading keeps every status update tied to its alert so:
- The channel feed stays clean — a single thread per failure, regardless of how many recovery attempts it took.
- Reviewers can scan top-level alerts to see which ones are open vs closed (closed = has a `✅` reply in-thread).
- The original alert's loan id is the threading anchor; the reply body therefore doesn't need to repeat the loan id.

**Discovery logic (matches the original alert to thread under):**
1. Read recent messages in `#finance-prod-alerts` via `mcp__claude_ai_Slack__slack_read_channel` (limit 50, newest first).
2. Scan from newest to oldest for the FIRST message whose `text` contains the loan id.
3. Use that message's `ts` as `thread_ts` for `slack_send_message`.

**Fallback when no alert is found** (e.g., the integration didn't post one, or the alert is older than the scan window): post the message top-level in the channel — no `thread_ts`. Print a one-line terminal warning so the operator knows the threading fell through. This is rare but not a failure of the skill.

In **interactive mode** the skill prints the copy-paste message to the terminal so the operator can post it themselves (in case they want to edit, reply to a different thread, add an `@`-mention, etc.). The discovery logic above does not run in interactive mode.
