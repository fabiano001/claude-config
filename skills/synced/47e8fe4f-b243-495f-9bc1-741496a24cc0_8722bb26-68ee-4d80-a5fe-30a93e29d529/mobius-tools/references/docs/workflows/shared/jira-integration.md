# JIRA Ticket Integration

> **Claude + Codex compatible**: This reference can be followed by both human
> engineers and AI agents.

Platform-shared JIRA ticket integration for Mobius commands. Provides a
standard pre-branch ticket prompt, branch naming from ticket IDs, and
ticket creation when needed.

JIRA integration is **optional** — users can always skip it. Some commands
strongly encourage it (see [Opt-In Guidance](#opt-in-guidance) below).

---

## First-Time Setup

Check whether the Jira CLI is installed and authenticated:

```bash
which jira && jira me
```

If the CLI is missing or not authenticated, present the user with three options:

```
Jira CLI is not installed. How would you like to proceed?

1. Install for me (recommended)
   I'll run: brew install jira-cli && jira init

2. I'll install it myself
   Run these commands:
   - brew install jira-cli
   - jira init (follow prompts for server, email, API token)

3. Use environment variables instead
   Set these in your shell profile:

   export JIRA_BASE_URL="https://your-company.atlassian.net"
   export JIRA_EMAIL="your-email@company.com"
   export JIRA_API_TOKEN="your-api-token"
   export JIRA_PROJECT="YOUR-PROJECT-KEY"

   Get an API token from: https://id.atlassian.com/manage-profile/security/api-tokens

Which option do you prefer? (1/2/3)
```

### Setup Commands by Choice

**Option 1 — Install for the user:**

```bash
brew install jira-cli
jira init
# Follow the interactive prompts
```

**Option 2 — User installs:**

Provide the commands above and wait for the user to confirm before continuing.

**Option 3 — Environment variables:**

```bash
# Verify the required variables are set
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:-NOT SET}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:-NOT SET}"
echo "JIRA_API_TOKEN: ${JIRA_API_TOKEN:+SET (hidden)}"
echo "JIRA_PROJECT: ${JIRA_PROJECT:-NOT SET}"
```

### Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `JIRA_BASE_URL` | Jira instance URL | `https://company.atlassian.net` |
| `JIRA_EMAIL` | Your Atlassian email | `user@company.com` |
| `JIRA_API_TOKEN` | API token (not password) | `ATATT3x...` |
| `JIRA_PROJECT` | Default project key | `PROJ` |

Get an API token from: https://id.atlassian.com/manage-profile/security/api-tokens

---

## Pre-Branch Ticket Prompt

Present this prompt at the start of the command's intake or preflight phase,
before any branch is created:

```
Before we create a branch, is there a Jira ticket for this work?

1. Yes, I have a ticket  ->  Enter ticket ID (e.g., PROJ-123)
2. No, create one for me ->  I'll create a ticket first
3. No ticket needed      ->  Skip JIRA integration
```

Store the outcome as `jira_ticket_id`:

- **Option 1**: `jira_ticket_id` = the ticket ID the user provides (e.g., `PLAT-123`)
- **Option 2**: `jira_ticket_id` = the ticket ID created in [Creating Tickets](#creating-tickets)
- **Option 3**: `jira_ticket_id` = `null`

Pass `jira_ticket_id` to the branch-naming step and to the git workflow doc.

---

## Branch Naming from Ticket

**Branch format with ticket:**

```
<type>/<ticket-id>-<short-description>
```

```bash
# Example: ticket PLAT-123, "Add cert-manager addon"
git checkout -b feat/PLAT-123-add-cert-manager
```

**Branch format without ticket** (user chose option 3):

```
<type>/<short-description>
```

```bash
# Example: no ticket
git checkout -b feat/add-cert-manager
```

### Type Mapping from Jira Issue Type

| Jira Issue Type | Branch Prefix |
|-----------------|---------------|
| Story | `feat/` |
| Task | `feat/` or `chore/` |
| Bug | `fix/` |
| Improvement | `refactor/` |
| Spike | `chore/` |

When the issue type is ambiguous or the ticket comes from option 1 (user-provided ID),
infer the prefix from the work being done rather than looking up the issue type.

---

## Creating Tickets

When the user selects option 2 ("create one for me"), gather the following before
calling the API or CLI:

```
I'll create a Jira ticket. Please provide:

1. Summary (required): Brief title for the ticket
2. Description (optional): Detailed description of the work
3. Issue Type: Task, Story, Bug, or Improvement (default: Task)

Example:
- Summary: "Add cert-manager addon to EKS platform"
- Description: "Deploy cert-manager via GitOps and wire IRSA role"
- Type: Task
```

### Using Jira CLI (Primary)

```bash
# Create ticket with parameters
jira issue create \
  --project "PROJ" \
  --type "Task" \
  --summary "Summary here" \
  --description "Description here"

# Capture the created ticket ID
TICKET_ID=$(jira issue list --created today --plain --columns key,summary | head -1 | awk '{print $1}')
echo "Created ticket: $TICKET_ID"
```

### Using API Fallback (if CLI is not available)

```bash
# Create ticket via REST API
curl -s -X POST \
  -H "Authorization: Basic $(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)" \
  -H "Content-Type: application/json" \
  --url "${JIRA_BASE_URL}/rest/api/3/issue" \
  --data '{
    "fields": {
      "project": {"key": "'"${JIRA_PROJECT}"'"},
      "summary": "TICKET_SUMMARY",
      "description": {
        "type": "doc",
        "version": 1,
        "content": [{"type": "paragraph", "content": [{"type": "text", "text": "TICKET_DESCRIPTION"}]}]
      },
      "issuetype": {"name": "Task"}
    }
  }' | jq -r '.key'
```

After the ticket is created, set `jira_ticket_id` to the returned key and
proceed with branch naming.

---

## Ticket ID Propagation

When `jira_ticket_id` is set (non-null), carry it through the full change lifecycle
to ensure traceability from ticket to PR.

| Artifact | Format | Example |
|----------|--------|---------|
| Branch name | `<type>/<ticket-id>-<description>` | `feat/PLAT-123-add-cert-manager` |
| Commit footer | Last line of the commit body | `PLAT-123` |
| PR title | `<conventional-title> [<ticket-id>]` | `feat(addon): add cert-manager [PLAT-123]` |
| PR body | JIRA section with ticket ID and link | See format below |

**Commit body format:**

```
feat(addon): add cert-manager

Deploy cert-manager via GitOps, create IRSA role, and wire
ApplicationSet discovery for bg-qa and bg-prod environments.

PLAT-123
```

**PR body JIRA section** (include when `JIRA_BASE_URL` is set):

```markdown
## JIRA

[PLAT-123](https://company.atlassian.net/browse/PLAT-123)
```

If `JIRA_BASE_URL` is not set, include only the bare ticket ID without a hyperlink.

---

## Integration with Mobius Commands

Commands reference this doc with a section anchor:

```markdown
> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt
```

### Invocation Point

Invoke the pre-branch ticket prompt at the **start of the intake or preflight
phase**, before any files are generated or branches are created. This is
typically the first question after the command identifies the target service,
XRD, or hub/spoke name.

### Handoff to Git Workflow

After the ticket prompt resolves, pass `jira_ticket_id` to the branch-naming
step in `docs/workflows/shared/multi-repo-git-workflow.md`. That doc handles
branch creation, commit sequencing, push, and PR creation — using the ticket ID
wherever the format above applies.

---

## Opt-In Guidance

All commands allow the user to skip JIRA integration with option 3. The table
below records the recommended stance for each command and the rationale.

| Command | JIRA Stance | Reason |
|---------|-------------|--------|
| `/mobius:add-service` | Strongly encouraged | New service deployments generate multiple cross-repo changes that benefit from ticket tracking |
| `/mobius:new-xrd` | Strongly encouraged | New XRDs are significant platform changes affecting composition and registration |
| `/mobius:new-hub` | Strongly encouraged | Hub creation is high-impact infrastructure with long-lived audit requirements |
| `/mobius:new-spoke` | Strongly encouraged | Spoke registration touches IAM trust chains and multi-repo wiring |
| `/mobius:migrate-ecs-service` | Strongly encouraged | Migration tracking is critical for rollback planning and stakeholder visibility |
| `/mobius:debug-service` | Optional | Diagnostic work is ephemeral; a ticket adds overhead without clear benefit |
| `/mobius:debug-appset` | Optional | Diagnostic work is ephemeral; a ticket adds overhead without clear benefit |
| `/mobius:new-project` | Optional | Depends on team workflow; some teams track ArgoCD project changes, others do not |

In all cases, the user can skip with option 3 and proceed without a ticket.
When skipping, log the decision:

```
Proceeding without a JIRA ticket. Branch: feat/add-cert-manager
```

---

## Verification Commands

Run these to confirm the JIRA integration is functional before invoking a
command that depends on it.

```bash
# Check CLI installation
which jira && echo "CLI installed" || echo "CLI not installed"

# Check CLI authentication
jira me 2>/dev/null && echo "CLI authenticated" || echo "CLI not authenticated"

# Check environment variables
[ -n "$JIRA_BASE_URL" ] && \
  [ -n "$JIRA_EMAIL" ] && \
  [ -n "$JIRA_API_TOKEN" ] && \
  echo "Env vars set" || echo "Env vars missing"

# Verify a specific ticket exists (replace PROJ-123 with the actual ID)
jira issue view PROJ-123 --plain 2>/dev/null || \
  curl -s \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    "${JIRA_BASE_URL}/rest/api/3/issue/PROJ-123" | jq -r '.key'
```
