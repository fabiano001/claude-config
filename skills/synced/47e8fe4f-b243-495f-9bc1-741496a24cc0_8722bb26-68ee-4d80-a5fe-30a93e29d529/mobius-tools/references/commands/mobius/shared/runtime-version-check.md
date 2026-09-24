# Runtime Version Check

Shared preflight module for verifying the active runtime version matches the
target repository's version spec. Any `/mobius:*` command that operates on a
codebase SHOULD reference this module in its preflight phase.

**Philosophy**: Zero friction when things are set up correctly. Auto-switch
silently when a version manager is present. Only interrupt the user when
there's a real mismatch and no automated fix.

---

## Step 1 — Detect Language(s)

Scan the repo root for language markers. A repo may contain multiple languages
(e.g., Node backend + Python scripts). Check ALL markers and build a list.

| Marker File(s) | Language | Notes |
|---|---|---|
| `package.json` | Node.js | Primary indicator |
| `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile` | Python | Any one suffices |
| `Gemfile`, `*.gemspec` | Ruby | |
| `go.mod` | Go | |
| `Cargo.toml` | Rust | |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | Java/Kotlin | |
| `*.sln`, `*.csproj` | .NET/C# | |

If the calling command targets a specific language (e.g., instrument-service
targets Node.js), only check that language. If the command is language-agnostic,
check all detected languages.

---

## Step 2 — Find Version Spec

For each detected language, find the version spec the repo expects. Check in
priority order — first match wins.

### Node.js

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `.nvmrc` | Bare version or `lts/*` | `20.11.0`, `lts/iron`, `20` |
| 2 | `.node-version` | Bare version | `20.11.0`, `20` |
| 3 | `package.json` → `volta.node` | Exact version | `"20.11.0"` |
| 4 | `package.json` → `engines.node` | Semver range | `">=18.0.0"`, `"^20"` |

**Parsing rules:**
- `.nvmrc` with `lts/*` or `lts/<codename>` → resolve to latest matching version
- `.nvmrc` with major only (e.g., `20`) → match any `20.x.x`
- `engines.node` is a semver range — check if current version satisfies it
- `volta.node` is always an exact pin

### Python

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `.python-version` | Bare version | `3.11.7`, `3.11` |
| 2 | `pyproject.toml` → `[project]` → `requires-python` | PEP 440 range | `">=3.10"` |
| 3 | `Pipfile` → `[requires]` → `python_version` | Bare major.minor | `"3.11"` |

### Ruby

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `.ruby-version` | Bare version | `3.2.2` |
| 2 | `Gemfile` → `ruby "X.Y.Z"` | Quoted version in ruby directive | `ruby "3.2.2"` |

### Go

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `go.mod` → `go X.Y` directive | Major.minor | `go 1.22` |

### Rust

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `rust-toolchain.toml` → `[toolchain]` → `channel` | Channel + version | `"1.77.0"`, `"stable"`, `"nightly"` |
| 2 | `rust-toolchain` (plain file) | Bare channel | `1.77.0` |

### Java/Kotlin

| Priority | Source | Format | Example |
|---|---|---|---|
| 1 | `.java-version` | Bare version | `21` |
| 2 | `.sdkmanrc` → `java=` | SDKMAN identifier | `21.0.2-tem` |
| 3 | `pom.xml` → `<maven.compiler.release>` | Major version | `21` |
| 4 | `build.gradle(.kts)` → `sourceCompatibility` / `jvmToolchain` | Major version | `JavaVersion.VERSION_21`, `jvmToolchain(21)` |

**If no version spec is found for a language**: Skip the version check for that
language entirely. Do NOT assume a version — the repo hasn't declared one.

---

## Step 3 — Check Active Runtime Version

For each language with a version spec, check if the currently active runtime
version satisfies the spec.

### Version Check Commands

| Language | Command | Parse Output |
|---|---|---|
| Node.js | `node --version` | Strip leading `v` → `20.11.0` |
| Python | `python3 --version` | Strip `Python ` prefix → `3.11.7` |
| Ruby | `ruby --version` | Extract `X.Y.Z` from `ruby 3.2.2 ...` |
| Go | `go version` | Extract `X.Y.Z` from `go version go1.22.0 ...` |
| Rust | `rustc --version` | Extract `X.Y.Z` from `rustc 1.77.0 (...)` |
| Java | `java --version` | Extract major from `openjdk 21.0.2 ...` |

### Match Logic

| Spec Type | Match Rule |
|---|---|
| Exact version (`20.11.0`) | Active version must match exactly |
| Major only (`20`) | Active major version must match |
| Major.minor (`3.11`) | Active major.minor must match |
| Semver range (`>=18.0.0`, `^20`) | Active version must satisfy range |
| `lts/*` | Active version must be any current LTS |
| `lts/<codename>` | Active version must match the LTS codename's major |

**If the runtime is not installed at all** (command not found): This is a harder
failure — report it clearly and suggest installation. Do NOT offer to install a
runtime from scratch (too invasive). Suggest the user install it via their OS
package manager or the official installer, then re-run.

---

## Step 4 — Detect Version Manager

If the active version does NOT match the spec, check for installed version
managers that can switch to the correct version.

### Node.js Version Managers

Check in this order. First match is used.

| Priority | Manager | Detection | How to Switch |
|---|---|---|---|
| 1 | volta | `which volta` exits 0 | **Transparent** — volta auto-switches based on `package.json` `volta.node`. No explicit command needed. Just tell the user to run `volta pin node@<version>` if not already pinned. |
| 2 | fnm | `which fnm` exits 0 | `fnm use` (reads `.nvmrc` or `.node-version`) or `fnm use <version>` |
| 3 | nvm | `[ -s "$NVM_DIR/nvm.sh" ]` or `type nvm` in shell | `nvm use` (reads `.nvmrc`) or `nvm use <version>` |
| 4 | mise | `which mise` exits 0 | `mise use node@<version>` |
| 5 | asdf | `which asdf` exits 0 | `asdf shell nodejs <version>` |

### Python Version Managers

| Priority | Manager | Detection | How to Switch |
|---|---|---|---|
| 1 | pyenv | `which pyenv` exits 0 | `pyenv shell <version>` |
| 2 | mise | `which mise` exits 0 | `mise use python@<version>` |
| 3 | asdf | `which asdf` exits 0 | `asdf shell python <version>` |

### Ruby Version Managers

| Priority | Manager | Detection | How to Switch |
|---|---|---|---|
| 1 | rbenv | `which rbenv` exits 0 | `rbenv shell <version>` |
| 2 | rvm | `which rvm` exits 0 | `rvm use <version>` |
| 3 | mise | `which mise` exits 0 | `mise use ruby@<version>` |
| 4 | asdf | `which asdf` exits 0 | `asdf shell ruby <version>` |

### Go Version Managers

| Priority | Manager | Detection | How to Switch |
|---|---|---|---|
| 1 | goenv | `which goenv` exits 0 | `goenv shell <version>` |
| 2 | mise | `which mise` exits 0 | `mise use go@<version>` |

### Rust Version Manager

| Manager | Detection | How to Switch |
|---|---|---|
| rustup | `which rustup` exits 0 | `rustup override set <toolchain>` |

### Java Version Managers

| Priority | Manager | Detection | How to Switch |
|---|---|---|---|
| 1 | SDKMAN | `[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]` | `sdk use java <version>` |
| 2 | jenv | `which jenv` exits 0 | `jenv shell <version>` |
| 3 | mise | `which mise` exits 0 | `mise use java@<version>` |
| 4 | asdf | `which asdf` exits 0 | `asdf shell java <version>` |

---

## Step 5 — Take Action

### Decision Matrix

| Active Version Matches? | Version Manager Found? | Action |
|---|---|---|
| ✅ Yes | — | **No action.** Proceed silently. |
| ❌ No | ✅ Yes | **Auto-switch silently.** Run the switch command. Verify new version matches. If switch fails (version not installed in manager), tell user: `Run '<manager> install <version>' then re-run this command.` |
| ❌ No | ❌ No | **Warn + offer to install.** See below. |
| — (no spec) | — | **Skip.** No version spec in repo — nothing to check. |
| — (runtime missing) | — | **Hard warn.** Report that the runtime is not installed. Suggest installation. Do NOT auto-install runtimes. |

### Auto-Switch Behavior

When a version manager is found and the version doesn't match:

1. Run the manager's switch command (see Step 4 tables)
2. Verify the switch worked: re-run the version check command
3. If successful: log a single info line and proceed

```
ℹ️  Switched Node.js to v20.11.0 via fnm (repo specifies 20.11.0 in .nvmrc)
```

4. If the switch command fails because the version isn't installed in the manager:

```
⚠️  Node.js v20.11.0 is required (.nvmrc) but not installed in fnm.

Run: fnm install 20.11.0
Then re-run this command.
```

Do NOT auto-install versions into the version manager — `fnm install` downloads
binaries from the internet. Let the user decide.

### Warn + Offer Install (No Manager Found)

When no version manager is found and versions don't match:

```
⚠️  Node.js version mismatch

  Required:  v20.11.0 (from .nvmrc)
  Active:    v18.19.0

No version manager detected (checked: volta, fnm, nvm, mise, asdf).

Recommended: Install fnm (Fast Node Manager)
  curl -fsSL https://fnm.vercel.app/install | bash

  Then: fnm install 20.11.0 && fnm use 20.11.0

Continue anyway? The generated code targets Node.js v20 features.
```

**This is NOT a hard block.** If the user says "continue", proceed with a
logged warning. The version mismatch may or may not cause issues — the user
can judge.

### Recommended Managers (when offering install)

| Language | Recommended Manager | Why |
|---|---|---|
| Node.js | fnm | Fastest install, Rust-based, cross-platform, reads .nvmrc natively |
| Python | pyenv | Widest adoption, handles build from source |
| Ruby | rbenv | Lightweight, plugin ecosystem |
| Go | — (usually fine) | Go is highly backward-compatible; version mismatch rarely matters |
| Rust | rustup | Official toolchain manager, universally expected |
| Java | SDKMAN | Multi-vendor JDK management, widely adopted |

---

## Step 6 — Mandatory Enforcement Mode

Some commands require the correct runtime version to be active — not just
recommended. For example, `/mobius:instrument-service` Phase 8 starts the
real service process, which will fail if the wrong Node.js version is active.

When the calling command requests **mandatory enforcement**, the behavior
changes from advisory (warn + continue) to blocking (auto-fix or hard-stop).

### Mandatory Mode Decision Matrix

| Active Version Matches? | Version Manager Found? | Action |
|---|---|---|
| ✅ Yes | — | **No action.** Proceed silently. |
| ❌ No | ✅ Yes (version installed) | **Auto-switch silently.** Same as advisory mode. |
| ❌ No | ✅ Yes (version NOT installed) | **Auto-install + switch.** Run `<manager> install <version>` then switch. This is the key difference from advisory mode. |
| ❌ No | ❌ No | **Auto-install fnm + install version + switch.** See below. |
| — (no spec) | — | **Skip.** No version spec — nothing to enforce. |
| — (runtime missing) | — | **HARD STOP.** Runtime not installed at all. |

### Auto-Install Version into Manager (mandatory only)

When a version manager is present but the required version is not installed:

```bash
# Example: fnm
fnm install <version>
fnm use <version>

# Example: nvm
nvm install <version>
nvm use <version>

# Example: volta
volta install node@<version>
```

Verify the switch worked after install. If install fails (network error,
unsupported platform), **HARD STOP** with the error message.

### Auto-Install fnm (mandatory only, no manager detected)

When no version manager is detected and mandatory enforcement is requested:

1. **Install fnm:**

```bash
curl -fsSL https://fnm.vercel.app/install | bash
```

2. **Source fnm into current shell session:**

```bash
# Detect shell and source appropriately
eval "$(fnm env)"
```

3. **Install and switch to the required version:**

```bash
fnm install <version>
fnm use <version>
```

4. **Verify:**

```bash
node --version  # Must now match required version
```

If any step fails, **HARD STOP**:

```
❌ Could not auto-install Node.js version manager.

This command requires Node.js <version> (from <source>) and will start the
real service process. The correct Node.js version MUST be active.

Manual fix:
  1. Install fnm: curl -fsSL https://fnm.vercel.app/install | bash
  2. Restart your terminal
  3. Run: fnm install <version> && fnm use <version>
  4. Re-run this command
```

### Mandatory Mode Output

When mandatory enforcement succeeds via auto-install:

```
ℹ️  Installed fnm (Fast Node Manager) — required for correct Node.js version.
ℹ️  Installed Node.js v<version> via fnm.
ℹ️  Switched to Node.js v<version> (repo specifies <version> in <source>).
```

---

## Integration Guide

### How to Reference This Module

In your command's preflight phase, add:

```markdown
### Step Xb: Runtime Version Check

> Reference: `commands/mobius/shared/runtime-version-check.md`

Verify the active <LANGUAGE> version matches the target repo's version spec.
<enforcement_mode: advisory | mandatory>
```

**Advisory mode** (default):
```markdown
If a version manager is available, auto-switch silently. If not, warn and
offer to install <RECOMMENDED_MANAGER>.

This check is non-blocking — the user may proceed despite a version mismatch.
```

**Mandatory mode** (for commands that start the real service):
```markdown
If a version manager is available, auto-switch silently. If the required
version is not installed in the manager, auto-install it. If no manager
is present, auto-install fnm, install the required version, and switch.

This check is BLOCKING — the command cannot proceed with a version mismatch.
```

### What the Calling Command Needs to Provide

| Input | Description |
|---|---|
| Target language | Which language to check (or "all detected") |
| Repo root path | Where to look for version spec files |
| Enforcement mode | `advisory` (default) or `mandatory` |

### What This Module Returns

| Output | Description |
|---|---|
| `version_check.status` | `matched`, `switched`, `installed_and_switched`, `mismatch_warned`, `skipped` |
| `version_check.language` | Language checked |
| `version_check.required_version` | Version from spec file |
| `version_check.active_version` | Currently active version (after any switch) |
| `version_check.manager_used` | Manager that performed the switch (if any) |
| `version_check.manager_installed` | Whether a manager was auto-installed (`true`/`false`) |
| `version_check.spec_source` | File the version spec came from |
| `version_check.enforcement_mode` | `advisory` or `mandatory` |

### Which Commands Use Which Mode

| Command | Mode | Rationale |
|---|---|---|
| `/mobius:instrument-service` | `mandatory` | Phase 8 starts the real service — wrong Node version = startup failure |
| `/mobius:validate-service` | `advisory` | Validation can proceed with warnings |
| `/mobius:document-service` | `advisory` | Documentation generation doesn't execute service code |
| All other commands | `advisory` | Default — warn but don't block |
