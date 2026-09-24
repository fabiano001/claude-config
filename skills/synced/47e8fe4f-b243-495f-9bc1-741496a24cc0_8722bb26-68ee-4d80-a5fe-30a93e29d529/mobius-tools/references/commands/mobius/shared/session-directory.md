<!-- MODULE_SUMMARY: Disk-backed session persistence protocol for large documentation commands. Stores deep analysis artifacts in .mobius-docs-session/ to reduce context compaction while keeping a compact in-context manifest. -->

# Shared Session Directory Protocol (`.mobius-docs-session/`)

Use this protocol for long-running documentation commands that produce large intermediate analysis datasets.

## Goals

1. Keep persistent analysis artifacts out of the model context window.
2. Preserve resumability across compactions and long runs.
3. Keep generation deterministic via explicit file-path contracts.

## Directory Location

- Create a fixed directory at the **target repo root**:
  - `.mobius-docs-session/`
- Never use random temp paths for core artifacts.
- The fixed path is part of the command contract and must be referenced by relative path in later phases.

## Required Safety Rules

1. Session artifacts MUST be ignored by git (`.mobius-docs-session/` in `.gitignore` or equivalent).
2. Session artifacts are **intermediate state**, not user-facing deliverables.
3. Do not commit session artifacts to PRs.
4. JSON is the canonical interchange format for pass artifacts.

## In-Context vs On-Disk Contract

Keep only a compact manifest in context (paths + tiny summaries). Store full findings on disk.

- **In context**: `session_manifest_compact`
  - session id
  - command name
  - target list
  - pass completion status
  - artifact file paths
  - short metrics (counts only)
- **On disk**: full pass-level findings and evidence arrays.

If artifact payload is large, always prefer on-disk storage and selective read-back.

## Resume / Stale Detection

When `.mobius-docs-session/manifest.json` already exists:

1. Validate it matches current command + repo + scope.
2. Check staleness (recommended: 24h threshold).
3. Prompt user to **resume** or **reset** if stale or scope changed.
4. If reset, clear only `.mobius-docs-session/` artifacts (not docs outputs).

## Selective Read-Back Rule

Generation phases MUST read only the pass artifacts required for the current output file.
Do not reload all pass artifacts into context at once.

## Recommended Manifest Shape

```json
{
  "session_id": "string",
  "command": "document-repo | document-service | document-iac | document-library",
  "repo_root": "string",
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601",
  "targets": [
    {
      "name": "string",
      "scope_root": "string",
      "status": "pending | in_progress | analyzed | generated",
      "artifacts": {
        "pass_files": ["relative/path.json"],
        "composed_discovery": "relative/path.json"
      },
      "summary": {
        "endpoints": 0,
        "modules": 0,
        "entities": 0,
        "env_vars": 0,
        "errors": 0
      }
    }
  ]
}
```

Use the smallest manifest that still allows deterministic continuation.

## Per-Command Directory Layouts

### document-library

When standalone:
```
.mobius-docs-session/
  manifest.json
  document-library/{target_app_name}/
    pass-L1-api-surface.json
    pass-L2-capabilities.json
    pass-L3-cloud-deps.json
    pass-L4-iam-permissions.json
    pass-L5-config-surface.json
    pass-L6-usage-patterns.json
```

When delegated from document-repo:
```
.mobius-docs-session/
  manifest.json
  {target_app_name}/
    document-library/
      pass-L1-api-surface.json
      pass-L2-capabilities.json
      pass-L3-cloud-deps.json
      pass-L4-iam-permissions.json
      pass-L5-config-surface.json
      pass-L6-usage-patterns.json
```
