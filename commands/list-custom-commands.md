# List Custom Commands

<!-- COMMAND_DESCRIPTION: List all available personal and project-level slash commands with their descriptions -->

List all available personal and project-level slash commands with their descriptions.

## Usage

```
/list-custom-commands
```

## Description

Scans both personal (`~/.claude/commands/`) and project-level (`./.claude/commands/`) directories to display all available custom slash commands with single-line descriptions.

## Output Format

The command will display:
- **Personal Commands** - Available across all projects
- **Project Commands** - Available only in current project
- Command name with concise single-line description for each

## Workflow

1. **Scan** `~/.claude/commands/` for personal commands
2. **Scan** `./.claude/commands/` for project-level commands  
3. **Extract** description from `<!-- COMMAND_DESCRIPTION: ... -->` comment in each file
4. **Display** organized list with command names and descriptions
5. **Fast execution** by reading only metadata, not full file content

## Notes

- Works in any project directory
- Shows commands from both personal and project scopes
- Extracts descriptions from markdown file headers and content
- Helpful for discovering available custom commands
- No arguments required - always scans both directories