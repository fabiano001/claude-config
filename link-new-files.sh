#!/bin/bash
# Script to sync new files from ~/.claude/ to git repository

set -e  # Exit on any error

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$HOME/PERSONAL-GITHUB/claude-config"

echo "🔗 Syncing new files from ~/.claude/ to git repository..."

# Function to sync directory
sync_directory() {
    local source_dir="$1"
    local target_dir="$2"
    local dir_name="$3"
    
    if [ ! -d "$source_dir" ]; then
        echo "⚠️  Source directory $source_dir does not exist, skipping..."
        return
    fi
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Copy new files from source to target
    echo "📁 Syncing $dir_name..."
    rsync -av --update "$source_dir/" "$target_dir/" --exclude=".*"
    
    # Update symbolic link
    if [ -L "$source_dir" ]; then
        echo "🔄 Updating symbolic link for $dir_name..."
        rm "$source_dir"
        ln -sf "$target_dir" "$source_dir"
    elif [ ! -L "$source_dir" ] && [ -d "$source_dir" ]; then
        echo "🔄 Creating symbolic link for $dir_name..."
        # Backup original directory
        mv "$source_dir" "${source_dir}.backup.$(date +%s)"
        ln -sf "$target_dir" "$source_dir"
        echo "📦 Original $dir_name backed up to ${source_dir}.backup.$(date +%s)"
    fi
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
    
    # Create target directory if needed
    mkdir -p "$(dirname "$target_file")"
    
    # Copy file if it's newer or doesn't exist in target
    if [ ! -f "$target_file" ] || [ "$source_file" -nt "$target_file" ]; then
        echo "📄 Syncing $file_name..."
        cp "$source_file" "$target_file"
    fi
    
    # Update symbolic link
    if [ -L "$source_file" ]; then
        echo "🔄 Updating symbolic link for $file_name..."
        rm "$source_file"
        ln -sf "$target_file" "$source_file"
    elif [ ! -L "$source_file" ] && [ -f "$source_file" ]; then
        echo "🔄 Creating symbolic link for $file_name..."
        # Backup original file
        mv "$source_file" "${source_file}.backup.$(date +%s)"
        ln -sf "$target_file" "$source_file"
        echo "📦 Original $file_name backed up to ${source_file}.backup.$(date +%s)"
    fi
}

# Sync directories
sync_directory "$CLAUDE_DIR/commands" "$REPO_DIR/commands" "commands"
sync_directory "$CLAUDE_DIR/agents" "$REPO_DIR/agents" "agents"

# Sync individual files
sync_file "$CLAUDE_DIR/settings.json" "$REPO_DIR/settings.json" "settings.json"

# Check for any other files that might need syncing
echo "🔍 Checking for other files in ~/.claude/ that might need syncing..."

# Look for any .md files in ~/.claude/ that aren't in commands or agents
find "$CLAUDE_DIR" -maxdepth 1 -name "*.md" -type f | while read -r file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_DIR/$filename" ] && [ ! -L "$file" ]; then
        echo "�� Found new file: $filename"
        echo "   Copying to repository..."
        cp "$file" "$REPO_DIR/$filename"
        echo "   Creating symbolic link..."
        mv "$file" "${file}.backup.$(date +%s)"
        ln -sf "$REPO_DIR/$filename" "$file"
        echo "   ✅ $filename synced and linked"
    fi
done

echo ""
echo "✅ Sync complete!"
echo ""
echo "📋 Next steps:"
echo "1. Review changes: cd $REPO_DIR && git status"
echo "2. Add new files: git add ."
echo "3. Commit changes: git commit -m 'Add new Claude files'"
echo "4. Push to GitHub: git push origin main"
echo ""
echo "🔍 To see what was synced:"
echo "   cd $REPO_DIR && git diff --cached"
