# SprintLoop

Automated sprint execution using Claude Code. Iteratively processes Jira tickets until all are complete.

## How It Works

1. **Initialize** a sprint with tickets using `init-sprint.sh`
2. **Run** the loop with `sprint-loop.sh`
3. **Each iteration**, the bash script:
   - Parses `sprintStatus.json` to find the next incomplete ticket (lowest priority number)
   - Extracts the `projectDir` for that ticket
   - Starts Claude from that project directory (for proper file permissions)
   - Passes ticket ID and project dir to the prompt
4. **Claude then:**
   - Sets up the Git branch for the ticket
   - Loads context and plan files
   - Executes all tasks in the plan
   - Updates status, records learnings, writes summary
   - Exits (loop restarts for next ticket)
5. **Loop ends** when all tickets are complete (`finished.true` is created)

## Important: Run from a Sandboxed Directory

Always run both scripts from a **dedicated empty directory** — never from `~/RalphLoops/SprintLoop/` or `~`. Claude inherits file permissions for the working directory, so:

- Running from `SprintLoop/` lets the loop modify its own scripts and prompt
- Running from `~` exposes your entire home directory

Create an empty run directory and always launch from there:

```bash
mkdir -p ~/RalphLoops/run
cd ~/RalphLoops/run
~/RalphLoops/SprintLoop/init-sprint.sh sprint_1 TRIDENT-802 TRIDENT-803
~/RalphLoops/SprintLoop/sprint-loop.sh sprint_1
```

Both scripts use absolute paths internally, so they work from any location.

## Sprint Initialization

```bash
~/RalphLoops/SprintLoop/init-sprint.sh <sprintName> [--project-dir <path>] [ticket1] [ticket2] ...
```

**Examples:**
```bash
# Default project (webapp-react-trident)
~/RalphLoops/SprintLoop/init-sprint.sh sprint_1 TRIDENT-802 TRIDENT-803 TRIDENT-804

# Custom project directory
~/RalphLoops/SprintLoop/init-sprint.sh sprint_1 --project-dir ~/other-org/other-repo OTHER-123 OTHER-456
```

**What it creates:**
- `sprintStatus.json` - tickets with priority, status, baseBranch, and projectDir
- `learnings.md` and `summary.md` - starter files
- Per-ticket directories (empty - files created in next step)

**After initialization:**
1. For each ticket, run `/ticket-driver PLAN-MODE <sprintName> <TICKET>` to generate `context.md` and `plan.md`
2. (Optional) Edit `sprintStatus.json` to change `baseBranch` or `projectDir` per ticket
3. Run the sprint loop

## Running the Sprint Loop

```bash
~/RalphLoops/SprintLoop/sprint-loop.sh <sprintName> [--watchMode]
```

**Examples:**
```bash
# Silent mode (default) - output logged to each ticket's output.log
~/RalphLoops/SprintLoop/sprint-loop.sh sprint_1

# Watch mode - streams Claude's output to terminal in real-time
~/RalphLoops/SprintLoop/sprint-loop.sh sprint_1 --watchMode
```

The loop runs until all tickets are complete. Claude's output is always saved to `<TICKET>/output.log` for review. Use `--watchMode` to also stream it to the terminal.

**Monitoring progress:** Claude updates `plan.md` with checkmarks after each completed task, so you can watch progress in real-time by tailing the file:
```bash
tail -f ~/RalphLoops/SprintLoop/Sprints/<sprintName>/<TICKET>/plan.md
```

**Requirements:**
- `jq` must be installed (`brew install jq`)

## Multi-Repo Support

Each ticket can have its own `projectDir` in `sprintStatus.json`. The loop starts each Claude session from the correct project directory, ensuring proper file permissions for autonomous operation.

```json
{
  "TRIDENT-802": {
    "projectDir": "~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident"
  },
  "OTHER-123": {
    "projectDir": "~/other-org/different-repo"
  }
}
```

## File Structure

```
~/RalphLoops/SprintLoop/
├── README.md              # This file
├── prompt.md              # Shared prompt for all sprints
├── sprint-loop.sh         # Main loop script
├── init-sprint.sh         # Sprint initialization script
└── Sprints/
    └── <sprintName>/
        ├── sprintStatus.json  # Sprint progress tracking
        ├── learnings.md       # Accumulated learnings
        ├── summary.md         # Work summary
        ├── finished.true      # Created when sprint is complete
        └── <TICKET>/
            ├── context.md     # Created via /ticket-driver PLAN-MODE
            ├── plan.md        # Created via /ticket-driver PLAN-MODE
            └── output.log     # Claude's output for this ticket (created by loop)
```

## sprintStatus.json Format

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
- **baseBranch**: Branch to base ticket's branch off of (`main` or a previous ticket for dependencies)
- **projectDir**: Absolute path to the project repository (supports `~` expansion)
- **sessionId**: UUID of the Claude session (set automatically by the loop; use `claude --resume <sessionId>` to resume)
- **startedAt**: UTC timestamp when the loop started processing this ticket (set automatically)
- **completedAt**: UTC timestamp when the loop finished processing this ticket (set automatically)
