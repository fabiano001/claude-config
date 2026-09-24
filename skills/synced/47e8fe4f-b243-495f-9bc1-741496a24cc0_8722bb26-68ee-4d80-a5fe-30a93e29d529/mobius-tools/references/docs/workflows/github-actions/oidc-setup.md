# GitHub Actions OIDC Role Setup

## What It Does

Provisions AWS credentials for a GitHub Actions workflow without storing
any long-lived secrets. Instead of a static IAM access key, GitHub's OIDC
provider issues a short-lived identity token per workflow run, which AWS
exchanges for temporary credentials via `AssumeRoleWithWebIdentity`.

```
GitHub Actions workflow run
        |
        v
GitHub OIDC token (short-lived, per-run)
        |
        v
AWS STS AssumeRoleWithWebIdentity
        |
        v
Temporary AWS credentials, scoped to this role's policy
```

This is provisioned via the `XGitHubOIDCRole` Crossplane claim. Despite
earlier documentation marking this claim "not yet production-ready," it is
confirmed live and working in production for at least one repo as of this
writing — treat it as the real, working pattern, not an experimental one.

## Inputs

| Field | Required | What it controls |
|---|---|---|
| `githubOrg` / `githubRepo` | Yes | Which repo's workflows can assume this role |
| `githubRef` | No, but strongly recommended | Restricts the role to a specific branch (e.g. `refs/heads/main`) — without it, any branch or PR in the repo can assume the role |
| `githubEnvironment` | No | Restricts to a specific GitHub Environment (useful for prod deploys requiring manual approval) |
| `awsAccountId` / `awsRegion` | Yes | Target AWS account and region |
| `createOidcProvider` | Yes | `false` if the GitHub OIDC provider already exists in this AWS account (it only needs to exist once per account) — `true` only the first time it's set up |
| `roleName` / `policyName` | Yes | Names for the created IAM role and policy |
| `policyDocument` | Yes | The actual permissions this role grants — scope tightly to specific resource ARNs, not `*` |

## Outputs

| Field | Where it shows up | Use for |
|---|---|---|
| `status.roleArn` | Claim status, after it's `Ready` | Reference/verification — see note below on how the role is actually referenced in practice |
| `status.policyArn` | Claim status | Reference if attaching additional policies later |

## Usage Example

### 1. The claim (goes in the app repo's ArgoCD overlay)

```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XGitHubOIDCRole
metadata:
  name: <repo-name>-gha
spec:
  githubOrg: boatsgroup
  githubRepo: <repo-name>
  githubRef: refs/heads/main   # restrict to main — don't omit this
  awsAccountId: "<account-id>"
  awsRegion: us-east-1
  createOidcProvider: false    # false unless this is the first role ever created in this account
  roleName: github-actions-<repo-name>
  policyName: github-actions-<repo-name>-policy
  policyDocument:
    Version: "2012-10-17"
    Statement:
      - Effect: Allow
        Action:
          - <only the specific actions this workflow needs>
        Resource:
          - <specific resource ARN, not "*">
  customTags:
    Team: devops
    Purpose: github-actions
```

### 2. The workflow step (uses the role once the claim is `Ready`)

```yaml
name: <workflow-name>

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:

jobs:
  run:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required — without this, OIDC auth fails
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Setup AWS Credentials
        uses: boatsgroup/github-actions-aws/setup-aws-credentials@v1
        with:
          aws-environment: <environment>
          role-name: ${{ secrets.AWS_PIPELINE_ROLE_NAME }}

      # ...rest of the job
```

This is the confirmed, real pattern — both production workflows in this
project use `boatsgroup/github-actions-aws/setup-aws-credentials@v1`, not
the generic `aws-actions/configure-aws-credentials` action shown in the
platform's OIDC docs page. Use this action and this input style.

**Important — how `role-name` actually works:** this is not a free-form
label. Internally, the wrapper action builds the IAM role ARN directly as:

```
arn:aws:iam::<account-id-for-this-environment>:role/<role-name>
```

**The value in the role-name secret must exactly match `spec.roleName`
from the `XGitHubOIDCRole` claim** (following the pattern
`github-actions-<repo-name>`). A mismatched value constructs a
valid-looking but wrong or nonexistent ARN, and the workflow fails at the
assume-role step with no obvious indication of what's wrong — this is a
real bug this project hit and had to debug. `AWS_PIPELINE_ROLE_NAME` itself
is just the secret name this project chose to use; it isn't required by
the action itself, but the *value* stored in it must match the real IAM
role name precisely.

## One Role Per Repo, Not Per Workflow

The real deployed example bundles ECR permissions (image push/pull) and S3
permissions (collector writes) into a single role for the whole repo, rather
than a separate role per individual workflow. Follow this pattern unless a
specific workflow needs meaningfully different trust scoping (e.g. a
production-deploy workflow that should require a GitHub Environment
approval gate the others don't).

## Checklist Before Shipping

- [ ] `githubRef` is set — don't leave it unset unless every branch/PR in
      the repo genuinely needs to assume this role
- [ ] `createOidcProvider` is `false` unless this is confirmed to be the
      first OIDC role ever created in this AWS account
- [ ] `policyDocument` actions and resources are scoped to exactly what
      this repo's workflows need — no `Resource: "*"` unless the action
      itself has no ARN-scoping option (e.g. `ecr:GetAuthorizationToken`)
- [ ] `permissions: id-token: write` is present in every workflow job that
      needs to assume the role — a missing permission block is a common,
      easy-to-miss cause of OIDC auth failures
- [ ] The repo secret holding the role name (e.g. `AWS_PIPELINE_ROLE_NAME`)
      is set to the exact value of `spec.roleName` in the claim — verify
      this directly rather than assuming it's correct, since a mismatch
      fails silently with a generic assume-role error
