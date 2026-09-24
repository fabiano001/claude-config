# Agent Interoperability Guide

> **Audience**: Platform engineers and AI agents (Claude Code, Codex, or any
> agent that reads AGENTS.md). This document explains how Claude and Codex
> share the same workflow layer and what each agent should do when it starts
> a session.

---

## Overview

The Mobius platform uses `mobius-tools` as a shared knowledge layer that both
Claude Code and Codex can read and follow. The design principle is:

> **Instructions are text, not hooks.**
> Any agent that can read a file can follow these workflows — no special
> tool integration, hooks, or plugins required.

---

## Session Bootstrap Protocol (All Agents)

Regardless of which AI agent you are, the bootstrap sequence is identical:

### Deterministic Bootstrap Checklist

Use this exact sequence at session start:

1. Read current repo `AGENTS.md`.
2. Read current repo `.claude/ecosystem.md` (**must read** — contains repo role, relationships, and operational context).
3. Ensure `../mobius-tools` exists (clone if missing).
4. Run `bash ../mobius-tools/scripts/resolve-deps.sh`.
5. Read `../mobius-tools/ecosystem/master-map.md`.
6. Read `CLAUDE.md` (or `docs/CLAUDE.md`) and relevant skill files.
7. Read `docs/` files on demand (architecture, workflow, dependencies) when deeper context is needed.

For long sessions after compaction, repeat steps 1-2 and 5-6 before continuing.

### Step 1 — Read this repo's AGENTS.md

Every Mobius repo's `AGENTS.md` is the primary entrypoint. It contains:
- YAML frontmatter declaring cross-repo dependencies
- Bootstrap instructions to run the resolver
- Working rules and conventions

```
Priority read order (per repo):
1. AGENTS.md                          ← always first (auto-loaded by Claude/Codex)
2. .claude/ecosystem.md               ← MUST READ — repo role, relationships, context
3. CLAUDE.md (or docs/CLAUDE.md)      ← repo-specific conventions
4. Relevant .claude/skills/*/SKILL.md ← procedural checklists
5. docs/*.md                          ← on demand (architecture, workflow, dependencies)
```

### Step 2 — Bootstrap mobius-tools

```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
```

If TypeScript validators are needed (any `npx mobius-validate-*` command), ensure they're built:

```bash
# Only needed once after clone — npm install triggers build automatically
[ -d "../mobius-tools/dist" ] || (cd ../mobius-tools && npm install)
```

### Step 3 — Run the resolver

```bash
bash ../mobius-tools/scripts/resolve-deps.sh
```

The resolver clones missing dependency repos and updates `.claude/settings.local.json`
so the agent has file access to all required repos.

### Step 4 — Read ecosystem context

```bash
# Full platform map
cat ../mobius-tools/ecosystem/master-map.md

# Workflow index
cat ../mobius-tools/docs/workflows/INDEX.md
```


## Internal-First Research Protocol

When asked a question or before making changes in any Mobius repo, agents MUST
follow a strict information hierarchy. This prevents incorrect assumptions and
ensures blast-radius awareness.

**Full protocol**: `.claude/skills/internal-first-research/SKILL.md`

**Quick reference**:
1. Read internal docs (AGENTS.md → ecosystem.md → master-map → dependency-graph → workflows)
2. Correlate across repos (cross-reference, map dependency chains)
3. Search external only after exhausting internal sources
4. Trace dependency paths (manifests → charts → modules → AWS resources)
5. Blast radius analysis before any change (HARD BLOCK on core/gitops repos)

**Automated impact analysis**:
```bash
npx mobius-trace-impact <repo-name>
```

**Bootstrap guard**: The Research Protocol in each repo's AGENTS.md includes inline
clone and resolve commands for `mobius-tools`. This ensures the skill file and all
cross-repo dependencies are accessible even if the agent skipped the main bootstrap
sequence (Step 1 in Resolve Dependencies). The clone step must never be skipped — if
even one dependency repo is missing, `resolve-deps.sh` will fetch it. If the agent
has no bash access, it should follow the key rule using local docs only and flag to
the user that cross-repo context is unavailable.

---

## Claude Code — Specific Behavior

Claude Code reads `AGENTS.md` automatically at session start via the
`userPromptPrefix` or file-read mechanisms built into the CLI.

### Capabilities

| Capability | Claude Code |
|------------|-------------|
| Read files across repos | Yes (via `additionalDirectories` in settings.local.json) |
| Write files | Yes |
| Run bash commands | Yes |
| Follow multi-repo workflows | Yes |
| Use skills (per-repo SKILL.md) | Yes — skills auto-activate by keyword or path |

### How Skills Activate

Claude Code loads skills from `.claude/skills/<name>/SKILL.md` in the current
repo. Skills are keyed by:
- **Keywords** in the user's prompt (e.g., "add service" → `addons-addon`)
- **File paths** being edited (e.g., editing `argocd/*/overlays/*/config.yaml`)

When a skill activates, Claude uses its checklist and freedom-level constraints
in addition to the workflow docs in `mobius-tools`.

### Persistence After Compaction

After context compaction, Claude must re-read:
1. Current repo `AGENTS.md`
2. Current repo `.claude/ecosystem.md`
3. `../mobius-tools/ecosystem/master-map.md`
4. Relevant skill files

This restores the full working context.

---

## Codex — Specific Behavior

Codex reads `AGENTS.md` via the standard file-read mechanism. It follows
the same bootstrap protocol as Claude, using the text instructions directly.

### Capabilities

| Capability | Codex |
|------------|-------|
| Read files across repos | Yes (if repos are cloned as siblings) |
| Write files | Yes |
| Run bash commands | Yes |
| Follow multi-repo workflows | Yes |
| Use per-repo skills | Yes — reads SKILL.md directly |

### Codex Session Notes

- Codex does not use `settings.local.json` for file access — it relies on
  the filesystem directly. Sibling repos cloned by the resolver are accessible
  by path.
- Codex should run `bash ../mobius-tools/scripts/resolve-deps.sh` to ensure
  sibling repos exist before attempting cross-repo operations.
- Codex reads skill files from `.claude/skills/*/SKILL.md` as regular docs.

---

## Shared Workflow Layer

Both agents share the same canonical workflow docs:

```
mobius-tools/docs/workflows/
├── INDEX.md                                 ← Start here
├── services/
│   └── add-service.md                       ← Adding a new EKS service
├── xrd/
│   └── new-xrd.md                           ← Creating a new Crossplane XRD
└── argocd/
    ├── new-project-or-applicationset.md     ← Adding project/ApplicationSet
    ├── debug-applicationset.md              ← Diagnosing discovery failures
    └── argocd-cli-auth.md                   ← ArgoCD CLI authentication
```

All workflow docs are:
- **Agent-neutral**: no agent-specific syntax or tool calls
- **Self-contained**: each doc has all required context
- **Verified**: each step has a validation command
- **Cross-linked**: reference per-repo skills where deeper checklists exist

---

## Command-First Invocation (Recommended)

Instead of typing full workflow doc paths, use slash commands for a path-free UX:

```
/mobius:help           → List all mobius commands
/mobius:add-service    → Route to docs/workflows/services/add-service.md
/mobius:new-xrd        → Route to docs/workflows/xrd/new-xrd.md
/mobius:new-project    → Route to docs/workflows/argocd/new-project-or-applicationset.md
/mobius:debug-appset   → Route to docs/workflows/argocd/debug-applicationset.md
/mobius:debug-service  → Self-contained (auth: docs/workflows/argocd/argocd-cli-auth.md)
```

**Installation:**
```bash
bash ../mobius-tools/scripts/install-command-pack.sh --force
```

Commands are installed to `~/.claude/commands/mobius/`. Each command references
the underlying workflow doc, so behavior is identical to reading the doc directly.

**Fallback:** If commands are not installed, reference workflow docs directly:
```bash
cat ../mobius-tools/docs/workflows/INDEX.md
cat ../mobius-tools/docs/workflows/services/add-service.md
```

---

## Conflict Resolution

If per-repo skill instructions conflict with workflow docs in `mobius-tools`:

1. **Per-repo skills** take precedence for single-repo operations (they have
   more recent, repo-specific context)
2. **Workflow docs** take precedence for cross-repo sequencing (merge order,
   which repo to update first)
3. **AGENTS.md working rules** take precedence for anti-patterns and
   forbidden operations

---

## Handoff Between Agents

When work is handed from one agent to another (e.g., Claude starts a task,
Codex continues):

1. The receiving agent reads the current repo's `AGENTS.md`
2. Runs the resolver to ensure all deps are present
3. Reads the relevant workflow doc from `mobius-tools/docs/workflows/`
4. Checks the git status of all touched repos to understand current state
5. Continues from the last completed step (look for leftover WIP branches)

```bash
# Quick handoff state check
git status
git log --oneline -5
find . -name "*.yaml" -newer AGENTS.md 2>/dev/null | head -10
```

---

## What NOT to Do (Shared Anti-Patterns)

These anti-patterns apply equally to both Claude and Codex:

| Anti-Pattern | Why Forbidden |
|--------------|--------------|
| Create per-repo resolver scripts | All resolver logic lives in `mobius-tools` only |
| Add `insecure: true` / `skipTLSVerify: true` | Security violation |
| Commit `settings.local.json` | Contains local absolute paths — git-ignored by design |
| Use `force: true` in ArgoCD sync | Can cause data loss |
| Add Go-templated XRDs to `iac-eks-crossplane` | Legacy pattern — use KCL Configuration packages |
| Import helpers in KCL `main.k` | KCL flat-file pattern — imports break compilation |
| Put `testBranch` on a feature branch | Only takes effect when merged to `main` |
| Deploy claims before compositions are ready | "No Composition found" errors |
| Hardcode secrets in YAML | Use ExternalSecrets / IRSA |

---

## Validation: Am I Reading the Right Docs?

Run this check at the start of any session:

```bash
# Verify mobius-tools is available and on main
ls ../mobius-tools/docs/workflows/INDEX.md && echo "✓ Workflow index found"
git -C ../mobius-tools branch --show-current  # Should be main

# Verify resolver scripts are present
ls ../mobius-tools/scripts/resolve-deps.sh && echo "✓ Resolver found"
ls ../mobius-tools/scripts/lib/parse-frontmatter.sh && echo "✓ Parser found"

# Verify dependency graph is readable
head -5 ../mobius-tools/ecosystem/dependency-graph.yaml
```

---

## Extending This Layer

When you add a new canonical workflow:

1. Create the doc in `mobius-tools/docs/workflows/<area>/<name>.md`
2. Add it to `docs/workflows/INDEX.md`
3. Cross-link from relevant per-repo `SKILL.md` files
4. Add a pointer in this doc if the workflow introduces new agent behavior

The goal is that both Claude and Codex will discover the new workflow
automatically — from `AGENTS.md` → resolver → `docs/workflows/INDEX.md` →
specific workflow doc.
