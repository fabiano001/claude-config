---
name: validate-graph
description: Detect dependency graph drift between AGENTS.md frontmatter and the authoritative graph
argument-hint: [workspace-dir] [--key-docs-strict] [--output json]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Validate Graph

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or OpenAI `o3-mini`).
>
> Graph validation is fully deterministic. The agent runs the validator,
> presents drift findings, and suggests which file to fix.

This command detects **dependency graph drift** — mismatches between what each
repo's `AGENTS.md` frontmatter declares and what the authoritative
`ecosystem/dependency-graph.yaml` says.

It catches:
- Repos listed in the graph but missing from disk (not cloned)
- Repos on disk but missing from the graph (untracked)
- Dependency mismatches (repo declares deps not in graph, or graph has deps repo doesn't declare)
- Missing or incorrect `org` field in frontmatter
- Missing `key_docs` entries for repos that declare them in the graph
- Stale key_docs paths that don't exist on disk

---

## Why This Matters

The dependency graph is the **single source of truth** for cross-repo
relationships. When it drifts:

- `resolve-deps.sh` may clone wrong or missing repos
- `npx mobius-trace-impact` returns incorrect blast radius
- Agents make incorrect assumptions about what depends on what
- Multi-repo workflows may miss affected repos

Run this command after:
- Adding a new repo to the platform
- Changing a repo's dependencies
- Updating `dependency-graph.yaml`
- Running `resolve-deps.sh` to verify all repos are consistent

---

## CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `[workspace-dir]` | Parent directory containing repo clones | auto-detect (parent of mobius-tools) |
| `--graph-file PATH` | Path to dependency-graph.yaml | `ecosystem/dependency-graph.yaml` |
| `--key-docs-strict` | Treat missing key_docs as failures (not just warnings) | off |
| `--output FORMAT` | Output format: `text` or `json` | text |

---

## Execution Flow

### Step 1: Ensure repos are cloned

The validator needs repos on disk to check their `AGENTS.md` frontmatter.
If repos are missing, run the resolver first:

```bash
bash ../mobius-tools/scripts/resolve-deps.sh
```

### Step 2: Run the validator

```bash
npx mobius-validate-graph
```

Or with a specific workspace:

```bash
npx mobius-validate-graph /path/to/repos
```

### Step 3: Interpret results

The validator checks each repo in the graph:

| Check | What It Means |
|-------|---------------|
| `GRAPH-REPO-001` (pass) | Repo exists on disk |
| `GRAPH-REPO-001` (fail) | Repo in graph but not cloned — run `resolve-deps.sh` |
| `GRAPH-DEPS-001` (pass) | Frontmatter deps match graph deps |
| `GRAPH-DEPS-001` (fail) | Mismatch — update either AGENTS.md frontmatter or dependency-graph.yaml |
| `GRAPH-ORG-001` (fail) | Wrong org in frontmatter |
| `GRAPH-KEYDOCS-001` (warn/fail) | key_docs path doesn't exist on disk |

### Step 4: Fix drift

**Source of truth**: `ecosystem/dependency-graph.yaml` is authoritative.

- If a repo's AGENTS.md frontmatter disagrees with the graph → **fix the frontmatter**
- If the graph is actually wrong → **fix the graph, then re-run**
- If a repo is missing from disk → `bash ../mobius-tools/scripts/resolve-deps.sh`

---

## Examples

### Basic drift check

```
/mobius:validate-graph
```

### Check with specific workspace

```
/mobius:validate-graph /Users/allen/repos/mobius
```

### Strict mode (key_docs failures)

```
/mobius:validate-graph --key-docs-strict
```

### CI/CD integration

```
/mobius:validate-graph --key-docs-strict --output json
```

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:trace-impact` | Uses the dependency graph — validate-graph ensures it's accurate |
| `/mobius:validate-service` | Validates a single service; validate-graph validates the ecosystem |
| `/mobius:refresh-docs` | Scans repos for stale docs; validate-graph checks dependency declarations |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: validation

**Context hints**:
- "Impact opener" → state how many repos were checked and how many have drift
- "What was accomplished" → describe which repos have mismatches between their declarations and the graph
- "Why it matters" → explain that drift causes incorrect dependency resolution and wrong blast radius calculations
- "What happens next" → fix the drifted frontmatter or update the graph

**Repo breakdown guidance**:
- List each repo with drift and explain what the mismatch is
- Explain that dependency-graph.yaml is the source of truth
