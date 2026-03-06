# Report Template

Use this template for the generated markdown report file.

## File Naming

```
{TICKET-NUMBER}-PR-REVIEW-{ITERATION}.md
```

**Examples:**
- `TRIDENT-825-PR-REVIEW-1.md`
- `TRIDENT-825-PR-REVIEW-2.md` (if `-1` already exists)
- `PR-175-REVIEW-1.md` (if no ticket number in PR title)

**Save location:** `dynamic-app/pr-reviews/` (create the directory if it doesn't exist)

**Iteration logic:**
1. Check if `dynamic-app/pr-reviews/{TICKET}-PR-REVIEW-1.md` exists
2. If yes, increment: check `-2`, `-3`, etc.
3. Use the first available number

## Template

````markdown
# PR Review: {PR Title}

**PR:** {PR URL}
**Branch:** `{headRefName}` -> `{baseRefName}`
**Author:** @{author}
**Reviewed:** {current date YYYY-MM-DD}
**Iteration:** {iteration number}

---

## Summary

| Category | Count |
|----------|-------|
| Resolved | {N} |
| Unresolved — Not a real issue | {N} |
| Unresolved — Real issue (fix) | {N} |
| Unresolved — Real issue (leave as is) | {N} |
| **Total threads** | **{N}** |

---

## Resolved Comments ({N})

{For each resolved thread:}

- ✅ **{file_path}:{line}** — {one-line summary of what was resolved} *(resolved by @{resolvedBy})*

---

## Unresolved Comments ({N})

{For each unresolved thread, create a subsection:}

### {index}. {file_path}:{line}

- **Reviewer:** @{author} {[bot] if applicable}
- **File:** `{path}:{line}`
- **Comment:**
  > {reviewer's comment body, blockquoted}

- **Determination:** {Not a real issue | Real issue}

{If Not a real issue:}

- **Analysis:** {explanation of why this is not an issue, referencing specific code}
- **Suggested response:**
  ```
  {response comment to paste in PR}
  ```

{If Real issue:}

- **Analysis:** {explanation of why this IS an issue}
- **Size:** {S | M | L}
- **Risk:** {S | M | L}
- **Recommendation:** {Fix | Leave as is}
- **Details:** {how to fix, or why leaving as is}
- **Suggested response:**
  ```
  {response comment to paste in PR — either acknowledging fix or explaining leave-as-is}
  ```

---

## Action Items

{Numbered list of real issues that warrant action, sorted by risk (highest first):}

| # | File | Issue | Size | Risk | Action |
|---|------|-------|------|------|--------|
| 1 | `path:line` | Brief description | M | L | Fix |
| 2 | `path:line` | Brief description | S | M | Leave as is |
````
