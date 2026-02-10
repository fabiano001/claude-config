#!/bin/bash
# Script to sync files from ~/.claude/ to git repository
# Syncs agents, commands, skills, and settings (including hooks) to claude-config repo
#
# What gets synced:
#   - ~/.claude/agents/       → ./agents/       (custom agents)
#   - ~/.claude/commands/     → ./commands/     (slash commands - legacy)
#   - ~/.claude/skills/       → ./skills/       (user-level skills)
#   - ~/.claude/settings.json → ./settings.json (settings including hooks config)
#   - ~/.claude/*.md          → ./*.md          (any markdown files in root)
#   - ~/RalphLoops/           → ./RalphLoops/   (RalphLoops, respects .gitignore)

set -e  # Exit on any error

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$HOME/PERSONAL-GITHUB/claude-config"

echo "🔄 Syncing files from ~/.claude/ to git repository..."

# Function to sync directory
sync_directory() {
    local source_dir="$1"
    local target_dir="$2"
    local dir_name="$3"
    local exclude_pattern="$4"  # optional: extra file/pattern to exclude

    if [ ! -d "$source_dir" ]; then
        echo "⚠️  Source directory $source_dir does not exist, skipping..."
        return
    fi

    echo "📁 Syncing $dir_name..."

    # Remove the symbolic link in the repo if it exists
    if [ -L "$target_dir" ]; then
        rm "$target_dir"
    fi

    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"

    # Copy files, excluding hidden files (and optional extra pattern)
    if [ -n "$exclude_pattern" ]; then
        rsync -av --delete "$source_dir/" "$target_dir/" --exclude=".*" --exclude="$exclude_pattern"
    else
        rsync -av --delete "$source_dir/" "$target_dir/" --exclude=".*"
    fi

    echo "✅ $dir_name synced successfully"
}

# Function to sync single file
sync_file() {
    local source_file="$1"
    local target_file="$2"
    local file_name="$3"
    
    if [ ! -f "$source_file" ]; then
        echo "⚠️  Source file $source_file does not exist, skipping..."
        return
    fi
    
    echo "📄 Syncing $file_name..."
    
    # Create target directory if needed
    mkdir -p "$(dirname "$target_file")"
    
    # Copy file
    cp "$source_file" "$target_file"
    
    echo "✅ $file_name synced successfully"
}

# Sync directories
sync_directory "$CLAUDE_DIR/agents" "$REPO_DIR/agents" "agents" "README.md"
sync_directory "$CLAUDE_DIR/commands" "$REPO_DIR/commands" "commands"
sync_directory "$CLAUDE_DIR/skills" "$REPO_DIR/skills" "skills"

# Sync RalphLoops directory (excluding .gitignore patterns if .gitignore exists)
RALPH_DIR="$HOME/RalphLoops"
RALPH_TARGET="$REPO_DIR/RalphLoops"

if [ -d "$RALPH_DIR" ]; then
    echo "📁 Syncing RalphLoops..."

    if [ -L "$RALPH_TARGET" ]; then
        rm "$RALPH_TARGET"
    fi

    mkdir -p "$RALPH_TARGET"

    if [ -f "$RALPH_DIR/.gitignore" ]; then
        rsync -av --delete "$RALPH_DIR/" "$RALPH_TARGET/" --exclude=".*" --filter=":- $RALPH_DIR/.gitignore"
    else
        rsync -av --delete "$RALPH_DIR/" "$RALPH_TARGET/" --exclude=".*"
    fi

    echo "✅ RalphLoops synced successfully"
else
    echo "⚠️  Source directory $RALPH_DIR does not exist, skipping..."
fi

# Sync settings.json (contains hooks configuration)
sync_file "$CLAUDE_DIR/settings.json" "$REPO_DIR/settings.json" "settings.json"

# Check for .md files in ~/.claude/ root
echo "🔍 Checking for .md files in ~/.claude/..."

find "$CLAUDE_DIR" -maxdepth 1 -name "*.md" -type f | while read -r file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_DIR/$filename" ]; then
        echo "📄 Found new file: $filename"
        cp "$file" "$REPO_DIR/$filename"
        echo "   ✅ $filename synced"
    fi
done

echo ""
echo "✅ Sync complete!"
echo ""
echo "📋 Next steps:"
echo "   cd $REPO_DIR && git status"
echo "   git add ."
echo "   git commit -m 'Sync Claude files'"
echo "   git push"
