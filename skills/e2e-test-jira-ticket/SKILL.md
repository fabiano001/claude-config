Base directory for this skill: /Users/fabianodesouza/.claude/skills/e2e-test-jira-ticket

# e2e-test-jira-ticket

Run an end-to-end test for a Jira ticket using Playwright CLI: deploy the changes to stage, drive the funnel manually, verify the pass/fail rule, capture evidence, and report. Production deployment is **forbidden**.

This skill has two entry modes — keep them straight as you read:

| Mode | Trigger | Behavior |
|---|---|---|
| **Standalone** (Mode 1) | `/e2e-test-jira-ticket TRIDENT-879` (no `--plan-confirmed` flag) | Skill drafts a 3-item proposal (URL / deploy / verify) using ticket text + branch diff + prior E2E learnings, asks the operator to confirm or update each, then executes. |
| **Embedded** (Mode 2) | `/e2e-test-jira-ticket TRIDENT-879 --plan-confirmed --url='…' --deploy='…' --verify='…' [--fix-and-retry]` | Skill skips the propose-and-confirm dialog (the caller already did it), echoes the resolved values back for safety, then executes. Used by `ticket-driver` and other orchestrators. |

The execution path (deploy → drive funnel → verify → capture → optional fix-and-retry → report) is identical for both modes.

## Argument schema

Positional:
- `<JIRA_TICKET_KEY>` — required. e.g. `TRIDENT-879`. Used for report headers, learnings entries, and (in Mode 1) Jira fetch.

Flags:
- `--plan-confirmed` — switches to Mode 2. Requires `--url`, `--deploy`, and `--verify` to also be present.
- `--url='<url>'` — the test URL. Required in Mode 2.
- `--deploy='<command>'` — the **stage-only** deploy command. Required in Mode 2. Must be safe (see safety guards below).
- `--verify='<rule>'` — pass/fail rule + evidence to capture. Required in Mode 2. May be a long string.
- `--fix-and-retry` — opt-in flag for the up-to-5-iteration commit/push/redeploy/re-run loop on failure. **Default OFF.**

If `--plan-confirmed` is present without all three of `--url`, `--deploy`, `--verify`, abort and tell the operator which arg is missing.

If `--plan-confirmed` is NOT present, ignore any of `--url`, `--deploy`, `--verify` that are present (don't silently use them) — Mode 1 is propose-and-confirm; pre-supplied values would bypass operator review.

## Safety guards (apply in BOTH modes — non-negotiable)

These are checked AT SKILL ENTRY and AGAIN before the deploy command runs. The skill must abort and tell the operator if any check fails.

1. **Production deployment is forbidden.** The deploy command must NOT contain `trident-funding` (the production Firebase project alias). The deploy command MUST contain `stage-trident` OR explicitly target a non-production environment via `--project <alias>` where `<alias>` is not `trident-funding`. If neither is true, abort with: "Refusing to run a deploy command that does not explicitly target stage-trident. Production is forbidden."
2. **No silent substitution of URL or deploy command mid-execution.** Once values are confirmed (Mode 1) or accepted as `--plan-confirmed` (Mode 2), they are LOCKED for the run. If the deploy fails, or the URL turns out to be wrong, **stop and ask the operator** — do not silently retry with a different command. (The verify rule is the only item that may be substituted mid-execution; see "Verification substitution rule" below.)
3. **Production-looking URL refusal.** If the URL contains `www.boattrader.com` or `www.yachtworld.com` or `www.boats.com` without a `qa.` or `stage.` prefix and without `prodTesting=true` in the query string, treat it as suspicious. Print it back to the operator and ask "Is this really the QA/stage URL? Type 'yes' to proceed." Do not proceed without explicit confirmation.

## Execution workflow

### Step 0 — Detect mode and validate args

1. Parse positional ticket key. If missing or doesn't match `[A-Z]+-[0-9]+`, abort: "Usage: /e2e-test-jira-ticket TICKET-123 [--plan-confirmed --url='…' --deploy='…' --verify='…'] [--fix-and-retry]"
2. Detect `--plan-confirmed`. If present, validate that `--url`, `--deploy`, `--verify` are all present (each non-empty). Otherwise abort with the missing arg list.
3. Run safety guards on the deploy command and URL (see "Safety guards" above). Abort cleanly if any guard trips.
4. Resolve the project root: use the current working directory's git toplevel (`git rev-parse --show-toplevel`). Capture as PROJECT_ROOT.
5. Resolve `<projectDir>` for the learnings file: basename of PROJECT_ROOT with any trailing `-worktree-<N>` stripped.

### Step 0.5 — Mode 1 only: ensure the local branch matches the ticket and is up to date

If `--plan-confirmed` was NOT supplied, run this step BEFORE Step 1. Otherwise skip — the caller is responsible for branch state in Mode 2.

The ticket branch name is the ticket key as-passed (including any `-TEST-<N>` suffix), e.g. `TRIDENT-892`. Do NOT strip the suffix for branch lookups.

1. **Refuse a dirty working tree.** Run `git -C <PROJECT_ROOT> status --porcelain` as a standalone Bash call. If the output is non-empty, abort with:

   ```
   Working tree has uncommitted changes — refusing to switch or pull, to avoid losing work.
   Commit, stash, or discard your changes, then re-run /e2e-test-jira-ticket <TICKET>.
   ```

   Stop. Do NOT proceed.

2. **Capture current branch.** `git -C <PROJECT_ROOT> branch --show-current` → CURRENT_BRANCH.

3. **Fetch from origin** (refresh remote refs). `git -C <PROJECT_ROOT> fetch --prune origin <TICKET>` — this is the focused fetch for the ticket branch only. If it fails because the ref doesn't exist on the remote (`fatal: couldn't find remote ref ...`), record that as `REMOTE_HAS_TICKET=false`; otherwise `REMOTE_HAS_TICKET=true`. This Bash call may exit non-zero on the no-remote-ref path — capture both stdout and exit code; do not abort the skill on this failure alone.

4. **Check local existence.** `git -C <PROJECT_ROOT> rev-parse --verify --quiet refs/heads/<TICKET>` — if exit 0, the branch exists locally (`LOCAL_HAS_TICKET=true`); if exit 1, it doesn't (`LOCAL_HAS_TICKET=false`).

5. **Decide based on the matrix:**

   | CURRENT_BRANCH == TICKET? | LOCAL_HAS_TICKET | REMOTE_HAS_TICKET | Action |
   |---|---|---|---|
   | yes | (already the case) | yes | `git -C <PROJECT_ROOT> pull --ff-only origin <TICKET>` to refresh. If non-fast-forward (local has diverged), abort with: "Local <TICKET> has diverged from origin/<TICKET>. Resolve manually (rebase or merge) before re-running E2E." |
   | yes | (already the case) | no | Warn the operator: "On <TICKET> locally but no remote branch exists — proceeding with local-only state. The deploy will use local code." Continue. |
   | no | yes | yes | `git -C <PROJECT_ROOT> checkout <TICKET>` then `git -C <PROJECT_ROOT> pull --ff-only origin <TICKET>`. Same divergence handling as above. |
   | no | yes | no | `git -C <PROJECT_ROOT> checkout <TICKET>`. Warn: "Switched to local <TICKET>; no remote branch — proceeding with local-only state." |
   | no | no | yes | `git -C <PROJECT_ROOT> checkout -b <TICKET> --track origin/<TICKET>` (create local tracking branch from remote). |
   | no | no | no | **Abort.** Print: "Branch <TICKET> does not exist locally or on origin. Cannot run E2E for a ticket with no branch. Either check out the correct branch manually, or create one (`git checkout -b <TICKET> origin/main`) and push it before re-running." Stop. Do NOT proceed. |

6. **Confirm to the operator** with one line — e.g. *"On branch TRIDENT-892, up to date with origin/TRIDENT-892."* Then continue to Step 1.

**Worktree note:** if the `git checkout` fails because the ticket branch is checked out in another worktree (`fatal: 'TRIDENT-892' is already used by worktree at ...`), abort with that exact error message + the suggestion: "Switch to that worktree or remove it (`git worktree remove`) before re-running E2E." Do NOT force-check-out.

**Safety boundary:** this skill never deletes branches, never force-pushes, never `--no-verify`s, never `git reset --hard`s. The only mutating ops are `fetch`, `checkout`, `checkout -b --track`, and `pull --ff-only`. Anything beyond those triggers an abort with operator instructions.

### Step 1 — Mode 1 only: draft and confirm the 3-item proposal

If `--plan-confirmed` was NOT supplied, run this step. Otherwise skip directly to Step 2.

1. **Fetch the Jira ticket** via `mcp__atlassian__getJiraIssue` (cloudId `ba2e3477-a4e5-4924-a530-47c471494d0f`, issueIdOrKey is the ticket key). Note: strip any `-TEST` / `-TEST-<N>` suffix when calling the API; keep the original ticket key for everything else.
2. **Fetch Acceptance Criteria** via `/fetch-jira-acceptance-criteria <key>` (which knows the custom-field plumbing).
3. **Read the diff** (improves draft quality, since branch is now confirmed): run `git -C <PROJECT_ROOT> diff main...HEAD --stat` to get the touched files. If that errors (no main/master), skip silently.
4. **Read prior E2E learnings**: try to Read `/Users/<user>/.claude/memory/E2E/<projectDir>/learnings.md`. If it doesn't exist, skip silently.
5. **Draft the 3-item proposal** using the heuristics below. Each item must be specific and actionable — no placeholders.

   **Drafting heuristics:**
   - **URL** — derive from the ticket's funnel scope:
     - Combined funnel → `https://www.qa.boattrader.com/boat-loans/apply/loan-application/combined/1044/OFEW5N3V_468/?source=101458&purpose=Boat&prodTesting=true`
     - LendAPI FullApp-only → `https://www.qa.boattrader.com/boat-loans/apply/loan-application/fullApp/<productId>/<slug>/?source=101458&purpose=Boat&prodTesting=true`
     - LendAPI Prequal-only or internal funnels — pick the corresponding QA URL based on ticket scope.
     - Always check the learnings file for known-good URLs and known-blocked domains for this project.
   - **Deploy command** — propose the minimum stage-only command that covers the modified surface, derived from the diff:
     - If files under `dynamic-app/` changed → include `hosting:dynamic-app`.
     - If files under `functions/src/` changed → include `functions:<name>` for each modified function (read from `functions/src/index.ts` exports). Always prefix with `firebase --project stage-trident deploy --only`. Example: `firebase --project stage-trident deploy --only hosting:dynamic-app,functions:lendAPIWebhook,functions:getLendAPIApprovalData`.
     - Never include `--project trident-funding` or omit `--project`.
   - **How to verify passing** — must combine a **pass/fail rule** (specific DOM text, specific GA event payload, specific final URL, absence of specific console errors) with the **evidence to capture** (dataLayer JSON, screenshot, console log, network request). Tailor to ticket scope: GA-event tickets → `window.dataLayer` capture; UI tickets → screenshots; backend tickets → network responses.

6. **Present the proposal to the operator** in this exact format:

   ```
   ### Proposed E2E Test Plan — please confirm or update each item

   1. **URL to use:** <proposed URL>
      (rationale: <one-line why — funnel scope match, learnings-recommended, etc.>)

   2. **How to deploy** (stage-trident only — production deployment is FORBIDDEN): <proposed command>
      (rationale: <one-line — which dirs changed and which functions/hosting targets are needed>)

   3. **How to verify passing:** <proposed pass/fail rule + evidence to capture>
      (rationale: <one-line — what AC requires + what the diff suggests we must observe>)

   Reply with edits to any item, or say "no further changes" to run.
   ```

7. **Loop on operator feedback** until the operator says "no further changes" / "ok" / "go" / "looks good." Apply edits in place; re-print the full 3-item block after each round.
8. Pass the confirmed values forward to Step 2 as if `--plan-confirmed --url='…' --deploy='…' --verify='…'` had been supplied.

### Step 2 — Echo resolved values (BOTH modes — safety check)

Print to the operator, BEFORE running the deploy command:

```
About to run E2E test for <TICKET>:
  URL:    <url>
  Deploy: <deploy command>
  Verify: <verify rule>
  Mode:   Standalone | Embedded
  Fix-and-retry: enabled | disabled

Production deployment is forbidden — confirmed safe by safety guards.
```

This is a last-chance visual review. The skill does NOT pause here — but the line is on the operator's screen before any action runs, so they can interrupt if something is wrong.

### Step 3 — Deploy

Run the deploy command via the Bash tool. This must be a foreground call so the operator sees the output in real time. Use `run_in_background: true` only if the deploy is expected to take >2 minutes; otherwise run inline.

**Bash command rules:**
- Run as a single Bash call (no `cd … &&`, no `$(…)`, no pipes — use absolute paths or `--prefix`).
- If the deploy returns non-zero, ABORT — do not proceed to drive. Print the deploy output and stop. The operator decides whether to retry or fix.

### Step 4 — Drive the funnel via Playwright CLI (snapshot-then-act loop)

**Drive the funnel manually using `playwright-cli`. Do NOT invoke any bundled funnel-driving scripts** (any `*-flow.sh` wrapper, any project-bundled "happy path" script, or any pre-baked "drive the whole funnel in one Bash call" wrapper). Project funnels drift faster than these scripts get maintained, and a stale script will burn iteration budget on selector debugging while reporting a misleading exit code 0.

#### The loop

Open the browser headed (Cloudflare blocks headless on boattrader-family domains):
```
playwright-cli open --headed "<url>"
```
Sleep ~5–6s for the iframe to load, then for each tab/step in the funnel, repeat:

1. **`playwright-cli snapshot`** — read the current accessibility tree. Note the `[ref=...]` IDs of inputs and buttons you need to interact with, and confirm the heading/title matches the expected tab.
2. **Act** — use the smallest, most specific `playwright-cli` command that fits:
   - `playwright-cli click <ref>` for buttons, radio options, links.
   - `playwright-cli fill <ref> "<value>"` for textboxes.
   - `playwright-cli check <ref>` for checkboxes.
   - For composite actions (combobox open + option select that loads asynchronously, or anything not directly supported), use `playwright-cli run-code "async (page) => { ... }"` with the Playwright Locator API. Inside `run-code`, the iframe pattern is `page.locator('iframe[title="..."]').contentFrame().getByRole(...)`. Use `click({ force: true })` if the click is intercepted by a wrapper div.
3. **Wait** — sleep 3–8s between tabs to let the next page render and the previous network calls settle. Cold-start backends and async iframe transitions need real time. Sleep ~30s after final submission to let confirmation events fire.
4. **Snapshot again** — verify the next tab loaded as expected. If the same tab still renders, your action didn't take — investigate before retrying.

#### Common gotchas

- **Element intercepted by overlay** → `click({ force: true })` inside a `run-code` block.
- **Strict-mode violations from `getByRole(... { name: 'X' })`** → multiple elements match. Use `.first()`, `.nth(N)`, or use the `[ref=...]` ID directly.
- **`option` not found** → dropdown options load asynchronously after a parent dropdown changes (e.g., Boat Type loads after Boat Year). Sleep 2–3s between cascading combobox selections.
- **Cross-origin iframe `dataLayer` is unreadable** → the inner LendAPI iframe is on a different origin. The dynamic-app's `pushToDataLayer` calls go to the **parent page's** `window.dataLayer`. Read it with `playwright-cli eval "() => JSON.stringify(window.dataLayer || [])"`.
- **`getByRole('option', { name: 'X' })` matches multiple options because `'X'` is a substring** (e.g., `'Own'` matches both `'Own With Mortgage'` and `'Own Free and Clear'`) → use the full visible label or `{ exact: true }`.
- **Validation errors only surface after a Submit attempt** → required fields are hidden until Submit reveals an inline `alert`. Snapshot after every Submit to surface these and fill what's missing.
- **AbortSignal timeout on Cloud Function calls** → cold-start can exceed default 3s timeout. If you see `AbortError: signal is aborted without reason` in the console, that's the smoking gun — it's a code-level tunable, not a test problem.
- **Bundled flow scripts have stale selectors** → the snapshot you just took is the source of truth. If a known-good selector from a project-specific script disagrees with the live snapshot, trust the snapshot.

### Step 5 — Verify against item 3 (with substitution rule)

After driving to the verification milestone(s), run the agreed verification approach from `--verify`. For most LendAPI tickets, this is:

```
playwright-cli eval "() => JSON.stringify(window.dataLayer || [], null, 2)"
```

Compare against the pass/fail rule. If it matches → success. If it doesn't, INVESTIGATE before declaring failure.

#### Verification substitution rule

You MAY switch to an alternate verification approach IF AND ONLY IF:
1. You first attempted the agreed approach and observed a concrete failure (not a guess that something else would be easier).
2. The alternate validates the same pass/fail intent (still proves the AC is met).

If you substitute, the post-test report MUST document BOTH the originally-agreed approach AND the alternate, with a one-line rationale for why the original didn't work.

URL or deploy command substitutions are NOT permitted. If either appears wrong mid-execution, **stop and ask the operator** — abort the run cleanly.

### Step 6 — Capture evidence

Capture whatever item 3 requires. Common artifacts:
- **Full dataLayer JSON** — write to `/tmp/<TICKET>-datalayer.json` via `playwright-cli eval` + the Write tool.
- **Final-page screenshot** — `playwright-cli screenshot --filename "/tmp/<TICKET>-e2e-final.png" --full-page`.
- **Snapshot YAML** — `playwright-cli snapshot --filename "/tmp/<TICKET>-final-snapshot.yml"`.
- **Console log** — automatically saved by playwright-cli to `<PROJECT_ROOT>/.playwright-cli/console-*.log`.

### Step 7 — Decide outcome

| Outcome | Action |
|---|---|
| **Verify passed** | Proceed to Step 8 (close + write learnings if new + return success). |
| **Verify failed AND `--fix-and-retry` not set** | Write `E2ETEST-Report.md` (Step 9), return failure. |
| **Verify failed AND `--fix-and-retry` set** | Enter the fix-and-retry loop (Step 7a). |

#### Step 7a — Fix-and-retry loop (only when `--fix-and-retry` is set)

Max 5 iterations. Each iteration:
1. **Investigate** — analyze captured evidence (screenshots, console logs, network requests, DOM state) to determine the root cause.
2. **Fix code** — make the minimal change that addresses the root cause.
3. **Commit + push** to the same branch (no `--no-verify`, no `--amend`):
   ```
   git -C <PROJECT_ROOT> add <files>
   git -C <PROJECT_ROOT> commit -m "<TICKET>: <one-line fix summary>"
   git -C <PROJECT_ROOT> push origin <branch>
   ```
4. **Redeploy** by re-running the deploy command from item 2 (URL and deploy command are LOCKED — do not modify them).
5. **Close the existing browser** (`playwright-cli close`) and **re-drive the same flow** (Steps 4–6).

Stop the loop when verify passes (→ Step 8) OR after 5 iterations (→ Step 9).

### Step 8 — Success path: close, learnings, return

1. Close the browser: `playwright-cli close`.
2. **Conditional learnings write** — only if there's something *new* to record. Re-read `/Users/<user>/.claude/memory/E2E/<projectDir>/learnings.md` and compare against what you'd write. Skip if a near-duplicate exists. Update an existing entry in place (rewriting its mitigation to current best advice) if the existing entry is stale (older than ~6 months) and your run confirmed the same issue or evolved the mitigation. If nothing new was learned, do nothing — skip the entire write step.

   When a write IS warranted, use the Write tool with the full file contents (existing + new entry, OR existing with in-place update). Entry format:
   ```
   ## YYYY-MM-DD — <short title>

   **Context:** <ticket key, branch, URL, what was being tested>
   **Observation:** <what happened>
   **Cause:** <root cause or "unknown">
   **Mitigation / what to do next time:** <actionable guidance>
   ```
3. Return a structured summary to the caller (printed to operator):
   ```
   ✓ E2E PASSED — <TICKET>
     URL:               <url>
     Deploy:            <deploy command>
     Verification used: <agreed | alternate (with rationale)>
     Artifacts:         <comma-separated paths>
     Iterations used:   <N> (of 5 max if --fix-and-retry)
   ```

### Step 9 — Failure path: write E2ETEST-Report.md, learnings, return

1. **Write `<PROJECT_ROOT>/E2ETEST-Report.md`** — this is the canonical failure signal. Callers (e.g., `ticket-driver`) check for this file's existence to decide whether to continue (e.g., skip Jira finalization). The file MUST include:

   ```markdown
   # E2E Test Report — <TICKET>

   ## Status

   FAILING after <N> iteration(s) <(of 5 max with --fix-and-retry | first attempt without --fix-and-retry)>

   ## E2E Test Plan (verbatim)

   1. **URL to use:** <url>
   2. **How to deploy** (stage-trident only): <deploy command>
   3. **How to verify passing:** <verify rule>

   ## Verification approach used

   - **Originally agreed:** <verify rule from item 3>
   - **Alternate used during execution (if any):** <alternate>
   - **Why the original didn't work:** <one-line rationale, or "N/A — original approach was used">

   ## What is failing

   <precise description: error messages, captured evidence summary, which step in the flow breaks>

   ## What has been done so far

   <bulleted summary of each iteration's hypothesis, code change made, and outcome>

   ## Suggested next steps

   <2–4 concrete suggestions: investigate specific subsystem, check infra/config, escalate to a domain owner, capture additional evidence type>

   ## Artifacts

   <comma-separated paths to screenshots, console logs, dataLayer JSON, etc.>
   ```

2. Close the browser: `playwright-cli close`.
3. **Conditional learnings write** — same rules as Step 8.2.
4. Return a structured summary to the caller:
   ```
   ✗ E2E FAILED — <TICKET>
     URL:               <url>
     Deploy:            <deploy command>
     Iterations used:   <N> (of 5 max if --fix-and-retry, else 1)
     Report:            <PROJECT_ROOT>/E2ETEST-Report.md
     Artifacts:         <comma-separated paths>
   ```

## Bash safety rules (non-negotiable)

These match the rules used by the parent `ticket-driver` skill — copied here so this skill is self-contained.

- NEVER use `cd path && command` — use `git -C <absolute-path>` or `--prefix` flags or absolute paths.
- NEVER use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution (`$(...)`, `${...}`) — split into separate Bash calls.
- NEVER use `&&`, `;`, or `||` to chain commands — separate Bash calls.
- NEVER use `--no-verify`, `--no-gpg-sign`, or `-c commit.gpgsign=false` unless the operator explicitly asked for it.
- NEVER use `git rebase -i` or `git add -i` (interactive flags).
- For `--testPathPattern` with multiple files use `"foo|bar"` (NOT `"(foo|bar)"`) — parens contain `=(` which Zsh interprets as process substitution, triggering a security prompt.

## Skill discovery and contract

This skill is at `~/.claude/skills/e2e-test-jira-ticket/SKILL.md` and is auto-discovered by Claude Code — no registration step needed.

When invoked via the Skill tool from `ticket-driver`, this skill runs in the same session as the caller (Skill tool, not Task subagent), so:
- Every `Bash` call surfaces to the operator's terminal with the same approval flow as inline calls.
- The operator can interrupt at any point.
- Context is shared with the caller — useful for inheriting prior plan context, but be mindful that long parent runs may push toward context limits.

The canonical failure signal is the existence of `<PROJECT_ROOT>/E2ETEST-Report.md`. The structured return summary is a secondary signal. Callers should prefer file existence as the primary decision input.
