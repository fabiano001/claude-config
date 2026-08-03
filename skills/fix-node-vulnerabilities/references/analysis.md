# Analysis Reference

Detailed commands and strategy for steps 2–4 of the skill. Run all commands from the **project
directory** that owns the lockfile for the vulnerability (e.g. `dynamic-app/`, `functions/`).

## Direct vs transitive

A package is **direct** if it is listed in that project's `package.json` under `dependencies` or
`devDependencies`. Check the file directly, or:

```bash
npm ls <pkg> --depth=0
```

If it is not a top-level entry, it is **transitive**. Find the dependency path to the root:

```bash
npm why <pkg>          # npm 7+: shows every path that pulls the package in
npm ls <pkg>           # full tree showing parents
```

The **upgrade target** is the top-level (package.json) dependency at the head of those paths. If
multiple top-level packages pull it in, each is a candidate target — prefer the one whose newer
release ships the patched transitive version.

## Minimum non-breaking upgrade

1. List published versions and pick the lowest that satisfies the advisory's patched range:

   ```bash
   npm view <target> versions --json
   npm view <target> version          # latest, for reference
   ```

2. Compare against the current installed/declared version and classify the jump per semver:
   - **patch**: `x.y.Z` changes only
   - **minor**: `x.Y.z` changes
   - **major**: `X.y.z` changes (potential breaking changes)

3. The goal is the **lowest version that clears the advisory**. If that is patch/minor, you are done
   for that target — no breaking-change research needed.

4. `npm audit --json` includes a `fixAvailable` field per advisory:
   - `fixAvailable: true` → a non-breaking fix exists via `npm audit fix`.
   - `fixAvailable: { name, version, isSemVerMajor }` → the named upgrade is required;
     `isSemVerMajor: true` means a major bump (trigger step 4).

## Transitive `overrides` pin (least-breaking option)

When the parent has not released a version that pulls a patched transitive dep — or that release is
a major bump — pin just the transitive dependency with an `overrides` block in the **root**
`package.json`:

```jsonc
{
  "overrides": {
    "<vulnerable-transitive-pkg>": "<patched-version>"
  }
}
```

Scope it under the parent when a global pin is too broad:

```jsonc
{
  "overrides": {
    "<parent-pkg>": {
      "<vulnerable-transitive-pkg>": "<patched-version>"
    }
  }
}
```

Prefer an override when it avoids a major bump of a widely-used parent. Validate after with
`npm install` + `npm ls <vulnerable-transitive-pkg>` (all instances should show the patched version)
and a build/test run, since a forced version can still break the parent at runtime.

## Major upgrade — breaking-change research

1. Resolve and read the package docs / changelog:
   - context7: `resolve-library-id` → `query-docs` (ask for "breaking changes" / "migration").
   - WebFetch the GitHub releases or `CHANGELOG.md` between current and target major.
2. Enumerate each breaking change as a discrete item (removed export, renamed API, changed default,
   dropped Node version, ESM-only, changed return type, etc.).
3. For each item, search the codebase for usage:

   ```bash
   grep -rn "<symbol-or-import>" <project>/src
   ```

   Decide **impacted** (used → needs refactor) or **not impacted** (unused). Record the affected
   files for the report and for the implementation step.
4. Watch for **type-level** breakage (TypeScript): a changed type signature may not grep cleanly —
   rely on the build/`tsc` step to surface those during implementation.
