# Determination Criteria

Use these criteria when evaluating each Codex finding against the actual codebase.

## Not a Real Issue

Classify a finding as **"Not a real issue"** when ANY of these apply:

| Reason | Example |
|--------|---------|
| **Already handled** | Codex flags missing error handling, but a try/catch exists in a parent function |
| **Project convention** | Codex suggests a pattern that contradicts the project's established conventions (check CLAUDE.md, existing code) |
| **Style preference** | Codex prefers a different naming convention, import style, or formatting approach that doesn't affect correctness |
| **False positive** | Codex misreads the code flow, misses a guard clause, or doesn't understand the framework (e.g., MobX, Ant Design) |
| **Out of scope** | The flagged code was not modified by this branch — it's a pre-existing issue |
| **Intentional design** | The code is written this way on purpose (e.g., performance optimization, backwards compatibility) |

## Real Issue

Classify a finding as **"Real issue"** when ANY of these apply:

| Reason | Example |
|--------|---------|
| **Bug** | Logic error, off-by-one, null reference, race condition |
| **Security** | XSS, injection, exposed secrets, missing authentication check |
| **Performance** | Unnecessary re-renders, N+1 queries, missing memoization on hot path |
| **Missing error handling** | Unhandled promise rejection, missing catch, no fallback for API failure |
| **Breaking change** | API contract violation, type mismatch, missing migration |
| **Resource leak** | Unclosed connection, missing cleanup in useEffect, event listener not removed |

### Sizing a Real Issue

| Size | Definition |
|------|------------|
| **S** | Single-line or few-line fix, localized to one function |
| **M** | Requires changes across 2-3 functions or files, moderate refactoring |
| **L** | Architectural change, affects multiple modules, requires new tests |

### Risk Assessment

| Risk | Definition |
|------|------------|
| **S** | Low probability of causing problems, easy to revert |
| **M** | Could cause bugs in specific scenarios, moderate blast radius |
| **L** | Could cause data loss, security vulnerability, or production outage |

### Fix vs Leave as Is

**Recommend "Fix"** when:
- The issue is in code modified/added by this branch
- The fix is straightforward (S or M size)
- The risk of NOT fixing is higher than the risk of the fix itself

**Recommend "Leave as is"** when:
- The issue is in pre-existing code not touched by this branch
- The fix is large (L size) and would significantly expand the scope
- The issue is low risk and can be addressed in a follow-up ticket
- Fixing it introduces more risk than leaving it (e.g., refactoring a fragile module)
