# Determination Criteria

How to assess each unresolved PR comment and reach a determination.

## Research Process

For each unresolved thread:

1. **Read the referenced file** at the exact line(s) mentioned in the comment
2. **Understand the reviewer's concern** — what specifically are they flagging?
3. **Check the surrounding context** — is there code nearby that addresses the concern?
4. **Search the codebase** for related patterns if the concern is about consistency, conventions, or existing utilities
5. **Check tests** — does the code have test coverage for the scenario the reviewer is concerned about?

## Determination: Not a Real Issue

Classify as "Not a real issue" when:

- The reviewer misread the code or missed context that addresses their concern
- The concern is about a pattern that is intentional and consistent across the codebase
- The suggestion conflicts with the project's established conventions
- The issue was already addressed in a subsequent commit (check the full diff)
- The concern is subjective style preference with no functional impact
- The reviewer is suggesting an optimization that would not meaningfully improve performance

**Required output:**
- Clear explanation of why it is not an issue
- A polite, professional response comment to paste in the PR that:
  - Acknowledges the reviewer's concern
  - Explains why it's handled or intentional
  - References specific code/lines if helpful

**Example response comment:**
```
Good catch — I can see why this looks off at first glance. The null check isn't needed here because `getUserById` is only called after the auth middleware validates the user exists (see `authMiddleware.ts:45`). The upstream guarantee means we're safe here.
```

## Determination: Real Issue

Classify as "Real issue" when:

- The code has a bug or logical error the reviewer identified
- There's a missing edge case or error handling gap
- The code violates the project's established patterns without justification
- There's a security concern (input validation, injection, auth bypass, etc.)
- There's a performance problem that would impact users at scale
- The code is misleading or will cause maintenance confusion

**Required output:**

### Size Assessment

| Size | Criteria |
|------|----------|
| **S** | 1-5 lines changed, single file, no test changes needed |
| **M** | 5-20 lines changed, 1-3 files, may need test updates |
| **L** | 20+ lines changed, 3+ files, requires new tests or refactoring |

### Risk Assessment

| Risk | Criteria |
|------|----------|
| **S** | Cosmetic or minor logic fix, low chance of regression |
| **M** | Logic change that could affect related functionality, test coverage exists |
| **L** | Core logic change, touches shared utilities, or affects critical path (auth, payments, data integrity) |

### Recommendation

- **Fix** — when the issue is clearly a bug, security concern, or high-risk gap
- **Leave as is** — when the fix introduces more risk than the issue itself, or it's a known tech debt item better tracked as a follow-up ticket

If recommending "Leave as is", provide a response comment that:
- Acknowledges the valid concern
- Explains why fixing it now introduces risk
- Suggests a follow-up (ticket, tech debt backlog)

**Example leave-as-is response:**
```
You're right that this could be cleaner. The current approach works correctly but isn't ideal for maintainability. I'd prefer to address this in a dedicated refactor rather than expanding the scope of this PR. I'll create a follow-up ticket to track it — TRIDENT-XXX.
```
