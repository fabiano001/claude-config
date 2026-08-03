# Implementation Reference

Step 7 detail. Only run after the report is approved and the implementation mode is chosen. Work
per project (grouped by lockfile); a single PR can touch multiple projects.

## 1. Apply version changes

- **Direct / parent upgrades:** edit the version range in the project's `package.json`.
- **Transitive pins:** add the `overrides` block (see analysis.md) to the root `package.json`.

## 2. Refresh the lockfile

Use the repo's documented install command. For an intentional upgrade, `npm install` is correct —
the lockfile bump is the intended effect (do not use `npm ci`, which only reproduces the existing
lockfile). Run it in each project whose `package.json` changed:

```bash
npm install --prefix <project-dir>
```

If an `overrides` pin did not take, delete `node_modules` + lockfile and reinstall, or run
`npm install` twice (overrides sometimes need a second resolution pass).

## 3. Refactor impacted breaking changes

For every breaking change marked **impacted** in the report, edit the affected files to the new API
while preserving behavior. Match surrounding code style. Do not add comments unless the repo asks.
If a breaking change cannot be resolved without a behavior change, stop and surface it to the
operator rather than guessing.

## 4. Gate: lint, test, build, audit

In each touched project, run the repo's gates (read its `CLAUDE.md` for exact scripts):

```bash
npm run lint --prefix <project-dir>
npm test --prefix <project-dir>          # or the repo's CI test command
npm run build --prefix <project-dir>     # or the repo's stage/dev build
npm audit --prefix <project-dir>         # confirm the findings are cleared
```

Fix any fallout from the upgrade. The audit must show the targeted advisories resolved; if new
findings appear from the upgrade, fold them into the same analysis/report loop.

## 5. Repo conventions

- Apply any required **semantic-version bump** (some repos require it for specific projects).
- Use the repo's **branch naming** and **commit-message prefix** conventions.
- Only commit files you changed; never commit auto-generated/copied files the repo excludes.

## 6. Branch, commit, PR

```bash
git checkout -b <convention-based-branch-name>
git add <changed files only>
git commit -m "<PREFIX>: fix node vulnerabilities (<pkg list>)"
git push -u origin <branch>
gh pr create --fill
```

PR body should link `dependency-vulnerability-upgrade-report.md` and summarize, per finding, the
advisory, the upgrade applied, and whether refactoring was needed. End the PR body / commit with the
repo's required trailers if any.

## Dynamic workflow mode

When the operator chose the dynamic workflow:

- Launch an Opus 4.8 dynamic background workflow — an autonomous executor in an **isolated git
  worktree** (`Agent` with `run_in_background: true` and `isolation: "worktree"`, or the repo's
  preferred dynamic-workflow mechanism).
- Hand it the **approved report** and this implementation reference as its spec. It owns steps 1–6
  above and opening the PR, then reports back on completion.
- The main conversation stays free; relay the executor's result (PR link, audit status, any
  refactors that needed judgment) when it finishes.

Standard mode runs steps 1–6 inline in the current conversation.
