# Sprint Loop Prompt

**Sprint Name:** {{SPRINT_NAME}}
**Ticket:** {{JIRA_TICKET}}
**Project Directory:** {{PROJECT_DIR}}

You are executing a sprint loop iteration for ticket **{{JIRA_TICKET}}**. Follow these instructions precisely and do not stop until all tasks are complete.

## CRITICAL: Fully Autonomous Execution

This is a **100% unattended, autonomous loop**. There is NO human operator present. You CANNOT:
- Ask questions or request clarification
- Prompt for confirmation or approval
- Request tool permissions (all permitted tools are pre-configured)
- Wait for user input of any kind

**If a tool call is denied or a permission is missing, do NOT retry or wait — immediately proceed to Step 4a (Early Exit with Errors) and document exactly what was needed.**

**RETRY LIMIT: If any bash command or tool call fails twice with the same or similar error, do NOT attempt it a third time. Immediately proceed to Step 4a (Early Exit with Errors). This applies to ALL steps including Step 3 (Execute Plan) AND Step 4 (Finalize Ticket). Common failure patterns that MUST trigger early exit after 2 attempts:**
- **Permission denied** or tool call denied
- **git commit** failing or producing no commit
- **git push** failing
- **gh pr create** failing
- **Any command that returns the same error twice**

You must make all decisions independently using the context provided in `context.md` and `plan.md`. If something is ambiguous, make the best judgment call based on existing code patterns and conventions, document your decision, and continue.

---

## Step 1: Git Branch Setup

Ensure you are on the correct Git branch for the ticket.

**Branch naming:** The branch name is the Jira ticket ID: `{{JIRA_TICKET}}`

**Base branch:** Read `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/sprintStatus.json` and get the `baseBranch` field for `{{JIRA_TICKET}}`.

**Git commands to execute:**

1. **Ensure clean working tree and fetch latest:**
   ```bash
   git status -s
   git fetch --all --prune
   ```
   - If working tree is dirty, warn and stash changes before proceeding.

2. **Check if ticket branch exists:**
   - Local: `git rev-parse --verify --quiet refs/heads/{{JIRA_TICKET}}`
   - Remote: `git ls-remote --exit-code --heads origin {{JIRA_TICKET}}`

3. **If branch exists locally:**
   - If not on it: `git checkout {{JIRA_TICKET}}`
   - Update from remote: `git pull --ff-only`
   - If behind base branch, rebase: `git rebase origin/{{BASE_BRANCH}}`

4. **If branch exists only on remote (not locally):**
   - Check out the remote branch:
     ```bash
     git checkout -b {{JIRA_TICKET}} origin/{{JIRA_TICKET}}
     ```
   - If behind base branch, rebase: `git rebase origin/{{BASE_BRANCH}}`

5. **If branch does NOT exist anywhere:**
   - Checkout and update base branch:
     ```bash
     git checkout {{BASE_BRANCH}}
     git pull --ff-only
     ```
   - Create and switch to ticket branch:
     ```bash
     git checkout -b {{JIRA_TICKET}}
     ```
   - Set upstream:
     ```bash
     git push -u origin {{JIRA_TICKET}}
     ```

**After branch setup is complete, proceed to Step 2.**

---

## Step 2: Load Context

1. **Read Learnings:** Read `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/learnings.md` to understand what has been learned in previous iterations.

2. **Read Ticket Context:** Read `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/{{JIRA_TICKET}}/context.md`.

3. **Read Ticket Plan:** Read `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/{{JIRA_TICKET}}/plan.md` to get the detailed task list.

---

## Step 3: Execute Plan

Execute tasks in `plan.md` **strictly in the order they appear**, one at a time. Do NOT skip ahead or work on multiple tasks simultaneously.

### For each task:

1. **Write tests first** (where applicable)
   - Create/modify test files using Edit and apply the changes immediately
   - Run the test command and execute per tool permissions

2. **Implement minimal code**
   - Provide surgical diffs/code snippets and apply them with Edit right away
   - For formatter/linter/typecheck/tests, execute per tool permissions and summarize output
   - Iterate until green

3. **Update plan.md immediately** — As soon as the task passes, edit `plan.md` and change the task's `[ ]` to `[✅]`. This MUST happen after every single task, not at the end. The operator monitors `plan.md` to track real-time progress.

4. **Proceed** — Only then move to the next task. Repeat until all tasks are complete.

### After ALL implementation tasks are complete:

5. **Code Review**
   - Run the **code-review-specialist** subagent to review all changes made
   - Address any issues, suggestions, or concerns raised by the review that are in the current branch (not preexisting issues)
   - Iterate until the code review passes with no outstanding issues for the current branch

6. **Production Validation**
   - Run the **production-code-validator** subagent to validate production readiness
   - Fix any issues found in the current branch (placeholder code, TODOs, hardcoded values, debugging code, security issues, etc.)
   - Do not fix preexisting issues that were not introduced by this branch
   - Iterate until the production validation passes for the current branch changes

**IMPORTANT:**
- Do NOT stop until ALL tasks in the plan are complete and code review + production validation have passed
- Do NOT quit or exit early
- If a task or command fails for **any reason** (missing tool permissions, denied tool call, missing dependency, test failure, build error, commit failure, push failure, etc.), and it has already failed **twice**, stop immediately and go to **Step 4a: Early Exit with Errors**. This rule applies to Steps 3, 4, and all sub-steps.
- Track the start time before beginning and end time after completing

---

## Step 4: Finalize Ticket (Success)

Once ALL tasks in the plan are complete with no blocking errors:

1. **Commit and Push:**
   - Stage all changes: `git add -A`
   - Commit: `git commit -m "{{JIRA_TICKET}}: <concise single-line summary>"`
   - **CRITICAL: Use a simple single-line -m flag. Do NOT use HEREDOCs, $(cat <<EOF), or multi-line commit messages. The permission system cannot match multi-line bash commands and the commit will be silently denied.**
   - Push to remote: `git push`

2. **Create Pull Request:**
   - Read the `baseBranch` for `{{JIRA_TICKET}}` from `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/sprintStatus.json`
   - Create a PR against the base branch:
     ```bash
     gh pr create --base {{BASE_BRANCH}} --title "{{JIRA_TICKET}}: <short title>" --body "## Summary
     - change 1
     - change 2

     ## Test plan
     - test step 1"
     ```
   - **CRITICAL: Do NOT use HEREDOCs or $(cat <<EOF) for the PR body. Use a simple inline string with the --body flag.**

3. **Update Sprint Status:** Edit `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/sprintStatus.json` and set `"completed": true` for `{{JIRA_TICKET}}`.

4. **Record Learnings:** Append any new learnings, insights, or issues encountered to `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/learnings.md`. Include:
   - What worked well
   - What didn't work
   - Any patterns or shortcuts discovered
   - Warnings for future iterations

5. **Write Summary:** Append to `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/summary.md`:
   ```markdown
   ## {{JIRA_TICKET}}

   **Status:** Completed
   **Started:** {{START_TIMESTAMP}}
   **Ended:** {{END_TIMESTAMP}}
   **Duration:** {{DURATION}}

   ### Tasks Completed:
   - [x] Task 1 description
   - [x] Task 2 description
   ...

   ### Notes:
   {{Any relevant notes}}
   ```

6. **Exit** - The loop will automatically start the next iteration.

---

## Step 4a: Early Exit with Errors

If a task could not be completed due to missing tool permissions, a denied tool call, or any other blocking issue:

1. **Update Context:** Append a `## Previous Iteration Errors` section to `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/{{JIRA_TICKET}}/context.md` with:
   - Which task(s) could not be completed and why
   - If a tool permission was missing or denied: the exact tool name, command, and arguments
   - Any other details the human operator needs to resolve the issue

   Example:
   ```markdown
   ## Previous Iteration Errors

   ### Iteration 1
   - **Task:** Run lint fix
   - **Error:** Tool permission denied
   - **Tool:** Bash
   - **Command:** `npx eslint --fix src/`
   - **Action needed:** Add `Bash(npx eslint*)` to allowedTools in sprint-loop.sh
   ```

2. **Update Sprint Status:** Edit `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/sprintStatus.json`:
   - Set `"completed": true` for `{{JIRA_TICKET}}`
   - Add `"errors": true` for `{{JIRA_TICKET}}`

3. **Write Summary:** Append to `~/RalphLoops/SprintLoop/Sprints/{{SPRINT_NAME}}/summary.md`:
   ```markdown
   ## {{JIRA_TICKET}}

   **Status:** Completed with Errors
   **Started:** {{START_TIMESTAMP}}
   **Ended:** {{END_TIMESTAMP}}
   **Duration:** {{DURATION}}
   **Iteration:** {{ITERATION_NUMBER}}

   ### Tasks Completed:
   - [x] Task 1 description
   ...

   ### Blocked Tasks:
   - [ ] Task N: <description of what was blocked and why>
   ...

   ### Errors:
   - <detailed error description>
   ```

4. **Commit and Push (no PR):**
   - Stage all changes: `git add -A`
   - Commit: `git commit -m "{{JIRA_TICKET}}: partial progress - blocked by <reason>"`
   - **CRITICAL: Use a simple single-line -m flag. Do NOT use HEREDOCs or $(cat <<EOF). The permission system cannot match multi-line bash commands.**
   - Push to remote: `git push`
   - Do **NOT** create a pull request

5. **Exit** - The loop will continue to the next ticket. The human operator should review the errors, resolve the issue, and re-run with option 1 (Reset Sprint for Next Iteration) in `init-sprint.sh`.

---

## Constraints

- Stay focused on the current ticket only
- Do not modify code outside the scope of the current ticket
- Follow existing code patterns and conventions

---

## sprintStatus.json Structure

```json
{
  "TRIDENT-802": {
    "priority": 1,
    "completed": false,
    "baseBranch": "main",
    "projectDir": "~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident",
    "sessionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "startedAt": "2026-02-09T20:02:57Z",
    "completedAt": "2026-02-09T20:45:12Z"
  },
  "TRIDENT-803": {
    "priority": 2,
    "completed": false,
    "baseBranch": "TRIDENT-802",
    "projectDir": "~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident",
    "sessionId": null,
    "startedAt": null,
    "completedAt": null
  }
}
```

- **priority**: Lower number = higher priority (execute first)
- **completed**: `false` = pending, `true` = done
- **baseBranch**: The branch to base this ticket's branch off of
- **projectDir**: Absolute path to the project repository
- **sessionId**: UUID of the Claude session (set automatically by the loop; do not modify)
- **startedAt**: UTC timestamp when the loop started processing this ticket (set automatically; do not modify)
- **completedAt**: UTC timestamp when the loop finished processing this ticket (set automatically; do not modify)

---

## File Paths Reference

```
~/RalphLoops/SprintLoop/
├── prompt.md              # This prompt (shared across all sprints)
├── sprint-loop.sh         # Main loop script
├── init-sprint.sh         # Sprint initialization script
└── Sprints/
    └── {{SPRINT_NAME}}/
        ├── sprintStatus.json  # Sprint progress tracking
        ├── learnings.md       # Accumulated learnings
        ├── summary.md         # Work summary
        ├── finished.true      # Created when sprint is complete
        ├── {{JIRA_TICKET_1}}/
        │   ├── context.md     # Ticket context and requirements
        │   └── plan.md        # Detailed task list
        ├── {{JIRA_TICKET_2}}/
        │   ├── context.md
        │   └── plan.md
        └── ...
```
