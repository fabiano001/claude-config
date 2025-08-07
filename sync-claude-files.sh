#!/bin/bash
# Script to sync files from ~/.claude/ to git repository
# This script works with the corrected setup where ~/.claude/agents and ~/.claude/commands are real directories

set -e  # Exit on any error

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$HOME/PERSONAL-GITHUB/claude-config"

echo "🔄 Syncing files from ~/.claude/ to git repository..."

# Function to sync directory
sync_directory() {
    local source_dir="$1"
    local target_dir="$2"
    local dir_name="$3"
    
    if [ ! -d "$source_dir" ]; then
        echo "⚠️  Source directory $source_dir does not exist, skipping..."
        return
    fi
    
    echo "📁 Syncing $dir_name..."
    
    # Remove the symbolic link in the repo
    if [ -L "$target_dir" ]; then
        rm "$target_dir"
    fi
    
    # Copy files from ~/.claude/ to the repo
    rsync -av --delete "$source_dir/" "$target_dir/" --exclude=".*"
    
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
sync_directory "$CLAUDE_DIR/agents" "$REPO_DIR/agents" "agents"
sync_directory "$CLAUDE_DIR/commands" "$REPO_DIR/commands" "commands"

# Sync individual files
sync_file "$CLAUDE_DIR/settings.json" "$REPO_DIR/settings.json" "settings.json"

# Check for any other .md files in ~/.claude/ that might need syncing
echo "🔍 Checking for other files in ~/.claude/ that might need syncing..."

find "$CLAUDE_DIR" -maxdepth 1 -name "*.md" -type f | while read -r file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_DIR/$filename" ]; then
        echo "📄 Found new file: $filename"
        echo "   Copying to repository..."
        cp "$file" "$REPO_DIR/$filename"
        echo "   ✅ $filename synced"
    fi
done

echo ""
echo "✅ Sync complete!"
echo ""
echo "📋 Next steps:"
echo "1. Review changes: cd $REPO_DIR && git status"
echo "2. Add new files: git add ."
echo "3. Commit changes: git commit -m 'Update Claude files'"
echo "4. Push to GitHub: git push origin main"
echo ""
echo "🔍 To see what was synced:"
echo "   cd $REPO_DIR && git diff --cached"
