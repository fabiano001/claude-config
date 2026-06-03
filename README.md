# Claude Code Commands

A collection of specialized skills, agents, and workflows for Claude Code that streamline software development workflows including ticket implementation, debugging, code optimization, E2E testing, and Jira integration.

> **Install once, use everywhere:** These skills and agents are designed to be installed globally in your home directory (`~/.claude/`) so they're available across all your projects.

## What are Skills?

Skills are the primary way to extend Claude Code's capabilities. When you type a slash command (e.g., `/ticket-driver`), it loads a skill that guides Claude through a specific workflow. Skills can also be triggered automatically based on context.

**Key features:**
- Defined as `SKILL.md` files with YAML front matter inside a named directory
- Stored in `~/.claude/skills/<skill-name>/SKILL.md`
- Automatically available in Claude Code after installation
- Can accept arguments (e.g., `/ticket-driver TRIDENT-655`)
- Can declare specific tool permissions and context isolation

> **Note:** The legacy `.claude/commands/` format has been deprecated by Claude Code. All former commands have been migrated to skills.

## What are Agents?

Agents are specialized autonomous processors that handle complex, multi-step tasks. They have access to specific tools and can make decisions independently.

**Key features:**
- More autonomous than skills
- Can perform complex research and exploration
- Useful for tasks requiring multiple tool calls and decision points
- Stored in `.claude/agents/` directory

## Available Skills

### Workflow Skills

#### `/ticket-driver`
**Purpose:** End-to-end ticket implementation with TDD-first approach

**Usage:**
```
/ticket-driver
/ticket-driver PLAN-MODE <SPRINT_NAME> <TICKET_NAME>
```

**What it does:**
- Fetches Jira ticket details OR accepts manual inputs
- Automatically handles Git branch creation/checkout
- Produces concrete implementation plan with mandatory review loop
- Dispatches execution to an autonomous Agent subagent (inherits parent permissions, no user interaction)
- Subagent writes progress to `dynamic-app/docs/status.md` and learnings to `dynamic-app/docs/learnings.md`
- After execution, reads learnings and runs `/review-pr-comments` and `/codex-review` autonomously
- Supports manual input override of Jira data
- Supports `USE-CURRENT-BRANCH` mode to skip branch creation
- Supports `PLAN-MODE` for SprintLoop integration (plan and context only, no execution)

**Ticket Name Resolution:** Strips `-TEST` or `-TEST-<N>` suffixes for Jira lookups only. `TRIDENT-802-TEST-2` fetches from `TRIDENT-802` in Jira but uses `TRIDENT-802-TEST-2` for branch name, save directory, and PR title.

**Modes:**

| Mode | Description |
|------|-------------|
| Standard | Plan interactively, then dispatch autonomous execution via Agent subagent |
| `USE-CURRENT-BRANCH` | Same as standard but stays on current branch, skips branch setup |
| `PLAN-MODE` | Creates `plan.md` and `context.md` for SprintLoop — no git ops, no execution |

**PLAN-MODE** generates two files under `~/RalphLoops/SprintLoop/Sprints/<SPRINT_NAME>/<TICKET_NAME>/`:
- `plan.md` — Flat checklist of actionable tasks for the SprintLoop executor
- `context.md` — Full ticket context (summary, acceptance criteria, design decisions, key files) so a separate LLM session can execute the plan independently

**Example workflows:**
```bash
# Standard: implement a ticket end-to-end
/ticket-driver
# → provide TRIDENT-655, review plan, autonomous execution via subagent

# Plan-only for SprintLoop
/ticket-driver PLAN-MODE sprint_1 TRIDENT-802
# → creates plan.md + context.md, no code changes

# Test sprint with suffix (fetches TRIDENT-802 from Jira, saves to TRIDENT-802-TEST-2/)
/ticket-driver PLAN-MODE test_sprint TRIDENT-802-TEST-2
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

#### `/e2e-test-jira-ticket`
**Purpose:** Drive an end-to-end test for a Jira ticket using `playwright-cli` in a headed browser

**Usage:**
```
/e2e-test-jira-ticket <TICKET_KEY>
/e2e-test-jira-ticket <TICKET_KEY> --plan-confirmed
```

**What it does:**
- Deploys the change to stage, drives the funnel through `playwright-cli`, verifies the pass/fail rule, and captures evidence
- **Mode 1 (standalone):** Proposes a 3-item plan and asks the operator to confirm before execution
- **Mode 2 (embedded):** `--plan-confirmed` skips the confirmation dialog — used internally by `/ticket-driver`

---

#### `/research`
**Purpose:** Research a topic in the current codebase and answer specific questions

**Usage:**
```
/research <topic or question>
/research <topic> inline output
```

**What it does:**
- Reads code thoroughly (entry points, helpers, callers, types, tests, config) until every question is answered
- Produces a concise technical write-up saved to `~/.claude/memory/research/<topic>.md` and indexed in `~/.claude/memory/research/index.md`
- Checks the index for prior research on the same topic and offers it before starting fresh work
- Use the literal phrase `inline output` (or `output inline`) to print the write-up to the terminal instead of writing a file

---

#### `/bq-analyst`
**Purpose:** Answer natural-language analytics questions about Trident Funding loan applications via BigQuery

**Usage:**
```
/bq-analyst <analytics question>
```

**What it does:**
- Generates BigQuery SQL against the `loan_export_1` dataset
- Dry-runs the query for cost validation, then returns a 50-row preview
- Triggers on questions about submitted loans, marketplaces (BoatTrader/YachtWorld/Boats.com), prequal, LendAPI, etc.
- Read-only — never writes data and never exports PII
- Backed by the `bq-analyst` MCP server (`functions/src/mcp-server`) for schema introspection

---

#### `/jira-sprint-manager`
**Purpose:** Daily Jira sprint status report and auto-actions for the Trident BG board (391)

**Usage:**
```
/jira-sprint-manager
/jira-sprint-manager autonomous
```

**What it does:**
- Fetches every ticket in the active sprint assigned to the operator (Fabiano Desouza), sorted by board priority within each status
- Runs six auto-action rules per invocation:
  - **Rule A** — Kickoff: transitions the top-of-New ticket to `In Progress` when nothing is currently in progress (skips blocked/impediment-flagged tickets)
  - **Rule B** — Live-ticket follow-up: Live QA pre-check, reminders, and close prompts
  - **Rule C** — `PROD READY` deploys: merge-to-main driven prod deploys with templated Jira comment
  - **Rule D** — In Progress worktree kickoff: spawns a worktree + fresh Claude session via `open-claude-session.sh` for implementation or research
  - **Rule E** — Testing-lane QA verification: confirms QA pass and transitions to `Under Review`
  - **Rule F** — Under-Review PR approval: auto-transitions to `PROD READY` or `Stakeholder Review` once all PRs are approved
- **Autonomous mode** (`/jira-sprint-manager autonomous`) — runs ONLY lane-moving rules that never queue questions (Rule A + Rule F). Designed for scheduled/cron-driven runs; writes no report file on a quiet day
- Writes a dated markdown report to `~/.claude/memory/jira-sprint-manager/<MM-DD-YY>.md` (never overwrites — appends `-v2`, `-v3`, … suffixes)
- Designed for daily scheduled execution but also runs on demand
- Does NOT execute `/ticket-driver` or `/ticket-creator` directly — it spawns those in fresh Claude sessions

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

### Utility Skills

| Skill | Description |
|-------|-------------|
| **playwright-cli** | Browser automation for web testing, form filling, screenshots, and data extraction |
| **e2e-debug-finance-funnel** | Debug finance funnel issues with iterative browser automation (reproduce → investigate → fix → verify) |
| **codex-review** | Run OpenAI Codex CLI peer review against a GitHub PR URL, generating a structured report with fix/no-fix determinations (defaults to blind-debate mode) |
| **review-pr-comments** | Analyze GitHub PR review threads, research unresolved comments, and optionally auto-fix issues |
| **fetch-jira-acceptance-criteria** | Extract Acceptance Criteria from a Jira ticket's custom field |
| **fetch-jira-qa-notes** | Extract QA Notes from a Jira ticket's custom field |
| **skill-authoring** | Best practices for creating Claude Code skills, MCP tools, and AI agent capabilities |
| **find-skills** | Discover and install skills from the open agent skills ecosystem |
| **fix-claude-installation** | Fix broken Claude Code CLI installation caused by failed auto-updates |
| **grill-me** | Interview the user relentlessly about a plan or design until shared understanding is reached (used by `ticket-creator` during clarification) |

## Plugins

This repo also tracks installed Claude Code plugin marketplaces under `plugins/marketplaces/`.

### `agent-peer-review-marketplace`

A marketplace for AI-to-AI peer validation plugins. Ships the **`codex-peer-review`** plugin, which dispatches a `codex-peer-reviewer` subagent (powered by OpenAI Codex CLI) to second-opinion Claude's designs, code reviews, and recommendations before they reach the user.

**How it works:**
1. Claude forms an opinion
2. A subagent runs the peer review agent in an isolated context (keeps the main conversation clean)
3. Findings are classified as agreement, disagreement, or complement
4. Persistent conflicts escalate to Perplexity MCP (or WebSearch fallback) for arbitration

**Trigger:**
```
/codex-peer-review              # current changes
/codex-peer-review --base <branch>
/codex-peer-review <question>   # for broad technical validation
```

**Prerequisites:** OpenAI Codex CLI installed (`npm i -g @openai/codex` + `codex login`).

### `claude-plugins-official`

The official Claude Code plugin marketplace (mirrored locally). Includes plugins like `code-review`, `commit-commands`, `feature-dev`, `plugin-dev`, `hookify`, `skill-creator`, `pr-review-toolkit`, language-specific LSP plugins, and more.

## Installation

### Quick Start (Recommended)

Install these skills globally so they're available in **all your projects**:

```bash
# 1. Clone this repository
git clone git@github.com:boatsgroup/claude-code-commands.git
cd claude-code-commands

# 2. Create global Claude directories if they don't exist
mkdir -p ~/.claude/agents ~/.claude/skills

# 3. Copy all files to your global directories
cp agents/*.md ~/.claude/agents/
cp -r skills/* ~/.claude/skills/

# 4. Verify installation
ls ~/.claude/agents/
ls ~/.claude/skills/
```

### Verify Installation

1. Open **any project** in VS Code or Cursor
2. Start Claude Code
3. Type `/` to see available skills
4. You should see `/ticket-driver`, `/bug-killer`, `/code-optimizer`, `/ticket-creator`, `/deep-dive-creator`, `/e2e-test-jira-ticket`, `/research`, `/bq-analyst`, and `/jira-sprint-manager`

### Alternative: Project-Specific Installation

If you prefer to install skills only for a specific project (e.g., for team-specific workflows):

```bash
# In your project directory
mkdir -p .claude/skills
cp -r /path/to/claude-code-commands/skills/* .claude/skills/

# Optional: Commit to version control for team sharing
git add .claude/skills/
git commit -m "Add Claude Code custom skills"
```

**Note:** Global skills (`~/.claude/skills/`) are available in all projects, while project-specific skills (`.claude/skills/`) only work in that project. Personal skills override project-level ones if they have the same name.

## Repository Structure

```
claude-code-commands/
├── README.md                    # This file
├── CLAUDE.md                    # Guidance for Claude Code instances
├── sync-claude-files.sh         # Sync files FROM ~/.claude/ TO this repo
├── sync-and-push.sh             # Sync, commit, push, and create PR in one step
├── settings.json                # Claude Code settings (permissions, env vars)
├── agents/                      # Agent definitions
│   ├── frontend-architect.md
│   ├── backend-api-architect.md
│   ├── code-review-specialist.md
│   ├── production-code-validator.md
│   └── tech-research-specialist.md
├── skills/                      # All skills (workflow + utility)
│   ├── SKILLS-INDEX.md          # Quick index of skills and commands
│   ├── ticket-driver/           # End-to-end ticket implementation
│   ├── bug-killer/              # Debugging workflow
│   ├── code-optimizer/          # PR diff optimization
│   ├── ticket-creator/          # Jira ticket generation
│   ├── deep-dive-creator/       # Technical documentation
│   ├── e2e-test-jira-ticket/    # E2E test driver for a Jira ticket
│   ├── research/                # Codebase research + memory-backed write-ups
│   ├── bq-analyst/              # BigQuery analytics for Trident loans
│   ├── jira-sprint-manager/     # Daily sprint status report + auto-actions
│   ├── playwright-cli/
│   ├── e2e-debug-finance-funnel/
│   ├── codex-review/
│   ├── review-pr-comments/
│   ├── fetch-jira-acceptance-criteria/
│   ├── fetch-jira-qa-notes/
│   ├── skill-authoring/
│   ├── find-skills/
│   ├── fix-claude-installation/
│   └── grill-me/                # Interview helper used by ticket-creator
├── plugins/
│   ├── marketplaces/            # Installed plugin marketplaces
│   │   ├── agent-peer-review-marketplace/  # Codex peer-review plugin
│   │   └── claude-plugins-official/        # Official Claude Code plugins
│   ├── repos/
│   └── data/
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

To add new skills or agents:

1. For skills: create `skills/<name>/SKILL.md` with YAML front matter (`name`, `description`)
2. For agents: create `agents/<name>.md` with YAML front matter
3. Write the instructions following existing patterns
4. Test thoroughly in various project contexts
5. Run `./sync-claude-files.sh` to sync from `~/.claude/`
6. Update this README with usage instructions

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.
