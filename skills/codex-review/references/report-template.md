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
**Codex model:** {CODEX_MODEL — resolved by Step 2 of SKILL.md, normally read from `[profiles.peer-review].model` in `~/.codex/config.toml` (e.g. `gpt-5.5`). If unknown, write `unknown (CLI default)`.}
**Plugin:** codex-peer-review v2.0.0 (blind-debate mode)

---

## Summary

| Category | Count |
|----------|-------|
| Not a real issue | {N} |
| Real issue — Fix | {N} |
| Real issue — Leave as is (Contested) | {N} |
| **Total findings** | **{N}** |

---

## Findings

### {index}. {file_path}:{line}

- **Plugin section:** {Critical | Important | Contested | Dismissed | Style notes}
- **Category:** {bug | security | performance | style | design | other}
- **File:** `{path}:{line}`
- **Source:** {both | claude | codex}  ← from the plugin's `Source:` sub-bullet (only present for Critical / Important / Contested)
- **Codex finding:**
  > {Codex's claim verbatim, blockquoted}

- **Evidence:** {the plugin's `Evidence:` sub-bullet — concrete exploit path, failing test, or specific failure mode}

- **Determination:** {Not a real issue | Real issue}  ← derived via the verdict mapping in SKILL.md Step 4

{If Not a real issue:}

- **Analysis:** {explanation of why this is not an issue, referencing specific code. If the plugin section was `Dismissed`, summarize WHY it was withdrawn during debate.}

{If Real issue:}

- **Analysis:** {explanation of why this IS an issue}
- **Size:** {S | M | L}
- **Risk:** {S | M | L}
- **Recommendation:** {Fix | Leave as is}
- **Fix description:** {how to fix, or why leaving as is}

{If Contested (both AIs held position — surface both views):}

- **Claude's view:** {from the plugin's `Claude's view:` sub-bullet}
- **Codex's view:** {from the plugin's `Codex's view:` sub-bullet}
- **Plugin recommendation:** {from the plugin's `Recommendation:` sub-bullet}
- **This skill's recommendation:** Default to **Leave as is** and present both views; do NOT auto-fix in autonomous mode.

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
