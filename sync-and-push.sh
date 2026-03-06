#!/bin/bash
# Syncs Claude Code files, commits changes on a dated branch, and creates a PR against main.
set -e

REPO_DIR="$HOME/PERSONAL-GITHUB/claude-config"
cd "$REPO_DIR"

# Generate branch name with current date (e.g. latest-changes-Mar-05-26)
BASE_BRANCH="latest-changes-$(date +'%b-%d-%y')"
BRANCH_NAME="$BASE_BRANCH"

# If branch already exists (local or remote), append incrementing suffix
COUNTER=2
while git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null \
   || git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME" 2>/dev/null; do
    BRANCH_NAME="${BASE_BRANCH}-${COUNTER}"
    COUNTER=$((COUNTER + 1))
done

echo "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

echo ""
echo "Running sync..."
./sync-claude-files.sh

echo ""
echo "Staging and committing changes..."
git add -A

if git diff --cached --quiet; then
    echo "No changes to commit. Cleaning up branch."
    git checkout main
    git branch -d "$BRANCH_NAME"
    exit 0
fi

git commit -m "$(cat <<'EOF'
Sync latest Claude Code config files

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"

echo ""
echo "Pushing branch to remote..."
git push -u origin "$BRANCH_NAME"

echo ""
echo "Creating pull request..."
PR_URL=$(gh pr create --title "Sync Claude Code config — $BRANCH_NAME" --body "$(cat <<'EOF'
## Summary
- Syncs latest agents, commands, skills, plugins, and settings from `~/.claude/`

## Test plan
- [ ] Review diff for unintended changes
- [ ] Verify no secrets or credentials included
EOF
)")

echo ""
echo "PR created: $PR_URL"
