---
name: fix-claude-installation
description: Fixes broken Claude Code CLI installation caused by failed auto-updates. Use when `claude` command is not found or broken after an auto-update. Cleans up stale npm directories and reinstalls.
invoke: user
context: fork
tools: Bash
---

# Fix Claude Code Installation

Repairs the Claude Code CLI when it breaks after an auto-update.

## Steps

1. Find the node version directory used by nvm:

```bash
NVM_NODE_DIR="$(dirname "$(dirname "$(which node)")")"
echo "Node directory: $NVM_NODE_DIR"
```

2. Remove stale claude-code directories that block reinstall:

```bash
rm -rf "$NVM_NODE_DIR/lib/node_modules/@anthropic-ai/claude-code" "$NVM_NODE_DIR/lib/node_modules/@anthropic-ai/.claude-code-"* 2>/dev/null
echo "Cleaned stale directories"
```

3. Remove broken symlink if present:

```bash
rm -f "$NVM_NODE_DIR/bin/claude" 2>/dev/null
echo "Cleaned broken symlink"
```

4. Reinstall Claude Code globally:

```bash
npm install -g @anthropic-ai/claude-code@latest
```

5. Verify the installation:

```bash
which claude && claude --version
```

6. Report the result to the user. If any step fails, show the error output.
