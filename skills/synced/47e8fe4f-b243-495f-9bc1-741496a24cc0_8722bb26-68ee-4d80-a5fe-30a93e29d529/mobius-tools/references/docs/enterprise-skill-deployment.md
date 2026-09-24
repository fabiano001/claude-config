# Enterprise Skill Deployment

Mobius Tools is distributed to all Claude users in the organization as an enterprise skill. This document covers the deployment process for administrators.

## How It Works

A GitHub Actions workflow (`package-skill.yml`) packages the skill into a versioned zip artifact conforming to the Claude skill format on every push to `main` that changes skill-relevant content. The zip must then be manually uploaded to Claude.

**There is no automated push to the enterprise — a fresh zip must be uploaded every time an update is merged to `main`.**

## Skill Format

The zip must contain exactly **one top-level folder** with `SKILL.md` directly inside it (not nested deeper). The artifact follows this structure:

```
mobius-tools/                 # Single top-level folder (required)
├── SKILL.md                  # Required entry point (YAML frontmatter + instructions)
└── references/               # Supporting documentation loaded as needed
    ├── commands/mobius/       # Top-level workflow specs (slash command definitions)
    ├── data/                  # Reference data (YAML/CSV)
    ├── templates/             # File templates for code generation
    ├── docs/                  # Architecture documentation
    └── ecosystem/             # Dependency graph and repo summaries
```

## Deployment Steps

### For Individual Users (Claude.ai)

1. Download the zip from the GitHub Actions artifact or Release
2. Open **Claude.ai > Settings > Capabilities > Skills**
3. Click **"Upload skill"**
4. Select the zip file
5. Toggle on the **mobius-tools** skill

### For Organization-Wide Deployment (Enterprise)

1. **Download the artifact** — After a merge to `main`, go to the repo's Actions tab, open the latest "Package Enterprise Skill" run, and download the zip from the Artifacts section. For tagged releases, the zip is also attached to the GitHub Release.

2. **Upload the skill** — In the Claude admin portal, navigate to **Settings > Skills** and click **"Upload skill"**. Select the zip file.

3. **Enable for organization** — Toggle the skill on and select the deployment scope (all users or specific groups).

4. **Verify distribution** — Members will see the mobius-tools skill on their next session.

### For Claude Code Users

Place the skill in the Claude Code skills directory:
- **macOS**: `/Library/Application Support/ClaudeCode/.claude/skills/mobius-tools/`
- **Linux/WSL**: `/etc/claude-code/.claude/skills/mobius-tools/`

Or deploy via MDM for organization-wide coverage.

## When to Deploy

Deploy a new zip whenever a merge to `main` changes any of:

- `commands/**`
- `data/**`
- `templates/**`
- `docs/**`
- `ecosystem/**`
- `.claude/skills/**`
- `SKILL.md`
- `CLAUDE.md`
- `VERSION`

The workflow only triggers on these paths, so if a run produced a new artifact, it should be deployed.

## Versioning

The zip is named `mobius-tools-skill-v<VERSION>.zip`, where the version comes from the `VERSION` file in the repo root. The version is also stamped into `SKILL.md` metadata. Bump `VERSION` when making significant changes to help track which version is deployed.

## Troubleshooting

**Skill won't upload**: The zip must contain exactly one top-level folder (e.g. `mobius-tools/`) with `SKILL.md` directly inside it — not nested deeper. Claude enforces a **200-file maximum** per zip; the workflow only includes top-level command specs (not sub-command files) to stay under this limit.

**Skill doesn't trigger**: Check that the `description` field in `SKILL.md` includes the trigger phrases relevant to the user's query. Ask Claude "When would you use the mobius-tools skill?" to debug.

**Skill triggers too often**: Add negative triggers or narrow the description scope in `SKILL.md`.
