# Grouping heuristics (Step 2 detail)

Load this when grouping any diff touching more than ~5 files. The goal: the right pane should read like a short table of contents for the PR, not a directory listing.

## Clustering rules

**Cluster into one section when files are part of the same unit of work:**
- A source file + its test file(s) (`foo.ts` + `foo.test.ts` / `foo.spec.ts`) → one section, even if the test changes are substantial.
- A source file + a config/schema file it depends on (a migration + the model that uses it, a feature-flag config + the code branching on it) → one section.
- Multiple files that only make sense together (a new component + the page that renders it + its stylesheet) → one section.
- A single logical change that happens to touch several layers (API route + service + repository for one new endpoint) → one section, describing the end-to-end effect, not each layer separately.

**Collapse into one section with a "+N similar files" note when files are mechanically identical in shape:**
- Generated files (lockfiles, compiled output, generated types/clients).
- Localization/translation files (the same key added across 15 language files).
- Boilerplate repeated across many modules (the same import added to 20 files by a codemod).
- Detection heuristic: if two or more changed files have near-identical diff hunks (same shape of addition/removal, differing only in literal values), they're mechanically identical — collapse them.
- The section's summary should name the "real" change once (e.g., "Added the `retryCount` field across all locale files") and note the count (e.g., "+ 14 similar files") rather than listing every path in the summary text. The file/line-range label under the card can still enumerate the files compactly (e.g., "15 locale files").

**Keep separate when files are independent, even if small:**
- Two unrelated bug-fix-shaped hunks in different, unrelated modules → two sections, even if each is only a few lines.
- Don't force unrelated tiny changes into one section just to reduce card count — a false "these are related" grouping is more confusing than two small cards.

## Sizing the card count

There's no fixed number, but as a guide: aim for a card count a reviewer can hold in their head at a glance — roughly 3–15 cards for most PRs, regardless of file count. A 60-file PR should still resolve to a manageable number of sections, most likely built from heavy use of the "mechanically identical" collapse rule above and layer-spanning clusters. If, after applying both clustering rules, the count is still large (a genuinely sprawling PR with many unrelated changes), that's fine — don't force artificial merges — but say so plainly in the top summary ("this PR touches many unrelated areas; each stayed separate because none of the clustering rules applied").

## Ordering sections

1. **Prefer natural reading order when it's actually inferable:**
   - A new function/type/schema defined, then its call sites/consumers updated → definition section before consumer section.
   - A schema or interface change, then the code that adapts to it → schema section first.
   - A new module, then its integration into an existing entry point → new module first, integration second.
2. **Fall back to diff order** (the order files/hunks appear in `gh pr diff`) when no dependency direction is inferable — most PRs with independent, parallel changes fall here. Don't invent a narrative order that isn't actually there; a forced ordering is worse than diff order.
3. Whichever order is used, it must be **consistent** between the right-pane card order and the left-pane's top-to-bottom section markers — the two panes describe the same document, just at different zoom levels.

## Line-range mapping

Each section needs one or more contiguous `(file, startLine, endLine)` ranges captured from the diff's hunk headers (`@@ -a,b +c,d @@`) — use the **new-file** line numbers (the `+c,d` side) since that's what the rendered diff pane scrolls through. A section spanning multiple files gets multiple ranges; the click-to-scroll behavior (see `html-artifact-template.md`) should scroll to the first range and the highlight should cover all of them as the reviewer scrolls through.

## Worked example

A PR adds retry logic for failed uploads:
- `src/upload/retry.ts` (new file, the retry helper)
- `src/upload/uploadClient.ts` (calls the new helper)
- `src/upload/retry.test.ts` (tests for the helper)
- `src/upload/uploadClient.test.ts` (tests for the call site)
- `locales/en.json`, `locales/fr.json`, `locales/de.json`, ... (12 files, each adding one new error-message string)
- `package-lock.json` (lockfile bump from a transitive dependency)

Grouping:
- **Section 1 — "Retry helper for failed uploads"**: `retry.ts` + `retry.test.ts`. Reading order: first, since `uploadClient.ts` calls it.
- **Section 2 — "Uploads now retry automatically on failure"**: `uploadClient.ts` + `uploadClient.test.ts`. Reading order: second (consumer of Section 1).
- **Section 3 — "New error message for retry exhaustion, added to all locales"**: the 12 locale files, collapsed with "+ 11 similar files" (one file shown as the representative diff, or all 12 listed compactly in the label).
- **Section 4 — "Dependency lockfile update"** (or omitted entirely if it's pure noise with no user-visible effect — use judgment; a lockfile-only change from a transitive bump is often not worth a card at all if nothing else in the PR references it). If kept, one line, no code-level detail.

Six original file-groups collapsed to 3–4 sections, in dependency order, with the mechanical locale change reduced to one card instead of twelve.
