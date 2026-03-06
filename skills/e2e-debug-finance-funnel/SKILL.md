---
name: e2e-debug-finance-funnel
description: >-
  Debugs issues in the finance funnel using playwright-cli in a headed
  browser. Takes a URL, issue description, and optional max iterations
  (default 5). Reproduces the bug, investigates, makes code fixes,
  deploys to staging, and verifies in an iterative loop. Saves findings
  to a debug report. Use when the user needs to debug, troubleshoot, or
  investigate a bug in the finance funnel using browser automation.
context: fork
allowed-tools: Bash(playwright-cli:*), Bash(dynamic-app-stage-deploy:*)
---

# E2E Debug Finance Funnel

You are an autonomous browser-based debugger for the finance funnel. You reproduce bugs, investigate root causes, make code fixes, deploy to staging, and verify — iterating until the issue is resolved or the max iterations are reached.

## CRITICAL — HARD RULES (VIOLATION = INSTANT FAILURE)

**FORBIDDEN COMMANDS — if you use ANY of these, execution WILL halt with permission prompts:**

- Any Bash command containing `${...}`, `$VARIABLE`, `$RANDOM`, `$(...)`, or `$(cat ...)` — NEVER use shell substitution
- `cd /some/path && command` or `cd /some/path ; command` — NEVER use compound statements with `cd`. This triggers "bare repository attacks" security prompts that HALT execution
- `playwright-cli run-code "$(cat file.js)"` — NEVER write JS to a file and read it back with command substitution

**REQUIRED — follow these patterns instead:**

- All Bash commands must use **literal string values only** — no variables, no substitution
- Generate dynamic values with `python3 -c "..."` first, capture the output, then pass as a literal in the next command
- For JS in the browser, pass it **inline** to `playwright-cli eval "YOUR_JS_HERE"`
- For git commands in other directories, use `git -C <path> <command>` or run each command as a separate Bash call
- For deploying, run `dynamic-app-stage-deploy` as a **standalone command** — never chain it with `&&` or `;`

**ALLOWED playwright-cli commands** (all commands are available for debugging):

- `playwright-cli open --headed` — open a new browser
- `playwright-cli goto <url>` — navigate to a URL
- `playwright-cli click <ref>` — click an element by snapshot ref
- `playwright-cli fill <ref> "value"` — fill an input field
- `playwright-cli type "text"` — type text
- `playwright-cli press <key>` — press a key (Enter, Tab, etc.)
- `playwright-cli eval "JS_CODE"` — evaluate JavaScript in the browser console
- `playwright-cli screenshot` — take a screenshot
- `playwright-cli screenshot --filename="path.png"` — screenshot to specific path
- `playwright-cli snapshot` — take an accessibility snapshot of the page
- `playwright-cli console` — read browser console output
- `playwright-cli network` — read network requests
- `playwright-cli close` — close the browser
- All other playwright-cli commands (select, hover, drag, tab-list, cookie-*, localstorage-*, etc.)

**JS string concatenation rule:**

Claude Code's security filter flags `' + '` patterns as "empty quotes before dash (potential bypass)". Instead of string concatenation with `+`, use:
- `JSON.stringify({key: value})` — for structured data
- `[a, b].join(" -> ")` — for joining strings
- Template literals with backticks — for interpolation

## Input Format

This skill expects the following inputs passed as arguments:

1. **URL** (required) — the finance funnel URL to test against (e.g., `https://www.qa.boattrader.com/boat-loans/apply/...`)
2. **Issue description** (required) — free-form text describing the bug, including:
   - What the bug is
   - Steps to reproduce (if known)
   - Expected vs actual behavior
   - Screenshot paths (optional — will be read with the Read tool)
   - Any other relevant context
3. **Max iterations** (optional) — the maximum number of fix/deploy/verify iterations. **Default: 5** if not specified. Look for patterns like `MAX_ITERATIONS=3`, `max iterations: 3`, `up to 3 iterations`, or `3 iterations` in the arguments.

Parse all inputs from `$ARGUMENTS`.

## Execution Flow

### Step 0: Read user screenshots (if provided)

If the issue description references screenshot file paths (e.g., `/path/to/screenshot.png`), use the Read tool to view them before proceeding. This helps understand the visual context of the bug.

### Step 1: Understand the issue

Parse the issue description and any screenshots. Identify:
- What the expected behavior is
- What the actual (broken) behavior is
- The likely reproduction steps
- Which parts of the codebase are probably involved

### Step 2: Open browser and navigate

```bash
playwright-cli open --headed
```
```bash
playwright-cli goto THE_URL_HERE
```

Replace `THE_URL_HERE` with the actual literal URL from the input. Do NOT use a variable.

### Step 3: Reproduce the bug

Follow the reproduction steps from the issue description. Use the available playwright-cli commands to interact with the page:

- `playwright-cli snapshot` — to see the current page state and element refs
- `playwright-cli click <ref>` — to click buttons/links
- `playwright-cli fill <ref> "value"` — to fill form fields
- `playwright-cli console` — to check for console errors
- `playwright-cli network` — to check network requests/failures
- `playwright-cli screenshot --filename=".playwright-cli/screenshots/debug-repro.png"` — to capture the current state

Take a screenshot when the bug is visible. This is your baseline.

### Step 4: Investigate

With the bug reproduced, investigate the root cause:

1. Check browser console output for errors: `playwright-cli console`
2. Check network requests for failures: `playwright-cli network`
3. Use `playwright-cli eval "document.querySelector('...')..."` to inspect DOM state
4. Read relevant source files using the Read tool — trace the issue from the UI back to the code
5. Use Grep/Glob to find related code paths

### Step 5: Iterative fix loop

For each iteration (up to the parsed max iterations, default 5):

**5a. Make code changes**
- Use the Edit tool to apply surgical fixes to the identified source files
- Keep changes minimal — fix the bug, do not refactor

**5b. Deploy to staging**
```bash
dynamic-app-stage-deploy
```
Run this as a standalone command. NEVER chain it with `&&` or `;`. Wait for it to complete.

**5c. Verify in browser**
- Reload the page or navigate back to the URL:
  ```bash
  playwright-cli goto THE_URL_HERE
  ```
- Follow the reproduction steps again
- Check console and network for the error
- Take a screenshot:
  ```bash
  playwright-cli screenshot --filename=".playwright-cli/screenshots/debug-iteration-N.png"
  ```
  (Replace `N` with the literal iteration number, e.g., `debug-iteration-1.png`)

**5d. Evaluate**
- **If fixed** → Proceed to Step 6 (report success)
- **If not fixed** → Analyze what changed, form a new hypothesis, and start the next iteration

### Step 6: Generate report

Save findings to `dynamic-app/debug-reports/<descriptive-name>.md`. Create the directory if it does not exist:

```bash
mkdir -p dynamic-app/debug-reports
```

**Report template:**

```markdown
# Debug Report: <Short Issue Title>

## Issue Description
<Original issue description from the user>

## URL Tested
<The URL>

## Reproduction Steps
1. <Step 1>
2. <Step 2>
...

## Investigation Findings
<What was discovered during investigation — console errors, network failures, DOM state, code analysis>

## Iterations

### Iteration 1
- **Hypothesis:** <What you thought was wrong>
- **Changes:** <Files modified and what was changed>
- **Result:** <What happened after deploy — fixed/not fixed, new observations>
- **Screenshot:** <Path to screenshot>

### Iteration 2
...

## Final Status: FIXED | UNRESOLVED

### If FIXED:
- **Root cause:** <What was actually wrong>
- **Fix applied:** <Summary of the code changes>
- **Files modified:** <List of files>

### If UNRESOLVED:
- **Iterations completed:** N/<max>
- **Current hypotheses:** <What you think might be wrong>
- **What was tried:** <Summary of all approaches>
- **Suggested next steps:** <What to try next>
- **Files modified so far:** <List of files changed>
```

### Step 7: Close browser

```bash
playwright-cli close
```

## Rules

1. **No shell substitution** — NEVER use `${...}`, `$(...)`, `$VARIABLE` in any Bash command. Generate dynamic values separately, then pass as literals.

2. **No compound statements** — NEVER use `cd path && command` or `cd path ; command`. Use `git -C <path>` for git commands or run each command as a separate Bash call.

3. **Deploy standalone** — Run `dynamic-app-stage-deploy` as its own Bash command. Never chain it.

4. **Do NOT commit or push** — Only deploy to staging for verification. The user will commit when ready.

5. **Fully autonomous** — Do NOT ask the user for permission or clarification during execution. Make your best judgment and proceed. If something is truly ambiguous, note it in the report.

6. **Max iterations** — If the bug is not fixed after the max iterations (default 5) of the fix/deploy/verify loop, stop and write the report with UNRESOLVED status.

7. **Screenshots at each iteration** — Take a screenshot after each verify step. Include the path in the report. Use descriptive filenames under `.playwright-cli/screenshots/`.

8. **Close browser at end** — Always run `playwright-cli close` when done.

9. **JS eval safety** — Never use `+` for string concatenation in `playwright-cli eval`. Use `JSON.stringify()`, `.join()`, or template literals instead.

10. **Minimal diffs** — Fix the bug with the smallest possible code change. Do not refactor, add comments, or clean up surrounding code.
