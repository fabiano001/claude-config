# Summary style examples (Step 3 detail)

Load this if unsure whether a draft summary has drifted into critique territory, or before writing summaries for domains where "risk" language creeps in easily (auth, payments, infra, security-adjacent code).

## The rule in one line

Describe **what changed and why it matters** (intent/effect), never **whether it's good** (judgment).

## Good vs. bad

| Bad (critique-flavored) | Good (comprehension-flavored) |
|---|---|
| "Wrapped the fetch call in a for loop to retry on failure." | "Added retry logic for failed uploads." |
| "This adds a new `retryCount` field but doesn't validate it's non-negative — could be an issue." | "Added a `retryCount` field to track how many times an upload has been retried." |
| "Refactored the auth middleware; recommend double-checking the token expiry logic." | "Reworked how the auth middleware checks token expiry." |
| "Bumped the lockfile — should verify no breaking changes in the transitive dep." | "Updated a transitive dependency via the lockfile." |
| "Added a new endpoint for canceling orders. Note: doesn't appear to check ownership before canceling." | "Added a new endpoint that lets a user cancel an order." |
| "Split the 200-line `handleSubmit` into three smaller functions — good cleanup." | "Reorganized the submit-handling code into three smaller functions." |

Notice the last row: even *positive* editorializing ("good cleanup") is out of scope — this skill doesn't praise either. State the effect, not an evaluation in either direction.

## Banned words/phrases (if a draft summary contains one of these, rewrite it)

- "should fix," "should probably," "recommend," "consider" (in the sense of suggesting a change)
- "bug," "issue," "risk," "vulnerability," "unsafe," "problem" (when used to flag something, as opposed to describing a feature literally named that — e.g. "fixes a bug in the retry counter" describing what the PR itself claims to do, drawn from the PR's own description, is fine; independently asserting something IS a bug is not)
- "missing," "doesn't handle," "fails to," "forgot to" (these describe an absence the reviewer is meant to judge — out of scope)
- severity words: "critical," "minor," "blocking," "nit"
- "good," "nice," "clean," "well done" (positive judgment is still judgment)

## The top-of-page overall summary

1–2 sentences, drawn from the PR description + a skim of the diff. Answer "what does this PR do and why," not "is it good."

**Example:**
> Adds automatic retry logic for failed file uploads and surfaces the new "retry exhausted" error message across all supported locales. 18 files changed; grouped into 4 sections.

**Not:**
> Adds retry logic for uploads — looks solid overall, though the lockfile bump should be double-checked for breaking changes.

## Handling a section that's obviously a defect

If a section's diff looks like it introduces a problem (e.g., an off-by-one, a missing null check, a hardcoded secret), **still only describe what changed, neutrally, with zero acknowledgment that it looks wrong.** This is the hardest discipline to hold — the instinct to flag something obviously worth flagging is strong, but that judgment belongs entirely to a different skill (`code-review-specialist`, `codex-review`). If the user later asks "did you notice anything concerning," the correct answer is to point them at one of those skills, not to retroactively add a flag to this artifact.
