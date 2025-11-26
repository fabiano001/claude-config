---
description: Compare two branch solutions for a Jira ticket, optionally promote winner
argument-hint: [ticket-number] [PROMOTE-V1|PROMOTE-V2]
---

You are comparing two different implementation approaches for the same Jira ticket. Analyze both solutions and provide a recommendation.

**Jira Ticket:** $1
**Branch 1:** $1-temp-v1
**Branch 2:** $1-temp-v2
**Promote Mode:** $2 (optional: PROMOTE-V1 or PROMOTE-V2)

## Your Task

**Mode Selection:**
- If $2 is NOT provided: **Comparison Mode** - Analyze and recommend only
- If $2 = PROMOTE-V1 or PROMOTE-V2: **Promotion Mode** - Skip analysis, commit and promote the specified branch

### Comparison Mode (when $2 is not provided):

1. **Fetch Jira Ticket Details**
   - Use the Jira MCP tools to fetch ticket $1
   - Extract: Summary, Description, Acceptance Criteria, Technical Requirements

2. **Analyze Branch 1 ($1-temp-v1)**
   - Switch to branch $1-temp-v1: `git checkout $1-temp-v1`
   - Identify all changed files: `git diff main...$1-temp-v1 --name-only`
   - Review key implementation changes: `git diff main...$1-temp-v1`
   - Document the approach taken

3. **Analyze Branch 2 ($1-temp-v2)**
   - Switch to branch $1-temp-v2: `git checkout $1-temp-v2`
   - Identify all changed files: `git diff main...$1-temp-v2 --name-only`
   - Review key implementation changes: `git diff main...$1-temp-v2`
   - Document the approach taken

4. **Comparative Analysis**
   - Map each solution against the Acceptance Criteria
   - Identify which requirements each branch satisfies
   - Note any requirements missed by either branch

5. **Generate Report**

Produce a concise report in this format:

```markdown
# Solution Comparison: $1

## Ticket Summary
[1-2 sentence summary of what the ticket requires]

## Branch 1: $1-temp-v1
**Approach:** [Brief description]
**Pros:**
- [Key advantage 1]
- [Key advantage 2]
**Cons:**
- [Key limitation 1]
- [Key limitation 2]
**AC Coverage:** [X/Y acceptance criteria met]

## Branch 2: $1-temp-v2
**Approach:** [Brief description]
**Pros:**
- [Key advantage 1]
- [Key advantage 2]
**Cons:**
- [Key limitation 1]
- [Key limitation 2]
**AC Coverage:** [X/Y acceptance criteria met]

## Recommendation

**Decision:** [Choose one of the following]
- ✅ **Use Branch 1 ($1-temp-v1) as-is**
- ✅ **Use Branch 2 ($1-temp-v2) as-is**
- ✅ **Use Branch 1 ($1-temp-v1) + incorporate [specific elements] from Branch 2**
- ✅ **Use Branch 2 ($1-temp-v2) + incorporate [specific elements] from Branch 1**

**Reasoning:** [2-3 sentences explaining why this is the best path forward, focusing on AC coverage, code quality, maintainability, and alignment with requirements]

**Action Items:** [If hybrid approach, list specific changes needed]
```

## Important Guidelines

- **Be succinct** - Focus on high-impact differences only
- **Prioritize AC coverage** - Solutions that meet all acceptance criteria rank higher
- **Consider code quality** - Cleaner, more maintainable code matters
- **Be objective** - Base recommendations on technical merit, not bias
- **Be decisive** - Provide a clear, actionable recommendation
- **Explain reasoning** - Always justify your choice with concrete evidence

## After Analysis

If **$2 is NOT provided** (comparison mode only):
- Return the user to their original branch: `git checkout -`
- **Ask the user which branch to promote:**
  - Present the recommendation from your analysis
  - Use AskUserQuestion tool with these options:
    - Option 1: "Promote V1 (recommended)" or "Promote V1" (label based on recommendation)
    - Option 2: "Promote V2 (recommended)" or "Promote V2" (label based on recommendation)
    - Option 3: "Neither - I'll handle it manually"
  - If user selects "Promote V1": Execute `/pick-better-solution $1 PROMOTE-V1`
  - If user selects "Promote V2": Execute `/pick-better-solution $1 PROMOTE-V2`
  - If user selects "Neither": End here
- **Important:** Use the SlashCommand tool to execute the command in promotion mode, NOT by repeating the logic inline

If **$2 is PROMOTE-V1** or **$2 is PROMOTE-V2**:

### Promotion Workflow

1. **Determine which branch to promote:**
   - If $2 = PROMOTE-V1, promote branch: $1-temp-v1
   - If $2 = PROMOTE-V2, promote branch: $1-temp-v2

2. **Commit staged changes on the temp branch:**
   - Verify you're on the correct temp branch (worktree)
   - Check if there are staged changes: `git status`
   - If staged changes exist, commit with message: `$1: <descriptive commit message>`
   - If no staged changes, skip commit step

3. **Create the final branch from the promoted temp branch:**
   - Create new branch with ticket name: `git branch $1 <promoted-temp-branch>`
   - Example: `git branch TRIDENT-781 TRIDENT-781-temp-v1`

4. **Remove both worktrees:**
   - Remove v1 worktree: `git worktree remove <path-to-v1-worktree> --force`
   - Remove v2 worktree: `git worktree remove <path-to-v2-worktree> --force`
   - Get worktree paths using: `git worktree list`

5. **Delete both local temp branches:**
   - Delete v1: `git branch -D $1-temp-v1`
   - Delete v2: `git branch -D $1-temp-v2`

6. **Checkout the new promoted branch:**
   - Switch to the new branch: `git checkout $1`

7. **Confirm promotion:**
   - Show final status: `git log -1 --oneline`
   - Display message: "✅ Promoted $1-temp-vX to $1. Both temp branches and worktrees removed."

### Important Notes for Promotion:
- **Staged changes only:** Only commit changes that are already staged (don't auto-stage)
- **Worktree paths:** Use `git worktree list` to find exact paths before removal
- **Force removal:** Use `--force` flag on worktree removal in case of uncommitted changes
- **Branch deletion:** Use `-D` (force delete) to ensure branches are removed even if not merged
- **Final verification:** Show the final commit and branch status to confirm success
