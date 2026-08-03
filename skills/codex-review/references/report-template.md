# Report Template

Use this template for the generated markdown report file.

## File Naming

```
{REPORT_LABEL}-CODEX-REVIEW-{ITERATION}.md
```

**Examples:**
- `TRIDENT-822-CODEX-REVIEW-1.md` (PR mode, ticket number found)
- `TRIDENT-822-CODEX-REVIEW-2.md` (if `-1` already exists)
- `PR-451-CODEX-REVIEW-1.md` (PR mode, no ticket number in title)
- `feature-login-CODEX-REVIEW-1.md` (Direct mode, current-branch fallback)
- `ADHOC-20260702T114500-CODEX-REVIEW-1.md` (Direct mode, no ticket key or git repo — timestamp fallback)

**Save location:** `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/` (create the directory if it doesn't exist) — durable storage outside the project tree, per SKILL.md Step 5.

**Iteration logic:**
1. Check if `~/.claude/memory/ticket-reports/{REPORT_LABEL}/codex-review/{REPORT_LABEL}-CODEX-REVIEW-1.md` exists
2. If yes, increment: check `-2`, `-3`, etc.
3. Use the first available number

## Template

````markdown
# Codex Review: {REPORT_LABEL} — {brief description of what was reviewed}

**Scope:** {PR mode: `{currentBranch}` vs `{baseBranch}` | Direct mode: one-line restatement of the caller's review brief — e.g. "src/utils/refreshSubmission.ts + tests, focus: idempotency guard" or "uncommitted changes in webapp-react-trident"}
**Reviewed:** {current date YYYY-MM-DD}
**Iteration:** {iteration number}
**Mode:** {Interactive | Autonomous}
**Reviewer model:** claude-opus-4-8 (independent subagent — not Codex; the Codex CLI dependency was removed)

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

- **Reviewer severity:** {Critical | Important | Minor}
- **Category:** {bug | security | performance | style | design | other}
- **File:** `{path}:{line}`
- **Reviewer's finding:**
  > {claim verbatim, blockquoted}

- **Evidence:** {the reviewer agent's stated evidence — concrete exploit path, failing test, or specific failure mode}

- **Determination:** {Not a real issue | Real issue}  ← derived via the verdict mapping in SKILL.md Step 4

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
