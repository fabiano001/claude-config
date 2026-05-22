# Known Salesforce error fixes

This table maps `errorCode` + signal to the automated fix path. When you see an error not listed here, **HALT** with `UNKNOWN_ERROR_CLASS` — don't guess.

Source for the live behavior: `functions/src/utils/salesforce.ts` (errorCode parsing) and `functions/src/utils/transformAppSalesforce.ts` (field mapping).

## Quick reference table

This table is the authoritative source for what the skill does on each error class. **The same action runs in both `interactive` and `auto` modes — the skill does not ask the operator for permission to apply a documented fix.** Interactive mode only asks the operator on genuinely unknown situations (not in this table).

The `auto_safe` column is documentation about *what kind of action* runs (whether a Firestore write is involved), not a gate on whether to ask. It matters when reviewing audit logs.

| Error class | `auto_safe` | Action (both modes) |
|---|---|---|
| `FIELD_INTEGRITY_EXCEPTION` on `Birthdate` | false (writes Firestore) | PROCEED — patch DOB using the heuristic (defaults to year 1980 if no signal) |
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` on `Applicant_Employment__c.Number_of_Years__c` ("years must be between 0 and 99") | false (writes Firestore) | PROCEED — patch `borrower.currentEmployer.years` (or coborrower) to the hardcoded value `5` |
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` on `Contact.SSN__c` ("The SSN format must be xxx-xx-xxxx.") | false (writes Firestore) | PROCEED — left-pad `borrower.ssn` (or coborrower) with `0`s to 9 digits, then format as `xxx-xx-xxxx` |
| `FIELD_INTEGRITY_EXCEPTION` on any other field | false | HALT |
| `REQUIRED_FIELD_MISSING` | false | HALT |
| `DUPLICATE_VALUE` | false | HALT |
| Transient SF row/record lock (3 patterns below) | **true** (no write) | PROCEED — no data fix, drive Resubmit |
| `NOT_FOUND` on `MarketingSource` | false | SKIP — close out as test/unknown-source, no Resubmit |
| `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY` | false | HALT |
| `STORAGE_LIMIT_EXCEEDED` / `API_DISABLED_FOR_ORG` / `SERVER_UNAVAILABLE` | false | HALT |
| Any errorCode not in this file | false | HALT |

---

## FIELD_INTEGRITY_EXCEPTION on Birthdate (Borrower or CoBorrower)

`auto_safe: false`. Action: **PROCEED** — patch the malformed DOB using the heuristic in `SKILL.md`.

**Signal:**
```json
{
  "referenceId": "Borrower",            // or "CoBorrower"
  "body": [{
    "errorCode": "FIELD_INTEGRITY_EXCEPTION",
    "fields": ["Birthdate"],
    "message": "Birthdate: invalid date: <...>"
  }],
  "httpStatusCode": 400
}
```

**Root cause:** `borrower.dateOfBirth` (or `coborrower.dateOfBirth`) in the Firestore loan is malformed. `transformAppSalesforce.ts:175` (`formatDate()`) splits on `/` and produces `YYYY-MM-DD` only if the year part has length 4. A truncated input like `"02/16/1"` produces `"1-02-16"`, which Salesforce parses as year 1 AD and rejects.

**Fix (same in both modes):**
1. Read `borrower.dateOfBirth` (or coborrower) from the loan doc.
2. Validate it matches the malformed value in the email envelope (idempotency guard).
3. Split on `/`. Keep month and day. Pick a new year via the heuristic in `SKILL.md` § DOB year heuristic. **The no-signal default is `1980`** in both modes — neither mode asks the operator. If you used the default, surface that in the Slack message (`… → MM/DD/1980, default — no signal`).
4. Write back `MM/DD/YYYY` format.

Schema enforces this format via `dateOfBirthValidator(val, 'locale')` in `functions/src/schema.ts:542` — year must be 4 chars.

## FIELD_CUSTOM_VALIDATION_EXCEPTION on Number_of_Years__c (employment years overflow)

`auto_safe: false`. Action: **PROCEED** — patch `borrower.currentEmployer.years` (or coborrower) to the hardcoded constant `5`. Same action in both modes; no operator prompt.

**Signal:**
```json
{
  "referenceId": "BorrowerEmployment",       // or "CoBorrowerEmployment"
  "body": [{
    "errorCode": "FIELD_CUSTOM_VALIDATION_EXCEPTION",
    "message": "Years must be between 0 and 99"
  }],
  "httpStatusCode": 400
}
```

**Root cause:** The applicant entered a value outside `0–99` (commonly the calendar year, e.g. `2025`) into the "Years at current employer" input. The loan doc carries that value in `borrower.currentEmployer.years` and forwards it to Salesforce as `Applicant_Employment__c.Number_of_Years__c`. A custom validation rule on that field requires `0 ≤ years ≤ 99` and rejects.

The corresponding composite request entry from the email body confirms the source:

```json
{
  "method": "POST",
  "referenceId": "BorrowerEmployment",
  "url": "/services/data/v54.0/sobjects/Applicant_Employment__c/",
  "body": {
    "Number_of_Years__c": 2025,
    "Months__c": 5,
    ...
  }
}
```

**Hardcoded replacement value: `5`.**

Always write the integer `5` regardless of the bad value. Do not interpret the input, do not compute anything from the calendar year, do not consult other loan fields. `5` is a mid-range tenure that always passes the `0–99` validation rule. The Slack message names the original bad value so a reader can audit the change.

**Slack message recipe:**
```
Employment years overflow (<badValue> → 5, hardcoded). Updated in Firestore. Resubmitted. ✅
```

Example:
```
Employment years overflow (2025 → 5, hardcoded). Updated in Firestore. Resubmitted. ✅
```

**Fix (both modes):**
1. Read `borrower.currentEmployer.years` from the loan doc (the email envelope's `loan.borrower.currentEmployer.years` is the same value; confirm against Firestore for idempotency).
2. Validate it matches the bad value from the email envelope (idempotency guard — abort if the Firestore value is already `5`, or if it differs from what the email reports).
3. Write back the integer `5`.
4. Preserve `currentEmployer.months` untouched.

For co-borrower employment overflow, the symmetric path: `referenceId: "CoBorrowerEmployment"`, patch `coborrower.currentEmployer.years` to `5`.

## FIELD_CUSTOM_VALIDATION_EXCEPTION on SSN__c (malformed Social Security Number)

`auto_safe: false`. Action: **PROCEED** — left-pad the Firestore `borrower.ssn` (or `coborrower.ssn`) with leading `0`s to 9 digits, then format as `xxx-xx-xxxx`. Same action in both modes; no operator prompt.

**Signal:**
```json
{
  "referenceId": "Borrower",            // or "CoBorrower"
  "body": [{
    "errorCode": "FIELD_CUSTOM_VALIDATION_EXCEPTION",
    "fields": ["SSN__c"],
    "message": "The SSN format must be xxx-xx-xxxx."
  }],
  "httpStatusCode": 400
}
```

**Root cause:** Salesforce enforces SSN format `xxx-xx-xxxx` (9 digits with dashes) via a custom validation rule on `Contact.SSN__c`. The Firestore `borrower.ssn` (passed through verbatim by `transformAppSalesforce.ts`) is one of:
- Fewer than 9 digits (e.g. `"11554414"` — 8 digits; applicant skipped a key).
- 9 digits but missing dashes (e.g. `"123456789"`).
- Dash-formatted but with the wrong digit count after stripping.

**Normalization rule (deterministic, no operator prompt):**

1. Strip all non-digit characters from `borrower.ssn` → `digits`.
2. If `digits` is empty or the original contained anything other than digits/dashes → HALT (`UNKNOWN_ERROR_CLASS`); can't reconstruct safely.
3. If `digits.length > 9` → HALT; can't safely truncate.
4. If `digits.length < 9` → left-pad with `0`s to length 9 (`digits.padStart(9, '0')`). This is the user-documented rule: *"just fill in missing digits with 0's."* Left-pad mirrors numeric-string convention; the operator accepts that the recovered SSN may be approximate (the wrong digit position can't be inferred from the input). The Slack message names the original bad value so a reader can audit the change.
5. Format the 9-digit string as `<3>-<2>-<4>` (e.g. `"011554414"` → `"011-55-4414"`).
6. Idempotency guard: the script aborts if `borrower.ssn` already matches the formatted target (re-run safe).

**Examples:**

| Firestore `borrower.ssn` (BEFORE) | Stripped digits | Padded | Formatted (AFTER) |
|---|---|---|---|
| `"11554414"` | `"11554414"` (8) | `"011554414"` | `"011-55-4414"` |
| `"5554414"` | `"5554414"` (7) | `"005554414"` | `"005-55-4414"` |
| `"123456789"` | `"123456789"` (9) | `"123456789"` | `"123-45-6789"` |
| `"123-45-6789"` | `"123456789"` (9) | `"123456789"` | `"123-45-6789"` (idempotent — script aborts) |

**Slack message recipe:**
```
SSN format error (<badValue> → <newValue>, leading-0 padded). Updated in Firestore. Resubmitted. ✅
```

Example:
```
SSN format error (11554414 → 011-55-4414, leading-0 padded). Updated in Firestore. Resubmitted. ✅
```

**Fix (both modes):**
1. Read `borrower.ssn` (or `coborrower.ssn` for `referenceId: "CoBorrower"`) from the loan doc.
2. Validate it matches the malformed value from the email envelope (idempotency guard — abort if Firestore already has the formatted target).
3. Apply the normalization above.
4. Write back to Firestore.

For co-borrower SSN format failures, the symmetric path: `referenceId: "CoBorrower"`, patch `coborrower.ssn`.

**Caveat (operator audit):** left-padding chooses one of several plausible reconstructions of a truncated SSN. If a downstream consumer (credit pull, KYC) re-validates the SSN and the loan re-fails, the rebuilt value was wrong; escalate to manual entry from a source-of-truth document (driver's license, applicant call-back).

## FIELD_INTEGRITY_EXCEPTION on other fields

`auto_safe: false`. Action: **HALT** with `UNKNOWN_ERROR_CLASS`.

Each Salesforce field has different validation rules; reconstructing the intended value is rarely safe. The halt log should include:

- The exact `fields` array.
- The full `message` (often hints at the parser error).
- The current value of the field in the Firestore loan.
- The referenceId so the operator knows whether it's Borrower / CoBorrower / Application / Address / etc.

## REQUIRED_FIELD_MISSING

`auto_safe: false`. Action: **HALT**.

Don't guess required values. Include the `fields` array and the referenced sub-object. The operator will need to either patch Firestore with the missing data or roll the loan back to draft.

## DUPLICATE_VALUE

`auto_safe: false`. Action: **HALT**.

Typically a duplicate SSN or Email on the Contact object. Resolving requires either:
- The original SF record was created and orphaned (look it up by SSN/Email in SF) — operator must reuse or merge.
- A genuine duplicate applicant — escalate.

Don't auto-write to Firestore.

## Transient SF row/record lock (UNABLE_TO_LOCK_ROW or Apex-trigger lock)

`auto_safe: **true**`. Action: **PROCEED** — no data fix, drive Resubmit.

**Signals (any one matches):**

1. Direct row lock:
```json
{
  "body": [{ "errorCode": "UNABLE_TO_LOCK_ROW" }],
  "httpStatusCode": 400
}
```

2. Lock surfaced via Apex DML wrap:
```json
{
  "body": [{
    "errorCode": "CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY",
    "message": "...UNABLE_TO_LOCK_ROW..."
  }],
  "httpStatusCode": 400
}
```

3. Lock surfaced from an Apex trigger via `System.QueryException` (no literal `UNABLE_TO_LOCK_ROW` string — same operational pattern):
```json
{
  "body": [{
    "errorCode": "CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY",
    "message": "...System.QueryException: Record Currently Unavailable: The record you are attempting to edit, or one of its related records, is currently being modified by another user. Please try again. ... JobStatusHelper.getJobStatusForUpdate ..."
  }],
  "httpStatusCode": 400
}
```

**Root cause:** Salesforce row/record-level contention. Patterns 1+2 are detected by the production retry loop (`functions/src/utils/salesforce.ts:81-92` substring-matches `UNABLE_TO_LOCK_ROW`) and auto-retried 3× with exponential backoff (8/16/32s). Pattern 3 is the same family of issue surfacing from inside an Apex trigger (e.g. `EmailRequestTriggerHandler` → `JobStatusHelper.getJobStatusForUpdate`) and is **not** caught by the retry detector, so the function fails immediately and emails the operator.

**Fix:**
1. No data change required.
2. **Wait 5 minutes** to let the lock expire — UNLESS the failure email is already older than 5 minutes (read the email `date` header). After ~30 minutes the contention is virtually always gone.
3. Drive the admin Resubmit button.
4. Mandatory GCP log verification (don't claim success on browser console alone — re-failures in this class do happen).
5. If the resubmit lands a *fresh* lock error of any pattern above, in interactive mode the operator can wait 15 minutes and try once more. In auto mode, do NOT auto-retry — HALT with `GCP_VERIFY_FAIL` (the verification step will catch the re-failure). Two consecutive lock failures need SF-admin investigation; there may be a stuck SF job holding the related record.

## INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY

`auto_safe: false`. Action: **HALT**.

Indicates a permission/visibility issue on the Salesforce side — not a data problem. The operator needs SF admin help.

## STORAGE_LIMIT_EXCEEDED / API_DISABLED_FOR_ORG / SERVER_UNAVAILABLE

`auto_safe: false`. Action: **HALT**.

SF-side outages or org-level configuration issues. Resubmitting won't help until the upstream is restored.

## NOT_FOUND on MarketingSource (often a test-loan tell)

`auto_safe: false`. Action: **SKIP** (close out as test/unknown source; do not drive Resubmit; do not patch the source code).

**Signal:**
```json
{
  "referenceId": "MarketingSource",
  "body": [{ "errorCode": "NOT_FOUND", "message": "The requested resource does not exist" }],
  "httpStatusCode": 404
}
```

This is the GET that opens the composite request — `/sobjects/Marketing_Source__c/External_ID__c/<sourceId>?fields=Id` — looking up a `Marketing_Source__c` by the loan's `source` value. A 404 means no such marketing source is provisioned in Salesforce.

**Root cause is one of:**
1. The loan's `source` is a **test/synthetic value** that was never meant to hit prod (most common).
2. A genuinely new portal source code that hasn't been added to Salesforce yet (rare).
3. Source ID was corrupted/transposed on the way in (very rare).

**Known prod source codes** (from `dynamic-app/src/constants.ts` `LEAD_SOURCE`):
| Code | Portal |
|---|---|
| 0 | Trident Funding |
| 101442 | YachtWorld |
| 101458 | BoatTrader |
| 101460 | Boats.com |
| 102565 | (RV portal — confirm before assuming) |

Any other `source` value warrants treating it as untrusted until proven.

**Test-loan smell signals — when present, default to SKIP:**
- `borrower.lastName === "Test"` or contains "test" (case-insensitive)
- `borrower.ssn` is `"111-11-1111"`, `"123-45-6789"`, or all-same-digit
- `borrower.email` doesn't match `firstName`/`lastName`
- `finance.purchasePrice` or `financedAmount` is implausible (>10× `collateral.usedRetailValue`)
- `source` is not in the known-portal table above

Two or more signals = treat as test, do not resubmit. **Both modes SKIP without asking the operator** — the documented action is the action.

**Slack message recipe (when SKIP):**
```
Test loan in prod (<short fingerprint, e.g. Test/111-11-1111/$15M financed, unknown source 301478>). Skipped — not resubmitting. ✅
```

Never auto-patch the `source` code. If a legitimate new source code starts appearing in failures, that's a signal to add the SF-side `Marketing_Source__c` record — not a signal to relax this rule.

## type: "exception"

`auto_safe: false`. Action: **HALT** with `EXCEPTION_TYPE`.

The envelope has no `apiResponse` — the failure happened before the SF call (or while parsing the response). The `exception` field contains the JS stack trace. These are code bugs, not data bugs.
