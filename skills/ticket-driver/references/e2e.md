# E2E driving technique + E2E learnings

Two related concerns for the E2E step: (1) how to drive a funnel with Playwright CLI, and (2) the persistent learnings file shared across runs. Load this when planning or running the E2E step.

---

## E2E driving technique (Playwright CLI — manual snapshot-then-act loop)

**Drive every E2E flow manually using `playwright-cli` directly. Do NOT invoke any bundled funnel-driving scripts** (any `*-flow.sh`, any project-bundled "happy path" wrapper, or any pre-baked "drive the whole funnel in one Bash call" script). Project funnels drift faster than these scripts get maintained, and a stale script will burn iteration budget on selector debugging while reporting a misleading exit code 0. The `playwright-cli` tool wraps every action in a single `playwright-cli run-code` call that exits cleanly even on an internal `TimeoutError`, so a wrapper script's "Flow complete" line tells you nothing about whether the flow actually completed.

### Artifact-path convention (screenshots, JSON dumps, snapshots, function-describes, etc.)

Every artifact captured during the E2E step — canonical captures from the delegated `e2e-test-jira-ticket` skill AND any ad-hoc captures the executor takes (per-step screenshots while debugging, intermediate dataLayer dumps, GCP function-describe outputs, webhook log dumps, etc.) — MUST land under the per-ticket memory directory:

```
~/.claude/memory/ticket-reports/<TICKET>/artifacts/
```

Create the directory once at the start of the E2E step: `mkdir -p ~/.claude/memory/ticket-reports/<TICKET>/artifacts` (standalone Bash). Name files with a `<TICKET>-` prefix and a short descriptor (e.g., `TRIDENT-904-e2e-final.png`, `TRIDENT-904-datalayer.json`, `TRIDENT-904-borrower-previous-employer-FILLED.png`, `TRIDENT-904-lendapi-webhook-live-log.json`).

**Do NOT write artifacts to `/tmp`.** `/tmp` is volatile on macOS (reboot wipes it) and Jira comments referencing those paths break the moment the operator opens them the next day. The memory directory is durable and per-ticket so the QA Pass comment's "Local artifacts captured" section stays valid.

The same convention applies to the `e2e-test-jira-ticket` skill (Mode 2 embedded by this skill, and Mode 3 live-QA) — that skill writes its canonical artifacts under the same `ARTIFACTS_DIR`. See [e2e-test-jira-ticket SKILL.md Step 6](../../e2e-test-jira-ticket/SKILL.md#step-6--capture-evidence) for the full contract.

### The loop

For each tab/step in the funnel, repeat:

1. **`playwright-cli snapshot`** — read the current accessibility tree. Note the `[ref=...]` IDs of inputs and buttons you need to interact with, and confirm the heading/title matches the expected tab.
2. **Act** — use the smallest, most specific `playwright-cli` command that fits:
   - `playwright-cli click <ref>` for buttons, radio options, links.
   - `playwright-cli fill <ref> "<value>"` for textboxes.
   - `playwright-cli check <ref>` for checkboxes.
   - For composite actions or anything not directly supported (e.g., opening a `combobox` and picking an option that loads asynchronously), use `playwright-cli run-code "async (page) => { ... }"` with Playwright Locator API. Inside `run-code`, the iframe pattern is `page.locator('iframe[title="..."]').contentFrame().getByRole(...)`.
3. **Wait** — sleep ~3–8 seconds between tabs to let the next page render and the previous network calls settle. Cold-start backends and async iframe transitions need real time. Sleep longer (~30s) after final submission to let confirmation events fire.
4. **Snapshot again** — verify the next tab loaded as expected. If you see the same tab still rendered, your action didn't take — investigate before retrying.

### Common gotchas (and how to handle them in the loop)

- **Element intercepted by overlay** — use `click({ force: true })` inside a `run-code` block. Common when a wrapper `div` with a click handler covers the inner radio/text.
- **Strict-mode violations from `getByRole(... { name: 'X' })`** — multiple elements match. Use `.first()`, `.nth(N)`, or use the `[ref=...]` ID directly via `playwright-cli click <ref>`.
- **`option` not found** — the dropdown options are likely loaded asynchronously after a parent dropdown changes (e.g., Boat Type loads after Boat Year). Sleep 2–3s between cascading combobox selections.
- **Cross-origin iframe `dataLayer` is unreadable** — the inner LendAPI iframe is on a different origin. The dynamic-app's `pushToDataLayer` calls go to the **parent page's** `window.dataLayer`. Read it with `playwright-cli eval "() => JSON.stringify(window.dataLayer || [])"`.
- **A `getByRole('option')` with `name: 'X'` resolves to two options because `'X'` is a substring** (e.g., `'Own'` matches both `'Own With Mortgage'` and `'Own Free and Clear'`). Use the full visible label or `{ exact: true }`.
- **Validation errors only surface after a Submit attempt** — required fields hidden until Submit reveals an inline `alert`. Snapshot after every Submit to surface these and fill what's missing.
- **Bundled flow scripts have stale selectors** — the snapshot you just took is the source of truth. If a known-good selector from a project-specific script disagrees with the live snapshot, trust the snapshot.

### dataLayer capture (project-specific but recurring pattern)

For GA-event validation, capture `window.dataLayer` with `playwright-cli eval "() => JSON.stringify(window.dataLayer || [], null, 2)"` at each milestone tab:
1. Right after the lead-submitted trigger tab (e.g., a result tab) loads — to validate the `lead_submitted` event.
2. After the final submit confirmation page loads — to validate the `application_submitted` event (or whatever the funnel's terminal event is).
Project-specific event names, trigger tabs, and timing behavior live in the **E2E Learnings** section below — read it before driving.

### When the live test reveals a real bug

If the snapshot-then-act loop shows the GA event firing without a required field (or any other observable correctness gap), trace it through the browser console (`playwright-cli` writes the page console log to `.playwright-cli/console-*.log`). Don't conclude the test passes per AC fallback rules until you've ruled out a code defect or a tunable like a fetch timeout.

---

## E2E Learnings (persistent memory across sessions, planners, and executors)

The E2E learnings file is persistent memory shared by the **planning agent** and the **execution agent** (which may be entirely different sessions/agents). It captures things like infra quirks, CDN/bot-protection behaviors, environment-specific gotchas, flaky selectors, and any other insight worth remembering across runs. Example entry: *"CloudFlare blocks headless playwright executions on the boattrader.com domain — must run headed or use a residential proxy."*

### File location

```
~/.claude/memory/E2E/<projectDir>/learnings.md
```

### Deriving `<projectDir>` (worktree-aware)

Take the **basename** of the project root and strip any trailing `-worktree-<N>` suffix (where `<N>` is any number). All worktrees of the same repo share one learnings file.

| Project root basename | `<projectDir>` |
|---|---|
| `webapp-react-trident` | `webapp-react-trident` |
| `webapp-react-trident-worktree-1` | `webapp-react-trident` |
| `webapp-react-trident-worktree-2` | `webapp-react-trident` |
| `webapp-react-trident-worktree-15` | `webapp-react-trident` |

Regex form (mental model): `s/-worktree-[0-9]+$//`. Compute the value once at the start of the session and reuse it.

### When to READ the learnings file

Read it (if it exists) at these points so prior insights inform decisions:

1. **Planning phase (standard mode and PLAN-MODE)** — read before producing the plan and the **E2E Test Plan**. If a learning is relevant (e.g., CloudFlare blocks headless on this domain), reflect it in the plan (choose headed mode, different URL, alternate evidence type, etc.).
2. **Execution phase Step 0 (executor subagent)** — read alongside `CLAUDE.md` and `MEMORY.md` so the executor enters its loop already aware of known traps.
3. **Before each E2E test attempt** — re-read so any learnings written by an earlier iteration of the fix-and-retry loop are available immediately.

If the file doesn't exist, that's fine — proceed without it.

### When to WRITE the learnings file

**Writing is conditional, not mandatory.** After the E2E test step completes (success **or** failure after 5 iterations), evaluate whether anything *new* was discovered relative to existing entries. Only write when ALL of the following are true:

1. **The discovery is non-obvious.** Routine, expected behavior is not a learning. Skip.
2. **The discovery is not already captured.** Re-read the current `learnings.md` content (already loaded earlier in the run). If an existing entry already documents the same observation/cause/mitigation, do NOT append a duplicate or near-duplicate entry. A near-duplicate is one where the **Cause** and the **Mitigation** would substantively repeat what's already on file — even if the date or ticket context differs.
3. **The discovery falls into one of these categories:**
   - A previously unknown blocker, quirk, or gotcha (CDN/bot-protection, auth, infra, env-specific behavior, selector instability, race conditions, etc.).
   - A workaround that future runs should know about.
   - A failure pattern diagnosed with a concrete root cause + fix that's likely to recur.

**If existing coverage is thin or stale (older than ~6 months) and the current run confirmed the same issue still happens or fixed it differently, prefer updating an existing entry's date and rewriting its mitigation to the current best advice over appending a duplicate.** Use the Write tool with the full file contents reflecting the in-place update.

**If nothing new was learned, do nothing — skip the entire write step.** No log, no empty file change, no placeholder entry. The fact that the file wasn't touched on this run is itself signal that the run was routine.

### Entry format

Append entries to `learnings.md` (do NOT overwrite the file). Each entry:

```markdown
## YYYY-MM-DD — <short title>

**Context:** <ticket key, branch, URL, what was being tested>
**Observation:** <what happened — concrete, specific>
**Cause:** <root cause if known, or "unknown" if not>
**Mitigation / what to do next time:** <actionable guidance for future runs>
```

### Bash for read/write (no compound commands, no command substitution)

- **Read:** Use the `Read` tool on `~/.claude/memory/E2E/<projectDir>/learnings.md`. If it returns "file does not exist," skip silently.
- **Create directory if missing:** `mkdir -p ~/.claude/memory/E2E/<projectDir>` as a standalone Bash call.
- **Write/append:** Use the `Write` tool (with the full prior contents + new entry appended) — do NOT use shell redirection (`>>`) or `echo`.
