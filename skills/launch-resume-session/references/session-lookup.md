# Session lookup, filtering, deduplication, and disambiguation

Used by `launch-resume-session` Step 1. Full detail behind the summary in SKILL.md.

## Finding the ticket's block

`~/.claude/memory/sessions.md` is organized as one H1 heading per ticket (newest-first overall), each followed by zero or more `##`-level subentries (also newest-first within the ticket). Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` (case-sensitive on the key itself — Jira keys are always uppercase, e.g. `TRIDENT-974`). Collect every `##` subentry between that heading and the next H1 (or EOF).

Each subentry has this shape:
```
## <label>
- session id: <uuid>
- repo/dir: <basename>
- date: <YYYY-MM-DD>
- notes: <optional free text>
- jira: <optional URL>
- artifact: <optional URL>
```

`<label>` examples seen in practice: `ticket-creation`, `ticket-creation (artifact mode)`, `ticket-driver`, `ticket-driver (TODO mode)`, `jira-sprint-manager (spike research worktree)`. There is no fixed enum — treat it as free text and match by prefix (see below), not exact string equality, since parenthetical suffixes vary.

## Filtering by session type (when one was given)

- `CREATION` → keep subentries whose `<label>` starts with `ticket-creation` (case-insensitive).
- `DRIVER` → keep subentries whose `<label>` starts with `ticket-driver` (case-insensitive).

Anything else (e.g. a `jira-sprint-manager (...)` subentry) never matches either type — it's simply excluded from consideration when a type is given. It's still included in the "no type given, show everything" path (see below).

## Deduplication — collapse repeat runs of the same repo

A ticket can be re-driven or re-created over time in the *same* repo (retries, follow-up passes), producing multiple subentries with the same `repo/dir` but different session ids and dates. Since sessions.md is newest-first within a ticket, **keep only the topmost (most recent) subentry per distinct `repo/dir` value** among whatever survived the type filter above. This mirrors the exact convention `jira-sprint-manager`'s Rule C already uses ("the topmost `## ticket-driver` subentry is the most recent implementation session").

## Multi-repo tickets are a real, expected case — not an error

A single ticket frequently spans multiple repos (e.g. `TRIDENT-972` has separate `## ticket-driver` subentries for `webapp-react-trident-TRIDENT-972` and `lambda-node-trident-partner-lender-TRIDENT-972` — two genuinely different, independently resumable sessions, both legitimately labeled `ticket-driver`). Passing a session type alone does **not** disambiguate between repos — there is no repo argument to this skill. After filtering + dedup, however many distinct `repo/dir` candidates remain is exactly how many options exist.

## Resolving to exactly one candidate

- **0 candidates** (after type filter, if one was given): report per SKILL.md's Step 1 "zero match" message and stop.
- **1 candidate**: use it directly. Do not ask a question when there's nothing to disambiguate — and note that `AskUserQuestion` itself requires at least 2 options, so a single-candidate case couldn't be asked about even if it seemed safer to confirm.
- **2+ candidates** (whether because no type was given and multiple types/repos exist, or because a type *was* given but spans multiple repos): ask via `AskUserQuestion`, one option per candidate — `label` = `<repo/dir> — <label>` (e.g. `webapp-react-trident-TRIDENT-972 — ticket-driver`), `description` = the `date` plus a truncated `notes` excerpt if present. Cap at 4 options (the tool's max) — if a ticket somehow has more than 4 distinct candidates, present the 4 most recent and mention in your own text that older/additional ones exist and can be targeted by asking again more specifically.

## Worked example

`TRIDENT-972`'s block (abridged):
```
## ticket-driver
- session id: b62b1073-9dee-4b84-bbaf-72807349ad07
- repo/dir: webapp-react-trident-TRIDENT-972
- date: 2026-07-14

## ticket-driver
- session id: 8ab55560-47e7-4d9c-9212-6948a30536d5
- repo/dir: lambda-node-trident-partner-lender-TRIDENT-972
- date: 2026-07-14

## ticket-creation
- session id: fc7e776c-0dfb-41a2-97a5-962ecbb22a6d
- repo/dir: terraform-stack-trident-TRIDENT-918
- date: 2026-07-13
```

- Operator asks for `TRIDENT-972 DRIVER` → filter to the two `ticket-driver` subentries (both survive dedup — different repos) → 2 candidates → ask which repo.
- Operator asks for `TRIDENT-972 CREATION` → filter to the one `ticket-creation` subentry → 1 candidate → use it directly, no question asked.
- Operator asks for bare `TRIDENT-972` (no type) → all three subentries survive (different labels AND different repos, so dedup collapses nothing) → 3 candidates → ask which one.
