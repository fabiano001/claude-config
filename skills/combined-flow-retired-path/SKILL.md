---
name: combined-flow-retired-path
description: Runs the combined loan application funnel using the "retired flow" (minimum tabs path) via playwright-cli. Use when you need to drive through the full combined funnel to reach the success/final page.
allowed-tools: Bash(~/.claude/skills/combined-flow-retired-path/retired-flow.sh:*), Bash(/Users/fabianodesouza/.claude/skills/combined-flow-retired-path/retired-flow.sh:*)
---

# Combined Flow Retired Path

Pre-built script that drives a headed browser through the entire combined loan application funnel using the "retired flow" (minimum tabs path). This is the fastest path to the success page.

## Usage

```bash
~/.claude/skills/combined-flow-retired-path/retired-flow.sh <test_url> <email> <app_type> <screenshot_path>
```

### Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `test_url` | Combined funnel URL with test params | `https://www.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&autoDocReqTest=true&testBorrowerFico=660` |
| `email` | Pre-generated unique email (must be literal, no shell substitution) | `fabiano.test.48291573@boats.com` |
| `app_type` | `Individual` or `Joint` | `Individual` |
| `screenshot_path` | Full path for the final screenshot PNG | `/path/to/screenshots/test1.png` |

### Example

```bash
# Step 1: Generate a unique email
EMAIL=$(python3 -c "import random; print(f'fabiano.test.{random.randint(10000000,99999999)}@boats.com')")

# Step 2: Run the flow
~/.claude/skills/combined-flow-retired-path/retired-flow.sh \
  "https://www.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000" \
  "$EMAIL" \
  "Individual" \
  "/path/to/screenshots/test1.png"
```

## What the script does

1. Opens a headed browser and navigates to the test URL
2. Fills out the prequal flow (boat info, personal info, SSN)
3. Passes through the soft pull results
4. Fills out the full application (personal details, boat details, loan details, income as Retired)
5. Submits via Credit Authorization
6. Waits for the success page to load
7. Takes a full-page screenshot and a DOM snapshot

## Output

- **Screenshot**: Saved to the `screenshot_path` argument (PNG)
- **Snapshot**: Saved alongside the screenshot as `*-snapshot.yml` (for DOM verification)
- **Console output**: Logs each tab as it progresses

## Important

- Browser MUST be closed before running (`playwright-cli close` if one is open)
- The script uses headed mode — Cloudflare blocks headless browsers
- Each run needs a unique email to avoid validation errors
- The script exits on first error (`set -e`)
