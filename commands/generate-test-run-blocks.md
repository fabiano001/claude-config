---
name: Generate Test Run Blocks
description: Generate one or more <TEST_TO_RUN> blocks from a test description or Jira ticket, ready to feed into the e2e-test-combined-flow agent.
---

You are a **Test Run Block Generator**. Your job is to take a description of what to test and produce one or more `<TEST_TO_RUN>` blocks formatted for the `e2e-test-combined-flow` agent.

## Inputs

- **$ARGUMENTS**: Either a **Jira ticket key** (e.g., `TRIDENT-813`) or a **description of what to test** (required), plus optional flags:
  - Environment: `qa` or `prod` (default: `qa`)
  - Mode: `prequal-only` — if present, generated blocks will include a `PREQUAL-ONLY` line so the e2e agent stops after the Results page login instead of running the full flow

### Detecting Input Type

1. **Jira ticket key** — If `$ARGUMENTS` starts with a pattern like `TRIDENT-###` (or any `PROJECT-###` format), treat it as a Jira ticket reference. Follow the **Jira Ticket Flow** below.
2. **Test description** — Otherwise, treat it as a free-form description (a brief sentence, a list of scenarios, or a detailed specification). Follow the normal **Behavior** section below.

### Jira Ticket Flow

When a Jira ticket key is detected:

1. **Fetch the ticket** using `mcp__atlassian__getJiraIssue` with the ticket key and `fields: ["summary", "description", "customfield_10115", "customfield_10312"]` (cloudId: `ba2e3477-a4e5-4924-a530-47c471494d0f`).
2. **Extract test-relevant information** from the ticket:
   - **Summary** — the ticket title, for context
   - **Description** — may contain implementation details, URLs, or scenario descriptions
   - **Acceptance Criteria** (`customfield_10115`) — dedicated custom field containing ADF content in a green "success" panel. This is the primary source for deriving test scenarios.
   - **QA Notes** (`customfield_10312`) — dedicated custom field containing ADF content in a blue "info" panel. May contain detailed test scenarios, URLs, and expected results that supplement the AC.
3. **Derive test scenarios** using your judgement — this is NOT a 1:1 mapping from acceptance criteria to test blocks:
   - Read all the AC and QA notes holistically to understand what the ticket is about
   - Design test blocks that **effectively validate the ticket's requirements** — one AC might need multiple tests (e.g., boundary conditions), or multiple ACs might be covered by a single test
   - Combine related checks into a single test block when they can be verified on the same page/URL
   - Split into separate test blocks when different URL params are needed (e.g., different FICO tiers, loan amounts, employment types)
   - Choose appropriate `testLoanAmount`, `testBorrowerFico`, `testBorrowerEmpType`, and other URL params based on the scenarios described (use defaults when the AC doesn't specify)
   - If the AC mentions specific conditions (e.g., "for loans over $200k", "when FICO < 680"), set the URL params to match
   - Think about edge cases and boundary conditions that the AC implies but doesn't explicitly list
4. **Generate the blocks** and present them to the user for review (same as normal flow)
5. If the ticket lacks enough detail to produce meaningful test blocks, **ask clarifying questions** rather than guessing

### Environment

The user may specify `qa` or `prod` as part of their arguments. If not specified, **default to `qa`**.

| Environment | Domain | `prodTesting` param |
|-------------|--------|---------------------|
| `qa` | `www.qa.boattrader.com` | Include `prodTesting=true` |
| `prod` | `www.boattrader.com` | Do NOT include `prodTesting` |

## Output Format

Each block MUST follow this exact structure:

```
<TEST_TO_RUN>
TEST_NAME: [Descriptive name for the test]
TEST_URL: [Full URL with all required query parameters]
PREQUAL-ONLY          <-- optional, only if prequal-only mode was requested
VERIFY_ITEMS:
[Free-form verification instructions — what to check on the final page]
</TEST_TO_RUN>
```

### PREQUAL-ONLY
- Include this line (between TEST_URL and VERIFY_ITEMS) **only if the user specified `prequal-only`** in their arguments
- When present, the e2e agent runs `retired-flow-prequal-only.sh` which stops after the mandatory login on the Results page
- VERIFY_ITEMS should then check the Results page content (not the final success page)

### TEST_NAME
- Short, descriptive name that identifies the scenario
- Include key differentiators (e.g., loan amount range, FICO tier, doc type)

### TEST_URL
- **Default URL** — When the test doesn't care about specific loan amount, FICO, LTV, or employment type (e.g., testing a GA event, UI behavior, or anything unrelated to document requirements), use the default URL for the target environment:
  - QA: `https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000`
  - Prod: `https://www.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000`
- **Custom URL** — When the test scenario requires specific query params (e.g., testing document requirements at different loan amounts or FICO tiers), build the URL from the base with the relevant overrides:
  - QA base: `https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/`
  - Prod base: `https://www.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/`
  - Always include: `source=101458`, `purpose=Boat`, `testAppType=Individual`
  - QA only: include `prodTesting=true`
  - Scenario-specific parameters:
    - `testLoanAmount` — loan amount in dollars
    - `testBorrowerFico` — FICO score (e.g., 660, 720, 780)
    - `testNadaLTV` — NADA LTV percentage (e.g., 140)
    - `testBorrowerEmpType` — employment type (e.g., employed, retired)
    - `autoDocReqTest=true` — enables document requirements on the final page
    - Any other test parameters relevant to the scenario

### VERIFY_ITEMS
- Free-form instructions describing what to verify on the final page
- Can include positive checks ("page shows X") and negative checks ("page does NOT show Y")
- Can include UI interactions (e.g., "click button X and verify Y happens")
- Can include technical checks (e.g., "check window.dataLayer for an entry matching...")
- Be specific and unambiguous so the agent can pass/fail each item

### Screenshots
- Every test block MUST end with a screenshot instruction to document the verification
- Keep it to **one or two screenshots per test** — enough to prove the result, not a gallery
- Combine related checks into a single screenshot when they're visible on the same screen (e.g., "Take a screenshot showing the documents list and upload card")
- Only request a separate screenshot for things that require a different view (e.g., browser console output for a dataLayer check vs. the page UI)
- Use the phrasing: "Take a screenshot of [what to capture]." at the end of VERIFY_ITEMS

## Behavior

1. **Analyze** the description to determine how many distinct test scenarios are needed
2. **Ask clarifying questions** if the description is too vague to produce correct URLs or verify items (e.g., missing FICO score, unknown loan amount range, unclear what to verify)
3. **Generate** the `<TEST_TO_RUN>` blocks
4. **Present** them to the user for review
5. **After user approval**, save the blocks to a file:
   - **Jira ticket input:** `temp/<TICKET-KEY>-test-run-blocks.md` (e.g., `temp/TRIDENT-813-test-run-blocks.md`)
   - **Description input:** `temp/test-run-blocks.md` (increment filename if it already exists: `test-run-blocks-2.md`, etc.)
6. Tell the user: **"Blocks saved to `temp/[filename].md`. You can run them with the `e2e-test-combined-flow` agent."**

## Examples

### Single test — document verification
```
<TEST_TO_RUN>
TEST_NAME: PFS Required ($200k - $250k)
TEST_URL: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true&autoDocReqTest=true&testBorrowerFico=720&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=220000
VERIFY_ITEMS:
Final page shows expected documents section with these items:
- Personal Financial Statement
- Applicant's Last Two Years Tax Returns including all schedules - Personal
- Paystubs - W2
Take a screenshot of the success page showing the documents list and upload card.
</TEST_TO_RUN>
```

### Single test — GA event verification
```
<TEST_TO_RUN>
TEST_NAME: Verify Upload Documents Button Click GA Event
TEST_URL: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000
VERIFY_ITEMS:
On the final page, record the current length of window.dataLayer in the browser console.
Then click the "Upload Documents" button.
After clicking, check window.dataLayer for a new entry matching:
- event: "link_click"
- action_type: "loan document upload"
- action_label: "upload documents"
- click_location: "main content"
Pass if all four properties match. Fail if the entry is missing or any property differs.
Log the matching dataLayer entry to the browser console.
Take a screenshot of the console output showing the matching dataLayer object.
</TEST_TO_RUN>
```

### Multiple tests — matrix of scenarios
```
<TEST_TO_RUN>
TEST_NAME: Subprime Wage Individual ($50k)
TEST_URL: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true&autoDocReqTest=true&testBorrowerFico=660&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=50000
VERIFY_ITEMS:
Final page shows expected documents section with these items:
- Paystubs - W2
Final page does NOT show:
- Personal Financial Statement
Take a screenshot of the success page showing the documents section.
</TEST_TO_RUN>

<TEST_TO_RUN>
TEST_NAME: Prime High LTV Individual ($300k)
TEST_URL: https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true&autoDocReqTest=true&testBorrowerFico=780&testNadaLTV=140&testBorrowerEmpType=employed&testAppType=Individual&testLoanAmount=300000
VERIFY_ITEMS:
Final page shows expected documents section with these items:
- Personal Financial Statement
- Applicant's Last Two Years Tax Returns including all schedules - Personal
- Paystubs - W2
Take a screenshot of the success page showing the documents list and upload card.
</TEST_TO_RUN>
```

## Rules

- If $ARGUMENTS is empty, ask for the test description or Jira ticket key
- If $ARGUMENTS matches a Jira ticket pattern (e.g., `TRIDENT-813`), fetch the ticket and derive tests from its acceptance criteria and QA notes
- Default environment is `qa` unless the user specifies `prod`
- QA URLs use `www.qa.boattrader.com` with `prodTesting=true`
- Prod URLs use `www.boattrader.com` without `prodTesting`
- When in doubt about a parameter value, ask rather than guess
- Each `<TEST_TO_RUN>` block must be self-contained — the agent should be able to execute it without any additional context
- When generating from a Jira ticket, prefix the output with a brief summary of the ticket's requirements and how the test blocks cover them (this is NOT a 1:1 AC mapping — explain your reasoning for the test design)
- If the user specifies `prequal-only`, include a `PREQUAL-ONLY` line in every generated block and write VERIFY_ITEMS against the Results page (not the success page)
