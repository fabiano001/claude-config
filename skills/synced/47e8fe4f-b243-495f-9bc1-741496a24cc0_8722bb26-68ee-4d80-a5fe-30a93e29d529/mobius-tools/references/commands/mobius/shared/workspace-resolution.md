<!-- MODULE_SUMMARY: Resolves workspace_dir once — the base directory under which every other boatsgroup repo this command touches is expected to live (and into which missing ones get cloned). Defaults to the parent of the current repo (preserving the ../ sibling convention), honors MOBIUS_WORKSPACE, and prompts the user once to confirm/override. Every downstream `../<repo>` reference becomes `<workspace_dir>/<repo>`. -->

# Shared Workspace Resolution (`workspace_dir`)

Mobius commands touch multiple boatsgroup repos (`iac-eks-argocd`, the service
repo, `terraform-modules-aws`, etc.). Historically every command hardcoded
`../<repo>` — a sibling-directory convention that only holds for engineers who
happen to keep all their repos in one flat parent directory. This module
resolves a single `workspace_dir` up front so the rest of the command (and the
shared preflight in `docs/workflows/shared/multi-repo-git-workflow.md`) can
locate — and, when missing, clone — every repo it needs, wherever the engineer
keeps them.

Run this **once, before the Preflight Checks**, and reuse the resolved
`workspace_dir` for every repo path for the rest of the command.

## Step W1 — Determine the default

Resolve the default in this priority order (first match wins):

1. **`MOBIUS_WORKSPACE` env var**, if set — this is already the discovery
   override honored by `scripts/lib/discover-repo.sh` and `resolve-deps.sh`.
   Using it here keeps discovery and clone-target consistent.
2. **Parent of the current working directory** — `$(dirname "$PWD")`. When the
   engineer runs the command from inside a checked-out repo (the common case),
   this is exactly today's `../` sibling behavior, so nothing changes for
   engineers who already have the flat layout.

```bash
workspace_dir="${MOBIUS_WORKSPACE:-$(dirname "$PWD")}"
```

## Step W2 — Confirm or override with the user (once)

Present the resolved default and let the user accept or point elsewhere. Ask
this **once per command run**, not per repo:

```
Other boatsgroup repos this command needs (iac-eks-argocd, the service repo,
etc.) will be looked up under — and cloned into, if missing:

  <workspace_dir>

1. **Use this location** (recommended)
2. **Use a different directory** — provide an absolute path

Note: set MOBIUS_WORKSPACE in your shell to skip this prompt on future runs.
```

- If the user picks a different directory, validate it: it must be an absolute
  path to an existing directory (create it only if the user explicitly confirms
  creating it). Re-prompt on an invalid path — never silently coerce.
- Record the final value as `workspace_dir` for the rest of the command.

## Step W3 — Persist for the session

So Claude Code can read/write the resolved repos without re-prompting for
directory permission on every `git -C` call, add `workspace_dir` to the current
repo's `.claude/settings.local.json` under
`permissions.additionalDirectories` — the same mechanism `resolve-deps.sh`
already uses via `scripts/lib/update-settings.sh`. Add the resolved
`workspace_dir` itself (the parent), which covers every `<workspace_dir>/<repo>`
child. Skip silently if it's already present; this is a convenience, not a hard
gate.

## Output contract

After this module, the following holds for the rest of the command:

- `workspace_dir` is an absolute path to an existing directory.
- Every repo reference elsewhere in the command is written
  `<workspace_dir>/<repo>` (e.g. `git -C <workspace_dir>/iac-eks-argocd status`),
  **never** a bare `../<repo>`.
- The Preflight Checks (`docs/workflows/shared/multi-repo-git-workflow.md`
  § Preflight Checks) use `workspace_dir` both to check for a repo's presence
  and as the clone target when it's missing.
