---
name: review-pr
description: Runs a critique review of a GitHub PR via the `code-review-specialist` agent (severity-tiered findings — security/correctness/performance/etc.) and, by default, ONLY that. Pass the literal argument `FULL` (e.g. `/review-pr FULL <PR>`) to additionally dispatch the `pr-review-assist` skill for a synced two-pane diff+summary HTML artifact, presenting both under two clearly labeled headings ("Code-Specialist-Review Results" and "PR-Review-Assist" — the latter showing only the artifact URL, not its contents). Use when the user runs `/review-pr` (critique only, the common case) or `/review-pr FULL` (critique AND a comprehension artifact in one shot). Do NOT use for a comprehension-only ask with no critique wanted (invoke `pr-review-assist` directly instead).
---

# Review PR (orchestrator)

Thin orchestrator. It does no reviewing or summarizing itself — it dispatches to already-built tools and presents their output. **Default is critique-only.** The comprehension artifact (`pr-review-assist`) only runs when the literal argument `FULL` is present — never assume the operator wants the artifact just because they're reviewing a PR.

## Inputs

- **PR reference (REQUIRED — do not proceed without one):** GitHub PR URL, `owner/repo#number`, or bare number (repo inferred from `git remote get-url origin` in the current directory — if that fails or is ambiguous, ask for the full `owner/repo`). If the request doesn't include one of these, ask for it before dispatching anything.
- Canonicalize into `PR_URL` = `https://github.com/<OWNER>/<REPO>/pull/<NUM>` — pass this **exact same string** to every dispatched task below, so there's no chance they end up looking at different PRs or different interpretations of an ambiguous reference.
- **Mode (optional):** scan the raw input for a standalone token `full` (case-insensitive — matches `FULL`, `Full`, etc., but only as its own word, not as a substring of something else like a repo or branch name). Present → **FULL mode**. Absent → **default mode**. This is the ONLY way to reach FULL mode — there's no other keyword, flag, or inference from phrasing.

## Workflow

### Default mode — critique only (no `FULL` token present)

Dispatch a single agent and render a single section:

`Agent({ subagent_type: "code-review-specialist", description: "Critique review of <PR_URL>", prompt: "Review this pull request: <PR_URL>. Produce your standard review exactly as you normally would for a PR URL." })`

Do not add any extra instructions beyond pointing it at the PR — this agent already has its own full methodology (source-of-truth rules, severity tiers, confidence labeling, etc.); don't second-guess or truncate it. Do NOT dispatch anything to `pr-review-assist` in this mode — no artifact, no second heading, no mention of it being available unless the operator asks.

Render:

```markdown
## Code-Specialist-Review Results

<Agent's full response, verbatim — do not summarize, trim, or re-tier its findings>
```

**On failure:** report the error plainly under the same heading — do not retry silently, do not fall back to FULL mode.

### FULL mode — critique + comprehension artifact (`FULL` token present)

Issue both `Agent` tool calls **in the same message** (parallel, awaited — the combined output needs both before responding, so do not background them):

1. **Agent 1 — critique.** Same call as default mode above.
2. **Agent 2 — comprehension artifact.** `Agent({ subagent_type: "general-purpose", description: "PR comprehension artifact for <PR_URL>", prompt: "Invoke the pr-review-assist skill (via the Skill tool) for this PR: <PR_URL>. Follow that skill's workflow exactly, including publishing the Artifact. Once done, report back ONLY: the resulting Artifact URL, and the PR title. Do not include the artifact's HTML/JSON contents, the diff, the section summaries, or anything else in your final response — just those two lines." })`
   The explicit "report back ONLY" instruction matters — without it, the subagent may paste large amounts of generated content into its final text, which is exactly what this skill's output contract forbids surfacing under the PR-Review-Assist heading.

Once both agents return, render exactly two top-level headings, in this order:

```markdown
## Code-Specialist-Review Results

<Agent 1's full response, verbatim — do not summarize, trim, or re-tier its findings>

## PR-Review-Assist

<Artifact URL only — e.g. "https://claude.ai/... — <PR title>". Do not paste any summary content, section list, or diff excerpt here, even if Agent 2's response included extra context; extract just the URL (and title if present) and discard the rest.>
```

Nothing else goes in the response — no added preamble, no editorializing about which review is "more important," no merging the two into one narrative. They are two independent outputs from two independent tools; present them as such.

**Failure handling in FULL mode** — the two dispatches are independent; a failure in one must not suppress the other:
- If Agent 1 (critique) fails or errors: still render the `## PR-Review-Assist` section normally, and under `## Code-Specialist-Review Results` state plainly that the critique failed and why (verbatim error if available), instead of omitting the heading.
- If Agent 2 (comprehension artifact) fails or errors: still render the `## Code-Specialist-Review Results` section normally, and under `## PR-Review-Assist` state plainly that artifact generation failed and why, instead of omitting the heading or fabricating a URL.
- If both fail: report both failures under their respective headings — do not retry silently or fall back to a different review path.

## Non-goals

- Do not perform any review or summarization logic in this skill itself — all judgment (what's a bug, what's worth a summary card) belongs to the dispatched tools, not to this orchestrator.
- Do not dispatch `pr-review-assist` in default mode for any reason — not "to be thorough," not because the PR is large or complex. Only the literal `FULL` token triggers it.
- Do not let Agent 2's report leak PR-review-assist's generated content (diff text, section summaries, JSON) into the final response — only the URL (and title) surface here; the full artifact lives at its published URL.
- Do not run `pr-review-assist` alone under this skill's name "to save time" — if only comprehension is wanted with no critique, that's a direct call to `pr-review-assist`, not this skill.
