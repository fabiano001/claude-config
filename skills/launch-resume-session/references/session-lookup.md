# Session lookup, filtering, deduplication, and disambiguation

Used by `launch-resume-session` Step 1. Full detail behind the summary in SKILL.md.

## Three heading schemes, picked by the identifier's shape

`~/.claude/memory/sessions.md` has three independent heading conventions living in the same file:

1. **Ticket-key headings** — `# <TICKET-KEY>` or `# <TICKET-KEY> (...)`, one per Jira ticket. Carries `CREATION`/`DRIVER`/`SPIKE`-flavored subentries. Searched when the identifier is ticket-key-shaped.
2. **Research-description headings** — `# Research Agent: <description>`, one per standalone `/research` topic (never tied to a ticket). Carries only `RESEARCH`-flavored (`## research`) subentries. Searched when the identifier is a description.
3. **Saved-Session headings** — `# Saved Session: <name>`, one per operator bookmark written by the `save-session-info` skill. Carries **no `##` subentry** — its fields sit directly under the H1. Has no session type. Searched when the identifier is a description (alongside scheme 2), *unless* an explicit `RESEARCH` type was given, which restricts to scheme 2 only.

Classify the given identifier first (uppercase it, test against `^[A-Z][A-Z0-9]*-\d+$`): ticket-key-shaped → scheme 1; anything else (a description) → schemes 2 **and** 3 combined. See SKILL.md Step 1.

## Finding the ticket's block (ticket-key identifier)

Find the H1 line matching `# <TICKET-KEY>` (exact) or `# <TICKET-KEY> (...)` (case-sensitive on the key itself — Jira keys are always uppercase, e.g. `TRIDENT-974`). Collect every `##` subentry between that heading and the next H1 (or EOF).

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

`<label>` examples seen in practice: `ticket-creation`, `ticket-creation (artifact mode)`, `ticket-driver`, `ticket-driver (TODO mode)`, `jira-sprint-manager (spike research worktree)`, `spike review`. There is no fixed enum — treat it as free text and match by prefix or substring (see below), not exact string equality, since parenthetical suffixes and phrasing vary.

## Finding the description blocks (description identifier — two schemes)

A description identifier searches **both** the research and saved-session schemes and combines the results.

### Research Agent headings

Scan every `# Research Agent: <description>` heading in the file. Keep the ones whose `<description>` contains the given identifier text as a case-insensitive substring — the operator is very unlikely to type back the exact computed phrase, so this must be forgiving, not an exact match. Collect the `## research` subentry (or subentries, if the same short description was reused across multiple separate research runs) under each matching heading, same shape as above minus `notes`/`jira`/`artifact` (those fields aren't part of `/research`'s own logging format). Each is a **RESEARCH** candidate.

If more than one distinct `Research Agent:` heading matches the given text, treat each one as its own candidate in the disambiguation step below — labeled by its full description, not collapsed together.

### Saved Session headings

*Skip this scheme entirely if an explicit `RESEARCH` type was given* — a typed request means the operator wants a research session, and saved sessions have no type.

Otherwise scan every `# Saved Session: <name>` heading. Keep the ones whose `<name>` contains the given identifier text as a case-insensitive substring (same forgiving rule). A saved-session entry has **no `##` subentry** — its fields sit directly under the H1, up to the next H1 or EOF:
```
# Saved Session: <name>

- session id: <uuid>
- directory: <absolute path, e.g. /Users/.../BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident>
- date: <YYYY-MM-DD>
```
Each matching heading is one **SAVED** candidate. Note the two structural differences from the other schemes: (1) the location is `directory:` — an **absolute path**, used verbatim as `REPO_PATH`, not a `repo/dir:` basename to resolve under `~/BOATS-GROUP-PROJECTS-GITHUB/`; (2) there is no `## label` line, so there's nothing to type-filter and no per-run subentries — one heading = one candidate.

## Filtering by session type (when one was given)

- `CREATION` → keep subentries whose `<label>` starts with `ticket-creation` (case-insensitive). Ticket-key headings only.
- `DRIVER` → keep subentries whose `<label>` starts with `ticket-driver` (case-insensitive). Ticket-key headings only.
- `SPIKE` → keep subentries whose `<label>` **contains** `spike` anywhere (case-insensitive) — deliberately a substring match, not a prefix match, since observed real labels don't share a common prefix (`spike review` vs. `jira-sprint-manager (spike research worktree)`). Ticket-key headings only.
- `RESEARCH` → keep subentries whose `<label>` starts with `research` (case-insensitive — matches `## research`). Research-description headings only, and **exclude `Saved Session:` headings entirely** (they have no type).

Saved sessions carry **no type label**, so type filtering doesn't apply to them — they can only ever appear on the no-type description path. When any type is given, drop them from consideration.

Anything that doesn't match the requested type is simply excluded from consideration when a type is given. It's still included in the "no type given, show everything (within the identifier's own heading scheme(s))" path (see below).

## Deduplication — collapse repeat runs of the same repo

A ticket can be re-driven or re-created over time in the *same* repo (retries, follow-up passes), producing multiple subentries with the same `repo/dir` but different session ids and dates. Since sessions.md is newest-first within a ticket, **keep only the topmost (most recent) subentry per distinct `repo/dir` value** among whatever survived the type filter above. This mirrors the exact convention `jira-sprint-manager`'s Rule C already uses ("the topmost `## ticket-driver` subentry is the most recent implementation session").

**Saved sessions don't need this dedup.** `save-session-info` already refuses to write a second entry for a session id that's already bookmarked, so each `Saved Session:` heading is a distinct bookmark. Treat every matching `Saved Session:` heading as its own candidate, keyed by its bookmark `<name>` — do not collapse two differently-named bookmarks even if they happen to point at the same `directory:`.

## Multi-repo tickets are a real, expected case — not an error

A single ticket frequently spans multiple repos (e.g. `TRIDENT-972` has separate `## ticket-driver` subentries for `webapp-react-trident-TRIDENT-972` and `lambda-node-trident-partner-lender-TRIDENT-972` — two genuinely different, independently resumable sessions, both legitimately labeled `ticket-driver`). Passing a session type alone does **not** disambiguate between repos — there is no repo argument to this skill. After filtering + dedup, however many distinct `repo/dir` candidates remain is exactly how many options exist.

## Resolving to exactly one candidate

- **0 candidates** (after type filter, if one was given): report per SKILL.md's Step 1 "zero match" message and stop.
- **1 candidate**: use it directly. Do not ask a question when there's nothing to disambiguate — and note that `AskUserQuestion` itself requires at least 2 options, so a single-candidate case couldn't be asked about even if it seemed safer to confirm.
- **2+ candidates** (whether because no type was given and multiple types/repos exist, or because a type *was* given but spans multiple repos, or because a description matched across both the research and saved-session schemes): ask via `AskUserQuestion`, one option per candidate — `label` = `<repo/dir> — <label>` (e.g. `webapp-react-trident-TRIDENT-972 — ticket-driver`), `description` = the `date` plus a truncated `notes` excerpt if present. Cap at 4 options (the tool's max) — if there are somehow more than 4 distinct candidates, present the 4 most recent and mention in your own text that older/additional ones exist and can be targeted by asking again more specifically.
  - **Research case specifically:** when multiple different `Research Agent:` headings matched the given text (not just multiple subentries under one heading), label each option by its **full heading description**, not `repo/dir` — e.g. `Mobile Finance CTA Flow — research` vs. `Mobile Finance Onboarding — research` — since the description is what actually distinguishes them to the operator; `repo/dir` alone might not (two different research topics can share the same base repo).
  - **Saved-session case specifically:** label each `SAVED` option by its **bookmark name** with a `— saved session` suffix so its kind is unmistakable — e.g. `Combined Funnel CSRF Cookie Error — saved session` — and set `description` to the `date` plus the `directory:` basename (so a shared-checkout bookmark is visible as such). A description that matched **both** schemes at once (e.g. one `Research Agent:` heading and one `Saved Session:` heading) presents them side by side as distinct options, each with its scheme-appropriate label.

## Worked example — research description

A `sessions.md` entry:
```
# Research Agent: Mobile Finance CTA Flow

## research
- session id: 6150c0e1-9792-464d-abc0-87fb274305fc
- repo/dir: bt-mobile-app-research-mobile-finance-cta-flow
- date: 2026-08-18
```

- Operator asks for `"Mobile Finance CTA Flow"` (no type) → identifier isn't ticket-key-shaped → research lookup → one heading matches → its one `## research` subentry → 1 candidate → use directly.
- Operator asks for `"mobile finance"` → still matches the same heading (case-insensitive substring) → same result.
- Operator asks for `"Mobile Finance CTA Flow" DRIVER` → type/identifier mismatch (`DRIVER` needs a ticket key) → stop, report the mismatch, don't guess.

## Worked example — saved session

A `sessions.md` entry (written by `save-session-info`):
```
# Saved Session: Combined Funnel CSRF Cookie Error

- session id: 33f64fe9-967a-432c-933f-659796b6c62a
- directory: /Users/fabianodesouza/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident
- date: 2026-09-10
```

- Operator asks for `"Combined Funnel CSRF Cookie Error"` (no type) → not ticket-key-shaped → description lookup across schemes 2 and 3 → no `Research Agent:` heading matches, one `Saved Session:` heading matches → 1 SAVED candidate → use directly. Step 2: `REPO_PATH` = the `directory:` verbatim. Step 2.5: `SESSION_NAME` = `"Combined Funnel CSRF Cookie Error"`. Step 3: `directory:` is the shared main checkout → sessionId-only liveness; no match → proceed and resume (with the shared-checkout caveat in the report).
- Operator asks for `"CSRF"` → same heading matches (case-insensitive substring) → same result.
- Operator asks for `"Combined Funnel CSRF Cookie Error" RESEARCH` → `RESEARCH` type restricts to scheme 2 only; the saved session is excluded; no `Research Agent:` heading matches → `"No sessions found in sessions.md for Combined Funnel CSRF Cookie Error."`

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
