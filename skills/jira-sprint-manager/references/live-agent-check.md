# Live-agent check (shared helper — before resuming any known session)

Used by Rule B (step 2b, Live QA kickoff) and Rule C (path 3b, unresolved-review-comments auto-resume) — both of these send a NEW prompt into a session the skill already knows about (looked up from `~/.claude/memory/sessions.md`). This check runs AFTER the session lookup (it needs `IMPL_SESSION_ID`) and BEFORE the `open-claude-session.sh --resume ...` call.

## Why this exists

`claude --resume <id>` only works when that session is NOT currently attached to a running background-agent process. If the daemon still has a live process for that session — even one that is idle with its last turn already finished — `--resume` is refused outright:

```
Error: Session <id> is currently running as a background agent (bg). Use `claude agents` to find
and attach to it, or add --fork-session to branch off a copy.
```

Empirically verified 2026-07-29 (TRIDENT-970 Live QA kickoff attempt, plus a dedicated throwaway "test run validation" session used specifically to test this):

- Killing the process's pid (`kill -TERM <pid>`) does **not** free the session up for `--resume`. The daemon runs a supervisor that treats the death as a crash, not a stop request, and auto-respawns a replacement process for the same session within a few seconds — new pid, new `startedAt`, same `sessionId`/`name`/`cwd`/`state`, no data loss, but still "live." Confirmed twice in a row on the test session.
- `--fork-session` does work, but it creates a **new** session id — it does not continue the original conversation, and the operator has explicitly said a new forked session is NOT the desired default behavior here.
- There is no documented, supported CLI verb to attach to or send a message into a live background agent non-interactively. That capability is TUI-only (`claude agents`, then navigate + `space` to reply, or `enter` to attach). Scripting that TUI blindly is unsafe: the rendered screen content available to automation does not expose which row is actually highlighted, and one exploratory keystroke during manual testing surfaced a "delete all" footer action with no way to confirm what was selected before committing to it.

**Conclusion:** when a session is live, the skill's only safe options are (a) leave it alone and hand the operator a ready-made prompt to paste in themselves, or (b) `--fork-session` if the operator has explicitly opted into that elsewhere. Rule B and Rule C both default to (a).

## The check

1. Run `claude agents --all --json` (standalone Bash). `--all` includes completed/idle background sessions, not just currently-busy ones — needed because idle-but-still-attached sessions (like TRIDENT-970-PRBT's `state: "done"`) are still LIVE per the test below.
2. Parse the JSON array. Find the entry whose `sessionId` field exactly matches `IMPL_SESSION_ID`.
3. **LIVE test:** the session is **LIVE** if a matching entry exists AND that entry has a `pid` field present (any value, including a plain running-but-idle agent). The session is **NOT LIVE** if either no entry matches `IMPL_SESSION_ID` at all, or a matching entry exists but carries no `pid` field.

   Rationale: every observed entry with an attached OS process carries `pid`, regardless of its `status`/`state` (idle, done, blocked, and busy/working all still carry `pid` when live). Entries whose background job has genuinely exited (no process left, transcript persisted to disk only) omit `pid` entirely. This matched the `--resume` gate's own real behavior in every case tested — including a false-positive check: sessions with no `pid` (e.g. two older entries with just `"state": "blocked"` and nothing else) were never tested against `--resume` directly in this round, but their shape matches the "job fully exited" pattern, not the "process still alive" pattern of every session that empirically failed to resume.

4. Capture, for use in the branches below:
   - `AGENT_NAME` — the matching entry's `name` field (empty string if no match / not live).
   - `AGENT_PID` — the matching entry's `pid` (for logging only; do not act on it — see "What NOT to do" below).

## What NOT to do when LIVE

- Do **not** call `open-claude-session.sh ... --resume <IMPL_SESSION_ID> ...` — it is guaranteed to fail with the background-agent error.
- Do **not** retry with `--fork-session` as a silent fallback — that creates a different session than the one the operator has been working in, and the operator has explicitly said this should not happen automatically.
- Do **not** attempt to `kill` the pid and retry — confirmed above to just trigger a respawn of the same live session, not a release of it.
- Do **not** attempt to drive `claude agents` via scripted/blind keystrokes to attach or reply — unsafe, per the safety note above.

## Branch on the result

### NOT LIVE → resume normally (unchanged from before this check existed)

Proceed exactly as documented in the calling rule: `open-claude-session.sh <dir> --resume <IMPL_SESSION_ID> --prompt "<the prompt>"`. No other behavior change.

### LIVE → skip the resume; hand the operator a ready-made prompt instead

1. Append to `actionsTaken` (wording adapted per calling rule, but same shape): `"<Live QA kickoff | Review-comments auto-resume> skipped — session <IMPL_SESSION_ID> (\"<AGENT_NAME>\") is currently live as a background agent; auto-resume is not possible (see references/live-agent-check.md). Ready-made prompt below for you to paste in manually."`
2. Append to `REMINDERS` a self-contained, copy-paste-ready block naming the session and the exact prompt text that would otherwise have been sent:
   ```
   <TICKET-KEY>: session "<AGENT_NAME>" is live in the background — open `claude agents`, find it, press space to reply, and paste this prompt:

   <the exact prompt text the calling rule would have sent, e.g. "/e2e-test-jira-ticket TRIDENT-970 --live-qa" or "/review-pr-comments <PR URL> autonomous">
   ```
3. Skip the rest of the calling rule's step for this ticket this run — this is a terminal outcome, same tier as the existing "no-session fallback" and "open-claude-session failed" branches. Do not fall through to any resume attempt.

## Re-discovery procedure

If `claude agents --json`'s shape changes (e.g., `pid` renamed, or a differently-named liveness field introduced), re-verify empirically before trusting the new field: pick any known live session, kill its pid, and check whether `--resume` on that session id still fails afterward. Whatever field reliably distinguishes "still refused by --resume" from "resumes fine" is the correct LIVE test — update the check above to match.
