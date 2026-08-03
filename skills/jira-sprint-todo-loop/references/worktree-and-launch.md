# Worktree creation and launch (Step 3 detail)

Applies to every ticket that passed all three gates in [ticket-selection.md](ticket-selection.md).

## 1. Parse the Repos Involved comment

Scan the ticket's comments (already fetched in Step 1) for one matching, case-insensitively, the start of `this ticket will involve changes in these repos:`. If more than one such comment exists (a ticket's scope can be revised), use the **most recently created** one. Parse everything after the colon as a comma-separated list, trim each entry, and match case-insensitively against the known-repo list in SKILL.md. Unrecognized entries: keep them (don't silently drop — `jira-sprint-manager`'s own Rule D treats an unrecognized-but-present repo name as worth flagging rather than discarding) but call them out explicitly in the Step 4 report as "unrecognized repo name — verify manually."

**No matching comment found at all:** do not fall back to scanning the Description/Technical Details text for repo names — that fuzzy-matching approach is exactly what an earlier incident in this codebase (documented in `ticket-creator`/`jira-sprint-manager`) moved away from. Skip this ticket, report it as qualifying but repo-unresolvable, and recommend the operator either add the comment manually or re-run `ticket-creator` against it.

## 2. Skip if this ticket already has its own Started/Completed marker

Before touching any repo, check this ticket's own comments (same fetch from Step 1) for `Ticket Driver Implementation Started` or `Ticket Driver Implementation Completed` (case-insensitive substring, either one). If either is present, skip the whole ticket here — report "already has a `<Started|Completed>` marker; not launching" and move to the next ticket. This is deliberate defense-in-depth: `ticket-driver`'s own pre-run Guard would refuse anyway once launched, but there's no reason to spend a worktree creation and a terminal-tab launch on a run that's guaranteed to immediately bail.

## 3. Per repo: resolve the dependency base-branch override, then create the worktree

Let `IMPL_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>` and the main repo checkout be `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>`.

**If `IMPL_PATH` already exists on disk:** skip creating it. Append a reminder ("worktree already exists at `<IMPL_PATH>` — implementation may already be underway there manually; not re-launching") and move to the next repo. Same idempotency rule `jira-sprint-manager` Rule D already applies to implementation worktrees.

**Otherwise, determine `BASE_REF` before creating anything:**

- **No dependency, or Gate 2 found the ticket has none:** `BASE_REF = origin/main`. This is the normal case for most tickets.
- **Ticket has a dependency `<DEP-KEY>` that Gate 2 judged implemented:** check whether `<DEP-KEY>`'s branch has actually landed in `main` yet:
  ```bash
  git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> fetch origin <DEP-KEY> main
  git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> merge-base --is-ancestor origin/<DEP-KEY> origin/main
  ```
  - **Exit 0** (already an ancestor — merged): `BASE_REF = origin/main`. The dependency's work is already in main; no special handling needed.
  - **Non-zero exit** (not yet merged): `BASE_REF = origin/<DEP-KEY>`. This is the actual point of the override — the new ticket's branch should build on top of the not-yet-merged dependency's work, not on a `main` that doesn't have it yet.
  - **`fetch` itself fails** (branch not found on origin, network error): this shouldn't happen if Gate 2 judged the dependency implemented — `ticket-driver` always pushes a branch and opens a PR as part of finishing implementation in this codebase, so an implemented ticket should always have a fetchable remote branch. But don't assume it silently: print an explicit warning naming the exact failure, fall back to `BASE_REF = origin/main`, and flag this ticket's launch as "base branch may be wrong — dependency branch unfetchable" in the Step 4 report, so the operator knows to double-check rather than trusting a silently-degraded choice.

**Create the worktree** using the same 3-case branch-wiring `jira-sprint-manager` Rule D already uses, with `BASE_REF` substituted for the literal `origin/main` in case 3 only:

1. `git -C <main-repo-path> rev-parse --verify --quiet refs/heads/<TICKET-KEY>` succeeds (local branch exists) → `git -C <main-repo-path> worktree add <IMPL_PATH> <TICKET-KEY>`. `BASE_REF` is irrelevant here — an existing local branch is reused as-is, dependency or not.
2. No local branch, but `git -C <main-repo-path> ls-remote --exit-code --heads origin <TICKET-KEY>` succeeds (remote branch exists) → `git -C <main-repo-path> worktree add <IMPL_PATH> -b <TICKET-KEY> --track origin/<TICKET-KEY>`. Same — `BASE_REF` doesn't apply, the ticket's own remote branch already has its history.
3. **Neither exists (brand new branch)** → `git -C <main-repo-path> worktree add <IMPL_PATH> -b <TICKET-KEY> <BASE_REF>`. This is the only case `BASE_REF` actually changes anything — normally `origin/main`, but `origin/<DEP-KEY>` when the dependency override applies.

If `worktree add` fails for any reason (permission, conflicting path, ref issue), report the verbatim error against this repo, do not retry, and move to the next repo — a failure on one repo must not block the others.

## 4. Launch the backgrounded session

```bash
~/.claude/skills/jira-sprint-manager/open-claude-session.sh \
  ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY> \
  --prompt "/background /ticket-driver <TICKET-KEY> TODO-MODE" \
  --session-name "<TICKET-KEY> - <CODE_NAME>"
```

- `<CODE_NAME>`: `WEBAPP` for `webapp-react-trident`; `PRBT` for `portal-react-boattrader`; `LAMBDA` for any repo name containing `lambda`; `TERRAFORM` for any repo name containing `terraform` (e.g. `terraform-stack-trident` → `TERRAFORM`); otherwise the repo's own literal name (e.g. `configd`, `pp-algorithm`).
- The session name uses `" - "` (space, hyphen, space) — e.g. `TRIDENT-895 - WEBAPP` — not a bare-hyphen `TRIDENT-895-WEBAPP` (that compact form is `jira-sprint-manager`'s own convention for its worktree-kickoff sessions; this skill uses the spaced form as given).
- The prompt is **exactly** `/background /ticket-driver <TICKET-KEY> TODO-MODE` — both the `/background` prefix and the `TODO-MODE` token are load-bearing:
  - Without `/background`, the new session starts in the ordinary foreground interactive view, not the agent view — defeating the entire point of a bulk, unattended launch.
  - `ticket-driver` checks for the literal token `TODO-MODE` to activate that mode. The bare word `TODO` does nothing — the run would silently execute in **standard** mode instead, which tries to transition the ticket to "Ready for QA" at the end (wrong, since the ticket is still sitting in TO DO and hasn't even been picked up into "In Progress").

Capture the script's own result line (`iTerm2: opened new tab ...` vs `iTerm2: focused existing tab ...`) for the Step 4 report — a "focused existing tab" result on a brand-new worktree would be unexpected and worth calling out (it would mean a `jsm:<dirbasename>` marker from an unrelated prior session collided with this directory's basename).

## Worked example

`TRIDENT-960` depends on `TRIDENT-954` (judged implemented via the fallback status signal — see `ticket-selection.md`'s worked example), touches `webapp-react-trident` only. `IMPL_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-960` doesn't exist yet. Checking the dependency: `git fetch origin TRIDENT-954 main` succeeds, but `merge-base --is-ancestor origin/TRIDENT-954 origin/main` exits non-zero — `TRIDENT-954` hasn't been merged yet (it's `Resolved - Ready for QA`, not `Live`/`Done`). `BASE_REF = origin/TRIDENT-954`. Neither a local nor remote `TRIDENT-960` branch exists → case 3 → `git worktree add ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-960 -b TRIDENT-960 origin/TRIDENT-954`. Launch: `open-claude-session.sh ~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident-TRIDENT-960 --prompt "/background /ticket-driver TRIDENT-960 TODO-MODE" --session-name "TRIDENT-960 - WEBAPP"`.
