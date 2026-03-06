# Claude Code Commands

A collection of specialized slash commands, agents, and skills for Claude Code that streamline software development workflows including ticket implementation, debugging, code optimization, E2E testing, and Jira integration.

> **Install once, use everywhere:** These commands, agents, and skills are designed to be installed globally in your home directory (`~/.claude/`) so they're available across all your projects.

## What are Slash Commands?

Slash commands are custom prompts that extend Claude Code's capabilities. When you type a slash command (e.g., `/ticket-driver`), it expands into a detailed prompt that guides Claude through a specific workflow.

**Key features:**
- Defined as markdown files with YAML front matter
- Stored in `.claude/commands/` directory in your project
- Automatically available in Claude Code after installation
- Can accept arguments (e.g., `/ticket-driver TRIDENT-655`)

## What are Agent Commands?

Agent commands are specialized agents that run autonomously to handle complex, multi-step tasks. They have access to specific tools and can make decisions independently.

**Key features:**
- More autonomous than slash commands
- Can perform complex research and exploration
- Useful for tasks requiring multiple tool calls and decision points
- Stored in `.claude/agents/` directory

## What are Skills?

Skills are reusable capabilities that Claude Code can invoke automatically based on context. They provide specialized knowledge and workflows for specific tasks.

**Key features:**
- Triggered automatically when context matches (e.g., browser automation, Jira queries)
- Defined as `SKILL.md` files with optional reference docs
- Stored in `.claude/skills/` directory
- Can declare specific tool permissions

## Available Commands

### Slash Commands

#### `/ticket-driver`
**Purpose:** End-to-end ticket implementation with TDD-first approach

**Usage:**
```
/ticket-driver
/ticket-driver PLAN-MODE <SPRINT_NAME> <JIRA_TICKET_NUMBER>
```

**What it does:**
- Fetches Jira ticket details OR accepts manual inputs
- Automatically handles Git branch creation/checkout
- Produces concrete implementation plan with review loop
- Implements features task-by-task with tests-first approach
- Supports manual input override of Jira data
- Supports `USE-CURRENT-BRANCH` mode to skip branch creation
- Supports `PLAN-MODE` for SprintLoop integration (plan and context only, no execution)

**Modes:**

| Mode | Description |
|------|-------------|
| Standard | Full workflow: plan, review, implement, validate, commit/push/PR |
| `USE-CURRENT-BRANCH` | Same as standard but stays on current branch, skips branch setup |
| `PLAN-MODE` | Creates `plan.md` and `context.md` for SprintLoop — no git ops, no execution |

**PLAN-MODE** generates two files under `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<TICKET>/`:
- `plan.md` — Flat checklist of actionable tasks for the SprintLoop executor
- `context.md` — Full ticket context (summary, acceptance criteria, design decisions, key files) so a separate LLM session can execute the plan independently

**Example workflows:**
```bash
# Standard: implement a ticket end-to-end
/ticket-driver
# → provide TRIDENT-655, review plan, Claude implements with TDD

# Plan-only for SprintLoop
/ticket-driver PLAN-MODE sprint_1 TRIDENT-802
# → creates plan.md + context.md, no code changes
```

---

#### `/bug-killer`
**Purpose:** Comprehensive debugging workflow with end-to-end tracing

**Usage:**
```
/bug-killer
```

**What it does:**
- Applies "observe → hypothesize → test" diagnostic loop
- Maps full request path (frontend → backend → microservices → datastores)
- Integrates Chrome DevTools and backend logging strategies
- Supports `CURRENT` branch mode to debug on existing branch
- Produces deterministic reproduction steps

**Example workflow:**
1. Run `/bug-killer` in Claude Code
2. Describe the bug symptoms and repro steps
3. Specify branch name or use `CURRENT` to stay on existing branch
4. Review diagnostic plan
5. Claude iteratively diagnoses and fixes the issue

---

#### `/code-optimizer`
**Purpose:** Reviews feature branch changes and proposes optimizations

**Usage:**
```
/code-optimizer
```

**What it does:**
- Analyzes PR diff against target branch (default: `main`)
- Proposes 3-5 concrete optimizations
- Checks React hooks compliance, performance patterns, DRY violations
- Implements optimizations with TDD-first approach
- Provides Big O analysis where applicable

**Example workflow:**
1. Checkout your feature branch
2. Run `/code-optimizer` in Claude Code
3. Specify branch name or use `CURRENT`
4. Review optimization proposals
5. Claude implements approved optimizations

---

#### `/ticket-creator`
**Purpose:** Transform descriptions into structured Jira tickets

**Usage:**
```
/ticket-creator <brief description>
```

**What it does:**
- Asks clarifying questions when needed
- Generates complete Jira ticket with:
  - User Story (in Trident team format)
  - Description
  - Acceptance Criteria
  - Technical Details (optional)
  - Testing Methodology
- Interactive refinement loop

**Example workflow:**
```
/ticket-creator Add user authentication with JWT tokens
```

---

#### `/deep-dive-creator`
**Purpose:** Generate comprehensive technical deep dive documentation

**Usage:**
```
/deep-dive-creator
```

**What it does:**
- Takes project name and main feature flows (required), plus optional codebase references and project context
- Produces a structured 9-section Markdown document covering:
  - Architecture, data & integrations, security, reliability
  - Implementation highlights, testing, operational readiness
  - Technical roadmap
- Tailored for executive and senior engineering audience (CTO, principals, security directors)
- Explores the codebase to understand how features are actually implemented

---

#### `/generate-test-run-blocks`
**Purpose:** Generate `<TEST_TO_RUN>` blocks for the E2E test agent

**Usage:**
```
/generate-test-run-blocks <Jira ticket key or test description>
/generate-test-run-blocks TRIDENT-813
/generate-test-run-blocks TRIDENT-813 prequal-only
```

**What it does:**
- Accepts a Jira ticket key or free-form test description
- Fetches ticket details (summary, description, acceptance criteria, QA notes) when given a Jira key
- Generates one or more `<TEST_TO_RUN>` blocks formatted for the `e2e-test-combined-flow` skill
- Supports `prequal-only` mode to stop after the Results page login
- Supports `qa` or `prod` environment targeting

---

### Agents

#### `frontend-architect`
**Purpose:** React/TypeScript frontend development with performance focus

Specializes in modern React development with TypeScript, Next.js, Tailwind CSS, and shadcn/ui. Handles component architecture, state management, responsive design, hooks compliance, and rendering performance optimization.

**Triggers:** Creating/refactoring React components, UI performance issues, component structure improvements.

---

#### `backend-api-architect`
**Purpose:** Backend API design and implementation

Expert in REST API design, database schemas, server-side business logic, authentication/authorization, middleware, and error handling patterns. Covers API security, server configuration, and backend testing.

**Triggers:** API endpoint creation, database design, authentication debugging, server-side validation.

---

#### `code-review-specialist`
**Purpose:** Comprehensive code review with security and best practices focus

Conducts thorough code reviews covering correctness, security, performance, maintainability, and style. Balances rigor with constructive feedback.

**Triggers:** User asks for code review, completes a feature/refactor, or finishes a code change.

---

#### `production-code-validator`
**Purpose:** Validates code for production readiness

Checks for placeholder code, TODO/FIXME comments, hardcoded values, debugging artifacts, and security issues. Specifically designed for deployment readiness checks.

**Triggers:** User asks "is this production ready?", "ready to deploy?", or similar deployment readiness questions.

---

#### `tech-research-specialist`
**Purpose:** Technology research and documentation

Researches frameworks, libraries, APIs, tools, and technical concepts. Synthesizes documentation into clear, actionable knowledge. Has access to Confluence and Jira for internal documentation.

**Triggers:** Learning about new technologies, API integration research, best practices exploration.

---

### Skills

| Skill | Description |
|-------|-------------|
| **playwright-cli** | Browser automation for web testing, form filling, screenshots, and data extraction |
| **e2e-test-combined-flow** | End-to-end testing of the combined app flow using Playwright in headed browser mode |
| **e2e-debug-finance-funnel** | Debug finance funnel issues with iterative browser automation (reproduce → investigate → fix → verify) |
| **combined-flow-retired-path** | Drive through the combined loan application funnel using the "retired flow" (minimum tabs path) |
| **codex-review** | Run OpenAI Codex CLI peer review against a branch, generating a structured report with fix/no-fix determinations |
| **review-pr-comments** | Analyze GitHub PR review threads, research unresolved comments, and optionally auto-fix issues |
| **fetch-jira-acceptance-criteria** | Extract Acceptance Criteria from a Jira ticket's custom field |
| **fetch-jira-qa-notes** | Extract QA Notes from a Jira ticket's custom field |
| **skill-authoring** | Best practices for creating Claude Code skills, MCP tools, and AI agent capabilities |
| **find-skills** | Discover and install skills from the open agent skills ecosystem |
| **fix-claude-installation** | Fix broken Claude Code CLI installation caused by failed auto-updates |

## Installation

### Quick Start (Recommended)

Install these commands globally so they're available in **all your projects**:

```bash
# 1. Clone this repository
git clone git@github.com:boatsgroup/claude-code-commands.git
cd claude-code-commands

# 2. Create global Claude directories if they don't exist
mkdir -p ~/.claude/commands ~/.claude/agents ~/.claude/skills

# 3. Copy all files to your global directories
cp commands/*.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
cp -r skills/* ~/.claude/skills/

# 4. Verify installation
ls ~/.claude/commands/
ls ~/.claude/agents/
ls ~/.claude/skills/
```

### Verify Installation

1. Open **any project** in VS Code or Cursor
2. Start Claude Code
3. Type `/` to see available commands
4. You should see `/ticket-driver`, `/bug-killer`, `/code-optimizer`, `/ticket-creator`, `/deep-dive-creator`, and `/generate-test-run-blocks`

### Alternative: Project-Specific Installation

If you prefer to install commands only for a specific project (e.g., for team-specific workflows):

```bash
# In your project directory
mkdir -p .claude/commands
cp /path/to/claude-code-commands/commands/*.md .claude/commands/

# Optional: Commit to version control for team sharing
git add .claude/commands/
git commit -m "Add Claude Code custom commands"
```

**Note:** Global commands (`~/.claude/commands/`) are available in all projects, while project-specific commands (`.claude/commands/`) only work in that project. Project-specific commands override global ones if they have the same name.

## Repository Structure

```
claude-code-commands/
├── README.md                    # This file
├── CLAUDE.md                    # Guidance for Claude Code instances
├── sync-claude-files.sh         # Sync files FROM ~/.claude/ TO this repo
├── sync-and-push.sh             # Sync, commit, push, and create PR in one step
├── settings.json                # Claude Code settings (permissions, env vars)
├── commands/                    # Slash command definitions
│   ├── ticket-driver.md
│   ├── bug-killer.md
│   ├── code-optimizer.md
│   ├── ticket-creator.md
│   ├── deep-dive-creator.md
│   └── generate-test-run-blocks.md
├── agents/                      # Agent definitions
│   ├── frontend-architect.md
│   ├── backend-api-architect.md
│   ├── code-review-specialist.md
│   ├── production-code-validator.md
│   └── tech-research-specialist.md
├── skills/                      # Skill definitions
│   ├── playwright-cli/
│   ├── e2e-test-combined-flow/
│   ├── e2e-debug-finance-funnel/
│   ├── combined-flow-retired-path/
│   ├── codex-review/
│   ├── review-pr-comments/
│   ├── fetch-jira-acceptance-criteria/
│   ├── fetch-jira-qa-notes/
│   ├── skill-authoring/
│   ├── find-skills/
│   └── fix-claude-installation/
├── plugins/                     # Installed plugins config
└── RalphLoops/                  # RalphLoops SprintLoop data
```

## Sync Scripts

### `sync-claude-files.sh`

Primary sync script that copies files **from** `~/.claude/` **to** this repository:

```bash
./sync-claude-files.sh
```

Use after modifying files in `~/.claude/` to capture changes in git.

### `sync-and-push.sh`

All-in-one script that creates a dated branch, syncs files, commits, pushes, and creates a PR:

```bash
./sync-and-push.sh
# Creates branch: latest-changes-Mar-5-26
# Runs sync, commits, pushes, opens PR against main
```

## Common Patterns

All commands in this repository follow these conventions:

### Git Branch Handling
- **Named branch mode**: Creates or checks out specified branch
- **`CURRENT` mode**: Works on existing branch without switching
- Always respects clean working tree
- Asks before rebasing/merging

### Plan Review Loop
1. Generate initial plan
2. Present to user for review
3. Accept edits and refine
4. Repeat until user says "no further changes"
5. Execute approved plan

### TDD-First Approach
1. Write failing tests first
2. Implement minimal code to pass tests
3. Run formatter/linter/typecheck
4. Iterate until green
5. Move to next task

### File Edits
- Applied immediately (no batching)
- Concise diff summaries shown
- Minimal changes (no speculative refactors)
- Confirmation required for >5 files

## Requirements

- Claude Code CLI (https://claude.ai/code)
- Git installed and configured
- For Jira integration: `gh` CLI or Jira API access (via Atlassian MCP)
- For E2E testing skills: `playwright-cli` installed
- For Codex review: OpenAI Codex CLI installed

## Contributing

To add new commands, agents, or skills:

1. Create files in the appropriate directory (`commands/`, `agents/`, or `skills/`)
2. Add YAML front matter with `name` and `description`
3. Write the instructions following existing patterns
4. Test thoroughly in various project contexts
5. Run `./sync-claude-files.sh` to sync from `~/.claude/`
6. Update this README with usage instructions

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.
