# Multi-Repo Git Workflow

Canonical multi-repo git workflow for Mobius platform commands that touch 2+ repositories.

> **Commands reference specific sections of this doc rather than duplicating git
> logic.** Link directly to the section anchor (e.g., `#preflight-checks`,
> `#branch-creation-gate`) from any command workflow that touches multiple repos.

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order; each step has a verification
> command so you can confirm success before proceeding.

> **Repo locations use `workspace_dir`, not a hardcoded `../`.** Every repo path
> below is written `<workspace_dir>/<repo-name>`. Resolve `workspace_dir` once,
> before Preflight, via
> [`commands/mobius/shared/workspace-resolution.md`](../../../commands/mobius/shared/workspace-resolution.md).
> Its default is the parent of the current directory, so engineers with the
> classic flat sibling layout see no change; engineers who keep repos elsewhere
> (or don't have them cloned yet) get them located — and cloned — under the
> directory they choose.

---

## Preflight Checks

Run these checks **before touching any files or generating any content**. A
failure at any point is a hard-stop — do not proceed until the issue is
resolved. Report which repo failed and what the error was.

### Step P1 — Verify GitHub CLI authentication

```bash
gh auth status
```

If this command fails or shows "not authenticated":

- Hard-stop.
- Tell the user: "GitHub CLI is not authenticated. Run `gh auth login` and try again."
- Do not proceed until `gh auth status` exits 0.

### Step P2 — For each affected repo: locate or clone

The repo must exist under `workspace_dir`. Check:

```bash
[ -d "<workspace_dir>/<repo-name>" ] || echo "MISSING: <repo-name>"
```

**If a repo is missing, do NOT hard-stop — discover it in the org and clone
it.** Most engineers won't have every platform repo pre-cloned, so cloning the
missing ones is the normal path, not an error:

1. Confirm the repo exists in the org (fail fast if the name is wrong):
   ```bash
   gh repo view boatsgroup/<repo-name> >/dev/null
   ```
2. Clone it into `workspace_dir` (prefer letting `resolve-deps.sh` do this — it
   already discovers + clones + freshens and records the path into
   `.claude/settings.local.json`; with `MOBIUS_WORKSPACE` set to the resolved
   `workspace_dir` it clones to the right place):
   ```bash
   MOBIUS_WORKSPACE="<workspace_dir>" bash "<workspace_dir>/mobius-tools/scripts/resolve-deps.sh"
   ```
   Or, for a single ad-hoc repo not declared in `AGENTS.md` dependencies:
   ```bash
   gh repo clone boatsgroup/<repo-name> "<workspace_dir>/<repo-name>"
   ```
3. Re-check presence and continue.

**Only hard-stop for the genuinely unrecoverable cases:**
- `gh repo view` fails → the repo name is wrong or you lack access. Report the
  exact name and stop.
- `gh` is unauthenticated → handled by Step P1; don't reach here.
- Clone itself fails after the repo is confirmed to exist → show the error and stop.

### Step P3 — For each affected repo: verify clean working tree

```bash
git -C <workspace_dir>/<repo-name> status --porcelain
```

If the output is non-empty, the tree is dirty:

- Hard-stop.
- List the dirty files by name.
- Tell the user: "Resolve uncommitted changes manually before proceeding. Do not
  stash — stashes are easy to lose and the work may be relevant to this change."
- Do not proceed until every affected repo returns empty output.

### Step P4 — For each affected repo: branch check

This is the **primary flow**, not an edge case. Users frequently create and
switch to branches before running a command. Handle both paths without
surprises.

```bash
git -C <workspace_dir>/<repo-name> branch --show-current
```

**If the current branch is `main`:**

Good. Pull the latest before proceeding:

```bash
git -C <workspace_dir>/<repo-name> pull origin main
```

If `git pull` fails (e.g., merge conflict, remote diverged):

- Hard-stop.
- Show the full error output.
- Tell the user to resolve the conflict and re-run.

**If the current branch is NOT `main`:**

Do not silently switch branches. Ask the user first:

```
You are currently on branch `<current-branch>` in <repo-name>.

How do you want to proceed?

1. Use this branch — continue on the current branch (recommended if you
   created it for this work)
2. Switch to main and create a new branch — start fresh from main
```

- If the user chooses **option 1 (use this branch)**:
  - Skip branch creation for this repo in the Branch Creation Gate.
  - Verify the working tree is clean (already done in P3).
  - Record the branch name so the Push + PR Pattern uses it.

- If the user chooses **option 2 (switch to main)**:
  ```bash
  git -C <workspace_dir>/<repo-name> checkout main
  git -C <workspace_dir>/<repo-name> pull origin main
  ```
  Then proceed to the Branch Creation Gate for this repo.

### Preflight summary

After all checks pass, print a summary before continuing:

```
Preflight Results:
  ✅ gh auth status — authenticated
  ✅ <repo-a>       — on main, pulled latest
  ✅ <repo-b>       — on feat/existing-branch (user keeping branch)
  ✅ <repo-c>       — on main, pulled latest

Proceeding to Branch Creation Gate.
```

If any item shows a failure symbol, stop and do not proceed.

---

## Branch Creation Gate

This is a **hard gate**. No file generation, no file modification, no content
written to disk until branches exist in all affected repos. This prevents
orphaned work on `main` and ensures every change is reviewable via PR.

### Branch naming convention

| Situation | Format | Example |
|-----------|--------|---------|
| JIRA ticket available | `feat/<ticket-id>-<description>` | `feat/PLAT-123-add-cert-manager` |
| No JIRA ticket | `feat/<description>` | `feat/add-cert-manager` |

Use kebab-case for the description. Keep it short and meaningful.

Other type prefixes (`fix/`, `chore/`, `docs/`) are valid when the change is
not a feature addition. Match the conventional commit type used in the commit
message.

### Step B1 — Create branch in each affected repo

Skip any repo where the user chose to keep their existing branch in the
preflight step.

```bash
git -C <workspace_dir>/<repo-name> checkout -b <branch-name>
git -C <workspace_dir>/<repo-name> branch --show-current   # Verify
```

**If the branch name already exists:**

```
Branch `<branch-name>` already exists in <repo-name>.

a) Switch to the existing branch and continue work on it
b) Choose a different branch name
```

- If option (a): `git -C <workspace_dir>/<repo-name> checkout <branch-name>`
- If option (b): prompt for a new name and retry.

### Step B2 — Gate verification

Before generating any files, print a status table showing every affected repo
and its branch state:

```
Branch Gate Status:
  ✅ iac-eks-addons   → feat/PLAT-123-add-cert-manager
  ✅ iac-eks-argocd   → feat/PLAT-123-add-cert-manager (existing branch, reused)

Proceeding to file generation.
```

If any repo failed to branch (error other than "already exists"), stop all work
and report the failure before touching any files in any repo.

---

## Commit Pattern

Make **one commit per repo**. Stage all generated and modified files for that
repo in a single commit. This keeps the PR diff clean and each commit
reviewable in isolation.

### Step C1 — Stage changes

```bash
git -C <workspace_dir>/<repo-name> add -A
```

If you want to stage specific files instead of everything:

```bash
git -C <workspace_dir>/<repo-name> add <file1> <file2> ...
```

### Step C2 — Analyze the diff

Always inspect the staged diff before generating the commit message:

```bash
git -C <workspace_dir>/<repo-name> diff --cached --stat
git -C <workspace_dir>/<repo-name> diff --cached
```

Use the diff output — file names, change counts, content — to write an
accurate commit message. Do not write the message from memory.

### Step C3 — Generate commit message

Follow the conventional commit format:

```
<type>(<scope>): <summary — 50 chars max>

<body: what changed and why>
- Bullet per file category or logical group

<TICKET-ID>
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`.

Scope is typically the primary component or service name being changed.

### Step C4 — Offer the message for review

Present the generated message to the user before committing:

```
I'll commit with this message:

---
<generated message>
---

Options:
- Press enter to accept
- Type a custom message if you prefer
```

Wait for a response. If the user provides a custom message, use theirs exactly.

### Step C5 — Commit

```bash
git -C <workspace_dir>/<repo-name> commit -m "<message>"
```

Verify:

```bash
git -C <workspace_dir>/<repo-name> log -1 --oneline
```

### Hard blocks — never do these

| Blocked behavior | Why |
|-----------------|-----|
| `Co-authored-by: Claude` or any AI attribution trailer | Adds noise, obscures authorship |
| "Generated by AI", "Written with Claude", etc. in body | Same reason |
| Vague summaries: "update", "changes", "wip", "fix" | Not reviewable |
| Emoji in commit messages | Unless user explicitly requests |

---

## Push + PR Pattern

### Step PP1 — Push each branch

```bash
git -C <workspace_dir>/<repo-name> push -u origin <branch-name>
```

The `-u` flag sets the upstream tracking reference. Subsequent pushes in the
same session can use `git push` without arguments.

Verify:

```bash
git -C <workspace_dir>/<repo-name> status
# Expected: "Your branch is up to date with 'origin/<branch-name>'"
```

### Step PP2 — Multi-repo ordering

When creating PRs across repos that have a dependency relationship, create
the upstream (dependency) repo PR first. Capture its URL. The downstream
PR description then references it.

Example ordering for a typical two-repo change:

1. PR in `iac-eks-argocd` (upstream, provides project permissions)
2. PR in the service repo (downstream, depends on those permissions)

The downstream PR body should include:

```
Depends on: <upstream-pr-url>
Merge upstream PR first — see Merge Order section in the workflow doc.
```

### Step PP3 — Create PR

```bash
gh pr create \
  --repo boatsgroup/<repo-name> \
  --title "<type>(<scope>): <summary> [TICKET-ID]" \
  --body "$(cat <<'EOF'
## Summary

- <bullet: what changed>
- <bullet: why>

## Merge Order

Merge `<upstream-repo>` PR first: <upstream-pr-url>

## Related PRs

- <downstream-repo>: <downstream-pr-url>

## JIRA

<ticket-url or N/A>
EOF
)"
```

Omit the `[TICKET-ID]` title suffix and the JIRA section if no ticket applies.
Omit the Merge Order and Related PRs sections if only one repo is involved.

### Step PP4 — Return PR URLs

Return the PR URL for each repo as proof of completion:

```
PRs created:
  iac-eks-argocd   → https://github.com/boatsgroup/iac-eks-argocd/pull/<n>
  iac-eks-addons   → https://github.com/boatsgroup/iac-eks-addons/pull/<n>

Merge iac-eks-argocd first.
```

Work is not complete until every affected repo has a PR URL.

---

## Error Handling

| Step | Failure | Detection | Action |
|------|---------|-----------|--------|
| Preflight: dirty tree | Uncommitted changes present | `git status --porcelain` returns non-empty output | Hard-stop. List dirty files by name. Tell user to resolve manually — do not stash. |
| Preflight: not on main | Repo is on a feature branch | `git branch --show-current` returns a branch name that is not `main` | Ask user: use the current branch or switch to main? Wait for answer before proceeding. |
| Preflight: `gh` not authenticated | GitHub CLI has no valid session | `gh auth status` exits non-zero | Hard-stop. Tell user: run `gh auth login`. |
| Preflight: `git pull` fails | Remote conflict or diverged history | `git pull` exits non-zero | Hard-stop. Show full error output. Tell user to resolve the conflict and retry. |
| Preflight: repo missing locally | Not cloned under `workspace_dir` yet | `[ -d "<workspace_dir>/<repo>" ]` fails | Not a hard-stop. Confirm it exists via `gh repo view boatsgroup/<repo>`, then clone into `workspace_dir` (via `resolve-deps.sh` with `MOBIUS_WORKSPACE` set, or `gh repo clone`). Only hard-stop if `gh repo view` fails (wrong name / no access). |
| Branch creation: name already exists | Branch with that name exists in local repo | `git checkout -b` exits non-zero with "already exists" message | Offer: (a) switch to existing branch, or (b) choose a new name. |
| Push: rejected | Remote branch has commits not in local | `git push` exits non-zero with "rejected" or "non-fast-forward" | Show error. Suggest: `git pull --rebase origin <branch-name>`, then push again. Warn user to review rebased changes before pushing. |
| PR creation: fails | Auth error, missing remote branch, or API issue | `gh pr create` exits non-zero | Show the full error output. Provide the equivalent `gh pr create` command as a copy-paste fallback so the user can run it manually after resolving the issue. |
