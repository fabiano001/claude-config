# Git Synch Target Branch

<!-- COMMAND_DESCRIPTION: Synchronize the current branch with a target branch (default: main) and push to remote -->

Synchronize the current branch with a target branch (default: main) and push to remote.

## Usage

```
/git-synch-target-branch [target-branch]
```

- `target-branch` (optional): Branch to sync with. Defaults to `main` if not specified.

## Workflow

1. **Fetch** latest changes from the target branch
2. **Merge** target branch into current branch (without staging unstaged changes)
3. **Push** the synchronized branch to remote

## Examples

```bash
# Sync with main branch (default)
/git-synch-target-branch

# Sync with specific branch
/git-synch-target-branch develop
```

## Commands Executed

1. `git fetch origin <target-branch>`
2. `git merge origin/<target-branch>`
3. `git push origin <current-branch>`

## Notes

- Only staged/committed changes are included in the sync
- Unstaged changes remain untouched
- Creates a merge commit if there are conflicts or new changes
- Current branch must be tracking a remote branch for push to work