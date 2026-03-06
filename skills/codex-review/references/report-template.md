# Report Template

Use this template for the generated markdown report file.

## File Naming

```
{TICKET-NUMBER}-CODEX-REVIEW-{ITERATION}.md
```

**Examples:**
- `TRIDENT-822-CODEX-REVIEW-1.md`
- `TRIDENT-822-CODEX-REVIEW-2.md` (if `-1` already exists)
- `feature-login-CODEX-REVIEW-1.md` (if no ticket number in branch name)

**Save location:** `dynamic-app/pr-reviews/` (create the directory if it doesn't exist)

**Iteration logic:**
1. Check if `dynamic-app/pr-reviews/{TICKET}-CODEX-REVIEW-1.md` exists
2. If yes, increment: check `-2`, `-3`, etc.
3. Use the first available number

## Template

````markdown
# Codex Review: {TICKET-NUMBER} — {branch description or ticket title}

**Branch:** `{currentBranch}` vs `{baseBranch}`
**Reviewed:** {current date YYYY-MM-DD}
**Iteration:** {iteration number}
**Mode:** {Interactive | Autonomous}

---

## Summary

| Category | Count |
|----------|-------|
| Not a real issue | {N} |
| Real issue — Fix | {N} |
| Real issue — Leave as is | {N} |
| **Total findings** | **{N}** |

---

## Findings

### {index}. {file_path}:{line}

- **Category:** {bug | security | performance | style | design | other}
- **File:** `{path}:{line}`
- **Codex finding:**
  > {Codex's original concern, blockquoted}

- **Determination:** {Not a real issue | Real issue}

{If Not a real issue:}

- **Analysis:** {explanation of why this is not an issue, referencing specific code}

{If Real issue:}

- **Analysis:** {explanation of why this IS an issue}
- **Size:** {S | M | L}
- **Risk:** {S | M | L}
- **Recommendation:** {Fix | Leave as is}
- **Fix description:** {how to fix, or why leaving as is}

---

## Action Items

| # | File | Issue | Category | Size | Risk | Action |
|---|------|-------|----------|------|------|--------|
| 1 | `path:line` | Brief description | bug | M | L | Fix |
| 2 | `path:line` | Brief description | style | S | S | Leave as is |

---

## Fixes Applied

{Only present if fixes were made}

| # | File | Fix Description | Tests Pass |
|---|------|----------------|------------|
| 1 | `path:line` | Brief description of fix | ✅ |
````
