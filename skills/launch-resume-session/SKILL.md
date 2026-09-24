---
name: launch-resume-session
description: Looks up an existing ticket-driver, ticket-creation, spike-research, standalone-research, or operator-bookmarked "Saved Session" in ~/.claude/memory/sessions.md, checks whether it's still live in the background agent view, and — if not — resumes it in a NEW backgrounded Claude Code session with no new prompt or instruction at all, just picking the conversation back up in the background under a fresh display name like "TRIDENT-974 - CREATION", "TRIDENT-974 - DRIVER - WEBAPP" (repo code only on DRIVER, since one ticket can have a separate driver session per repo), "TRIDENT-949 - SPIKE", "RESEARCH - Mobile Finance CTA Flow - WEBAPP", or the saved session's own bookmark name, then auto-closes the now-idle launching terminal tab once the handoff completes. Takes a mandatory identifier — either a Jira ticket key (e.g. TRIDENT-974, for CREATION/DRIVER/SPIKE) or a short description; a description matches both "Research Agent: <description>" headings (standalone /research sessions, for RESEARCH) and "Saved Session: <name>" headings (operator bookmarks from save-session-info) — plus an optional session type (`CREATION`, `DRIVER`, `SPIKE`, or `RESEARCH`); when the type is omitted, the identifier's own shape picks the heading scheme(s) and presents every session found for the operator to pick from. Use when the operator asks to resume/reopen/relaunch/background a prior ticket-driver, ticket-creation, spike-research, research-agent, or saved-bookmark session, or runs `/launch-resume-session`. Do NOT use to start brand-new work — that's `/ticket-driver`, `/ticket-creator`, or `/research` directly, not this; this skill only ever resumes a session that already exists in sessions.md, and sends it no new instructions.
---

# Launch Resume Session (orchestrator)

Thin orchestrator. It writes no code and does no ticket work itself — it looks up a known session, checks it isn't already running, and opens a new backgrounded Claude Code session that resumes it with **zero new content**. All the actual ticket-driver/ticket-creation logic already happened in the session being resumed; this skill's only job is safely reopening that exact conversation in the background without creating a duplicate.

## Inputs

1. **Identifier (REQUIRED):** either a **Jira ticket key** (e.g. `TRIDENT-974` — matches `^[A-Z][A-Z0-9]*-\d+$` after uppercasing) or a **description** (free text — e.g. `"Mobile Finance CTA Flow"` or `"Combined Funnel CSRF Cookie Error"`). A description is matched against **both** `# Research Agent: <description>` headings (standalone `/research` sessions) **and** `# Saved Session: <name>` headings (operator bookmarks written by the `save-session-info` skill). If missing, ask for it before doing anything else. The identifier's shape determines which heading scheme(s) in `sessions.md` get searched — see Step 1.
2. **Session type (optional):** `CREATION`, `DRIVER`, `SPIKE`, or `RESEARCH`, case-insensitive standalone token.
   - `CREATION` matches subentries whose label starts with `ticket-creation` (covers `## ticket-creation` and variants like `## ticket-creation (artifact mode)`) — lives under a **ticket-key** heading.
   - `DRIVER` matches subentries whose label starts with `ticket-driver` (covers `## ticket-driver` and variants like `## ticket-driver (TODO mode)`) — lives under a **ticket-key** heading.
   - `SPIKE` matches subentries whose label *contains* `spike` anywhere (case-insensitive — covers observed variants `## spike review` and `## jira-sprint-manager (spike research worktree)`, which don't share a common prefix) — lives under a **ticket-key** heading.
   - `RESEARCH` matches subentries whose label starts with `research` (covers `## research`, from `/research`'s own self-logging) — lives under a **`Research Agent: <description>`** heading, never a ticket-key one.
   - There is **no explicit type token for `Saved Session` entries** — they carry no type label, so the operator can't request them by type. They're only discovered via the no-type description path (see below), never when a type is given.
   - **Type vs. identifier mismatch:** `CREATION`/`DRIVER`/`SPIKE` require a ticket-key-shaped identifier; `RESEARCH` requires a description (non-ticket-shaped) identifier. If the operator gives a ticket key with `RESEARCH`, or a description with any of the other three, stop and say so plainly — don't guess which one they actually meant (see Failure & fallback).
   - **If omitted:** don't guess a type, but the identifier's shape still narrows the search — a ticket-key-shaped identifier searches that ticket's heading for any of `CREATION`/`DRIVER`/`SPIKE`-flavored subentries (never `RESEARCH`, which can't live there); a description searches **both** `Research Agent:` heading(s) (for `RESEARCH` subentries) **and** `Saved Session:` heading(s) (operator bookmarks). Collect whatever's found across both schemes and let the operator pick. See Step 1.
   - **Note:** when the type *is* given as `RESEARCH`, only `Research Agent:` headings are searched — `Saved Session:` entries are excluded, since they have no type and the operator explicitly asked for a research session. `Saved Session:` entries are reached only via the no-type description path.

## Workflow

### Step 1 — Find the matching session(s) in sessions.md

**First, classify the identifier** (Input 1): uppercase it and check against `^[A-Z][A-Z0-9]*-\d+$`.
- **Matches → ticket-key lookup.** If a type was given, it must be `CREATION`, `DRIVER`, or `SPIKE` — if `RESEARCH` was given instead, stop and report the mismatch (see Failure & fallback). Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` — same convention `jira-sprint-manager` already uses. Collect every `##`-level subentry under that heading, up to the next H1 or EOF.
- **Does not match → description lookup (two schemes).** If a type was given, it must be `RESEARCH` — if `CREATION`/`DRIVER`/`SPIKE` was given instead, stop and report the mismatch.
  - **`Research Agent:` headings** — find every H1 line matching `# Research Agent: <description>` whose `<description>` contains the given identifier text (case-insensitive substring match — the operator won't necessarily know the exact computed phrase). Collect every `##`-level subentry (always `## research`) under each matching heading, up to its next H1 or EOF. Each such subentry is a **RESEARCH** candidate.
  - **`Saved Session:` headings** — *unless a `RESEARCH` type was explicitly given* (in which case skip this scheme entirely), also find every H1 line matching `# Saved Session: <name>` whose `<name>` contains the given identifier text (same case-insensitive substring rule). A `Saved Session:` entry has **no `##` subentry** — its fields (`session id:`, `directory:` (an absolute path, not a basename), `date:`) sit directly under the H1, up to the next H1 or EOF. Each matching heading is one **SAVED** candidate, labeled by its bookmark name.
  - Combine the candidates from both schemes for the dedup/disambiguation step.

**If no matching heading exists at all** (ticket-key case), or **no `Research Agent:` or `Saved Session:` heading matches** (description case), or a matching ticket/research heading has zero subentries: reply `"No sessions found in sessions.md for <identifier>."` and stop. Do not guess a session id or repo from anywhere else.

**Full matching, filtering, deduplication, and disambiguation rules — load [references/session-lookup.md](references/session-lookup.md).** Short version: filter by session type if one was given, collapse repeat re-runs of the same repo down to the most recent entry, and if more than one distinct candidate remains (including, in the description case, multiple different `Research Agent:` and/or `Saved Session:` headings whose text all matched), ask the operator which one via `AskUserQuestion`. If exactly one candidate remains after filtering/dedup, use it directly — no need to ask when there's nothing to disambiguate.

**If a type was given and zero subentries match it:** reply `"No <TYPE> session found for <identifier>. Sessions that do exist: <list the distinct labels found>."` and stop.

This step resolves exactly one `SESSION_ID` plus, depending on the candidate kind:
- **Ticket-key / research candidate** → one `REPO_DIR` (a basename, e.g. `webapp-react-trident-TRIDENT-974` or `bt-mobile-app-research-mobile-finance-cta-flow`), and — for the research case — the exact matched `SHORT_DESCRIPTION` (the heading's own description text, needed verbatim for Step 2.5).
- **SAVED candidate** → the absolute `directory:` value verbatim (used directly as `REPO_PATH` in Step 2, no basename resolution) and the exact `Saved Session:` bookmark name (used verbatim as `SESSION_NAME` in Step 2.5).

### Step 2 — Resolve the repo path

- **Ticket-key / research candidate:** `REPO_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<REPO_DIR>`
- **SAVED candidate:** `REPO_PATH = <directory>` — the `Saved Session:` entry's `directory:` field verbatim, which is already an absolute path (e.g. `/Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident`). Do **not** prepend the base dir or treat it as a basename.

**If `REPO_PATH` doesn't exist on disk** (worktree deleted/moved since the session was recorded): stop, report `"Session <SESSION_ID> for <identifier> was found, but its directory <REPO_PATH> no longer exists on disk — nothing to resume it in."` Do not create a new worktree — this skill only resumes, it never creates.

### Step 2.5 — Compute the session name

```
CREATION → SESSION_NAME = "<TICKET-KEY> - CREATION"
DRIVER   → SESSION_NAME = "<TICKET-KEY> - DRIVER - <REPO_CODE>"
SPIKE    → SESSION_NAME = "<TICKET-KEY> - SPIKE"
RESEARCH → SESSION_NAME = "RESEARCH - <SHORT_DESCRIPTION> - <REPO_CODE>"
SAVED    → SESSION_NAME = "<Saved Session bookmark name>"   (verbatim, no prefix/suffix)
```

**SAVED needs no computation** — a `Saved Session:` bookmark already carries the operator's own chosen display name in its heading; reuse it verbatim. There's no ticket key, repo code, or topic slug to derive, so skip the `REPO_CODE`/`BASE_REPO` steps below entirely for a SAVED candidate.

`CREATION` and `SPIKE` never get a repo suffix — a ticket only ever has one active creation/research line or one active spike line, so there's nothing to disambiguate. `DRIVER` always does, since one ticket commonly has a separate `ticket-driver` session per repo (e.g. `TRIDENT-972` has one for `webapp-react-trident` and one for `lambda-node-trident-partner-lender` — without the suffix, resuming either would produce an identically-named session). `RESEARCH` always does too, for the same reason `launch-research-agent` includes one in its own naming — this is deliberately the **exact same format** that skill uses, so a resumed research session's display name is indistinguishable from one freshly launched.

**Computing `REPO_CODE` for `DRIVER`:** first strip any ticket-specific suffix from `REPO_DIR` to get `BASE_REPO` — find the known repo name (from the list below) that `REPO_DIR` either equals exactly or starts with followed by a `-` (e.g. `webapp-react-trident-TRIDENT-971` → `BASE_REPO = webapp-react-trident`). If `REPO_DIR` doesn't match any known repo this way, fall back to using `REPO_DIR` itself as `BASE_REPO` (best effort for an unrecognized repo).

**Computing `REPO_CODE` for `RESEARCH`:** `REPO_DIR` follows `launch-research-agent`'s own worktree convention, `<MAIN_REPO>-research-<TOPIC_SLUG>` — split on the literal substring `-research-` and take everything before it as `BASE_REPO`. (This is a different split rule than `DRIVER`'s, deliberately — the known-repo prefix-match above doesn't cover every real repo, e.g. `bt-mobile-app`, so don't reuse it here; splitting on `-research-` is exact and doesn't depend on a hardcoded list.) If `REPO_DIR` doesn't contain `-research-` at all (malformed/unexpected data), fall back to using `REPO_DIR` itself as `BASE_REPO`.

Either way, apply the same repo→code mapping `jira-sprint-todo-loop`, `launch-research-agent`, and `launch-pr-review-agent` all already use:
- `webapp-react-trident` → `WEBAPP`
- `portal-react-boattrader` → `PRBT`
- any repo name containing `lambda` → `LAMBDA`
- any repo name containing `terraform` → `TERRAFORM`
- anything else → `BASE_REPO`'s own literal name

Known base repos (for `DRIVER`'s prefix-strip step): `portal-react-boattrader`, `portal-nextjs-platform`, `webapp-react-trident`, `api-node-boats`, `api-node-boattrader`, `boatsdotcom`, `lambda-node-trident-700credit`, `lambda-node-trident-advertised-rates`, `lambda-node-trident-portal-lead`, `lambda-node-trident-partner-lender`, `lambda-node-trident-services`, `pp-algorithm`, `configd`, `terraform-stack-trident`.

### Step 3 — Check whether it's already live in the background agent view

**This is not a single simple check — it's genuinely load-bearing.** Empirically confirmed (2026-07-31): calling `--resume <id> --prompt "/background"` twice on the same session id, with nothing in between, produces **two separate live background processes**, both anchored to the **same single transcript file** on disk, with no refusal or error from the CLI either time. This step exists specifically to prevent that.

**Do NOT reuse `jira-sprint-manager`'s `references/live-agent-check.md` verbatim** — that check matches purely on the `sessionId` field in `claude agents --all --json`, which silently misses a session that was already resumed-and-backgrounded once (the daemon assigns the backgrounded process a **fresh** tracking id, decoupled from the original conversation id, confirmed by checking that only one transcript file — under the *original* id — ever exists on disk).

**Also do NOT use pure cwd-matching** — a separate real-world gap: `sessions.md`'s `repo/dir` is not always a dedicated per-ticket directory. Some `ticket-creation` sessions are recorded against the shared main checkout (e.g. `webapp-react-trident`, no ticket suffix) or a generic scratch worktree reused across *multiple, unrelated* tickets (observed in real data: `webapp-react-trident-worktree-research` shared between TRIDENT-974 and TRIDENT-975). Matching by `cwd` alone there produces false positives against unrelated live sessions.

**Use the hybrid check instead — full detail in [references/live-agent-check.md](references/live-agent-check.md).** Summary: check whether `REPO_DIR` contains the relevant **identifying token** as a substring — for `CREATION`/`DRIVER`/`SPIKE` that's `TICKET_KEY`; for `RESEARCH` it's `TOPIC_SLUG` (`SHORT_DESCRIPTION` lowercased with spaces/punctuation replaced by hyphens — the same slugging `launch-research-agent` does for its own worktree path).

- **Contains the identifying token (dedicated directory)** → check liveness by `cwd` match in `claude agents --all --json` (safe here — nothing else legitimately shares this exact directory).
- **Does NOT contain it (shared directory)** → check liveness by exact `sessionId` match only. If no match, **do not conclude NOT LIVE and proceed** — report that liveness can't be reliably confirmed in a shared directory, and hand the operator a ready-made `claude --resume` command to run themselves after checking `claude agents` on their own. This is a terminal outcome for this branch.

**SAVED candidates** have no identifying token (no ticket key or topic slug) and their `directory:` is frequently a shared checkout (e.g. the main `webapp-react-trident`), so the cwd-match branch above never applies. Check liveness by **exact `sessionId` match only** in `claude agents --all --json`:
- **`sessionId` matches (LIVE)** → reply plainly that the session is still active under the agent view (name it) and stop — do not attempt to resume.
- **No match (treat as NOT LIVE)** → proceed to Step 4 and resume it. Unlike the shared-directory branch above, a SAVED candidate *does* proceed on a no-match — the operator named this specific bookmark and resuming it is the whole point of the feature. **Caveat to include in the Step 5 report:** if this bookmark's `directory:` is a shared checkout *and* it had already been resumed-and-backgrounded through this skill once before, the daemon would have given that process a fresh tracking id, so a `sessionId`-only check could miss it — advise the operator to glance at the agent view to confirm a duplicate isn't already running.

In either ticket-specific or shared branches: **LIVE** → reply plainly that the session is still active under the agent view (name it) and stop — do not attempt to resume. **NOT LIVE** (ticket-specific branch, or SAVED no-match) → proceed to Step 4.

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

State plainly: the identifier (ticket key or description), the session kind resolved — `CREATION`/`DRIVER`/`SPIKE`/`RESEARCH`, or **SAVED** for a `Saved Session:` bookmark — (and whether a type was given or the candidate was picked by the operator), the repo/directory, the `SESSION_ID` resumed, the `SESSION_NAME` it was resumed under, and the helper script's own result line (resumed-and-auto-closed vs. left open because no handoff was detected in time). **For a SAVED candidate in a shared checkout, also include the Step 3 caveat** (sessionId-only liveness could miss an already-backgrounded duplicate — advise a glance at the agent view).

## Failure & fallback

- No identifier given → ask for one; do not guess.
- Identifier/type mismatch (a ticket key with `RESEARCH`, or a description with `CREATION`/`DRIVER`/`SPIKE`) → say so plainly and explain which identifier shape that type actually needs; do not silently reinterpret the operator's input as the other kind.
- No heading / no subentries matching the identifier in sessions.md (no ticket-key heading, and in the description case no `Research Agent:` *or* `Saved Session:` heading) → say so plainly; do not fall back to guessing a session id from anywhere else (git branches, PR titles, etc.).
- A type was given but nothing matches it → say so, and list what session types *do* exist for that identifier so the operator can retry correctly.
- More than one candidate remains after filtering/dedup → ask via `AskUserQuestion`, never guess which repo/session (or, in the research case, which matching heading) the operator meant.
- `REPO_PATH` doesn't exist on disk → stop, report; this skill never creates worktrees.
- Session is LIVE per Step 3 → stop, report it's active; never attempt a resume on a live session (this is the exact failure mode Step 3 exists to prevent — a second process writing to the same transcript concurrently).
- `REPO_DIR` is a shared/non-ticket-specific directory and no `sessionId` match was found → do not proceed automatically; hand the operator a ready-made `claude --resume` command to run themselves after they've checked `claude agents` on their own (see Step 3 / references/live-agent-check.md).
- `open-claude-session.sh` exits non-zero → report the verbatim failure.
- Auto-close times out (left tab open) → `open-claude-session.sh` now self-diagnoses this (fixed 2026-08-03): it captures the tab's last few non-empty lines of output and prints them alongside the timeout message, so you don't need to manually cross-check `claude agents --all --json` against `ps aux` to figure out what happened — read the printed tail directly. A real error there (e.g. "No conversation found", "command not found") means the resume itself failed, not just a slow startup. If the tail is unreadable or absent, or you still can't tell, that's the point where manual cross-checking remains a legitimate fallback.
- Separately: the launching tab's own keystroke-injection race (an operator's in-flight typing landing inside the injected command and corrupting it — the original motivation for the fixes above) has been fixed at the source in `open-claude-session.sh` by removing its focus-stealing `activate` call. This was root-caused and verified empirically, not just theorized — see that script's own header/inline comments for the full account.

## Non-goals

- Do not start new ticket-driver, ticket-creation, or research work — that's `/ticket-driver` / `/ticket-creator` / `/research` directly, not this skill. This skill only resumes a session that's already recorded in sessions.md.
- Do not send any real instruction/prompt into the resumed session — the bare `/background` in Step 4 is intentional and load-bearing; appending anything after it would turn this into a "resume and give it a new task" skill, which is not what this is.
- Do not reuse `jira-sprint-manager`'s sessionId-based live-agent-check for this skill's Step 3 verbatim, and do not use pure cwd-matching either — see that step's rationale and references/live-agent-check.md; each is unreliable on its own, for two separate, empirically-confirmed reasons.
- Do not treat a shared/non-ticket-specific `REPO_DIR` as "probably fine, just check cwd anyway" — see Step 3's SHARED branch; that's precisely the case that produces false positives.
- Do not create a worktree if `REPO_PATH` is missing — report and stop instead.
