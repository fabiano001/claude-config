# Workflow: Migrate an ECS Service to EKS

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order; each step has a verification
> command so you can confirm success before proceeding. Do not skip the human
> approval gate in Step 4 — it is mandatory before any artifact generation.

---

## Purpose

Migrates a single ECS service (running on `node10` or `node-indexers`) to EKS
using the Mobius GitOps platform. The workflow is divided into two phases:

1. **Discover** — extract and classify the ECS service configuration
2. **Generate** — produce Helm + ArgoCD artifacts ready for review and deployment

A mandatory human approval gate separates the two phases. No EKS files are
generated until an engineer has reviewed the extracted configuration and
explicitly approved it.

**When to use this workflow**:
- Migrating an application currently running as an ECS service
- Service lives in `node10` or `node-indexers` cluster in `bg-qa` or `bg-prod`
- Target platform is EKS with ArgoCD GitOps (Helm charts via `helm-charts/` repo)

**Related documents**:
- [`docs/workflows/migration/ecs-eks-mapping.md`](./ecs-eks-mapping.md) — field-by-field mapping reference
- [`docs/workflows/migration/ecs-extraction-reference.md`](./ecs-extraction-reference.md) — all AWS CLI extraction commands
- [`docs/workflows/migration/cutover-runbook-template.md`](./cutover-runbook-template.md) — cutover checklist template

---

## Preflight Gate (MANDATORY)

> **STOP — Before running any commands, answer Q0, select intake mode, and
> complete the checklist below. Do not proceed to Step 1 until all items are
> checked.**

### Q0: Is the ECS service active and in scope?

```
Q0: Confirm the ECS service before proceeding.
    - Service status must be ACTIVE (not DRAINING or INACTIVE)
    - Cluster must be `node10` or `node-indexers`
    - Account must be `bg-qa` or `bg-prod`
    - Service must NOT have a `manual-required` blocker already documented
```

Verify:

```bash
aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'services[0].{status:status,desiredCount:desiredCount,taskDef:taskDefinition}' \
  --output table
```

Do not migrate a service with status `INACTIVE`. Confirm with the service owner
before migrating a `DRAINING` service.

### Q1: Intake Mode Selection

After Q0, select the intake mode:

```
Q1: Which intake mode?
    a) deterministic - You provide all values in the intake YAML directly
    b) ai-propose    - AI extracts from AWS and proposes values for your approval
```

- **deterministic**: Engineer fills all intake fields manually from known values.
  Use when you have full knowledge of the service configuration.
- **ai-propose**: The agent runs the discovery commands (Step 2), populates
  the intake YAML, and presents the complete proposal for your review before
  generating any files. Use for unfamiliar services or when automating bulk
  migration discovery.

In `ai-propose` mode the agent sets `proposal_accepted: false` in the intake
file. **The agent must not proceed past Step 4 until the engineer changes this
to `true`.**

### Preflight Checklist

Before proceeding to Step 1, verify ALL of the following are captured:

| # | Item | Value | Status |
|---|------|-------|--------|
| 1 | Intake mode selected | `deterministic` / `ai-propose` | [ ] |
| 2 | ECS cluster confirmed | `node10` / `node-indexers` | [ ] |
| 3 | AWS profile confirmed | `bg-qa` / `bg-prod` | [ ] |
| 4 | Service status is ACTIVE | Verified via `describe-services` | [ ] |
| 5 | Service name (exact, case-sensitive) | `<service-name>` | [ ] |
| 6 | Target EKS namespace confirmed | e.g., `api-node` | [ ] |
| 7 | Target environments captured | `bg-qa`, `bg-prod`, etc. | [ ] |
| 8 | ALB listener rule count known (if applicable) | `<N>` rules or "none" | [ ] |
| 9 | If ai-propose: discovery commands completed | Steps 2a–2f passed | [ ] |
| 10 | If ai-propose: proposal reviewed and accepted | `proposal_accepted: true` | [ ] |
| 11 | `manual-required` blockers resolved or escalated | None outstanding | [ ] |
| 12 | Service family classified (Step 3) | `api-node` / `portal-react` / `webapp-react` / `webapp-node` / `other` | [ ] |

---

## Inputs Required

Before starting, gather:

| Input | Example | Where to find |
|-------|---------|---------------|
| ECS cluster name | `node10` | AWS Console → ECS → Clusters |
| ECS service name | `api-node-ai-provider` | AWS Console → ECS → Services |
| AWS profile | `bg-qa` | `~/.aws/config` |
| AWS region | `us-east-1` | Platform standard |
| Target EKS namespace | `api-node` | Naming convention (cluster group) |
| Target environments | `bg-qa`, `bg-prod` | Platform team |
| Intake YAML path | `/tmp/my-service-intake.yaml` | Copied from template |
| Service family | `api-node` | See Step 3 classification |
| ALB listener rule count | `72` or `0` | AWS Console → EC2 → Load Balancers |

---

## Repositories / Files Touched

| Repo | Files | Purpose |
|------|-------|---------|
| `helm-charts` | `argocd/<service>/base/kustomization.yaml` | Kustomize base |
| `helm-charts` | `argocd/<service>/base/xirsarole.yaml` | Crossplane IRSA claim |
| `helm-charts` | `argocd/<service>/overlays/<env>/config.yaml` | ApplicationSet discovery |
| `helm-charts` | `argocd/<service>/overlays/<env>/values.yaml` | Per-env Helm values |
| `helm-charts` | `argocd/<service>/overlays/<env>/kustomization.yaml` | Per-env Kustomize overlay |
| `iac-eks-argocd` | `applicationsets/<group>/<service>.yaml` | 3-source ApplicationSet |
| `iac-eks-argocd` | `applicationsets/<group>/kustomization.yaml` | Register new ApplicationSet |
| `iac-eks-argocd` | `projects/<project>.yaml` | ArgoCD project permissions |
| `iac-eks-argocd` | `hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml` | Register ApplicationSet group with hub (per target env) |

> **Merge order matters**: `iac-eks-argocd` must be merged **before** `helm-charts`.
> See [Merge Order](#merge-order) section.

---

## Two-Phase Architecture

```
╔══════════════════════════════════════════════════════════════════╗
║  PHASE 1 — DISCOVER                                              ║
║                                                                  ║
║  Steps 1–3: Extract ECS configuration from AWS                  ║
║             Classify service family and compatibility            ║
║             Populate intake YAML (deterministic or ai-propose)  ║
╚══════════════════════════════════════════════════════════════════╝
                           │
                           ▼
╔══════════════════════════════════════════════════════════════════╗
║  ⚠  HUMAN APPROVAL GATE (Step 4)  ⚠                            ║
║                                                                  ║
║  Engineer reviews extracted configuration.                      ║
║  Sets proposal_accepted: true in intake YAML.                   ║
║  Agent waits — no files generated until approval is explicit.   ║
╚══════════════════════════════════════════════════════════════════╝
                           │
                           ▼
╔══════════════════════════════════════════════════════════════════╗
║  PHASE 2 — GENERATE                                              ║
║                                                                  ║
║  Steps 5–7: Generate Helm + ArgoCD artifacts                    ║
║             Run validators and parity checks                    ║
║             Produce cutover runbook                             ║
╚══════════════════════════════════════════════════════════════════╝
```

**Why two phases?** Discovery extracts raw AWS configuration that may contain
`hybrid` fields requiring human judgment (IAM policy scope, unknown sidecars,
step-scaling policies). Separating discovery from generation ensures an engineer
has reviewed every `hybrid` field before it is written to a file.

---

## Step-by-Step Procedure

### Step 1 — Prepare migration intake

Copy the intake template and fill in the service metadata:

```bash
# 1. Copy the intake template
cp docs/workflows/migration/migrate-ecs-intake.yaml /tmp/<service-name>-intake.yaml

# 2. Fill in the service identification fields
#    (at minimum: service_name, cluster, profile, target_namespace, target_environments)

# 3. Validate the intake file structure
npx mobius-validate-intake migration /tmp/<service-name>-intake.yaml
```

The intake file captures:
- Service identity (`service_name`, `cluster`, `profile`)
- Target EKS coordinates (`target_namespace`, `target_environments`)
- Intake mode (`deterministic` or `ai-propose`)
- Proposal status (`proposal_accepted: false` — do NOT set to `true` yet)

In **deterministic** mode, also fill in all discovered field sections manually
before running the validator. In **ai-propose** mode, leave the discovered
sections empty — Step 2 populates them.

---

### Step 2 — Run discovery extraction

Extract the ECS service configuration using the commands in
[`docs/workflows/migration/ecs-extraction-reference.md`](./ecs-extraction-reference.md).
Run all six extraction commands in order:

```bash
# 2a. Authenticate with AWS SSO
aws sso login --profile <PROFILE>

# 2b. List services (enumerate cluster contents)
aws ecs list-services \
  --cluster <CLUSTER> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'serviceArns[*]' \
  --output text

# 2c. Describe the ECS service (replicas, LB, network mode)
aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1

# 2d. Describe the task definition (image, CPU, memory, env vars, secrets, IAM role)
aws ecs describe-task-definition \
  --task-definition <TASK_DEFINITION_ARN> \
  --profile <PROFILE> \
  --region us-east-1

# 2e. Describe target groups + listener rules (ALB health check, routing rules)
TARGET_GROUP_ARN=$(aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'services[0].loadBalancers[0].targetGroupArn' \
  --output text)

aws elbv2 describe-target-groups \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --profile <PROFILE> \
  --region us-east-1

# For ALB listener rule extraction (required when rule count > 0 — see DEVOPS-5598)
ALB_ARN=$(aws elbv2 describe-target-groups \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'TargetGroups[0].LoadBalancerArns[0]' \
  --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --profile <PROFILE> \
  --region us-east-1

aws elbv2 describe-rules \
  --listener-arn <LISTENER_ARN> \
  --profile <PROFILE> \
  --region us-east-1

# 2f. Describe scaling policies (HPA bounds)
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids "service/<CLUSTER>/<SERVICE_NAME>" \
  --profile <PROFILE> \
  --region us-east-1

aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs \
  --resource-id "service/<CLUSTER>/<SERVICE_NAME>" \
  --profile <PROFILE> \
  --region us-east-1

# 2g. List and fetch IAM task role policies
aws iam list-attached-role-policies \
  --role-name ecs/<ROLE_NAME> \
  --profile <PROFILE>

aws iam get-policy-version \
  --policy-arn <POLICY_ARN> \
  --version-id <DEFAULT_VERSION_ID> \
  --profile <PROFILE>
```

**Redaction rules** (apply before writing any extracted value to a file):
- Never log SSM parameter **values** — extract paths only
- Never log Secrets Manager **secret values** — extract ARN/name only
- Replace AWS account IDs with `AWS_ACCOUNT_ID`
- Redact env vars whose names contain `PASSWORD`, `SECRET`, `TOKEN`, `KEY`,
  `CREDENTIAL`, `DSN`, `DATABASE_URL`, `CONN`

Populate the discovered sections of the intake YAML with the extracted output.
Flag every `hybrid` field with a `# REVIEW:` comment explaining the ambiguity.

---

### Step 3 — Classify compatibility and service family

After extraction, classify the service before presenting it for review:

#### Compatibility Classification

| Classification | Criteria | Action |
|----------------|----------|--------|
| `fully-compatible` | No EFS, no App Mesh, no unknown sidecars, no step scaling, no lambda targets, no custom CloudWatch metric scaling | Proceed to Step 4 |
| `supported-with-prompts` | One or more `hybrid` fields: custom sidecars, step scaling, Secrets Manager refs, shared ALB with complex routing | Document each item; proceed to Step 4 with caveats noted |
| `manual-required` | EFS volumes, GPU requirements, App Mesh, multiple unknown sidecars, custom CloudWatch metric scaling | Escalate to platform team; do not proceed until blockers are resolved |

#### Service Family Classification

Map the service to a Helm chart family template in `helm-charts/`:

| Family | Criteria | Template chart |
|--------|----------|----------------|
| `api-node` | Node.js API service in `api-node-*` family | `helm-charts/charts/api-node-template` |
| `portal-react` | Portal frontend in `portal-react-*` family | `helm-charts/charts/portal-react-template` |
| `webapp-react` | React webapp in `webapp-react-*` family | `helm-charts/charts/webapp-react-template` |
| `webapp-node` | Node-based webapp in `webapp-node-*` family | `helm-charts/charts/webapp-node-template` |
| `other` | Does not fit above — requires manual chart selection | Prompt engineer |

Record both classifications in the intake YAML under `compatibility` and
`service_family` fields.

#### DEVOPS-5598: Listener-Rule-Heavy ALB Migrations

Services with a large number of ALB listener rules (such as the BoatTrader
migration tracked in DEVOPS-5598, which involves 72 rules across redirect,
forward, default catch-all, and lambda-target categories) require explicit parity
checks before and after cutover. Before proceeding past Step 3 for any service
with more than 10 ALB listener rules, count and group the rules by category:

```bash
# Count rules by action type (redirect / forward / lambda / default)
aws elbv2 describe-rules \
  --listener-arn <LISTENER_ARN> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'Rules[*].Actions[0].Type' \
  --output text | sort | uniq -c
```

Record the category counts in the intake YAML. The `npx mobius-validate-intake migration-parity`
validator (Step 6) uses these counts to verify that every rule category is
accounted for in the generated HTTPRoute manifests. For listener-rule-heavy
services, the cutover strategy must use weighted DNS rollback (Route53 weighted
routing with ECS weight reversal as the rollback path) rather than a hard
DNS cutover. Target rollback execution time: under 5 minutes. See
[`docs/workflows/migration/ecs-eks-mapping.md`](./ecs-eks-mapping.md) (ALB
Listener Rules / DEVOPS-5598 section) for the full rule-type mapping matrix and
known translation gaps.

##### Automated Listener Rule Translation

For services with >10 ALB listener rules, use the automated translator to generate
Gateway API routing artifacts:

```bash
# Step 1: Fetch listener rules to JSON (or use existing describe-rules output)
aws elbv2 describe-rules \
  --listener-arn <LISTENER_ARN> \
  --profile <PROFILE> \
  --region us-east-1 \
  --output json > /tmp/<service>-describe-rules.json

# Step 2: Run translator in offline mode
python3 scripts/translate-alb-rules-to-gateway.py \
  --intake /tmp/<service>-intake.yaml \
  --rules-json /tmp/<service>-describe-rules.json \
  --output-gateway-yaml /tmp/<service>-gateway.yaml \
  --output-report /tmp/<service>-translation-report.json

# Alternative: Live AWS mode (fetches rules automatically)
python3 scripts/translate-alb-rules-to-gateway.py \
  --intake /tmp/<service>-intake.yaml \
  --output-gateway-yaml /tmp/<service>-gateway.yaml \
  --output-report /tmp/<service>-translation-report.json

# Step 3: Apply translated gateway rules to overlay values.yaml
bash scripts/apply-listener-rule-translation.sh \
  --intake /tmp/<service>-intake.yaml \
  --overlay-values helm-charts/argocd/<service>/overlays/<env>/values.yaml \
  --rules-json /tmp/<service>-describe-rules.json \
  --allow-partial \
  --allow-unsupported
```

`apply-listener-rule-translation.sh` uses scoped mode by default (`--scope-service-rules`),
which keeps only rules relevant to the service target group plus required listener defaults/redirects.
This is critical for shared ALBs to avoid polluting service overlays with unrelated host rules.

**Translator outputs:**
- `gateway.yaml`: Gateway API structure with `gateway.enabled`, `gateway.hostnames`, and `gateway.rules`
- `report.json`: Per-rule translation status with counts and reasons for partial/unsupported rules
- report `summary` includes:
  - `source_total_rules` (before scoping)
  - `total_rules` (after scoping)
  - `scoped_mode` flag

**Translation status categories:**
| Status | Meaning | Action |
|--------|---------|--------|
| `full` | Rule fully translated to Gateway API | Include in generated HTTPRoute |
| `partial` | Rule translated with caveats (wildcards, unknown TGs) | Review reasons, may need manual adjustment |
| `unsupported` | Rule cannot be translated (lambda, fixed-response, auth) | Document as known gap, implement alternative |

Review the report and resolve all `unsupported` rules before proceeding. Use
`--allow-partial` flag only after confirming manual intervention plan for flagged rules.

`apply-listener-rule-translation.sh` is the preferred execution path in generate mode because it:
- runs translation
- enforces fail-closed behavior unless allow flags are set
- replaces top-level `gateway` block in overlay `values.yaml` with translated `gateway.hostnames` + `gateway.rules`

---

### Step 4 — Human review and approval gate

**The agent must stop here and present the following to the engineer:**

1. **Extracted configuration summary** — all fields from the intake YAML in
   human-readable form (not raw YAML dump)
2. **`hybrid` field list** — every field flagged `# REVIEW:` with the specific
   question or concern
3. **Compatibility classification** — `fully-compatible`, `supported-with-prompts`,
   or `manual-required`
4. **Service family** — which template chart will be used
5. **ALB listener rule summary** — category counts if rules > 0
6. **Proposed EKS coordinates** — namespace, target environments, image, resource
   requests/limits, replica count, HPA configuration (if applicable)

The engineer must:
- Confirm or correct every `hybrid` field
- Resolve any `manual-required` blockers before setting approval
- Explicitly set `proposal_accepted: true` in the intake YAML

```bash
# After engineer review, open the intake file and set:
#   proposal_accepted: true

# Re-validate the approved intake
npx mobius-validate-intake migration /tmp/<service-name>-intake.yaml
# Must exit 0 with no REVIEW: warnings outstanding
```

**The agent must NOT proceed to Step 5 until `npx mobius-validate-intake migration`
exits 0 with `proposal_accepted: true` confirmed.**

---

### Step 5 — Generate Helm + ArgoCD artifacts

With the intake approved, generate all required files in the two target repos.

#### 5a. Generate helm-charts overlay structure

```bash
# Create base directory
mkdir -p helm-charts/argocd/<service>/base

# Create per-env overlay directories
for env in <TARGET_ENVIRONMENTS>; do
  mkdir -p helm-charts/argocd/<service>/overlays/$env
done
```

**`helm-charts/argocd/<service>/base/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - xirsarole.yaml
```

**`helm-charts/argocd/<service>/base/xirsarole.yaml`**:
```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XIRSARole
metadata:
  name: <service>
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  component: <service>
  clusterName: placeholder   # Patched per env via overlay
  clusterPrefix: placeholder
  serviceAccount:
    name: <service>
    namespace: <target-namespace>
  policyDocument:
    Version: "2012-10-17"
    Statement:
      # Populated from iam-extracted policy statements (hybrid — reviewed in Step 4)
      - Effect: Allow
        Action:
          - ssm:GetParameter
          - ssm:GetParameters
          - ssm:GetParametersByPath
        Resource: "arn:aws:ssm:us-east-1:AWS_ACCOUNT_ID:parameter/<ssm-path-prefix>/*"
```

**`helm-charts/argocd/<service>/overlays/<env>/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: crossplane-system
resources:
  - ../../base
patches:
  - path: xirsarole-patch.yaml
```

**`helm-charts/argocd/<service>/overlays/<env>/xirsarole-patch.yaml`**:
```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XIRSARole
metadata:
  name: <service>
spec:
  clusterName: <env>
  clusterPrefix: <env>
```

**`helm-charts/argocd/<service>/overlays/<env>/config.yaml`** (ApplicationSet discovery):
```yaml
service: "<service>"
environment: "<env>"
enabled: true
testBranch: "main"

git:
  repoURL: "https://github.com/boatsgroup/helm-charts"
  overlayPath: "argocd/<service>/overlays/<env>"

helm:
  repoURL: "https://github.com/boatsgroup/helm-charts"
  chart: "<family-template-chart>"
  version: "<chart-version>"
  releaseName: "<service>"
  namespace: "<target-namespace>"

argocd:
  project: "app-workloads"
  syncWave: "0"
  prune: true
  selfHeal: true
  allowEmpty: false

labels:
  app.kubernetes.io/part-of: "<team-name>"
```

**`helm-charts/argocd/<service>/overlays/<env>/values.yaml`**:
```yaml
# --- Image ---
image:
  repository: <ecr-registry>/<image-name>
  tag: "<image-tag>"
  pullPolicy: IfNotPresent

# --- Deployment ---
deployment:
  replicas: <desired-count>

# --- Resources (converted from ECS CPU units / MiB) ---
resources:
  requests:
    cpu: "<cpu-millicores>m"
    memory: "<memory-request>Mi"
  limits:
    memory: "<memory-limit>Mi"
    # CPU limits intentionally omitted — set only if throttling is a concern

# --- Service ---
service:
  port: <container-port>
  targetPort: <container-port>

# --- Gateway (if ALB was attached) ---
gateway:
  enabled: <true|false>
  hostname: <service>.<env>.svc.bgrp.io
  path: /
  port: <container-port>

# --- Probes ---
readinessProbe:
  httpGet:
    path: <health-check-path>
    port: <container-port>
  initialDelaySeconds: <grace-period-seconds>
  periodSeconds: <health-check-interval>
  timeoutSeconds: <health-check-timeout>
  failureThreshold: <unhealthy-threshold>

livenessProbe:
  httpGet:
    path: <health-check-path>
    port: <container-port>
  initialDelaySeconds: <grace-period-seconds>
  periodSeconds: 30
  failureThreshold: 3

# --- Environment variables ---
env:
  # Non-sensitive vars from ECS task definition environment array
  # ECS-specific vars (ECS_CONTAINER_METADATA_URI*, AWS_XRAY_DAEMON_ADDRESS) dropped
  PORT: "<container-port>"
  AWS_REGION: "us-east-1"

# --- Autoscaling (if target-tracking HPA) ---
autoscaling:
  enabled: <true|false>
  minReplicas: <min-capacity>
  maxReplicas: <max-capacity>
  targetCPUUtilizationPercentage: <cpu-target>
```

#### 5b. Generate iac-eks-argocd ApplicationSet

**`iac-eks-argocd/applicationsets/<group>/<service>.yaml`** (3-source pattern):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <service>
  namespace: argocd
  labels:
    app.kubernetes.io/name: <service>
    app.kubernetes.io/component: applicationset
    app.kubernetes.io/part-of: app-workloads
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: "https://github.com/boatsgroup/helm-charts"
              revision: main
              files:
                - path: "argocd/<service>/overlays/*/config.yaml"
          - clusters:
              selector:
                matchLabels:
                  environment: '{{.environment}}'
  template:
    metadata:
      name: "{{.service}}-{{.environment}}"
      namespace: argocd
      labels:
        app.kubernetes.io/name: "{{.service}}"
        app.kubernetes.io/part-of: '{{index .labels "app.kubernetes.io/part-of"}}'
        environment: "{{.environment}}"
        managed-by: applicationset
      annotations:
        argocd.argoproj.io/sync-wave: "{{.argocd.syncWave}}"
    spec:
      project: "{{.argocd.project}}"
      sources:
        - repoURL: "{{.helm.repoURL}}"
          chart: "{{.helm.chart}}"
          targetRevision: "{{.helm.version}}"
          helm:
            releaseName: "{{.helm.releaseName}}"
            valueFiles:
              - $values/argocd/<service>/base/values.yaml
              - $values/argocd/<service>/overlays/{{.environment}}/values.yaml
        - repoURL: "https://github.com/boatsgroup/helm-charts"
          targetRevision: "{{.testBranch}}"
          ref: values
        - repoURL: "https://github.com/boatsgroup/helm-charts"
          targetRevision: "{{.testBranch}}"
          path: "argocd/<service>/overlays/{{.environment}}"
      destination:
        server: '{{.server}}'
        namespace: "{{.helm.namespace}}"
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
          - ApplyOutOfSyncOnly=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 5
          backoff:
            duration: 30s
            factor: 2
            maxDuration: 10m
      revisionHistoryLimit: 5
  templatePatch: |
    spec:
      syncPolicy:
        automated:
          prune: {{ .argocd.prune }}
          selfHeal: {{ .argocd.selfHeal }}
          allowEmpty: {{ .argocd.allowEmpty }}
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
```

Register in the ApplicationSet kustomization:

```bash
# In iac-eks-argocd/applicationsets/<group>/kustomization.yaml, add:
#   - <service>.yaml
grep "<service>" iac-eks-argocd/applicationsets/<group>/kustomization.yaml \
  || echo "  - <service>.yaml" >> iac-eks-argocd/applicationsets/<group>/kustomization.yaml
```

#### 5c. Update ArgoCD project permissions

In `iac-eks-argocd/projects/<project>.yaml`, verify or add:

```yaml
sourceRepos:
  - "https://github.com/boatsgroup/helm-charts"

destinations:
  - namespace: "<target-namespace>"
    server: "*"
```

#### 5d. Register ApplicationSet group with hub environment kustomization

**This step is required for the ApplicationSet to appear in ArgoCD.** The
`applicationsets/<group>/` directory is not auto-discovered — each hub must
explicitly opt in to a group via its environment kustomization.

For each target environment, find its hub kustomization and add the group:

```bash
# Locate the hub kustomization for the target environment
# Pattern: hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml
#
# Profile → hub mapping:
#   bg-qa  → hubs/ops-prod/environments/bg-qa/
#   bg-prod → hubs/ops-prod/environments/bg-prod/
```

In `iac-eks-argocd/hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml`, add:

```yaml
resources:
  # ... existing groups ...
  # <ServiceGroup> workloads
  - ../../../../../../applicationsets/<group>
```

**Verification:**

```bash
grep "<group>" iac-eks-argocd/hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml
```

> **Why this step exists**: The `applicationsets/<group>/kustomization.yaml`
> defines the ApplicationSet resources, but it is inert until a hub environment
> kustomization references it. The hub kustomization is what ArgoCD actually
> syncs. Omitting this step results in the ApplicationSet being absent from
> the ArgoCD UI even after both PRs are merged.

---

### Step 6 — Run validators

Run all three validators in order. All must exit 0 before proceeding.

```bash
# Validator 1: Intake file structure and approval status
npx mobius-validate-intake migration /tmp/<service-name>-intake.yaml
# Checks: all required fields non-empty, proposal_accepted: true,
#         no outstanding REVIEW: flags, no manual-required blockers open

# Validator 2: Wiring consistency (ApplicationSet ↔ helm-charts overlay paths)
npx mobius-validate-wiring migration <service-name> \
  --service-repo ../helm-charts \
  --envs bg-qa,bg-prod
# Checks: generator repoURL matches helm-charts config.yaml git.repoURL,
#         overlay paths exist in helm-charts, kustomize build succeeds per env,
#         ApplicationSet registered in kustomization.yaml,
#         ArgoCD project sourceRepos and destinations updated

# Validator 3: Migration parity (ECS ↔ EKS configuration equivalence)
npx mobius-validate-intake migration-parity \
  /tmp/<service-name>-intake.yaml \
  --overlay-dir helm-charts/argocd/<service>
# Checks: CPU/memory conversion correctness, env var parity (excluding dropped vars),
#         health check path matches, replica count matches desiredCount,
#         HPA bounds match ECS scaling bounds (if applicable),
#         ALB listener rule category counts match HTTPRoute count (if rules > 0)
```

Additionally, verify kustomize builds for all target environments:

```bash
for env in <TARGET_ENVIRONMENTS>; do
  echo -n "kustomize build helm-charts/argocd/<service>/overlays/$env ... "
  kustomize build helm-charts/argocd/<service>/overlays/$env --enable-helm \
    && echo "✓" || echo "✗ FAILED"
done

# ApplicationSet kustomization
kustomize build iac-eks-argocd/applicationsets/<group>
```

---

### Step 7 — Produce cutover runbook

Generate the per-service cutover runbook by filling in the template:

```bash
# Copy the runbook template
cp docs/workflows/migration/cutover-runbook-template.md \
   /tmp/<service-name>-cutover-runbook.md

# Replace all {{PLACEHOLDERS}} with values from the intake YAML and extraction output
# The following substitutions are required before handoff to the service owner:
#   {{SERVICE_NAME}}             → <service>
#   {{ECS_SERVICE_NAME}}         → <ecs-service-name>
#   {{ECS_CLUSTER}}              → <cluster>
#   {{AWS_ACCOUNT}}              → bg-qa or bg-prod
#   {{EKS_NAMESPACE}}            → <target-namespace>
#   {{EKS_CLUSTER}}              → <eks-cluster-name>
#   {{SERVICE_FAMILY}}           → <service-family>
#   {{FAMILY_TEMPLATE_CHART}}    → <template-chart>
#   {{EXPECTED_REPLICAS}}        → <replica-count>
#   {{GATEWAY_ENABLED}}          → true or false
#   {{GATEWAY_HOSTNAME}}         → <service>.<env>.svc.bgrp.io
#   {{HEALTH_CHECK_PATH}}        → <health-check-path>
#   {{SERVICE_PORT}}             → <container-port>
#   {{HPA_ENABLED}}              → true or false
#   {{SOAK_PERIOD}}              → 24 hours (prod) / 4 hours (qa)
#   {{ORIGINAL_DNS_TARGET}}      → DNS value recorded before cutover
```

For services with more than 10 ALB listener rules, the runbook must include an
explicit pre-cutover parity check for each rule category (redirect, forward,
lambda, default). Add the rule category counts from Step 3 to Section 1.4 of
the runbook under **Configuration Parity**.

The runbook is a **checklist only** — see [Anti-Patterns](#anti-patterns) for
what it must not attempt to automate.

---

## Validation Commands

```bash
# Intake validation (intake YAML structure and approval)
npx mobius-validate-intake migration /tmp/<service-name>-intake.yaml

# Wiring validation (ApplicationSet ↔ overlay consistency)
npx mobius-validate-wiring migration <service-name> \
  --service-repo ../helm-charts \
  --envs bg-qa,bg-prod

# Parity check (ECS ↔ EKS configuration equivalence)
npx mobius-validate-intake migration-parity \
  /tmp/<service-name>-intake.yaml \
  --overlay-dir helm-charts/argocd/<service>

# Kustomize build — all target environments
for env in <TARGET_ENVIRONMENTS>; do
  kustomize build helm-charts/argocd/<service>/overlays/$env --enable-helm
done

# ApplicationSet kustomization builds without error
kustomize build iac-eks-argocd/applicationsets/<group>

# ApplicationSet registered in kustomization
grep "<service>" iac-eks-argocd/applicationsets/<group>/kustomization.yaml

# ApplicationSet group registered with hub environment (required for ArgoCD visibility)
grep "<group>" iac-eks-argocd/hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml

# ArgoCD project has helm-charts in sourceRepos
grep "helm-charts" iac-eks-argocd/projects/<project>.yaml

# After merge — ArgoCD Application created
kubectl -n argocd get applications | grep <service>

# After sync — pods running in EKS
kubectl get pods -n <target-namespace> -l app.kubernetes.io/name=<service>

# IRSA annotation present on ServiceAccount
kubectl get sa -n <target-namespace> <service> -o yaml \
  | grep eks.amazonaws.com/role-arn

# XIRSARole claim healthy
kubectl get xirsarole <service> -n crossplane-system
```

---

## Failure Modes

| Symptom | Cause | Where to look | Fix |
|---------|-------|---------------|-----|
| `npx mobius-validate-intake migration` exits non-zero | Missing required fields or `proposal_accepted` still false | Script output; intake YAML | Fill all required fields; set `proposal_accepted: true` after review |
| `npx mobius-validate-wiring migration` fails on repoURL mismatch | `config.yaml git.repoURL` does not match ApplicationSet generator `repoURL` | `helm-charts/argocd/<service>/overlays/<env>/config.yaml` | Set both to `https://github.com/boatsgroup/helm-charts` |
| `npx mobius-validate-intake migration-parity` fails on listener rule count | HTTPRoute count does not match ALB listener rule category counts | Parity report output | Generate missing HTTPRoute resources for each uncovered rule category |
| `kustomize build` fails with "no matches for kind XIRSARole" | Crossplane CRD not installed in target cluster | `kubectl get crd xirsaroles.aws.bgrp.io` | CRD is managed by `iac-eks-crossplane` — do not install manually |
| No Application generated by ApplicationSet | `config.yaml` missing or in wrong path | `find helm-charts/argocd/<service>/overlays -name config.yaml` | Create `config.yaml` in every overlay directory |
| No Application generated | ApplicationSet not in `kustomization.yaml` | `cat iac-eks-argocd/applicationsets/<group>/kustomization.yaml` | Add `- <service>.yaml` to the resources list |
| ApplicationSet registered but not visible in ArgoCD UI | ApplicationSet group not registered with hub environment kustomization | `cat iac-eks-argocd/hubs/<hub>/environments/<env>/us-east-1/applicationsets/kustomization.yaml` | Add `- ../../../../../../applicationsets/<group>` to the resources list (Step 5d) |
| Application created, sync fails with permissions error | ArgoCD project missing `sourceRepos` or `destinations` | `kubectl get appproject -n argocd <project> -o yaml` | Add `helm-charts` to `sourceRepos`; add namespace to `destinations` |
| XIRSARole stuck in `Creating` | `clusterName` not patched by overlay | `kubectl describe xirsarole <service> -n crossplane-system` | Verify `xirsarole-patch.yaml` exists in each overlay and kustomization references it |
| Pods start but fail IAM calls | IRSA role ARN not on ServiceAccount annotation | `kubectl get sa -n <ns> <service> -o yaml` | Wait for XIRSARole to reach `Ready` state; describe to check Crossplane status |
| Pods start but fail SSM reads | IAM policy missing SSM path or wrong ARN template | Application logs; check XIRSARole `policyDocument` | Verify resource ARN pattern matches actual SSM parameter prefix |
| Readiness probe failing immediately | Wrong health check path or port | `kubectl describe pod -n <ns>` | Cross-check with ECS task definition `healthCheck.command` or ALB target group `HealthCheckPath` |
| OOMKilled pods | Memory limit set too low | `kubectl describe pod -n <ns>` | Increase `resources.limits.memory`; revisit ECS `memory` → EKS limit conversion |
| Listener rule parity incomplete for redirect rules | Redirect action `RequestRedirect` filter missing or wrong path/status | `kubectl get httproute -n <ns> -o yaml` | Add or correct `RequestRedirect` filter; verify host/path/statusCode match ALB rule exactly |
| Weighted DNS cutover shows elevated 5xx on EKS target | Application startup time exceeds `initialDelaySeconds` | Application logs; Grafana EKS namespace dashboard | Increase `readinessProbe.initialDelaySeconds` and re-deploy before shifting more traffic |

---

## Merge Order

This workflow touches two repositories. Merge in this exact order to avoid
broken states:

1. **`iac-eks-argocd`** — merge ApplicationSet + project permission changes first
   - ArgoCD project permissions must exist before the Application is created
   - Merging out of order causes the Application to appear but immediately fail
     sync with a permissions error
   - PR must include: `applicationsets/<group>/<service>.yaml`,
     `applicationsets/<group>/kustomization.yaml`, and `projects/<project>.yaml`

2. **`helm-charts`** — merge overlay configs and Helm values second
   - ApplicationSet discovers `config.yaml` and creates the Application
   - Sync begins only after `helm-charts` PR is merged to `main`
   - PR must include: all files under `argocd/<service>/base/` and
     `argocd/<service>/overlays/<env>/`

> **Do not merge `helm-charts` before `iac-eks-argocd`.** If they are merged in
> the wrong order: the Application will be created immediately, ArgoCD will
> attempt to sync, and the sync will fail with a project permissions error that
> leaves the Application in a degraded state until the project PR is merged.

---

## Anti-Patterns

| Anti-Pattern | Why It Is Forbidden |
|--------------|---------------------|
| Automatic DNS cutover | DNS changes affect live production traffic. All cutover steps in the runbook are a checklist only and must be executed by a human engineer during a planned window. |
| Automatic ECS scale-down | Scaling down the ECS service before the soak period completes removes the rollback path. ECS must remain at full desired count until the soak period passes and the service owner signs off. |
| Secrets or credential values in extraction output | Extraction commands are read-only. Apply the redaction decision tree in `ecs-extraction-reference.md` to every extracted value before writing it to any file or log. |
| `force: true` sync in ArgoCD | Force sync bypasses diff calculation and can cause data loss on stateful resources including the XIRSARole Crossplane claim. Never add `force: true` to sync policy. |
| `testBranch` in a feature branch `config.yaml` | `testBranch` only takes effect when the file is on `main`. Placing it in a feature branch PR has no effect and is misleading. |
| Copying broad IAM wildcards verbatim | IAM policy statements containing `Resource: "*"` or action wildcards (e.g., `s3:*`) must be flagged in the intake for human review. Do not copy broad permissions as-is. |
| Skipping the human approval gate | The two-phase architecture exists to prevent generating incorrect artifacts from `hybrid` fields. Proceeding from discovery to generation without explicit `proposal_accepted: true` is forbidden. |
| Direct ECS teardown before soak period | ECS must serve as the live rollback target for the full soak period (24 hours production, 4 hours QA). Deleting the ECS service before soak completion eliminates the rollback path. |
| Migrating an `INACTIVE` or `DRAINING` service without owner confirmation | An inactive or draining service may be in the middle of a planned shutdown or emergency rollback. Always confirm with the service owner. |
| Hardcoding AWS account IDs in YAML files | Use `AWS_ACCOUNT_ID` placeholder in templates; actual account IDs are resolved at apply time via overlay patches or ExternalSecrets. |
| Setting `allowEmpty: true` without explicit justification | `allowEmpty: true` masks missing resources and hides configuration errors. Only set if the service explicitly requires it and the rationale is documented. |
| Generating artifacts for a `manual-required` service without resolving blockers | Services with EFS volumes, GPU requirements, App Mesh, or custom CloudWatch metric scaling cannot be generated by this workflow. Escalate to the platform team first. |
