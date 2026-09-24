<!--
  TEMPLATE: agents-bootstrap-section.md
  PURPOSE : "Cross-Repo Bootstrap" section inserted into every repo's AGENTS.md body.
            This section teaches agents (and engineers) how to pull cross-repo context
            before starting work in any Mobius repo.

  PLACEMENT: Add this section immediately after the opening # heading (or after any
             existing Quick Reference / intro block) and before repo-specific sections
             like "Skills", "Working Rules", etc.

  USAGE   : Copy the Markdown below the dashed separator verbatim.
            No placeholders to fill in — this section is IDENTICAL across all repos.

  SHARED vs UNIQUE:
    - This entire section is SHARED.  Do not customise it per-repo.
    - The reading order in "After Resolution" intentionally stays generic; each
      repo's AGENTS.md "Ecosystem Position" section carries the repo-specific map.

  DEPENDENCY: Requires the YAML frontmatter (agents-frontmatter.md) to be present
              at the top of the file so that resolve-deps.sh can read the dependency
              list.
-->

<!-- ======================================================
     COPY FROM HERE ↓  (paste into AGENTS.md body)
     ====================================================== -->

## Cross-Repo Bootstrap

This repo is part of the **Mobius platform** (multi-repo DevOps platform).
Cross-repo context (ecosystem.md, skills, docs) is available through the shared
resolver in `mobius-tools`.

### Docs-First Reading Protocol (MANDATORY)

**STOP. Before answering questions, making changes, or exploring source code in this repository, complete this reading list.**

If any file below does not exist, skip it and continue to the next.

1. `.claude/ecosystem.md` — repo role, relationships, and operational context
2. `docs/README.md` — documentation navigation hub
3. `docs/architecture.md` — service architecture, tech stack, patterns
4. `docs/workflow.md` — development, testing, building, deployment
5. `docs/dependencies.md` — platform and runtime dependencies

#### Token Conservation Rule

- You MUST read the docs listed above before scanning any source code.
- You MUST NOT launch explore agents, grep searches, or file reads against source code until docs have been consulted.
- If the docs answer the question, STOP. Respond from docs alone.
- Source code is a FALLBACK — only when docs have a gap for the specific question asked.

#### Source Code Rules

- NEVER open source files to answer a question that docs already answer.
- When docs and code conflict, code wins — but note the discrepancy for the user.

### Resolve Dependencies

**Step 1** — Ensure mobius-tools is available:

```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
```

**Step 2** — Run the resolver:

```bash
bash ../mobius-tools/scripts/resolve-deps.sh
```

This will locate or clone all dependency repos listed in the frontmatter above,
freshen them if already present, and update `.claude/settings.local.json` so you
have native file access to all dependencies.

### After Resolution

Read additional cross-repo context in this order (`.claude/ecosystem.md` should already be loaded per Essential Context above):

1. `../mobius-tools/ecosystem/master-map.md` (full platform overview)
2. Each dependency's `.claude/ecosystem.md` (their perspective)
3. Relevant `.claude/skills/*/SKILL.md` from dependency repos

### Research Protocol

Before answering questions or making changes, follow the **Internal-First Research Protocol**.

Ensure `../mobius-tools` is available (clone if needed — even if Step 1 above was skipped):
```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
```
Then resolve all cross-repo dependencies and build CLI tools:
```bash
bash ../mobius-tools/scripts/resolve-deps.sh
( cd ../mobius-tools && [ -d dist ] || npm install )
```

Then read the skill: `../mobius-tools/.claude/skills/internal-first-research/SKILL.md`

Key rule: **exhaust internal documentation before searching the web.**
For blast radius analysis: `npx mobius-trace-impact <repo-name>`

> **No bash?** If you cannot execute commands, apply the key rule using only this repo's
> docs (`AGENTS.md`, `.claude/ecosystem.md`). Flag to the user that cross-repo context is unavailable.
### If Resolution Fails

If `gh` is not available or not authenticated:

1. Install: `brew install gh`
2. Authenticate: `gh auth login`
3. Re-run the resolver

<!-- ======================================================
     COPY TO HERE ↑
     ====================================================== -->
