# Worktree creation and launch (Step 3 detail)

Applies to every ticket that passed all three gates in [ticket-selection.md](ticket-selection.md).

## 1. Parse the Repos Involved comment

Scan the ticket's comments (already fetched in Step 1) for one matching, case-insensitively, the start of `this ticket will involve changes in these repos:`. If more than one such comment exists (a ticket's scope can be revised), use the **most recently created** one. Parse everything after the colon as a comma-separated list, and for each entry:
- Trim whitespace.
- Check for a trailing `(new)` marker (case-insensitive, tolerate the space before it) — `ticket-creator` tags a repo this way when it doesn't exist yet and must be created from scratch (e.g. `lambda-node-trident-loan-recovery (new)`). If present, strip it and set `IS_NEW_REPO[<name>] = true`; otherwise `false`.
- Match the (stripped) name case-insensitively against the known-repo list in SKILL.md.

Unrecognized entries that are NOT tagged `(new)`: keep them (don't silently drop — `jira-sprint-manager`'s own Rule D treats an unrecognized-but-present repo name as worth flagging rather than discarding) but call them out explicitly in the Step 4 report as "unrecognized repo name — verify manually." **Entries tagged `(new)` are never labeled "unrecognized — verify manually"**, even when absent from the known-repo list — that's the expected case for a repo that doesn't exist yet; see Step 2.5 below for how they're handled.

**No matching comment found at all:** do not fall back to scanning the Description/Technical Details text for repo names — that fuzzy-matching approach is exactly what an earlier incident in this codebase (documented in `ticket-creator`/`jira-sprint-manager`) moved away from. Skip this ticket, report it as qualifying but repo-unresolvable, and recommend the operator either add the comment manually or re-run `ticket-creator` against it.

## 2. Skip if this ticket already has its own Started/Completed marker

Before touching any repo, check this ticket's own comments (same fetch from Step 1) for `Ticket Driver Implementation Started` or `Ticket Driver Implementation Completed` (case-insensitive substring, either one). If either is present, skip the whole ticket here — report "already has a `<Started|Completed>` marker; not launching" and move to the next ticket. This is deliberate defense-in-depth: `ticket-driver`'s own pre-run Guard would refuse anyway once launched, but there's no reason to spend a worktree creation and a terminal-tab launch on a run that's guaranteed to immediately bail.

## 2.5. Bootstrap any repo tagged `(new)` whose directory doesn't exist yet

Run this **before** Step 3, per repo, whenever `IS_NEW_REPO[<repo>] == true` AND `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>` does not exist on disk. (If the directory already exists — e.g. a prior run already bootstrapped it — skip straight to Step 3 for this repo; this is idempotent, same as everything else in this workflow.)

1. **Create the base directory** (not a worktree — this becomes the repo's own root checkout, the same role `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>` plays for every other repo):
   ```
   mkdir -p ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>
   ```
   (standalone Bash.)

2. **Create the actual GitHub repo.** Invoke the `create-boatsgroup-repo` skill with the repo name as its argument, and **wait for it to finish** — do not proceed to step 3 until it returns. Confirm it actually reports a created repo URL (`https://github.com/boatsgroup/<repo>`) before continuing.
   - **If it reports the name is already taken:** the `(new)` tag was stale — the repo actually already exists on GitHub. Skip step 3's `git init` + push entirely and instead run `git clone git@github.com:boatsgroup/<repo>.git ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>` to pull down whatever's already there. Then go straight to Step 3 below.
   - **Any other failure:** this repo cannot be bootstrapped this run. Do not create a worktree for it. Record the reason for this ticket's Step 4 disposition line: `repo <repo> tagged (new) but automated repo creation failed: <error>`. Move to the next repo (or, if this was the ticket's only repo, the ticket gets the "Didn't match..." line with this reason).

3. **Seed the first commit and push `main`** (each a standalone Bash call — never `&&`, never shell redirection):
   - Write `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>/README.md` (via the Write tool, not `echo`) with content `# <repo>`.
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> init`
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> add README.md`
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> commit -m "first commit"`
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> branch -M main`
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> remote add origin git@github.com:boatsgroup/<repo>.git`
   - `git -C ~/BOATS-GROUP-PROJECTS-GITHUB/<repo> push -u origin main`

   If any of these fail: this repo cannot be bootstrapped this run. Record for the Step 4 disposition line: `repo <repo> tagged (new), created on GitHub, but first-commit push failed: <error> — resolve manually, then re-run`. Do not create a worktree for it.

4. **Fall through to Step 3.** `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>` is now a real repo with `main` pushed to `origin` — proceed exactly as for any pre-existing repo.

**Note (this can block on a live GitHub sign-in):** `create-boatsgroup-repo` opens a real, visible browser; if its persisted session has expired, it pauses waiting for someone to complete SSO. Since this skill is designed to run unattended, that's a real limitation for this specific path — if nobody's watching when it happens, this run sits blocked until someone notices. Keep the browser's persisted session signed in if you expect `(new)`-tagged repos to come through an unattended run.

## 3. Per repo: resolve the dependency base-branch override, then create the worktree

Let `IMPL_PATH = ~/BOATS-GROUP-PROJECTS-GITHUB/<repo>-<TICKET-KEY>` and the main repo checkout be `~/BOATS-GROUP-PROJECTS-GITHUB/<repo>` (guaranteed to exist by this point — either it already did, or Step 2.5 just bootstrapped it).

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
