# CodeGraphContext (CGC) Setup Guide

CGC provides graph-based code intelligence across your entire repository ecosystem. It's optional but highly recommended for Mobius commands.

## What is CGC?

CodeGraphContext indexes your codebase into a graph database, enabling:
- **Cross-repo code search**: Find code patterns across 1000+ repos instantly
- **Dependency mapping**: Visualize relationships between services/libraries
- **Impact analysis**: Understand ripple effects of changes
- **Architecture queries**: Ask questions about your codebase structure

## Performance Impact

**Without CGC (baseline):**
- `mobius:document-service`: 15-30 minutes per service (sequential repo scans)
- `mobius:document-repo`: 10-20 minutes (limited cross-repo context)

**With CGC (accelerated):**
- `mobius:document-service`: 2-5 minutes (parallel graph queries)
- `mobius:document-repo`: 3-8 minutes (full ecosystem context)

**10-100x speedup** for cross-repo operations!

## Installation

### Step 1: Install CGC

```bash
npm install -g codegraphcontext
```

Verify installation:
```bash
cgc --version
```

### Step 2: Configure MCP Server

CGC is already configured in mobius-tools' `.mcp.json`. No additional setup needed.

### Step 3: Index Your Repos

**Option A: Index entire ~/repos directory (recommended)**

```bash
cd ~/repos
cgc index .
```

This will take 2-4 hours for ~1000 repos. Run overnight or during lunch.

**Option B: Index specific repos**

```bash
cgc index ~/repos/mobius/mobius-tools
cgc index ~/repos/iac/iac-eks-*
```

Faster but provides less cross-repo context.

### Step 4: Keep Index Fresh

**Option A: Watch mode (recommended)**

```bash
cd ~/repos
cgc watch .
```

Keeps index automatically updated as you edit files. Run in a tmux/screen session.

**Option B: Scheduled updates**

```bash
# Add to crontab (daily at 2 AM)
0 2 * * * cd ~/repos && /usr/local/bin/cgc index . >> /tmp/cgc-index.log 2>&1
```

## Verify Setup

Check that CGC is working:

```bash
# Should show indexed repositories
cgc list

# Should return results
cgc find "class AuthService"
```

## Troubleshooting

### "No configuration file found"

CGC uses default settings (FalkorDB Lite). This is normal and works fine.

### "No indexed repositories"

Run `cgc index <path>` to index your repos.

### "Connection refused" or MCP errors

1. Check `.mcp.json` is present: `cat .mcp.json | grep CodeGraphContext`
2. Restart Claude Code
3. Check logs: `tail -f ~/.codegraphcontext/logs/cgc.log`

### Index takes too long

Index incrementally:
```bash
# High-priority repos first
cgc index ~/repos/mobius
cgc index ~/repos/iac

# Rest later
cgc index ~/repos
```

## Usage in Mobius Commands

Mobius commands **automatically detect** CGC availability. No code changes needed!

When CGC is available:
```
🚀 CGC acceleration enabled (1247 repos indexed)
Using cross-repo graph queries for dependency analysis...
```

When CGC is unavailable:
```
🐌 CGC not available: No indexed repositories
Falling back to sequential repo analysis (slower but works)...
```

## Team Adoption Strategy

1. **Start small**: Install CGC, index mobius-tools only
2. **Test it**: Run `mobius:document-service` on a known service
3. **Compare**: Notice the speed difference?
4. **Scale up**: Index more repos gradually
5. **Share wins**: Post benchmarks in #devops-tooling

## Questions?

- **Do I need this?** No, but it makes Mobius 10x faster
- **Does it work offline?** Yes, fully local (no cloud dependencies)
- **Does it affect my code?** No, read-only index
- **Can I uninstall?** Yes, just delete `~/.codegraphcontext/`

## Resources

- GitHub: https://github.com/CodeGraphContext/CodeGraphContext
- MCP Server Docs: (see .mcp.json in mobius-tools)
