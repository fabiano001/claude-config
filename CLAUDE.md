# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## User Requests

- **"sync claude code files"** or **"sync claude code"** → Run `./sync-claude-files.sh`

## Repository Purpose

This is a configuration repository for Claude Code. It stores custom agents, slash commands, skills, and settings that are synced to/from `~/.claude/`. The repository serves as version control for Claude Code customizations.

## Directory Structure

- `agents/` - Custom agent definitions (markdown files with YAML frontmatter)
- `commands/` - Slash command definitions (markdown files with YAML frontmatter)
- `skills/` - User-level skills (synced from `~/.claude/skills/`)
- `settings.json` - Claude Code settings including permissions and environment variables

## Sync Scripts

### sync-claude-files.sh
Primary sync script that copies files FROM `~/.claude/` TO this repository:
```bash
./sync-claude-files.sh
```
Use after modifying files in `~/.claude/` to capture changes in git.

### link-new-files.sh
Creates symbolic links from `~/.claude/` to this repository and backs up originals. Use for initial setup or when adding new files.

## Agent/Command File Format

All agents and commands use markdown files with YAML frontmatter:

```markdown
---
name: Agent Name
description: Description text for when the agent is invoked
model: sonnet  # optional: sonnet, opus, haiku
tools: tool1, tool2  # optional: comma-separated tool names
color: orange  # optional: UI color
---

[Agent instructions in markdown]
```

## Key Agents

- **frontend-architect** - React/TypeScript frontend development with performance focus
- **backend-api-architect** - Backend API development
- **code-review-specialist** - Code review with security and best practices focus
- **production-code-validator** - Validates production readiness
- **tech-research-specialist** - Technology research and documentation
- **jira-ticket-executor** - Executes Jira tickets end-to-end

## Key Commands

- **ticket-driver** - TDD-first workflow for implementing Jira tickets with plan review loops
- **bug-killer** - Iterative debugging with observe-hypothesize-test loop
- **code-optimizer** - Reviews PR diffs for optimization opportunities
- **deep-dive-creator** - Generates technical documentation
- **ticket-creator** - Creates structured Jira tickets

## Settings Configuration

The `settings.json` contains:
- `permissions.allow` - Pre-approved tools and Bash command patterns
- `permissions.defaultMode` - Default permission mode (acceptEdits)
- `env` - Environment variables for telemetry/integrations

## Workflow

1. Make changes to agents/commands/settings in `~/.claude/`
2. Run `./sync-claude-files.sh` to copy to this repo
3. Review changes with `git diff`
4. Commit and push to preserve configuration
