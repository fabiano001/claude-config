# Mobius Tools — Resolver Architecture

> **Audience**: Platform engineers and agents who need to understand how
> the `mobius-tools` resolver SDK works, why it is designed the way it is,
> and how to extend it.
>
> **Looking for platform architecture?** See
> [Platform Overview](architecture/platform-overview.md) for how the Mobius
> platform works end-to-end, or browse the full
> [architecture directory](architecture/) for deep dives on ArgoCD,
> Crossplane, IRSA, environments, and networking.

---

## The SDK Model

### Why `mobius-tools` Is the Ecosystem Hub

`mobius-tools` is intentionally the single coordination point for the platform:

- Resolver runtime (`scripts/resolve-deps.sh`) lives in one repo.
- Reference graph (`ecosystem/dependency-graph.yaml`) lives in one repo.
- Portable system map (`ecosystem/master-map.md`) lives in one repo.
- Cross-repo drift checks (`npx mobius-validate-graph`) run from one repo.

This design removes per-repo resolver duplication and keeps agent/human
bootstrap behavior deterministic across all repositories.

### Problem Statement

The Mobius platform consists of 20 interdependent repos. When an AI agent (or
developer) starts work in `iac-eks-addons`, it needs context from
`iac-eks-argocd` and `iac-eks-crossplane` to reason correctly. Without
those repos cloned and accessible, the agent is blind to half the system.

**The naive solution** (v1 of this harness): put a script in every repo that
clones its own dependencies. This creates:
- 18 copies of hook wrapper logic to maintain
- 18 PRs every time the resolver logic changes
- Drift between repos as they update at different rates
- Complexity in the individual repos

**The SDK solution** (v2, current): centralize ALL resolver logic in one repo
(`mobius-tools`), and have individual repos contain only:
1. YAML frontmatter declaring their dependencies
2. Two lines of instructions pointing to `mobius-tools`

This is the "SDK pattern" — one place to update, zero per-repo scripts.

### Directory Structure

```
mobius-tools/
├── AGENTS.md                              # This repo's own agent instructions
├── README.md                              # Human-facing overview
├── .claude/
│   └── ecosystem.md                       # Optional: this repo's ecosystem perspective
│
├── scripts/                               # ALL resolver logic lives here
│   ├── resolve-deps.sh                    # Main entry point (agents invoke this)
│   ├── validate-graph.sh                  # Drift detection
│   └── lib/
│       ├── parse-frontmatter.sh           # YAML frontmatter extractor
│       ├── discover-repo.sh               # Finds existing repo on disk
│       ├── freshen-repo.sh                # Safe git pull with dirty-state guard
│       └── update-settings.sh            # Merges paths into settings.local.json
│
├── ecosystem/
│   ├── master-map.md                      # Full platform map (portable)
│   ├── dependency-graph.yaml              # Authoritative machine-readable graph
│   └── repo-summaries/                    # 20 one-paragraph summaries
│
├── templates/
│   ├── agents-frontmatter.md              # YAML frontmatter template
│   ├── agents-bootstrap-section.md        # Bootstrap section template
│   └── agents-minimap-section.md          # Ecosystem mini-map template
│
└── docs/
    ├── onboarding.md                      # New team member guide
    ├── architecture.md                    # This document
    ├── agent-interop.md                   # Claude + Codex shared workflow layer
    ├── dependency-graph-visual.md         # Mermaid + ASCII diagrams
    ├── troubleshooting.md                 # Common issues and fixes
    └── workflows/                         # Canonical platform engineering procedures
        ├── INDEX.md                       # Workflow index — start here
        ├── services/
        │   └── add-service.md
        ├── argocd/
        │   ├── new-project-or-applicationset.md
        │   ├── debug-applicationset.md
        │   └── argocd-cli-auth.md
        └── xrd/
            └── new-xrd.md
```

---

## Resolution Flow

The resolution flow describes what happens from the moment an agent reads
`AGENTS.md` to the moment it has full file access to all dependency repos.

```
Agent starts session in {repo}/
    │
    ▼
1. Agent reads {repo}/AGENTS.md
   (Mandatory first read — specified in per-repo AGENTS.md)
    │
    ▼
2. Agent sees YAML frontmatter block:
   ---
   mobius:
     repo: iac-eks-addons
     org: boatsgroup
     dependencies:
       - iac-eks-argocd
       - iac-eks-crossplane
   ---
    │
    ▼
3. Agent reads "Cross-Repo Bootstrap" section.
   Sees instruction: ensure ../mobius-tools exists
    │
    ├──► Does ../mobius-tools/ exist?
    │    YES: skip clone
    │    NO:  gh repo clone boatsgroup/mobius-tools ../mobius-tools
    │
    ▼
4. Agent runs: bash ../mobius-tools/scripts/resolve-deps.sh
    │
    ▼
5. Resolver: parse-frontmatter.sh
   Extracts: repo=iac-eks-addons, org=boatsgroup
   Dependencies: [iac-eks-argocd, iac-eks-crossplane]
    │
    ▼
6. For each dependency (iac-eks-argocd):
    │
    ├──► discover-repo.sh: check ../iac-eks-argocd/
    │    FOUND (with valid .git and matching remote)?
    │      YES: freshen-repo.sh (safe git pull)
    │      NO:  gh repo clone boatsgroup/iac-eks-argocd ../
    │
    └──► record absolute path: /Users/.../iac-eks-argocd
    │
    ▼
7. update-settings.sh:
   Read {repo}/.claude/settings.local.json
   Merge /Users/.../iac-eks-argocd into additionalDirectories
   Write atomically (temp file + mv)
    │
    ▼
8. Agent now has native file access to all dependency repos.
   Can read, edit, branch, and PR across repos.
   Reads ecosystem context files to build full mental model.
```

---

## Dual-Source Design

The harness uses **two sources** for dependency information:

| Source | File | Who Reads It | Purpose |
|--------|------|-------------|---------|
| Per-repo frontmatter | `{repo}/AGENTS.md` | `resolve-deps.sh` (runtime) | What the resolver reads during a session |
| Centralized graph | `mobius-tools/ecosystem/dependency-graph.yaml` | `validate-graph.sh`, humans | Reference + drift detection |

### Why Two Sources?

**The resolver needs the local file**. When `resolve-deps.sh` runs, it reads the
AGENTS.md in the current working directory. This is always available — it's in
the repo the agent is working in. The resolver doesn't need to clone mobius-tools
first just to read the graph.

**The centralized graph is for humans and validation**. The YAML graph in
mobius-tools is the authoritative reference: it documents all repos, their
tiers, roles, and relationships in one place. The `validate-graph.sh` script
compares per-repo frontmatter against this graph to detect drift.

### Drift Detection

When you update a repo's dependencies (add a new dep, remove an old one):

1. Update the repo's `AGENTS.md` frontmatter (runtime source)
2. Update `mobius-tools/ecosystem/dependency-graph.yaml` (reference source)
3. Run `npx mobius-validate-graph` to confirm they match

The validate script reads the graph YAML, checks each repo's frontmatter (if
the repo exists locally as a sibling), and reports any mismatches.

---

## Bootstrap Pattern

### How Agents Discover mobius-tools

Every Mobius repo's `AGENTS.md` contains:

```markdown
## Cross-Repo Bootstrap

**Step 1** — Ensure mobius-tools is available:
```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
```

**Step 2** — Run the resolver:
```bash
bash ../mobius-tools/scripts/resolve-deps.sh
```
```

This pattern works because:
- `mobius-tools` is cloned into the same parent directory as all other repos
- The two-line bootstrap is text, not code — works in Claude Code, Codex, CI, or any agent
- Once mobius-tools is present, it never needs to be re-cloned (it's a dependency of itself)

### Session Deduplication

The resolver writes a daily marker at `/tmp/mobius-resolved-{uid}-{date}` (where
`{date}` is `YYYYMMDD`) to avoid repeating work within the same calendar day. If
you re-run the resolver for the same repo on the same day — e.g., after switching
tabs or restarting a session — it exits immediately with a "already resolved today"
message. This prevents duplicate clone attempts when multiple repos share a
dependency. The marker does not persist across days: a new run on the following
day will freshen all dependencies as normal.

---

## Library Design

Each library in `scripts/lib/` has a single responsibility:

### parse-frontmatter.sh

**Input**: Path to an AGENTS.md file  
**Output**: Space-separated string: `"repo org dep1 dep2 dep3"`  
**Approach**: `awk` to extract content between `---` markers, then `grep`/`sed`
for specific fields. No external YAML parser — the frontmatter format is
intentionally flat to enable reliable shell parsing.

```bash
source scripts/lib/parse-frontmatter.sh
result=$(parse_frontmatter /path/to/AGENTS.md)
# result: "iac-eks-addons boatsgroup iac-eks-argocd iac-eks-crossplane"
```

### discover-repo.sh

**Input**: `repo_name`, `parent_dir` (default: `../`)  
**Output**: Absolute path to repo root, or empty string  
**Validation**: Directory must exist AND contain `.git/` AND have a remote
matching `{org}/{repo_name}` (prevents false matches from unrelated repos with
the same name).

```bash
source scripts/lib/discover-repo.sh
path=$(discover_repo "iac-eks-argocd" "../")
# path: /Users/you/repos/mobius/iac-eks-argocd  OR  ""
```

### freshen-repo.sh

**Input**: Absolute path to repo root  
**Output**: Status message (freshened / skipped-dirty / skipped-branch)  
**Safety checks**:
1. `git status --porcelain` -> non-empty = dirty -> skip with warning
2. `git branch --show-current` -> not `main` -> skip with warning
3. Both pass -> `git fetch origin && git pull origin main --ff-only`

The `--ff-only` flag prevents creating merge commits in dependency repos.
A failed fast-forward (e.g., diverged history) warns but does NOT abort.

### update-settings.sh

**Input**: `REPO_ROOT`, array of resolved absolute paths  
**Output**: Updated `.claude/settings.local.json`  
**Logic**: Creates the file if missing, merges new paths into
`permissions.additionalDirectories`, deduplicates, preserves all other fields.
Writes atomically via temp file + `mv` to prevent partial writes.

---

## Why No Per-Repo Scripts

This is the most important design decision. Here's the comparison:

| Aspect | Per-Repo Scripts (v1) | Central SDK (v2) |
|--------|-----------------------|-----------------|
| Logic location | N copies across repos | 1 copy in mobius-tools |
| Update a bug fix | N PRs to N repos | 1 commit to mobius-tools |
| Adding a new feature | Update N repos | Update mobius-tools once |
| Drift between repos | Inevitable over time | Impossible (single source) |
| New repo onboarding | Copy script + modify | Add 2-line bootstrap text |
| Works in non-Claude agents | Only if they execute hooks | Yes — it's instructions |

The AGENTS.md instructions work in **any** AI agent that reads the file:
- Claude Code with hooks
- Codex
- CI/CD agents
- Future agents that don't exist yet

Scripts require execution capability; text instructions require only reading.

---

## Extending the Harness

### Adding a New Dependency to an Existing Repo

1. Edit the repo's `AGENTS.md` frontmatter — add the new dep name
2. Edit `mobius-tools/ecosystem/dependency-graph.yaml` — update the repo's deps list
3. Run `npx mobius-validate-graph` — confirm no drift
4. Commit both files

### Adding a Brand New Repo to the Platform

1. Create the new repo with `AGENTS.md` (use `mobius-tools/templates/agents-frontmatter.md`)
2. Add the repo to `mobius-tools/ecosystem/dependency-graph.yaml`
3. Create `mobius-tools/ecosystem/repo-summaries/{repo-name}.md`
4. Update the master-map if the repo has significant platform relationships
5. Run `validate-graph.sh`

### Adding a New Script to the Resolver

1. Create `scripts/lib/new-library.sh` with a single `source`-able function
2. Source it in `scripts/resolve-deps.sh`
3. Follow the existing pattern: function name = file name without `.sh`
4. No external dependencies beyond standard macOS tools + `jq` + `gh`

---

## Security Model

- No secrets ever stored in this repo — only repo names and org names
- `settings.local.json` is git-ignored in all Mobius repos (never committed)
- No `insecure: true` or `skipTLSVerify: true` anywhere
- `gh` authentication is the user's own GitHub token (not a shared secret)
- Resolver only clones from `boatsgroup/` org (validated in discover-repo.sh)

---

## File Access Model

Claude Code's `additionalDirectories` (in `settings.local.json`) grants the
agent native file access to directories outside the current working directory.
This means:

- **Read**: Agent can `cat`, `grep`, and read any file in dependency repos
- **Write**: Agent can edit files, create branches, and stage commits
- **Execute**: Agent can run scripts in dependency repos

The resolver only adds paths the current repo declared as dependencies.
Users retain full control — the file is local and git-ignored.
