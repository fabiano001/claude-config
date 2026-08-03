---
name: pr-review-assist
description: Generates a single-file HTML artifact that helps a reviewer quickly understand a GitHub PR — a synced two-pane view with the diff on the left and plain-language, non-judgmental summary cards on the right, grouped into logical units of change rather than a flat one-card-per-file list. Clicking a summary card scrolls and highlights the matching diff range; scrolling the diff highlights the in-view card. This is a comprehension aid only — it never flags bugs, suggests fixes, assigns severity, or uses "should fix" language; use `code-review-specialist` or `codex-review` instead when the ask is a review/critique. Use when the user gives a GitHub PR URL or `owner/repo#number` and asks to understand, walk through, summarize, get oriented on, or get up to speed on a PR — NOT when they ask for a review, critique, feedback, or "what's wrong with this."
model: claude-opus-4-8
---

# PR Review Assist

## Non-negotiable scope boundary

**This skill produces a comprehension aid, not a critique.** It exists entirely so a reviewer can *understand what changed and why* before they form their own opinion — it must never form or express an opinion for them.

Never, anywhere in the output:
- Flag something as a bug, risk, vulnerability, or issue.
- Use "should fix," "recommend," "consider changing," "this could break," or any variant that implies a judgment call.
- Assign a severity, priority, or confidence label to a change.
- Silently omit describing a change because it "looks fine" or hint that another change "looks wrong" — describe what every section does, neutrally, whether it looks correct or not. If something is clearly a defect, that is out of scope to mention at all.

If the user actually wants critique, feedback, or a bug hunt, that's `code-review-specialist` or `codex-review` — say so and stop, don't produce a watered-down review under this skill's name.

## Trigger

Activate when the user provides a GitHub PR URL (`https://github.com/{owner}/{repo}/pull/{n}`) or `{owner}/{repo}#{n}` (or a bare PR number when the current directory's `git remote` unambiguously resolves the repo), **and** the request is phrased as wanting to understand/walk through/summarize/get oriented/get up to speed/get a quick grasp of the PR — as opposed to asking for a review, critique, feedback, or "what's wrong with this."

Do not activate on a bare "review this PR" — that phrasing means critique (a different skill's job), even though the PR-URL shape matches.

## Inputs

- **PR reference (REQUIRED — do not proceed without one):** GitHub PR URL, `owner/repo#number`, or bare number (repo inferred from `git remote get-url origin` in the current directory — if that fails or is ambiguous, ask for the full `owner/repo`). If the user's request doesn't include any of these forms, ask for the PR URL/number before doing anything else — there is no default target and nothing to fall back to.
- Once resolved, canonicalize this into `PR_URL` = `https://github.com/<OWNER>/<REPO>/pull/<NUM>` — this canonical URL is carried through Step 1 and must appear in the artifact itself (see Step 4).

## Workflow

### Step 1 — Fetch PR data

1. **Parse** the PR reference into `OWNER`, `REPO`, `NUM`.
2. **Fetch metadata:** `gh pr view <NUM> --repo <OWNER>/<REPO> --json title,body,headRefName,baseRefName,changedFiles,additions,deletions`
3. **Fetch the diff:** `gh pr diff <NUM> --repo <OWNER>/<REPO>`
4. **If either call fails** (PR not found, auth error, network error, ambiguous reference): **STOP and report the failure to the user.** Do not guess at PR contents from local `git status`, `git log`, or the working tree — this skill only ever describes the actual PR, never local state.

### Step 2 — Group changes into logical sections

Do not mirror the flat file list — cluster related files/hunks into logical units of change (e.g., a source file + its test + a related config change = one section, not three), and collapse mechanically-identical files (generated files, localization files, lockfiles) into one section with a note like "+ 12 similar files."

Order sections by natural reading order when it's inferable (definition before its call sites, schema before its consumers) — fall back to diff order when no clear order exists; don't force one.

Each section must map to one or more specific, contiguous line ranges in the diff, so the artifact can anchor a click to a scroll position.

**Full grouping heuristics, thresholds, and worked examples — load [references/grouping-heuristics.md](references/grouping-heuristics.md) before grouping any diff touching more than ~5 files.** For small diffs (≤5 files, clearly one topic), you may skip the reference and group by inspection.

### Step 3 — Write each section's summary

- Plain language, high level, intent/effect — not implementation mechanics. ("Added retry logic for failed uploads," not "wrapped the fetch call in a for loop.")
- 1–3 sentences per section. Skimmable in seconds, not a report.
- At the very top of the page: a 1–2 sentence overall summary of what the PR accomplishes and why, drawn from the PR description + diff, so the reviewer is oriented before reading any section.
- No severity, no "should fix," no bug flags, no suggestions — see the scope boundary above. This applies even when a change is obviously questionable; silently describe what it does, nothing more.

**Style examples (good vs. bad phrasing, banned-word list) — load [references/summary-style-examples.md](references/summary-style-examples.md)** if unsure whether a draft summary has drifted into critique territory, or before writing summaries for an unfamiliar domain (e.g., infra/security-adjacent code where "risk" language creeps in easily).

### Step 4 — Build and publish the HTML artifact

**Before writing anything, load the `artifact-design` skill** (its own mandatory pre-step for any Artifact publish) for the environment's styling/theme conventions — this must read as a deliberate, distinctive tool, not a generic two-column bootstrap dashboard. There is no separate "frontend design" skill in this environment; `artifact-design` is the relevant one. (`dataviz` exists too, but it's for charts/graphs, not diff/code panes — not applicable here.)

**Header (REQUIRED):** at the very top of the page, above the two panes, show the PR title and the overall summary, and render `PR_URL` (from Inputs) as a real, visible, clickable link — e.g. `<a href="<PR_URL>" target="_blank" rel="noopener">#<NUM> · <OWNER>/<REPO></a>`. This is the reviewer's way back to the actual PR (to leave comments, check status, etc.) — the artifact is a comprehension aid, not a replacement for GitHub, so it must never obscure where the real PR lives. This is a hard requirement, not a nice-to-have — do not ship the artifact without it.

**Layout:** left pane = the diff, grouped/collapsible by file, read-only, syntax-colored by add/remove/context (no external highlighter CDN — the Artifact CSP blocks external scripts, so use a small inline diff renderer, not a library). Right pane = a vertical scrollable list of summary cards, one per Step 2 section, each showing its file path(s) + line-range label alongside the summary text.

**Sync behavior (both directions):**
- Card click → scroll the left pane to that section's line range and apply a highlight background to those lines.
- Left-pane scroll → detect which section is currently in view (`IntersectionObserver` on the diff's section markers) and highlight the matching card on the right.
- Every card shows its file/line mapping at rest, without requiring a click, so the mapping is legible even before interacting.

**Diagrams are opt-in per section, not default.** Only add one when a section genuinely represents a flow/state-transition/call-sequence that's hard to convey in one sentence — most sections stay text-only. When used, render as a `<pre class="mermaid">` block (Artifacts render Mermaid natively; no external diagram library needed) — a simple `sequenceDiagram` or `flowchart` sketch, nothing elaborate.

**Self-contained, no live calls:** all PR data (diff text, section groupings, summaries, metadata) gets baked into the HTML at generation time (e.g., as an inline `<script>` JSON blob the page's own JS reads) — the rendered artifact never calls the GitHub API, never executes anything from the diff, and offers no inline commenting. It's a read-only snapshot.

**Large PRs:** if grouping in Step 2 had to be aggressive to keep the card count sane (dozens of changed files), say so explicitly in the top-of-page overall summary — e.g., "23 files changed; grouped into 6 sections, several combining mechanically similar files."

**Full markup/CSS/JS skeleton (two-pane layout, sync JS, diff renderer, data-embedding pattern) — load [references/html-artifact-template.md](references/html-artifact-template.md)** before writing the artifact file. Don't reinvent the sync mechanics from scratch each time; adapt the skeleton to the specific PR's sections.

1. Write the assembled HTML to a scratch/temp file (this session's scratch directory if one exists, otherwise `/tmp`).
2. Call the `Artifact` tool with that file path (title: the PR title; a one-or-two-emoji favicon; `description`: the one-line overall summary).
3. Report the returned URL to the user along with the one-line overall summary and the count of sections/files covered.

## Failure & fallback

- No PR reference in the request → ask for one; do not proceed, do not guess a PR from local branch/state.
- Step 1 fetch failure → stop, report verbatim error, do not proceed.
- If the diff is empty or the PR has zero changed files → say so, don't fabricate sections.
- If `git remote` can't resolve `owner/repo` for a bare PR number → ask the user for the full `owner/repo#number` instead of guessing.

## Output format

One published Artifact URL, plus a short confirmation message: the PR title, `PR_URL`, the one-line overall summary, and how many sections/files it covers (and whether grouping was aggressive due to size). Nothing else — no separate written review, no findings list, no follow-up "want me to also review this?" offer (that's a different skill, and offering it here blurs the boundary this skill exists to keep clean).
