---
name: launch-research-agent
description: Launches a NEW, SEPARATE background Claude Code session that runs `/research` against a given repo (or repos), instead of running the research inline in the current conversation — the current session stays free while the research runs elsewhere, visible in the agent view under a name like "RESEARCH - Loan Approval Flow - WEBAPP". Takes two mandatory arguments — the repo(s) to research (first one is the "main" repo for naming/worktree purposes) and a research description (a sentence, a paragraph, or multiple paragraphs) — plus an optional `USE-OPUS` token to pin the launched session to Opus 4.8 instead of its default model, plus any extra `/research` modifier phrases (e.g. `inline output`), which are forwarded through verbatim. Use when the operator asks to launch/kick off/background a research task, or run `/launch-research-agent`. Do NOT use when the operator wants the research to run right here and see the result immediately — that's `/research` directly, not this.
---

# Launch Research Agent (orchestrator)

Thin orchestrator. It does no research itself — it derives a session name, resolves (or creates) a dedicated worktree so it can't collide with another launch, and opens a new backgrounded Claude Code session whose first message is `/background /research <description> repos involved: <repos> [<passthrough args>]`. All research logic belongs to `/research`; this skill's only job is getting a correctly-named, correctly-backgrounded session started without stepping on another one.

## Inputs

1. **Repo(s) to research (REQUIRED):** one or more repo identifiers (e.g. `webapp-react-trident`). If more than one is given, the research likely spans multiple repos — use the **first one given** as `MAIN_REPO` for naming and worktree purposes; carry the full list through verbatim into the launched prompt (see Step 5).
2. **Research description (REQUIRED):** free text describing what to research — a sentence, a paragraph, or several. This becomes (most of) the prompt `/research` receives.
3. **Passthrough args (optional):** any other `/research` modifier phrase the operator includes (e.g. `inline output` / `output inline` — `/research`'s actual recognized phrase for its inline mode; a bare word like "INLINE" is NOT recognized by `/research`, so if the operator wants that mode, use the real phrase). Forward whatever's given verbatim — this skill doesn't interpret or validate it.
4. **`USE-OPUS` (optional):** a literal standalone token, case-insensitive (matches `USE-OPUS`/`Use-Opus`/`use-opus` as its own word, not a substring of something else) — same detection style as `review-pr`'s `FULL` token. Present → the launched session is pinned to `claude-opus-4-8` (the same Opus 4.8 model string used elsewhere in this repo, e.g. `code-review-specialist`) instead of whatever it would otherwise default to. Absent → don't pass any `--model` override at all; let the session default normally. **This token is consumed by this skill, not forwarded to `/research`** — strip it out before treating the remainder of the operator's input as passthrough args (Input 3).

**Parsing heuristic (no rigid delimiter required, but disambiguate if asked to):** the repo(s) are short, identifier-shaped tokens (e.g. `webapp-react-trident`, no spaces) that normally appear at the very start of the input; the research description is everything after them, up to a trailing recognized `/research` modifier phrase if one is present. If the operator explicitly labels sections (e.g. `Repos:` / `Research:`), respect those labels over positional guessing. If it's genuinely ambiguous where the repo list ends and the description begins, ask for an explicit label rather than guessing.

## Workflow

### Step 1 — Resolve `MAIN_REPO` and the full repo list

Take the first repo token as `MAIN_REPO`. Keep the **full list exactly as the operator typed it** (don't reformat, reorder, or validate against a known-repo list — this skill accepts any repo, known or not) — call this verbatim text `REPOS_TEXT`; it's reused as-is in Step 5's prompt.

### Step 2 — Compose `TOPIC`

Read the research description and compose a short phrase capturing its essence — **your own judgment call, not a mechanical extraction.** Max 5 words, ideally 3. Title Case (e.g. `Loan Approval Flow`, `Kameleoon Flag Timing`, `Webhook Retry Logic`). This is exactly the kind of phrase a person would use to label the session in their own head — favor clarity over cleverness.

### Step 3 — Compute `REPO_CODE` from `MAIN_REPO`

Same mapping `jira-sprint-todo-loop` already uses for its own session naming:
- `webapp-react-trident` → `WEBAPP`
- `portal-react-boattrader` → `PRBT`
- any repo name containing `lambda` → `LAMBDA`
- any repo name containing `terraform` → `TERRAFORM`
- anything else → the repo's own literal name (e.g. `configd`, `pp-algorithm`, or an unrecognized repo — whatever `MAIN_REPO` actually is)

### Step 4 — Build `SESSION_NAME`

```
RESEARCH - <TOPIC> - <REPO_CODE>
```
Exactly this literal format, spaces included — e.g. `RESEARCH - Loan Approval Flow - WEBAPP`.

### Step 5 — Resolve a dedicated worktree (avoids a real tab-collision bug)

**Do NOT open the new session directly in the shared main checkout** (e.g. `~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO>`). Here's exactly why: `~/.claude/skills/jira-sprint-manager/open-claude-session.sh` (the helper this skill uses to open the tab) has iTerm2 tab-reuse detection keyed **purely on the target directory's basename**. If two different research launches both targeted the same shared repo directory, the second launch would silently focus the first one's tab instead of opening a new one — its prompt would never get submitted at all. This is the same collision `launch-pr-review-agent` and `jira-sprint-todo-loop` already had to design around.

**The fix:** a dedicated worktree, unique per repo **and** topic (unlike a PR or a Jira ticket, a research topic has no natural numeric ID, so use a slug of `TOPIC` instead):

```
TOPIC_SLUG = <TOPIC lowercased, spaces/punctuation replaced with hyphens>   e.g. "loan-approval-flow"
RESEARCH_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO>-research-<TOPIC_SLUG>
```

- **If `RESEARCH_PATH` already exists** (the exact same repo+topic was launched before): reuse it as-is — don't recreate it. `open-claude-session.sh`'s own tab-reuse logic will then correctly focus that existing tab instead of duplicating it, which is the right behavior for a genuine repeat of the same topic.
- **If it doesn't exist**, and the main checkout `~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO>` does exist: create it as a **detached-HEAD** worktree off a fresh `main` (research is read-only — no branch needed, and `main` is very likely already checked out in the main checkout itself, so it can't be checked out again as a *branch* in a second worktree):
  ```bash
  git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO> fetch origin main
  git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO> worktree add ~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO>-research-<TOPIC_SLUG> --detach origin/main
  ```
- **If the main checkout doesn't exist at all** (repo never cloned locally): stop and tell the operator to clone `<MAIN_REPO>` to `~/BOATS-GROUP-PROJECTS-GITHUB/<MAIN_REPO>` first — this skill doesn't clone repos on its own.

### Step 6 — Build the launched prompt

```
/background /research <research description> repos involved: <REPOS_TEXT> <passthrough args, if any>
```

- `/background` is mandatory — in this environment a session only lands in the backgrounded agent view when `/background` is the literal first word of its submitted prompt; there's no other mechanism.
- `repos involved: <REPOS_TEXT>` is informational context appended to the topic so the research agent knows which repo(s) are actually in scope, verbatim as the operator listed them — `/research` has no dedicated "repos" input field, so this rides along as part of the free-text topic/description it already accepts.
- Passthrough args (Step 3 of Inputs) go at the very end, exactly as given.

### Step 7 — Launch

```bash
~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
  <RESEARCH_PATH> \
  --prompt "<prompt from Step 6>" \
  --session-name "<SESSION_NAME from Step 4>" \
  --auto-close-on-background \
  [--model claude-opus-4-8]
```

The `--model` flag is only included when the `USE-OPUS` token (Input 4) was present in the operator's request — omit it entirely otherwise, don't pass an empty or default value.

**Why `--auto-close-on-background`:** once `/research` hands off to `/background`, the launched tab's `claude` process exits and the tab just sits idle forever with nothing left to do — this flag has `open-claude-session.sh` watch for that handoff (Claude Code's own `backgrounded ·` completion line) and close the now-idle tab automatically, within a bounded ~20s window. If the handoff is never detected in time (e.g. the dispatched `/research` errored before backgrounding), the tab is deliberately left open so the operator can see why. Same mechanism `launch-pr-review-agent` already uses — see `open-claude-session.sh`'s own header comment for the full detail.

**If this exits non-zero:** report the failure verbatim — don't retry silently, don't fall back to running the research inline in the current session instead (that would silently change what the operator asked for).

### Step 8 — Report back

State plainly: the repo(s) being researched, the composed `TOPIC` and `REPO_CODE`, the resulting `SESSION_NAME`, whether `USE-OPUS` was requested (and therefore `claude-opus-4-8` was pinned), the `RESEARCH_PATH` used (new worktree vs. reused existing one), and the helper script's own result line (new tab opened and later auto-closed after the `/background` handoff vs. left open because no handoff was detected in time vs. an existing tab focused for a genuine repeat of the same topic).

## Failure & fallback

- Either mandatory input missing (no repo, or no research description) → ask for it; do not guess.
- Main checkout for `MAIN_REPO` doesn't exist locally → stop, ask the operator to clone it first.
- `git fetch`/`git worktree add` fails → report the verbatim error; don't fall back to the shared checkout directory (that reintroduces the collision risk Step 5 exists to avoid).
- `open-claude-session.sh` exits non-zero → report the verbatim failure; the operator can retry or open the session manually.

## Non-goals

- Do not perform any research here — no exploring the codebase, no writing the research file, no publishing the Artifact. All of that belongs to `/research`, running inside the launched session, not this one.
- Do not skip the `/background` prefix "since the operator didn't say it explicitly" — see Step 6; omitting it defeats the purpose of this skill.
- Do not reuse the shared main-checkout directory as a shortcut — see Step 5; it causes silent cross-launch collisions.
- Do not "fix" a bare `INLINE`-style passthrough arg into `/research`'s real `inline output` phrase on the operator's behalf — forward it exactly as given (see Inputs). If it's clearly a typo for the real phrase, mention that to the operator rather than silently substituting.
