---
name: migrate-pipeline-to-atlantis
description: Convert a Terraform repository from pipeline CI/CD to Atlantis
argument-hint: [repo-path]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->

# Migrate Terraform Repository from Pipeline to Atlantis

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-5`).
>
> This command performs file detection, pattern matching, multi-file edits, and
> documentation updates. A capable model is needed for accurate detection and safe
> transformation, but the workflow is deterministic enough that opus is not required.

This command converts a Terraform repository from the legacy `pipeline-terraform`
module CI/CD approach to Atlantis-based GitOps workflow. It handles both
`terraform_legacy` (Makefile-based with symlinks) and `default` (standard Terraform)
workflow patterns.

> **Self-contained**: This command documents the full conversion workflow.
> No external workflow doc required.

## What Gets Changed

1. **Pipeline module removal** — Removes `module "pipeline"` declarations from Terraform code
2. **Version upgrades** — Updates Terraform to `~> 1.14.0` and AWS provider to `>= 5.0, < 7.0`
3. **Backend modernization** — Replaces `dynamodb_table = "TerraformState"` with `use_lockfile = true`
4. **Atlantis configuration** — Generates `atlantis.yaml` at repository root
5. **Documentation updates** — Updates all references from pipeline to Atlantis

## Architecture Context

> For background on Atlantis and Terraform workflows:
> - [Terraform Workflows via Atlantis](https://github.com/boatsgroup/mobius-docs/blob/main/docs/platform-runbooks/terraform-workflow.mdx) — How Atlantis automates Terraform changes
> - [Atlantis Authorization](https://github.com/boatsgroup/mobius-docs/blob/main/docs/platform-runbooks/atlantis-authorization.mdx) — CODEOWNERS and access control
> - [Atlantis UI Access](https://github.com/boatsgroup/mobius-docs/blob/main/docs/platform-runbooks/atlantis-ui.mdx) — Accessing the Atlantis web interface

---

## Canonical Rules

- No file modification before detection phase completes.
- No completion claim before all phases verify successfully.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before starting.
- JIRA ticket is prompted before intake questions — strongly encouraged but skippable.
- No file generation on `main` — a feature branch MUST exist before Phase 1.
- Only the `module "pipeline"` block is removed — do NOT delete entire files unless they contain nothing else.
- Pipeline module can appear in `pipeline.tf` OR `resources.tf` — check both locations.
- Work is not complete until a PR exists with all changes.

---

## Q0 Gate (MANDATORY)

> **STOP: Answer these questions FIRST before ANY file modification.**

```
Q0: What is the path to the Terraform repository?
    (Default: current directory if already in a terraform repo)

Q1: Which optional environments should be included in Atlantis?
    (Comma-separated list, or 'all' to include everything, or 'none' for required only)
    
    Typically OPTIONAL (not managed via Atlantis):
      - bg-dev, bg-stage, dp-dev, dp-test (development/test environments)
    
    Typically REQUIRED (always included):
      - bg-main, bg-qa, bg-prod, bg-prod-ls
      - ops-qa, ops-prod
      - dp-prod, dp-sharedservices
      - corp-it, trident, yc-prod
      - (production and production-like environments)
    
    Default: none (only include required environments)
```

**Rules:**
- Repository must contain Terraform code (`.tf` files)
- Repository must currently use the `pipeline-terraform` module
- Repository path must exist and be accessible
- Repository must NOT use Terragrunt (temporary limitation - will be removed when Atlantis supports it)

**Ask the user:**
> "What is the path to the Terraform repository you want to convert?
> (Press Enter to use current directory if already in a terraform repo)
>
> Which optional environments should be included in Atlantis?
> Enter a comma-separated list (e.g., 'bg-dev,bg-stage'), 'all' for everything, or 'none' (default).
>
> Typically optional: bg-dev, bg-stage, dp-dev, dp-test
> Typically required: bg-main, bg-qa, bg-prod, bg-prod-ls, ops-qa, ops-prod, dp-prod, dp-sharedservices, corp-it, trident, yc-prod"

---

## Git and JIRA Preflight (before file modifications)

Before making any changes, verify git prerequisites and prompt for JIRA.

### Step 0a: Git Prerequisites

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks

Verify for the target repository:

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree is clean: `git status --porcelain` returns empty. If dirty, hard-stop — user must resolve manually.
3. Check current branch:
   - If on `main`: pull latest (`git pull origin main`), then create feature branch.
   - **If NOT on `main`**: Ask the user before doing anything:
     ```
     You're currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
        (recommended if you created it for this work)
     2. **Switch to main and create new branch** — start fresh from main
     ```
     If user chooses "use this branch", skip branch creation.

### Step 0b: JIRA Ticket Prompt (REQUIRED)

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

JIRA ticket is **required** for infrastructure changes:

```
Before we begin, please provide the Jira ticket ID for this migration:

Enter ticket ID (e.g., DEVOPS-6702):
```

If the user doesn't have a ticket, prompt them to create one first:

```
Infrastructure migrations require a JIRA ticket for tracking.
Please create a ticket in JIRA and come back with the ticket ID.
```

Store as `jira_ticket_id` (e.g., `DEVOPS-6702`). This value flows into:
- Branch name
- Commit message footer
- PR title and body

### Step 0c: Branch Creation

Branch name pattern (JIRA ticket is required):
- `feat/<jira_ticket_id>-migrate-to-atlantis` (e.g., `feat/DEVOPS-6702-migrate-to-atlantis`)

```bash
git checkout -b <branch-name>
git branch --show-current   # Verify
```

If a branch with that name already exists, ask: `(a) switch to existing branch` or `(b) choose a different name`.

---

## Phase 0: Detection & Validation

**Purpose:** Understand the repository structure and validate conversion eligibility.

### Detection Steps

1. **Check for Terragrunt (TEMPORARY BLOCKER - remove when Atlantis supports Terragrunt):**
   ```bash
   # Check for Terragrunt - our Atlantis installation doesn't currently support it
   # TODO: Remove this check once Atlantis is configured for Terragrunt workflows
   if find . -name "terragrunt.hcl" -o -name ".terragrunt-cache" | grep -q .; then
     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     echo "❌ Cannot migrate: Repository uses Terragrunt"
     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     echo ""
     echo "This repository uses Terragrunt, which is not currently"
     echo "supported by our Atlantis installation. Terragrunt support"
     echo "is on the roadmap."
     echo ""
     echo "Exiting without making changes."
     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     exit 1
   fi
   ```

2. **Locate Terraform root directory:**
   ```bash
   # Check if there's an iac/ subdirectory (default workflow pattern)
   if [ -d "iac" ]; then
     TERRAFORM_ROOT="iac"
   else
     TERRAFORM_ROOT="."
   fi
   ```

2. **Detect workflow type:**
   ```bash
   # Check for Makefile and symlinks (terraform_legacy pattern)
   if [ -f "${TERRAFORM_ROOT}/Makefile" ] && \
      find "${TERRAFORM_ROOT}/environments" -type l -name "*.tf" | grep -q .; then
     WORKFLOW_TYPE="terraform_legacy"
   else
     WORKFLOW_TYPE="default"
   fi
   ```

3. **Verify pipeline module exists:**
   ```bash
   # Search for module "pipeline" in shared directory
   if grep -r 'module\s*"pipeline"' "${TERRAFORM_ROOT}/shared/"*.tf 2>/dev/null; then
     PIPELINE_EXISTS=true
   else
     echo "ERROR: No pipeline module found. Is this repo already migrated?"
     exit 1
   fi
   ```

4. **Discover environments:**
   ```bash
   # List all environment directories
   ENVS=$(ls -1 "${TERRAFORM_ROOT}/environments/")
   
   # Known AWS profiles/environments (from iac-eks-atlantis):
   # bg-main, bg-dev, bg-qa, bg-stage, bg-prod, bg-prod-ls
   # ops-qa, ops-prod
   # dp-dev, dp-test, dp-prod, dp-sharedservices
   # corp-it, trident, yc-prod
   # Store which ones exist for later atlantis.yaml generation
   ```

5. **Check current Terraform version:**
   ```bash
   # Read from shared/common.tf
   CURRENT_TF_VERSION=$(grep 'required_version' "${TERRAFORM_ROOT}/shared/common.tf" | \
                        grep -oP '~>\s*\K[0-9.]+')
   
   # Read AWS provider version
   CURRENT_AWS_VERSION=$(grep -A3 'provider "aws"' "${TERRAFORM_ROOT}/shared/common.tf" | \
                         grep 'version' | grep -oP '~>\s*\K[0-9.]+')
   ```

### Validation Checks

Report findings to the user:

```
✅ Detection Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Repository:          <repo-name>
Terraform Root:      <TERRAFORM_ROOT>
Workflow Type:       <WORKFLOW_TYPE>
Pipeline Module:     Found in <file-path>

Current Versions:
  Terraform:         <CURRENT_TF_VERSION>
  AWS Provider:      <CURRENT_AWS_VERSION>

Environments Found:  <list of environments>

Will Upgrade To:
  Terraform:         ~> 1.14.0
  AWS Provider:      >= 5.0, < 7.0

Atlantis Environments (based on your choices):
  <list of environments that will be in atlantis.yaml>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Proceed with conversion? (yes/no)
```

Only proceed after user confirms.

---

## Phase 1: Terraform & Provider Upgrade

**Purpose:** Modernize Terraform and AWS provider versions, update backend configuration.

### Step 1.1: Update shared/common.tf

Edit `${TERRAFORM_ROOT}/shared/common.tf`:

**Find:**
```hcl
terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
```

**Replace with:**
```hcl
terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
```

### Step 1.2: Update backend.tf in ALL environments

For each environment directory under `${TERRAFORM_ROOT}/environments/`:

Edit `backend.tf`:

**Find:**
```hcl
    dynamodb_table = "TerraformState"
```

**Replace with:**
```hcl
    use_lockfile = true
```

**Important:** This change must be made in **all** environment directories (bg-dev, bg-qa, bg-stage, bg-prod, and any others found).

### Verification

```bash
# Verify Terraform version was updated
grep 'required_version.*1.14' "${TERRAFORM_ROOT}/shared/common.tf"

# Verify AWS provider version was updated
grep 'version.*>= 5.0, < 7.0' "${TERRAFORM_ROOT}/shared/common.tf"

# Verify all backend.tf files were updated
for env in ${TERRAFORM_ROOT}/environments/*/; do
  if ! grep -q 'use_lockfile = true' "${env}/backend.tf"; then
    echo "ERROR: ${env}/backend.tf not updated"
  fi
done
```

---

## Phase 2: Remove Pipeline Module

**Purpose:** Remove the `module "pipeline"` declaration from Terraform code.

### Step 2.1: Locate Pipeline Module

The pipeline module can appear in two locations:
1. **Dedicated file:** `${TERRAFORM_ROOT}/shared/pipeline.tf`
2. **Embedded in:** `${TERRAFORM_ROOT}/shared/resources.tf`

```bash
# Check both locations
if [ -f "${TERRAFORM_ROOT}/shared/pipeline.tf" ]; then
  PIPELINE_FILE="pipeline.tf"
elif grep -q 'module.*"pipeline"' "${TERRAFORM_ROOT}/shared/resources.tf" 2>/dev/null; then
  PIPELINE_FILE="resources.tf"
else
  echo "WARNING: Pipeline module not found in expected locations"
fi
```

### Step 2.2: Remove Module Block

**If in pipeline.tf (dedicated file):**
- Delete the entire `${TERRAFORM_ROOT}/shared/pipeline.tf` file
- Remove symlinks from environment directories:
  ```bash
  find "${TERRAFORM_ROOT}/environments" -type l -name "pipeline.tf" -delete
  ```

**If in resources.tf (embedded):**
- Remove ONLY the module block, not the entire file
- Find and delete this block:
  ```hcl
  module "pipeline" {
    source  = "boatsgroup.pe.jfrog.io/TF__BG/pipeline-terraform/aws"
    version = "~> 3.0"
    
    # ... all module configuration ...
  }
  ```
- Also remove any `data "aws_subnets" "pipeline"` blocks that reference the pipeline

### Verification

```bash
# Ensure no pipeline module references remain
if grep -r 'module.*"pipeline"' "${TERRAFORM_ROOT}/shared/"*.tf; then
  echo "ERROR: Pipeline module still found"
  exit 1
fi

# Ensure no pipeline.tf symlinks remain
if find "${TERRAFORM_ROOT}/environments" -type l -name "pipeline.tf" | grep -q .; then
  echo "ERROR: pipeline.tf symlinks still exist"
  exit 1
fi
```

---

## Phase 3: Generate atlantis.yaml

**Purpose:** Create Atlantis configuration for automated Terraform workflows.

### Step 3.1: Determine Project List

Based on user choices in Q0 Gate and discovered environments:

```bash
# Define which environments are typically required vs optional
REQUIRED_ENVS=("bg-main" "bg-qa" "bg-prod" "bg-prod-ls" "ops-qa" "ops-prod" "dp-prod" "dp-sharedservices" "corp-it" "trident" "yc-prod")
OPTIONAL_ENVS=("bg-dev" "bg-stage" "dp-dev" "dp-test")

# Start with environments that exist in the repo
ALL_DISCOVERED_ENVS=($(ls -1 "${TERRAFORM_ROOT}/environments/"))

# Filter to required environments that actually exist
ATLANTIS_ENVS=()
for env in "${ALL_DISCOVERED_ENVS[@]}"; do
  if [[ " ${REQUIRED_ENVS[@]} " =~ " ${env} " ]]; then
    ATLANTIS_ENVS+=("$env")
  fi
done

# Add optional environments based on user choice
if [ "$OPTIONAL_ENVS_CHOICE" = "all" ]; then
  # Include all discovered environments
  ATLANTIS_ENVS=("${ALL_DISCOVERED_ENVS[@]}")
elif [ "$OPTIONAL_ENVS_CHOICE" != "none" ]; then
  # Parse comma-separated list (e.g., "bg-dev,bg-stage")
  IFS=',' read -ra REQUESTED_OPTIONAL <<< "$OPTIONAL_ENVS_CHOICE"
  for env in "${REQUESTED_OPTIONAL[@]}"; do
    env=$(echo "$env" | xargs) # trim whitespace
    if [[ " ${ALL_DISCOVERED_ENVS[@]} " =~ " ${env} " ]]; then
      ATLANTIS_ENVS+=("$env")
    fi
  done
fi

# Sort environments for consistent execution order
# Typical order: dev environments first, then qa/test, then prod
IFS=$'\n' ATLANTIS_ENVS=($(sort <<<"${ATLANTIS_ENVS[*]}"))
unset IFS
```

### Step 3.2: Generate atlantis.yaml Template

Create `atlantis.yaml` at **repository root** (not in TERRAFORM_ROOT):

**For terraform_legacy workflow:**

```yaml
version: 3

abort_on_execution_order_fail: true
projects:
  - &template
    terraform_distribution: terraform
    workflow: terraform_legacy
    name: template
    dir: template
    autoplan:
      enabled: true
      when_modified:
        - "../../shared/*.tf"
        - "../../shared/templates/*"
        - "*.tf"
        - "*.tfvars"
```

**For default workflow:**

```yaml
version: 3

abort_on_execution_order_fail: true
projects:
  - &template
    terraform_distribution: terraform
    workflow: default
    name: template
    dir: template
    autoplan:
      enabled: true
      when_modified:
        - "../../shared/*.tf"
        - "*.tf"
        - "*.tfvars"
```

### Step 3.3: Add Environment Projects

For each environment in `ATLANTIS_ENVS`, append with appropriate settings:

**For QA/Test environments (group 1):**
```yaml
  - <<: *template
    name: <env-name>
    dir: ./<TERRAFORM_ROOT>/environments/<env-name>
    autoplan:
      enabled: true
    execution_order_group: 1
    apply_requirements:
      - undiverged
```

**For Production environments (group 2):**
```yaml
  - <<: *template
    name: <env-name>
    dir: ./<TERRAFORM_ROOT>/environments/<env-name>
    autoplan:
      enabled: true
    execution_order_group: 2
```

**For Optional/Dev environments (group 99):**
```yaml
  - <<: *template
    name: <env-name>
    dir: ./<TERRAFORM_ROOT>/environments/<env-name>
    autoplan:
      enabled: false
    execution_order_group: 99
    apply_requirements:
      - undiverged
```

Execution order groups (assign based on environment type):
- QA/Test environments: 1 (bg-qa, ops-qa) — **requires `apply_requirements: [undiverged]`**
- Production environments: 2 (bg-main, bg-prod, bg-prod-ls, ops-prod, dp-prod, dp-sharedservices, corp-it, trident, yc-prod) — no additional requirements
- Optional/Dev environments: 99 (bg-dev, bg-stage, dp-dev, dp-test) — **`autoplan: enabled: false`, requires `apply_requirements: [undiverged]`**

**Why group 99 for optional environments?**
- Optional environments have `autoplan: enabled: false`, so they **don't run automatically at all**
- They must be manually triggered with `atlantis plan -p <env>` and `atlantis apply -p <env>`
- The `execution_order_group: 99` is essentially irrelevant for manual operations (execution order only applies to global `atlantis apply` commands)
- However, if someone does run a global `atlantis apply`, group 99 ensures optional environments run last and their failures don't block QA/Production
- Atlantis projects default to group `0`, which would run first and block everything with `abort_on_execution_order_fail: true`

```bash
# Function to determine execution order group
get_execution_order() {
  local env=$1
  case "$env" in
    bg-qa|ops-qa)
      echo 1 ;;
    bg-main|bg-prod|bg-prod-ls|ops-prod|dp-prod|dp-sharedservices|corp-it|trident|yc-prod)
      echo 2 ;;
    bg-dev|bg-stage|dp-dev|dp-test)
      echo 99 ;; # Optional environments run last
    *)
      # Unknown environment - default to group 1 (with qa/test)
      echo 1 ;;
  esac
}

# Function to check if environment needs apply_requirements
needs_apply_requirements() {
  local env=$1
  case "$env" in
    # Group 1 (qa/test) and Group 99 (optional/dev) require undiverged
    bg-qa|ops-qa|bg-dev|bg-stage|dp-dev|dp-test)
      return 0 ;; # true - needs apply_requirements
    *)
      return 1 ;; # false - no apply_requirements (production environments)
  esac
}

# Function to check if environment should disable autoplan
disable_autoplan() {
  local env=$1
  case "$env" in
    # Optional environments don't autoplan (must be manually triggered)
    bg-dev|bg-stage|dp-dev|dp-test)
      return 0 ;; # true - disable autoplan
    *)
      return 1 ;; # false - enable autoplan
  esac
}
```

**Note:** Adjust `dir:` path based on whether TERRAFORM_ROOT is "." or "iac"
- If TERRAFORM_ROOT is ".": `dir: ./environments/<env-name>`
- If TERRAFORM_ROOT is "iac": `dir: ./iac/environments/<env-name>`

### Example Complete atlantis.yaml (terraform_legacy with qa, prod, and optional dev):

```yaml
version: 3

abort_on_execution_order_fail: true
projects:
  - &template
    terraform_distribution: terraform
    workflow: terraform_legacy
    name: template
    dir: template
    autoplan:
      when_modified:
        - "../../shared/*.tf"
        - "../../shared/templates/*"
        - "*.tf"
        - "*.tfvars"
  - <<: *template
    name: bg-qa
    dir: ./environments/bg-qa
    autoplan:
      enabled: true
    execution_order_group: 1
    apply_requirements:
      - undiverged
  - <<: *template
    name: bg-prod
    dir: ./environments/bg-prod
    autoplan:
      enabled: true
    execution_order_group: 2
  - <<: *template
    name: bg-dev
    dir: ./environments/bg-dev
    autoplan:
      enabled: false
    execution_order_group: 99
    apply_requirements:
      - undiverged
```

**Execution order with this configuration:**

**Automatic behavior (when files change in a PR):**
1. bg-qa auto-plans (group 1)
2. bg-prod auto-plans (group 2)
3. bg-dev does NOT auto-plan (`autoplan: enabled: false`)

**Manual apply order (if running global `atlantis apply`):**
1. Group 1 (bg-qa) applies first
2. If bg-qa fails → bg-prod is blocked, process stops
3. If bg-qa succeeds → Group 2 (bg-prod) applies
4. If bg-prod fails → bg-dev is blocked, process stops
5. If bg-prod succeeds → Group 99 (bg-dev) applies (but only if someone ran a manual plan first)

**Typical workflow for optional environments:**
- Dev environments require manual interaction: `atlantis plan -p bg-dev`, then `atlantis apply -p bg-dev`
- These manual commands ignore execution order groups entirely
- The group 99 assignment only matters for the rare case of a global `atlantis apply`

### Verification

```bash
# Verify atlantis.yaml exists at repo root
[ -f "atlantis.yaml" ] || { echo "ERROR: atlantis.yaml not created"; exit 1; }

# Verify it has correct number of projects
PROJECT_COUNT=$(grep -c '^  - <<: \*template' atlantis.yaml)
EXPECTED_COUNT=${#ATLANTIS_ENVS[@]}
[ "$PROJECT_COUNT" -eq "$EXPECTED_COUNT" ] || \
  { echo "ERROR: Expected $EXPECTED_COUNT projects, found $PROJECT_COUNT"; exit 1; }
```

---

## Phase 4: Update Documentation

**Purpose:** Update all documentation references from pipeline to Atlantis.

### Step 4.1: Locate Documentation Files

Common documentation files to update:
```bash
DOC_FILES=(
  "README.md"
  "docs/architecture.md"
  "docs/workflow.md"
  "docs/dependencies.md"
  "docs/iac-overview.md"
)
```

### Step 4.2: Update README.md

Look for sections mentioning:
- Terraform version requirements
- Pipeline module references
- CI/CD workflow descriptions

**Example changes:**
- `Terraform = 1.6.0` → `Terraform = 1.14.0`
- References to `pipeline-terraform` module → Atlantis workflow
- CodePipeline/CodeBuild mentions → Atlantis PR comments

### Step 4.3: Update docs/architecture.md

**Find and update:**
- Version table with Terraform and AWS provider versions
- Module catalog table (remove `pipeline-terraform` module row)
- List of symlinked files (remove `pipeline.tf` if present)

### Step 4.4: Update docs/workflow.md

**Find and update:**
- Terraform version in prerequisites section
- Deployment workflow description:
  - Remove CodePipeline/CodeBuild references
  - Add Atlantis workflow description
- May need to add new "Atlantis Commands" section

### Step 4.5: Update docs/dependencies.md

**Find and update:**
- AWS Services section:
  - Remove `CodePipeline / CodeBuild` row
  - Add `Atlantis` row with reference to `atlantis.yaml`

### Step 4.6: Update docs/iac-overview.md

**Find and update:**
- Toolchain version table (Terraform, AWS provider)
- Repository structure diagram (remove `pipeline.tf`, add `atlantis.yaml`)

### Automated Search & Replace Patterns

For each documentation file that exists:

1. **Version updates:**
   - `1.6.0` → `1.14.0`
   - `~> 5.0` → `>= 5.0, < 7.0`

2. **Pipeline removal:**
   - Remove lines mentioning `pipeline-terraform` module
   - Remove lines mentioning `CodePipeline` or `CodeBuild`
   - Remove `pipeline.tf` from file structure lists

3. **Atlantis addition:**
   - Add `atlantis.yaml` to repository structure
   - Update deployment workflow to mention Atlantis PR commands
   - Update CI/CD references to point to Atlantis

### Verification

```bash
# Verify version updates were applied
for file in "${DOC_FILES[@]}"; do
  if [ -f "$file" ]; then
    if grep -q '1.6.0' "$file" || grep -q '~> 5.0' "$file"; then
      echo "WARNING: Old versions still found in $file"
    fi
  fi
done

# Verify no pipeline references remain
if grep -ri 'pipeline-terraform\|CodePipeline\|CodeBuild' docs/ README.md 2>/dev/null; then
  echo "WARNING: Pipeline references still found in documentation"
fi
```

---

## Phase 4.5: Update CODEOWNERS

**Purpose:** Ensure the atlantis.yaml file is protected by CODEOWNERS.

### Step 4.5.1: Check for CODEOWNERS file

```bash
# Check standard locations
if [ -f ".github/CODEOWNERS" ]; then
  CODEOWNERS_FILE=".github/CODEOWNERS"
elif [ -f "CODEOWNERS" ]; then
  CODEOWNERS_FILE="CODEOWNERS"
elif [ -f "docs/CODEOWNERS" ]; then
  CODEOWNERS_FILE="docs/CODEOWNERS"
else
  CODEOWNERS_FILE=".github/CODEOWNERS" # Create in standard location
  mkdir -p .github
fi
```

### Step 4.5.2: Add atlantis.yaml ownership rule

Check if atlantis.yaml is already covered by an existing rule (e.g., `*` or `/`):

```bash
# Check if atlantis.yaml already has explicit ownership or is covered by a wildcard
if grep -q '^/atlantis.yaml' "$CODEOWNERS_FILE" 2>/dev/null; then
  echo "atlantis.yaml already has explicit ownership"
elif grep -q '^\*\s\+@' "$CODEOWNERS_FILE" 2>/dev/null || \
     grep -q '^/\s\+@' "$CODEOWNERS_FILE" 2>/dev/null; then
  echo "atlantis.yaml covered by existing wildcard rule"
else
  # Add explicit rule for atlantis.yaml
  echo "/atlantis.yaml        @boatsgroup/devops" >> "$CODEOWNERS_FILE"
  echo "Added atlantis.yaml ownership to $CODEOWNERS_FILE"
fi
```

**Why this matters:**
- The atlantis.yaml file controls Terraform automation for the entire repository
- Only the DevOps team should be able to modify it
- This prevents accidental or unauthorized changes to the Atlantis configuration

### Verification

```bash
# Verify the rule exists
if ! grep -q 'atlantis.yaml.*@boatsgroup/devops' "$CODEOWNERS_FILE"; then
  echo "WARNING: atlantis.yaml may not be properly protected in CODEOWNERS"
fi
```

---

## Phase 5: Commit & PR

**Purpose:** Commit all changes and create a pull request.

### Step 5.1: Detect What Changed

Before committing, detect which changes were actually made:

```bash
# Track what changed
CHANGES=()
COMMIT_DETAILS=()

# Check for new atlantis.yaml
if [ -f "atlantis.yaml" ] && ! git ls-files --error-unmatch atlantis.yaml >/dev/null 2>&1; then
  CHANGES+=("atlantis.yaml")
  COMMIT_DETAILS+=("- Add atlantis.yaml configuration")
fi

# Check for pipeline removal
if git status --porcelain | grep -q "D.*pipeline.tf"; then
  CHANGES+=("pipeline_removed")
  COMMIT_DETAILS+=("- Remove pipeline-terraform module")
fi

# Check for version upgrades in common.tf
if git diff --cached --quiet "${TERRAFORM_ROOT}/shared/common.tf" 2>/dev/null || \
   git diff --quiet "${TERRAFORM_ROOT}/shared/common.tf" 2>/dev/null; then
  : # No changes
else
  CHANGES+=("common.tf")
  if git diff "${TERRAFORM_ROOT}/shared/common.tf" | grep -q "1.14.0"; then
    COMMIT_DETAILS+=("- Upgrade Terraform to ~> 1.14.0")
  fi
  if git diff "${TERRAFORM_ROOT}/shared/common.tf" | grep -q ">= 5.0, < 7.0"; then
    COMMIT_DETAILS+=("- Upgrade AWS provider to >= 5.0, < 7.0")
  fi
fi

# Check for backend.tf changes
if git status --porcelain | grep -q "backend.tf"; then
  CHANGES+=("backend.tf")
  COMMIT_DETAILS+=("- Replace dynamodb_table with use_lockfile in backends")
fi

# Check for documentation changes
if git status --porcelain | grep -qE "README.md|docs/"; then
  CHANGES+=("documentation")
  COMMIT_DETAILS+=("- Update documentation to reference Atlantis workflow")
fi

# Check for CODEOWNERS changes
if git status --porcelain | grep -q "CODEOWNERS"; then
  CHANGES+=("CODEOWNERS")
  COMMIT_DETAILS+=("- Protect atlantis.yaml in CODEOWNERS")
fi
```

### Step 5.2: Review Changes

Show the user what changed:

```bash
echo "═══════════════════════════════════════════════════"
echo "Changes detected:"
echo "═══════════════════════════════════════════════════"
git status --short
echo ""
echo "Summary of changes:"
for detail in "${COMMIT_DETAILS[@]}"; do
  echo "$detail"
done
echo "═══════════════════════════════════════════════════"
```

**Ask the user for confirmation before committing:**
> "Review the changes above. Proceed with commit? (yes/no)"

If no changes detected:
> "No changes detected. The repository may already be configured for Atlantis or the conversion had no effect. Exiting."

### Step 5.3: Stage and Commit Changes

Only stage files that actually changed:

```bash
# Stage all modified and new files (but not untracked files outside our scope)
git add -u  # Stage modified and deleted files
git add atlantis.yaml 2>/dev/null || true  # Add new atlantis.yaml if it exists

# Add CODEOWNERS if it was modified or created
if [ -n "$CODEOWNERS_FILE" ] && [ -f "$CODEOWNERS_FILE" ]; then
  git add "$CODEOWNERS_FILE" 2>/dev/null || true
fi

# Build commit message dynamically based on what changed
COMMIT_MSG="feat: migrate from pipeline CI/CD to Atlantis"
if [ ${#COMMIT_DETAILS[@]} -gt 0 ]; then
  COMMIT_MSG="$COMMIT_MSG

${COMMIT_DETAILS[0]}"
  for ((i=1; i<${#COMMIT_DETAILS[@]}; i++)); do
    COMMIT_MSG="$COMMIT_MSG
${COMMIT_DETAILS[$i]}"
  done
fi

# Add footer
COMMIT_MSG="$COMMIT_MSG

Generated using /mobius:migrate-pipeline-to-atlantis
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
$jira_ticket_id"

# Commit
git commit -m "$COMMIT_MSG"
```

### Step 5.4: Push and Create PR

Build PR body dynamically based on what actually changed:

```bash
# Build PR body with only the changes that were made
PR_BODY="## Summary

Migrates this repository from the legacy \`pipeline-terraform\` module to Atlantis-based GitOps workflow.

## Changes
"

# Add each change as a checkbox
for detail in "${COMMIT_DETAILS[@]}"; do
  # Convert "- Add foo" to "- ✅ Added foo"
  detail_past_tense=$(echo "$detail" | sed -e 's/^- Add /- ✅ Added /' \
                                            -e 's/^- Remove /- ✅ Removed /' \
                                            -e 's/^- Upgrade /- ✅ Upgraded /' \
                                            -e 's/^- Replace /- ✅ Replaced /' \
                                            -e 's/^- Update /- ✅ Updated /' \
                                            -e 's/^- Protect /- ✅ Protected /')
  PR_BODY="$PR_BODY
$detail_past_tense"
done

PR_BODY="$PR_BODY

## Atlantis Configuration

This PR includes Atlantis configuration for the following environments:
$(for env in "${ATLANTIS_ENVS[@]}"; do echo "- $env"; done)

## Test Plan

**In this PR (before merging):**
- [ ] Verify Atlantis discovers the new configuration (it reads \`atlantis.yaml\` from the PR branch)
- [ ] Push a trivial change to this PR (e.g., add a comment to a .tf file)
- [ ] Verify Atlantis auto-plans the change for required environments
- [ ] Verify Atlantis does NOT auto-plan for optional environments (if any are included)
- [ ] Comment \`atlantis plan\` to test manual planning
- [ ] Verify plan output is correct
- [ ] Comment \`atlantis plan -p <optional-env>\` to test manual planning for optional environments
- [ ] If authorized via CODEOWNERS: Comment \`atlantis apply -p bg-qa\` to test apply
- [ ] Verify apply works correctly

**After merge (if needed):**
- [ ] Verify Atlantis continues to work on subsequent PRs
- [ ] Test execution order by making changes that affect multiple environments

## Testing in this PR

Before merging, you can test the Atlantis configuration directly in this PR:
1. Atlantis reads \`atlantis.yaml\` from the **PR branch**, not from \`main\`
2. Make a trivial change (add a comment to any .tf file) and push to this branch
3. Atlantis will auto-plan based on the new configuration
4. Test manual commands: \`atlantis plan -p <env>\`, \`atlantis apply -p <env>\`
5. Verify everything works before merging

## Post-Merge

After merging:
1. Run \`terraform init\` in each environment directory to regenerate lock files
2. Review [Atlantis documentation](https://mobius.bgrp.io/platform-runbooks/terraform-workflow) for workflow details

## References

- [Terraform Workflows via Atlantis](https://mobius.bgrp.io/platform-runbooks/terraform-workflow)
- [Atlantis Authorization](https://mobius.bgrp.io/platform-runbooks/atlantis-authorization)

---

🤖 Generated using \`/mobius:migrate-pipeline-to-atlantis\` with [Claude Code](https://claude.com/claude-code)"

# Push and create PR
git push -u origin $(git branch --show-current)

gh pr create --title "$jira_ticket_id: Migrate to Atlantis CI/CD" --body "$PR_BODY"
```

**Note:** PR is created as ready for review, which triggers Atlantis autoplan immediately.

---

## Post-Execution Checklist

After the PR is created, remind the user:

```
✅ Conversion Complete!

Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Review the PR: <PR-URL>

2. Test Atlantis in the PR (BEFORE merging):
   - Atlantis reads atlantis.yaml from the PR branch
   - Push a trivial change (add a comment to a .tf file)
   - Verify Atlantis auto-plans for required environments
   - Test manual commands: 'atlantis plan -p <env>'
   - Verify configuration works correctly

3. After merge, run in each environment directory:
   cd ${TERRAFORM_ROOT}/environments/<env>
   terraform init -upgrade

   This will:
   - Update provider lock files (.terraform.lock.hcl)
   - Initialize the new backend locking mechanism
   - Download the latest provider versions

3. Reference docs:
   - Atlantis workflow: https://mobius.bgrp.io/platform-runbooks/terraform-workflow
   - Authorization: https://mobius.bgrp.io/platform-runbooks/atlantis-authorization

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Anti-Patterns to Avoid

| Pattern | Why Forbidden |
|---------|---------------|
| Deleting resources.tf when removing pipeline | File may contain other resources; only remove the module block |
| Forgetting to update all backend.tf files | Every environment needs `use_lockfile = true` |
| Including bg-dev in Atlantis by default | Dev environments typically aren't managed via Atlantis |
| Forgetting to remove pipeline.tf symlinks | Atlantis will error on broken symlinks |
| Wrong atlantis.yaml path | Must be at repository root, not in iac/ or shared/ |
| Missing when_modified patterns | Atlantis won't auto-plan on shared/ changes |
| Skipping documentation updates | Leaves confusing references to removed pipeline |
| Committing on main branch | All changes must go through PR workflow |
| Missing execution_order_group | Environments might apply in wrong order |
| Attempting to migrate Terragrunt repo | Tool will detect and refuse (temporary - remove check when Atlantis supports Terragrunt) |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: transformative

**Context hints**:
- "Impact opener" → state which repository was migrated from pipeline to Atlantis
- "What was accomplished" → describe the CI/CD migration, version upgrades, and configuration changes
- "Why it matters" → Atlantis provides GitOps-native Terraform workflow with PR-based reviews and CODEOWNERS authorization
- "What happens next" → explain post-merge terraform init steps, CODEOWNERS setup, and workflow testing

**Key points to include:**
- Pipeline module removal simplifies infrastructure
- Version upgrades bring latest features and fixes
- Atlantis enables GitOps workflow with better visibility
- CODEOWNERS provides fine-grained access control
- Lock file improvements (use_lockfile vs DynamoDB)
