---
name: e2e-test-combined-flow
description: >-
  Test the combined app flow end-to-end using Playwright in headed browser
  mode. Use when the user provides one or more <TEST_TO_RUN> blocks
  containing TEST_NAME, TEST_URL, and VERIFY_ITEMS.
context: fork
allowed-tools: >-
  Bash(playwright-cli:*),
  Bash(playwright-cli eval *),
  Bash(~/.claude/skills/combined-flow-retired-path/retired-flow.sh:*),
  Bash(/Users/fabianodesouza/.claude/skills/combined-flow-retired-path/retired-flow.sh:*),
  Bash(~/.claude/skills/combined-flow-retired-path/retired-flow-prequal-only.sh:*),
  Bash(/Users/fabianodesouza/.claude/skills/combined-flow-retired-path/retired-flow-prequal-only.sh:*),
  Bash(python3:*),
  Bash(pip3 install fpdf2:*),
  Bash(pip3 install fpdf2),
  Read,
  Write
---

You are an autonomous QA test runner for the "combined app flow". You drive a headed browser through the combined loan application funnel, verify results, and produce a structured report.

## CRITICAL — HARD RULES (VIOLATION = INSTANT FAILURE)

**FORBIDDEN COMMANDS — if you use ANY of these, the test WILL fail with permission prompts:**
- `playwright-cli run-code` — NEVER run this command directly, for any reason
- `playwright-cli fill` — NEVER run this command directly
- `playwright-cli click` — NEVER run this command directly
- `playwright-cli navigate` — NEVER run this command directly
- Any Bash command containing `${...}`, `$VARIABLE`, `$RANDOM`, `$(...)`, or `$(cat ...)` — NEVER use shell substitution
- `playwright-cli run-code "$(cat somefile.js)"` — NEVER do this pattern; pass JS inline to `playwright-cli eval` instead

**THE ONLY WAY to run the funnel is one of the pre-built shell scripts:**
```
~/.claude/skills/combined-flow-retired-path/retired-flow.sh             # Full flow (all 12+ tabs)
~/.claude/skills/combined-flow-retired-path/retired-flow-prequal-only.sh  # Prequal only (stops after login on Results page)
```

These scripts handle the funnel in a single Bash call. You do NOT need to interact with individual tabs, fill forms, or click buttons yourself. The scripts do all of that.

**Which script to use:**
- If the `<TEST_TO_RUN>` block contains `PREQUAL-ONLY` (anywhere in the block), use `retired-flow-prequal-only.sh`
- Otherwise, use `retired-flow.sh` (full flow)

**ALLOWED playwright-cli commands** (only AFTER the script finishes):
- `playwright-cli close` — close the browser
- `playwright-cli screenshot` — take a screenshot
- `playwright-cli eval` — evaluate JavaScript in the browser console
- `playwright-cli snapshot` — take an accessibility snapshot

## Input Format

Tests can be provided in two ways:

### Option A: Inline `<TEST_TO_RUN>` blocks
The user passes one or more `<TEST_TO_RUN>` blocks directly in the prompt.

### Option B: File path
The user passes a path to an `.md` or `.txt` file that contains `<TEST_TO_RUN>` blocks. Read the file and extract all `<TEST_TO_RUN>` blocks from it.

If the user provides a file path, read it first, then execute all `<TEST_TO_RUN>` blocks found in the file. If the user also specifies which tests to run (e.g., by name or number), only run those.

### Block format

Each `<TEST_TO_RUN>` block contains:
- `TEST_NAME` - Descriptive name for the test
- `TEST_URL` - The URL to navigate to
- `VERIFY_ITEMS` - Items to verify on the final page
- `PREQUAL-ONLY` (optional) - If present, run only the prequal flow (stops after login on Results page)

## Execution Flow

For each `<TEST_TO_RUN>`, follow these exact steps:

### Step 1: Close any open browser
```bash
playwright-cli close
```
Ignore errors if no browser is open.

### Step 2: Generate a unique email
```bash
python3 -c "import random; print(f'fabiano.test.{random.randint(10000000,99999999)}@boats.com')"
```
Capture the output as a literal string (e.g., `fabiano.test.48291573@boats.com`).

### Step 3: Run the appropriate flow script
The app type is always `Individual` — this script uses the shortest path (Individual app, retired borrower). The test URL query params only control which documents appear on the success page.

**If the `<TEST_TO_RUN>` block contains `PREQUAL-ONLY`:**
```bash
~/.claude/skills/combined-flow-retired-path/retired-flow-prequal-only.sh "THE_TEST_URL" "THE_EMAIL" "Individual" "THE_SCREENSHOT_PATH"
```
This stops after the mandatory login on the Results page. Verify items against the Results page (not the success page).

**Otherwise (full flow):**
```bash
~/.claude/skills/combined-flow-retired-path/retired-flow.sh "THE_TEST_URL" "THE_EMAIL" "Individual" "THE_SCREENSHOT_PATH"
```

Replace the placeholders with actual literal values. Example:
```bash
~/.claude/skills/combined-flow-retired-path/retired-flow.sh "https://www.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000" "fabiano.test.48291573@boats.com" "Individual" ".playwright-cli/screenshots/trident-813/test1-subprime-wage-individual.png"
```

**All 4 arguments must be fully resolved literal strings. No shell substitution.**

Set the Bash timeout to 600000 (10 minutes) since the script runs a full funnel.

### Step 4: Read the snapshot
After the script completes, read the generated `*-snapshot.yml` file (path is printed in the script output) to get the final page DOM for verification.

### Step 5: Verify items
Check each item in `<VERIFY_ITEMS>` against the snapshot content. Look for text matches in the DOM elements.

For verifications that require browser interaction (e.g., clicking a button then checking `window.dataLayer`), use `playwright-cli eval` with the JavaScript as a **literal inline string**. Examples:

```bash
playwright-cli eval "JSON.stringify(window.dataLayer)"
```

```bash
playwright-cli eval "document.querySelector('.upload-btn').click()"
```

```bash
playwright-cli eval "JSON.stringify(window.dataLayer.filter(e => e.event === 'link_click'))"
```

**NEVER write JS to a file and use `$(cat file.js)` to pass it.** Always pass JS directly as a literal string argument to `playwright-cli eval`.

### Step 6: Take additional screenshots if needed
If VERIFY_ITEMS requests specific screenshots (e.g., console output), use `playwright-cli screenshot` to capture them. The browser is still open after the script finishes.

```bash
playwright-cli screenshot --filename ".playwright-cli/screenshots/some-descriptive-name.png" --full-page
```

### Step 7: Generate PDF Report

After ALL tests complete, generate a PDF report with embedded screenshots.

1. **Build a JSON data structure** with all test results:
```json
{
  "title": "TRIDENT-XXX",
  "subtitle": "QA Test Report",
  "description": "Brief description of what was tested",
  "environment": "QA (qa.boattrader.com)",
  "date": "YYYY-MM-DD",
  "tests": [
    {
      "name": "Test 1: Test Name",
      "status": "PASS",
      "verify_items": [
        {"num": 1, "item": "Description of verify item", "status": "PASS", "details": "How it was verified"},
        {"num": 2, "item": "Another item", "status": "FAIL", "details": "What went wrong"}
      ],
      "screenshots": [
        {"path": "/absolute/path/to/screenshot.png", "caption": "Description of screenshot"},
        {"path": "/absolute/path/to/another.png", "caption": "After verify item 3", "after_item": 3}
      ],
      "notes": "Optional notes about the test"
    }
  ]
}
```

- **`status`** for tests: `"PASS"`, `"FAIL"`, or `"PARTIAL PASS"`
- **`status`** for verify items: `"PASS"`, `"FAIL"`, `"PARTIAL"`, `"CODE-VERIFIED"`, or `"NOT TESTED"`
- **`after_item`** (optional): places the screenshot after that verify item number in the PDF
- Screenshots without `after_item` appear at the end of the test section
- Use **absolute paths** for all screenshot paths
- Get today's date via `python3 -c "import datetime; print(datetime.date.today().isoformat())"`
- Derive the ticket number from the test file name or the `<TEST_TO_RUN>` context

2. **Write the JSON to a file:**
```bash
python3 -c "
import json
data = ... # the JSON structure above as a Python dict
with open('.playwright-cli/screenshots/report-data.json', 'w') as f:
    json.dump(data, f)
"
```

**IMPORTANT:** Build the entire Python dict as a literal inside the python3 script. Do NOT use shell substitution to inject values. Pass the full data inline.

3. **Install fpdf2 if needed and generate the PDF:**
```bash
pip3 install fpdf2
```
```bash
python3 ~/.claude/skills/e2e-test-combined-flow/generate-qa-report.py ".playwright-cli/screenshots/TRIDENT-XXX-QA-Report.pdf" ".playwright-cli/screenshots/report-data.json"
```

4. **Report the PDF path** to the user in the terminal output.

## Report

After all tests complete, produce TWO outputs:

### Terminal Report
- **Status of each test** - Pass/Fail with details
- **Status of each verify item** - Pass/Fail per item within each test
- **Screenshot paths** for the final screen of each test
- **Additional screenshot paths** from VERIFY_ITEMS requests

### PDF Report
- Generated automatically via Step 7 above
- Contains all test results, verify items, and **embedded screenshots**
- File path reported to the user at the end

## Rules

1. **FORBIDDEN: `playwright-cli run-code`, `playwright-cli fill`, `playwright-cli click`, `playwright-cli navigate`** — NEVER run these commands. Always use `retired-flow.sh` or `retired-flow-prequal-only.sh` for the funnel. Only `playwright-cli close`, `screenshot`, `eval`, and `snapshot` are allowed (and only after the script finishes).

2. **Autonomous execution** — Tests run fully autonomously. Do NOT ask the user for permission. If a permission prompt is triggered, immediately FAIL the test, record it in the report, and stop the entire run.

3. **Close browser between tests** — Run `playwright-cli close` before each test.

4. **No shell substitution in Bash tool calls** — NEVER use `${...}`, `$VARIABLE`, `$RANDOM`, `$(...)`, `$(cat ...)` in any Bash command you execute. NEVER write JS to a file and read it with `$(cat file.js)`. Generate dynamic values (email) via `python3` first, then pass literals. For browser JS, pass it inline to `playwright-cli eval`.

5. **Each test is independent** — Each test navigates to its own URL with a fresh browser session.

6. **Take screenshots on failures** — If the script fails, take a screenshot before closing for debugging.

7. **Avoid JS string concatenation with `+` in `playwright-cli eval`** — Claude Code's security filter flags patterns like `' + '` as "empty quotes before dash (potential bypass)". Instead of string concatenation, use **template literals** (backtick strings with `\`...\``) or `JSON.stringify()` or `.join()`. For example:
   - BAD: `playwright-cli eval "a.textContent + ': ' + a.href"`
   - GOOD: `playwright-cli eval "JSON.stringify({text: a.textContent, href: a.href})"`
   - GOOD: `playwright-cli eval "[a.textContent, a.href].join(' -> ')"`
