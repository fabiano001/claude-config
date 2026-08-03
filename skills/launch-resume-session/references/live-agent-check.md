# Live-agent check (revised — hybrid, not pure cwd-matching)

Used by `launch-resume-session` Step 3, right after resolving `REPO_PATH` and before any `--resume` attempt.

## History of this check (read this before "simplifying" it back)

**First design (sessionId-matching, copied from `jira-sprint-manager`):** rejected. Empirically found (2026-07-31) that resuming a session and then backgrounding it (`--resume <id> --prompt "/background"`) gets tracked in `claude agents --all --json` under a **freshly-minted daemon id**, decoupled from the original conversation id — even though the transcript file on disk stays keyed to the original id the whole time. Matching on `sessionId` would silently report "not live" for a session that had already been resumed-and-backgrounded once, since the live entry's `sessionId` never again equals the id recorded in `sessions.md`.

**Second design (pure cwd-matching):** also rejected, for a *different* reason a user caught in real usage: `sessions.md`'s `repo/dir` field is not always a dedicated per-ticket directory. Some session types (especially `ticket-creation`) get recorded against the **shared main checkout** (e.g. `repo/dir: webapp-react-trident`, no ticket suffix) or a **generic, non-ticket-specific scratch worktree reused across multiple tickets** (e.g. `repo/dir: webapp-react-trident-worktree-research` — observed shared between TRIDENT-974 and TRIDENT-975, two unrelated tickets, in real production `sessions.md` data). Matching purely on `cwd` in that case produces false positives: any unrelated live session that happens to share that same shared/generic directory gets mistaken for a live copy of *this* target session.

**Third, empirically-confirmed risk that makes this check load-bearing, not just theoretical:** on 2026-07-31, deliberately called `open-claude-session.sh <dir> --resume <same-id> --prompt "/background"` **twice in a row** on the same original session id. Both calls succeeded with no error or refusal from the CLI. `claude agents --all --json` afterward showed **two separate live processes**, each with its own distinct daemon-assigned id, both sharing the same `cwd` — and only **one** transcript file existed on disk for both of them. There is no built-in guard against double-resuming the same session — this skill's own Step 3 is the only thing standing between a repeat invocation and two processes appending to the same transcript file concurrently.

## The hybrid check

### Step A — classify `REPO_PATH` as ticket-specific or shared

Check whether `REPO_DIR`'s basename **contains the literal `TICKET_KEY` string as a substring** (e.g. does `webapp-react-trident-TRIDENT-971` contain `TRIDENT-971`? Yes.). This is the actual dividing line found in real data — not "does it look like a worktree path":

- **Contains the ticket key → TICKET-SPECIFIC.** Nothing else has a legitimate reason to run in a directory named after this exact ticket. Proceed to Step B (cwd-matching; safe here).
- **Does NOT contain the ticket key → SHARED.** Covers both the bare main-checkout case (`webapp-react-trident`) and the generic-scratch-worktree case (`webapp-react-trident-worktree-research`, reused across unrelated tickets in observed real data). Skip Step B — go directly to Step C.

### Step B — TICKET-SPECIFIC: check liveness by `cwd`

Run `claude agents --all --json`. Find any entry whose `cwd` field exactly equals `REPO_PATH`. **LIVE** if a matching entry exists and carries a `pid` field. **NOT LIVE** otherwise. This is safe here because the directory is provably unique to this one ticket — proceed to Step 4 (resume) if NOT LIVE, or report active-in-agent-view and stop if LIVE.

### Step C — SHARED: check liveness by `sessionId` only, and refuse to guess beyond that

`cwd`-matching is unsafe here (too many unrelated sessions could share the directory). Fall back to matching `claude agents --all --json`'s `sessionId` field against the exact known `SESSION_ID` from `sessions.md` — zero false positives, but it can miss a session that was already resumed-and-backgrounded once before (see "First design" above).

- **`sessionId` matches, with a `pid`** → LIVE. Report active-in-agent-view and stop, same as Step B's LIVE branch.
- **No `sessionId` match** → **do not conclude NOT LIVE and proceed automatically.** The directory is shared, so the absence of a `sessionId` match is not strong enough evidence that no derived-id copy is running there. Instead: report that `REPO_DIR` (`<value>`) is a shared/non-ticket-specific directory, liveness for this exact session cannot be reliably confirmed automatically, and hand the operator a ready-made command to run themselves after checking `claude agents` on their own:
  ```
  <TICKET-KEY> (<TYPE>): repo/dir "<REPO_DIR>" is shared across multiple tickets/sessions, not dedicated to this one — I can't safely confirm whether session <SESSION_ID> is already running there in the background. Please check `claude agents` yourself, then if it's clear, run:

  cd <REPO_PATH> && claude --resume <SESSION_ID> "/background"
  ```
  This is a terminal outcome for this ticket this run — do not attempt the resume yourself in this branch.

## What NOT to do

- Do not classify by "does the path look like a worktree" (contains a hyphen, contains "research", etc.) — the actual, verified dividing line is whether the ticket key itself appears in the path. Guessing from shape alone would have still misclassified the `webapp-react-trident-worktree-research` shared case.
- Do not silently fall back to cwd-matching for the SHARED case "since it's probably fine most of the time" — the whole reason this branch exists is that it demonstrably isn't reliable there.
- Do not treat a single failed double-resume test as a fluke and skip Step C's caution "since it probably won't happen in practice" — it reproduced on the very first deliberate attempt, with no special conditions.

## Re-verification procedure

If `claude agents --json`'s shape changes, or if `sessions.md`'s `repo/dir` convention changes (e.g. `ticket-creation` starts always using dedicated directories), re-run the double-resume test on a disposable session before trusting any simplification of this check.
