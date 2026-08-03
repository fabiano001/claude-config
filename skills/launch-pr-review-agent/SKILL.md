---
name: launch-pr-review-agent
description: Launches a NEW, SEPARATE background Claude Code session that runs `/review-pr` against a given PR, instead of running the review inline in the current conversation — the current session stays free while the review runs elsewhere, visible in the agent view under a Jira-ticket-and-repo-derived name like "PR REVIEW - TRIDENT-974 - WEBAPP" (the repo suffix prevents a name collision when the same ticket spans multiple repos, each getting its own PR reviewed separately). Takes a GitHub PR URL (or `owner/repo#n`) and an optional `FULL` token forwarded to `/review-pr`. Use when the user asks to launch/kick off/background a PR review, or run `/launch-pr-review-agent`. Do NOT use when the user wants the review to run right here in this conversation and see the result immediately — that's `/review-pr` directly, not this.
---

# Launch PR Review Agent (orchestrator)

Thin orchestrator. It does no reviewing itself — it derives a session name, picks a safe directory, and opens a new backgrounded Claude Code session whose first message is `/review-pr <PR_URL> [FULL]`. All review logic belongs to `/review-pr` and what it dispatches; this skill's only job is getting a correctly-named, correctly-backgrounded session started without stepping on another one.

## Inputs

- **PR reference (REQUIRED — do not proceed without one):** GitHub PR URL (`https://github.com/{owner}/{repo}/pull/{n}`) or `owner/repo#n`. If missing, ask for it before doing anything else.
- **`FULL` (optional):** a literal standalone token, case-insensitive (matches `FULL`/`Full`/`full` as its own word, not a substring of something else) — scanned the same way `review-pr`'s own `FULL`-token detection works. Present → forward it. Absent → don't.

## Workflow

### Step 1 — Parse and canonicalize

Parse the PR reference into `OWNER`, `REPO`, `NUM`. Canonicalize `PR_URL = https://github.com/<OWNER>/<REPO>/pull/<NUM>`.

### Step 2 — Fetch PR metadata (also validates the PR exists)

```bash
gh pr view <NUM> --repo <OWNER>/<REPO> --json headRefName,title,body
```

**If this fails** (bad PR reference, no access, auth error): **STOP and report the failure.** Do not launch a session speculatively against a PR that doesn't resolve — a backgrounded session pointed at a dead PR just wastes a tab and confuses the operator later when it reports its own failure.

### Step 3 — Derive the Jira ticket key for naming

Scan, **in this priority order**, `headRefName` first, then `title`, then `body`, for a ticket-key pattern `[A-Z][A-Z0-9]+-[0-9]+` (case-insensitive match; output the matched key **uppercased**). Stop at the first match — e.g. a branch named `trident-955-foo` yields `TRIDENT-955`, and you never look at the title/body once the branch matched.

**If a ticket key was found**, also compute `REPO_CODE` from `REPO` (Step 1) — the same repo→code mapping `jira-sprint-manager`, `jira-sprint-todo-loop`, and `launch-research-agent` all already use for their own session naming:
- `webapp-react-trident` → `WEBAPP`
- `portal-react-boattrader` → `PRBT`
- any repo name containing `lambda` → `LAMBDA`
- any repo name containing `terraform` → `TERRAFORM`
- anything else → the repo's own literal name

`SESSION_NAME = "PR REVIEW - <ticket key> - <REPO_CODE>"` — this exact literal format, spaces included (e.g. `PR REVIEW - TRIDENT-974 - WEBAPP`, `PR REVIEW - TRIDENT-974 - TERRAFORM`). **The repo suffix is mandatory whenever a ticket key was found** — a single Jira ticket often spans multiple repos, each getting its own PR reviewed separately, and without the repo suffix a second PR for the same ticket would collide with (and get misidentified as a duplicate of) the first PR's session name.

**If no ticket key match anywhere:** fall back to a deterministic name, `<OWNER>-<REPO>-<NUM>` (e.g. `boatsgroup-portal-react-boattrader-243`) — `SESSION_NAME = "PR REVIEW - <OWNER>-<REPO>-<NUM>"`. No repo-code suffix needed here: the PR number already makes this name unique per PR, so appending `REPO_CODE` on top would just be redundant (the repo name is already baked into the fallback). Never leave the name blank and never invent a ticket key that wasn't actually found in the text.

### Step 4 — Build the launched prompt

`PROMPT = "/background /review-pr <PR_URL>"`, then append literal ` FULL` if the `FULL` token was present in this skill's own input.

**Why the `/background` prefix is required even though it wasn't spelled out verbatim in the target prompt shape:** in this environment, a Claude Code session only lands in the backgrounded agent view when `/background` is the first word of its submitted prompt — there is no separate CLI flag or startup option that does this. This is the exact same convention `jira-sprint-manager` uses everywhere it opens a backgrounded session (e.g. `--prompt "/background /ticket-driver TICKET-KEY"`). Submitting bare `/review-pr <PR_URL> [FULL]` without the prefix would start the session in the ordinary **foreground** interactive view instead — technically running the right command, but not backgrounded, which defeats the actual point of this skill ("frees up the current session while it runs elsewhere"). So the prefix is not optional even though the user-facing description of the target command didn't literally include it.

### Step 5 — Pick a directory that won't collide with another review's tab

**Do NOT open the new session directly in the shared repo checkout** (e.g. `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`). Here's why this matters, precisely:

`~/.claude/skills/jira-sprint-manager/open-claude-session.sh` (the helper this skill uses to actually open the tab) has iTerm2 tab-reuse detection keyed **purely on the target directory's basename** (marker `jsm:<dirbasename>`) — if directory X already has a tab tagged with that marker, a new call targeting X **focuses the existing tab instead of opening a new one and does NOT submit the new prompt**. If two different PR reviews both targeted the same shared repo directory, the second launch would silently focus the first PR's tab and never actually start reviewing the second PR at all — a real, silent failure, not a cosmetic one.

**The fix:** use a dedicated, per-PR-unique directory: `REVIEW_DIR = ~/.claude/pr-reviews/<OWNER>-<REPO>-<NUM>`. Create it if it doesn't exist:

```bash
mkdir -p ~/.claude/pr-reviews/<OWNER>-<REPO>-<NUM>
```

This directory does **not** need to be a git checkout or worktree — `review-pr` and everything it dispatches (`code-review-specialist`, `pr-review-assist`) always operate via `gh ... --repo <owner>/<repo>` explicitly and never depend on the local working directory matching the target repo. A plain empty directory is sufficient.

This also gives the *correct* behavior if the exact same PR is launched twice in a row: the existing tab-reuse logic will correctly focus the already-running review session for that PR instead of duplicating it — which is what you'd actually want in that case. The fix only prevents the *cross-PR* collision, not same-PR reuse.

### Step 6 — Launch

```bash
~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
  <REVIEW_DIR> \
  --prompt "<PROMPT from Step 4>" \
  --session-name "<SESSION_NAME from Step 3>" \
  --auto-close-on-background
```

**Why `--auto-close-on-background`:** once `/review-pr` hands off to `/background`, the launched tab's `claude` process exits and the tab just sits idle forever with nothing left to do — this flag has `open-claude-session.sh` watch for that handoff (Claude Code's own `backgrounded ·` completion line) and close the now-idle tab automatically, within a bounded ~20s window. If the handoff is never detected in time (e.g. the dispatched `/review-pr` errored before backgrounding), the tab is deliberately left open so the operator can see why. See `open-claude-session.sh`'s own header comment for the full mechanism.

**If this exits non-zero:** report the failure verbatim — do not retry silently, do not fall back to running the review inline in the current session instead (that would silently change what the operator asked for).

### Step 7 — Report back

State plainly: the PR being reviewed (`PR_URL`), the derived ticket key (or note that the fallback name was used, and why — no key found in branch/title/body), the resulting `SESSION_NAME`, whether `FULL` mode was requested, the `REVIEW_DIR` used, and the helper script's own result line (new tab opened vs. an existing tab reused for the same PR vs. new tab opened then auto-closed after the `/background` handoff vs. new tab opened but left open because no handoff was detected in time).

## Failure & fallback

- No PR reference given → ask for one; do not guess.
- Step 2's `gh pr view` fails → stop, report the verbatim error, launch nothing.
- Step 6's `open-claude-session.sh` exits non-zero → report the verbatim failure; the operator can retry or open the session manually.

## Non-goals

- Do not perform any review logic here — no fetching diffs, no critique, no artifact generation. All of that belongs to `/review-pr` and what it dispatches, running inside the launched session, not this one.
- Do not skip the `/background` prefix "since the user only asked for `/review-pr URL FULL`" — see Step 4's rationale; omitting it defeats the purpose of this skill.
- Do not reuse the shared repo checkout directory as a shortcut — see Step 5; it causes silent cross-PR collisions.
- Do not drop the `REPO_CODE` suffix from `SESSION_NAME` "since the ticket key alone already identifies it" — see Step 3; a single ticket spanning multiple repos would produce identically-named sessions for different PRs otherwise.
