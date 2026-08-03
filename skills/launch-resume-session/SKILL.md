---
name: launch-resume-session
description: Looks up an existing ticket-driver or ticket-creation session for a Jira ticket in ~/.claude/memory/sessions.md, checks whether it's still live in the background agent view, and — if not — resumes it in a NEW backgrounded Claude Code session with no new prompt or instruction at all, just picking the conversation back up in the background under a fresh display name like "TRIDENT-974 - CREATION" or "TRIDENT-974 - DRIVER - WEBAPP" (repo code only on DRIVER, since one ticket can have a separate driver session per repo), then auto-closes the now-idle launching terminal tab once the handoff completes. Takes a mandatory Jira ticket key (e.g. TRIDENT-974) and an optional session type (`CREATION` or `DRIVER`); when the type is omitted, presents every session found for that ticket so the operator can pick one. Use when the operator asks to resume/reopen/relaunch/background a prior ticket-driver or ticket-creation session for a ticket, or runs `/launch-resume-session`. Do NOT use to start brand-new work on a ticket — that's `/ticket-driver` or `/ticket-creator` directly, not this; this skill only ever resumes a session that already exists in sessions.md, and sends it no new instructions.
---

# Launch Resume Session (orchestrator)

Thin orchestrator. It writes no code and does no ticket work itself — it looks up a known session, checks it isn't already running, and opens a new backgrounded Claude Code session that resumes it with **zero new content**. All the actual ticket-driver/ticket-creation logic already happened in the session being resumed; this skill's only job is safely reopening that exact conversation in the background without creating a duplicate.

## Inputs

1. **Jira ticket key (REQUIRED):** e.g. `TRIDENT-974`. If missing, ask for it before doing anything else.
2. **Session type (optional):** `CREATION` or `DRIVER`, case-insensitive standalone token.
   - `CREATION` matches sessions.md subentries whose label starts with `ticket-creation` (covers `## ticket-creation` and variants like `## ticket-creation (artifact mode)`).
   - `DRIVER` matches subentries whose label starts with `ticket-driver` (covers `## ticket-driver` and variants like `## ticket-driver (TODO mode)`).
   - **If omitted:** don't guess — collect every session found under that ticket (any type/label) and let the operator pick. See Step 2.

## Workflow

### Step 1 — Find the ticket's sessions in sessions.md

Read `~/.claude/memory/sessions.md`. Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` (key followed by a parenthetical) — same convention `jira-sprint-manager` already uses. Collect every `##`-level subentry under that heading, up to the next H1 or EOF.

**If no matching heading exists, or it has zero subentries:** reply `"No sessions found in sessions.md for <TICKET-KEY>."` and stop. Do not guess a session id or repo from anywhere else.

**Full matching, filtering, deduplication, and disambiguation rules — load [references/session-lookup.md](references/session-lookup.md).** Short version: filter by session type if one was given, collapse repeat re-runs of the same repo down to the most recent entry, and if more than one distinct candidate remains, ask the operator which one via `AskUserQuestion` (label each option by repo + type + date). If exactly one candidate remains after filtering/dedup, use it directly — no need to ask when there's nothing to disambiguate.

**If a type was given and zero subentries match it:** reply `"No <TYPE> session found for <TICKET-KEY>. Sessions that do exist for this ticket: <list the distinct labels found>."` and stop.

This step resolves exactly one `SESSION_ID` and one `REPO_DIR` (a basename, e.g. `webapp-react-trident-TRIDENT-974`) before continuing.

### Step 2 — Resolve the repo path

```
REPO_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<REPO_DIR>
```

**If `REPO_PATH` doesn't exist on disk** (worktree deleted/moved since the session was recorded): stop, report `"Session <SESSION_ID> for <TICKET-KEY> was found, but its worktree <REPO_PATH> no longer exists on disk — nothing to resume it in."` Do not create a new worktree — this skill only resumes, it never creates.

### Step 2.5 — Compute the session name

```
CREATION → SESSION_NAME = "<TICKET-KEY> - CREATION"
DRIVER   → SESSION_NAME = "<TICKET-KEY> - DRIVER - <REPO_CODE>"
```

`CREATION` never gets a repo suffix (a ticket only ever has one active creation/research line, so there's nothing to disambiguate); `DRIVER` always does, since one ticket commonly has a separate `ticket-driver` session per repo (e.g. `TRIDENT-972` has one for `webapp-react-trident` and one for `lambda-node-trident-partner-lender` — without the suffix, resuming either would produce an identically-named session).

**Computing `REPO_CODE`:** first strip any ticket-specific suffix from `REPO_DIR` to get `BASE_REPO` — find the known repo name (from the list below) that `REPO_DIR` either equals exactly or starts with followed by a `-` (e.g. `webapp-react-trident-TRIDENT-971` → `BASE_REPO = webapp-react-trident`). If `REPO_DIR` doesn't match any known repo this way, fall back to using `REPO_DIR` itself as `BASE_REPO` (best effort for an unrecognized repo). Then apply the same repo→code mapping `jira-sprint-todo-loop`, `launch-research-agent`, and `launch-pr-review-agent` all already use:
- `webapp-react-trident` → `WEBAPP`
- `portal-react-boattrader` → `PRBT`
- any repo name containing `lambda` → `LAMBDA`
- any repo name containing `terraform` → `TERRAFORM`
- anything else → `BASE_REPO`'s own literal name

Known base repos (for the prefix-strip step): `portal-react-boattrader`, `webapp-react-trident`, `api-node-boats`, `api-node-boattrader`, `lambda-node-trident-700credit`, `lambda-node-trident-advertised-rates`, `lambda-node-trident-portal-lead`, `lambda-node-trident-partner-lender`, `pp-algorithm`, `configd`, `terraform-stack-trident`.

### Step 3 — Check whether it's already live in the background agent view

**This is not a single simple check — it's genuinely load-bearing.** Empirically confirmed (2026-07-31): calling `--resume <id> --prompt "/background"` twice on the same session id, with nothing in between, produces **two separate live background processes**, both anchored to the **same single transcript file** on disk, with no refusal or error from the CLI either time. This step exists specifically to prevent that.

**Do NOT reuse `jira-sprint-manager`'s `references/live-agent-check.md` verbatim** — that check matches purely on the `sessionId` field in `claude agents --all --json`, which silently misses a session that was already resumed-and-backgrounded once (the daemon assigns the backgrounded process a **fresh** tracking id, decoupled from the original conversation id, confirmed by checking that only one transcript file — under the *original* id — ever exists on disk).

**Also do NOT use pure cwd-matching** — a separate real-world gap: `sessions.md`'s `repo/dir` is not always a dedicated per-ticket directory. Some `ticket-creation` sessions are recorded against the shared main checkout (e.g. `webapp-react-trident`, no ticket suffix) or a generic scratch worktree reused across *multiple, unrelated* tickets (observed in real data: `webapp-react-trident-worktree-research` shared between TRIDENT-974 and TRIDENT-975). Matching by `cwd` alone there produces false positives against unrelated live sessions.

**Use the hybrid check instead — full detail in [references/live-agent-check.md](references/live-agent-check.md).** Summary: check whether `REPO_DIR` contains the literal `TICKET_KEY` as a substring.

- **Contains the ticket key (ticket-specific directory)** → check liveness by `cwd` match in `claude agents --all --json` (safe here — nothing else legitimately shares this exact directory).
- **Does NOT contain the ticket key (shared directory)** → check liveness by exact `sessionId` match only. If no match, **do not conclude NOT LIVE and proceed** — report that liveness can't be reliably confirmed in a shared directory, and hand the operator a ready-made `claude --resume` command to run themselves after checking `claude agents` on their own. This is a terminal outcome for this branch.

In either ticket-specific or shared branches: **LIVE** → reply plainly that the session is still active under the agent view (name it) and stop — do not attempt to resume. **NOT LIVE** (ticket-specific branch only) → proceed to Step 4.

### Step 4 — Resume it in the background, with no new prompt

```bash
~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
  <REPO_PATH> \
  --resume <SESSION_ID> \
  --session-name "<SESSION_NAME from Step 2.5>" \
  --prompt "/background" \
  --auto-close-on-background
```

- `--prompt "/background"` — the **bare** command, nothing appended. Empirically verified (2026-07-31): this cleanly backgrounds the resumed session with zero new content injected into the conversation (Claude Code records it as a no-op local command and replies "No response requested" — the transcript is not polluted). This is the whole point of this skill: pick the conversation back up in the background exactly where it left off, no new instruction.
- `--session-name` **does** take effect here even though this is a `--resume` call, not a fresh session — empirically verified (2026-07-31): resuming with a different `--session-name` than the session's original name correctly overrides the display name shown in `claude agents --json` going forward. (`open-claude-session.sh`'s header comment used to claim this flag was a no-op on `--resume`; that claim was never actually tested and has since been corrected there.)
- `--auto-close-on-background` — same mechanism `launch-pr-review-agent` and `launch-research-agent` already use: once the handoff completes, the now-idle launching tab closes itself automatically within ~20s. If it never completes in that window, the tab is left open on purpose — see Failure & fallback.

**If this exits non-zero:** report the failure verbatim.

### Step 5 — Report back

State plainly: the ticket key, the session type resolved (and whether it was given or picked by the operator), the repo, the `SESSION_ID` resumed, the `SESSION_NAME` it was resumed under, and the helper script's own result line (resumed-and-auto-closed vs. left open because no handoff was detected in time).

## Failure & fallback

- No ticket key given → ask for one; do not guess.
- No heading / no subentries for the ticket in sessions.md → say so plainly; do not fall back to guessing a session id from anywhere else (git branches, PR titles, etc.).
- A type was given but nothing matches it → say so, and list what session types *do* exist for that ticket so the operator can retry correctly.
- More than one candidate remains after filtering/dedup → ask via `AskUserQuestion`, never guess which repo/session the operator meant.
- `REPO_PATH` doesn't exist on disk → stop, report; this skill never creates worktrees.
- Session is LIVE per Step 3 → stop, report it's active; never attempt a resume on a live session (this is the exact failure mode Step 3 exists to prevent — a second process writing to the same transcript concurrently).
- `REPO_DIR` is a shared/non-ticket-specific directory and no `sessionId` match was found → do not proceed automatically; hand the operator a ready-made `claude --resume` command to run themselves after they've checked `claude agents` on their own (see Step 3 / references/live-agent-check.md).
- `open-claude-session.sh` exits non-zero → report the verbatim failure.
- Auto-close times out (left tab open) → `open-claude-session.sh` now self-diagnoses this (fixed 2026-08-03): it captures the tab's last few non-empty lines of output and prints them alongside the timeout message, so you don't need to manually cross-check `claude agents --all --json` against `ps aux` to figure out what happened — read the printed tail directly. A real error there (e.g. "No conversation found", "command not found") means the resume itself failed, not just a slow startup. If the tail is unreadable or absent, or you still can't tell, that's the point where manual cross-checking remains a legitimate fallback.
- Separately: the launching tab's own keystroke-injection race (an operator's in-flight typing landing inside the injected command and corrupting it — the original motivation for the fixes above) has been fixed at the source in `open-claude-session.sh` by removing its focus-stealing `activate` call. This was root-caused and verified empirically, not just theorized — see that script's own header/inline comments for the full account.

## Non-goals

- Do not start new ticket-driver or ticket-creation work — that's `/ticket-driver` / `/ticket-creator` directly, not this skill. This skill only resumes a session that's already recorded in sessions.md.
- Do not send any real instruction/prompt into the resumed session — the bare `/background` in Step 4 is intentional and load-bearing; appending anything after it would turn this into a "resume and give it a new task" skill, which is not what this is.
- Do not reuse `jira-sprint-manager`'s sessionId-based live-agent-check for this skill's Step 3 verbatim, and do not use pure cwd-matching either — see that step's rationale and references/live-agent-check.md; each is unreliable on its own, for two separate, empirically-confirmed reasons.
- Do not treat a shared/non-ticket-specific `REPO_DIR` as "probably fine, just check cwd anyway" — see Step 3's SHARED branch; that's precisely the case that produces false positives.
- Do not create a worktree if `REPO_PATH` is missing — report and stop instead.
