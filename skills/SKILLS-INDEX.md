# Skills & Commands Index

## Skills

- **codex-review** — Runs Codex CLI peer review against a PR branch, generates a report, and optionally auto-fixes
- **e2e-debug-finance-funnel** — Debugs finance funnel bugs with playwright-cli in an iterative fix/deploy/verify loop
- **e2e-test-jira-ticket** — Drives an E2E test for a Jira ticket: deploy to stage, drive funnel via playwright-cli, verify pass/fail rule, capture evidence; Mode 1 standalone (proposes 3-item plan + asks operator to confirm) and Mode 2 embedded (`--plan-confirmed` skips dialog, used by `ticket-driver`)
- **fetch-jira-acceptance-criteria** — Fetches acceptance criteria from a Jira ticket's custom field
- **fetch-jira-qa-notes** — Fetches QA notes from a Jira ticket's custom field
- **fix-claude-installation** — Fixes broken Claude Code CLI after failed auto-updates
- **review-pr-comments** — Fetches PR review threads via GraphQL, researches unresolved comments, generates report, optionally auto-fixes
- **find-skills** — Helps discover and install agent skills from the marketplace
- **playwright-cli** — Browser automation reference — commands for navigating, clicking, filling, screenshots
- **skill-authoring** — Best practices guide for creating Claude Code skills and MCP tools

## Commands

- **bug-killer** — Iterative debug loop: observe, hypothesize, test, fix with TDD-first approach
- **code-optimizer** — Reviews PR diff and proposes 3-5 optimizations with plan-review loop
- **deep-dive-creator** — Generates comprehensive 9-section technical deep dive documentation
- **ticket-creator** — Turns a short description into a structured Jira ticket
- **ticket-driver** — End-to-end ticket execution: fetch from Jira, plan, TDD implementation, PR, review
