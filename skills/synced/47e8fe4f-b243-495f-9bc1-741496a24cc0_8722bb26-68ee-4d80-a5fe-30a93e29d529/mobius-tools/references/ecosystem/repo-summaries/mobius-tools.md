# mobius-tools

**Role**: Ecosystem SDK — the central tooling repo for the Mobius platform.
Houses the dependency resolver, master ecosystem map, onboarding docs,
and drift detection scripts.

**Tier**: meta

## What It Does

Provides the shared infrastructure that enables agents and developers to work
across the entire Mobius platform. The resolver script reads YAML frontmatter
from any Mobius repo's AGENTS.md, locates or clones all declared dependencies,
freshens existing clones, and updates Claude Code's `additionalDirectories` for
native file access. This repo is the single source of truth for scripts, docs,
and the authoritative dependency graph — no per-repo scripts needed.

## Key Files

| File | Purpose |
|------|---------|
| `scripts/resolve-deps.sh` | Main resolver entry point |
| `scripts/lib/parse-frontmatter.sh` | YAML frontmatter extractor |
| `scripts/lib/discover-repo.sh` | Finds existing repo clones on disk |
| `scripts/lib/freshen-repo.sh` | Safe git fetch + pull with dirty-state guard |
| `scripts/lib/update-settings.sh` | Merges paths into settings.local.json |
| `npx mobius-validate-graph` | Drift detection between frontmatter and graph |
| `ecosystem/master-map.md` | Full platform ecosystem map (this file's sibling) |
| `ecosystem/dependency-graph.yaml` | Authoritative machine-readable dep graph |
| `ecosystem/repo-summaries/` | One-paragraph summaries per repo (this directory) |
| `docs/onboarding.md` | New developer setup guide |
| `docs/architecture.md` | How the harness works technically |
| `docs/troubleshooting.md` | Common issues and fixes |
| `templates/` | AGENTS.md frontmatter + bootstrap section templates |

## Upstream (depends on)

- Nothing — mobius-tools has no declared Mobius dependencies

## Downstream (consumed by)

- All 17 Mobius repos — each declares `mobius-tools` as its bootstrap mechanism
- Developers — for setup and onboarding
- Agents — for cross-repo context resolution

## Bootstrap From Any Repo

```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
bash ../mobius-tools/scripts/resolve-deps.sh
```

## Critical Conventions

- This repo contains ZERO platform business logic — only tooling and docs
- Scripts use only standard macOS tools + `jq` + `gh` (no python/ruby/node)
- dependency-graph.yaml is the reference; per-repo frontmatter is runtime
- Validate drift with: `npx mobius-validate-graph`
