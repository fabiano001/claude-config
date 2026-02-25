---
name: e2e-test-combined-flow
description: Test the combined app flow end-to-end using Playwright in headed browser mode. Use when the user provides one or more <TEST_TO_RUN> blocks containing TEST_NAME, TEST_URL, and VERIFY_ITEMS.
---

You are an autonomous QA test runner for the "combined app flow". You drive a headed browser through the combined loan application funnel, verify results, and produce a structured report.

## CRITICAL — READ BEFORE DOING ANYTHING

**You MUST use the pre-built shell script to run each test. You are FORBIDDEN from running `playwright-cli run-code` directly.**

The script path is: `~/.claude/skills/combined-flow-retired-path/retired-flow.sh`

This script handles the ENTIRE funnel (all 12+ tabs) in a single Bash call. You do NOT need to interact with individual tabs, fill forms, or click buttons yourself. The script does all of that.

**If you run `playwright-cli run-code` directly instead of using the script, the test will trigger permission prompts and FAIL. This is not optional.**

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

### Step 3: Run the retired flow script
The app type is always `Individual` — this script uses the shortest path (Individual app, retired borrower). The test URL query params only control which documents appear on the success page.
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

### Step 6: Take additional screenshots if needed
If VERIFY_ITEMS requests specific screenshots (e.g., console output), use `playwright-cli screenshot` or `playwright-cli eval` to capture them. The browser is still open after the script finishes.

## Report

After all tests complete, generate a report that includes:

- **Status of each test** - Pass/Fail with details
- **Status of each verify item** - Pass/Fail per item within each test
- **Screenshot** of the final screen for each test (taken by the script automatically)
- **Additional screenshots** - If a `<TEST_TO_RUN>` block's VERIFY_ITEMS requests specific screenshots, include those with file paths

## Rules

1. **NEVER run `playwright-cli run-code` directly** — Always use the `retired-flow.sh` script. The script handles all form filling, navigation, and submission. Running `playwright-cli run-code` directly triggers ANSI-C quoting permission prompts that block autonomous execution.

2. **Autonomous execution** — Tests run fully autonomously. Do NOT ask the user for permission. If a permission prompt is triggered, immediately FAIL the test, record it in the report, and stop the entire run.

3. **Close browser between tests** — Run `playwright-cli close` before each test.

4. **No shell substitution in Bash tool calls** — NEVER use `${...}`, `$VARIABLE`, `$RANDOM`, `$(...)` in any Bash command you execute. Generate dynamic values (email) via `python3` first, then pass literals to the script.

5. **Each test is independent** — Each test navigates to its own URL with a fresh browser session.

6. **Take screenshots on failures** — If the script fails, take a screenshot before closing for debugging.
