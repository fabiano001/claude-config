# ECS Extraction Reference

> Documents every AWS CLI command used during the discover phase of ECS-to-EKS migration.
> Used by `/mobius:migrate-ecs-service` to extract ECS service configuration.
>
> **SECURITY**: Never log SSM parameter values, secret ARNs, or credential strings.
> Only extract resource names and paths for mapping purposes.

---

## Prerequisites

### AWS SSO Profiles

| Profile | Account ID | Environment |
|---|---|---|
| `bg-qa` | `AWS_ACCOUNT_ID` (QA) | Non-production |
| `bg-prod` | `AWS_ACCOUNT_ID` (Prod) | Production |

Authenticate before running any extraction commands:

```bash
aws sso login --profile <PROFILE>
```

### ECS Clusters

| Cluster | Service Count | Notes |
|---|---|---|
| `node10` | ~100+ services | Primary application cluster |
| `node-indexers` | 9 services | Indexer workloads |

Both clusters exist in each account (`bg-qa` and `bg-prod`).

### Required IAM Permissions

The executing principal must have all of the following:

- `ecs:Describe*`
- `ecs:List*`
- `elasticloadbalancing:Describe*`
- `application-autoscaling:Describe*`
- `iam:ListAttachedRolePolicies`
- `iam:GetPolicyVersion`
- `iam:GetPolicy`

All commands in this document are **read-only**. No write permissions are required or used.

---

## Extraction Commands

### 3a. List ECS Services

**Purpose:** Enumerate all services in a cluster to build the discovery list.

```bash
aws ecs list-services \
  --cluster <CLUSTER> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'serviceArns[*]' \
  --output text
```

**What it returns:**

A newline-delimited list of service ARNs in the format:

```
arn:aws:ecs:us-east-1:AWS_ACCOUNT_ID:service/<CLUSTER>/<SERVICE_NAME>
```

**Field extraction:**

| Field | Source | Auto/Hybrid | Notes |
|---|---|---|---|
| Service name | Parsed from ARN (last `/`-delimited segment) | Auto | Use as key for all subsequent lookups |
| Cluster name | Parsed from ARN (second-to-last segment) | Auto | Cross-check against `--cluster` input |

**Error handling:**

| Condition | Response |
|---|---|
| Cluster not found | Error with: "Cluster not found. Available clusters: node10, node-indexers. Run `aws ecs list-clusters --profile <PROFILE> --region us-east-1` to confirm." |
| Empty result | Service list is empty for this cluster — confirm cluster name and account. |
| Pagination | Command does not paginate automatically. If `nextToken` is present in raw output, re-run with `--next-token <TOKEN>`. |

---

### 3b. Describe ECS Service

**Purpose:** Retrieve the service-level configuration — replica counts, load balancer attachments, network mode, and deployment strategy.

```bash
aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1
```

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Desired count | `.services[0].desiredCount` | Auto | `deployment.replicas` |
| Task definition ARN | `.services[0].taskDefinition` | Auto | Input for step 3c |
| Launch type | `.services[0].launchType` | Auto | Informational |
| Load balancers | `.services[0].loadBalancers` | Auto | Gateway API config |
| Network config | `.services[0].networkConfiguration` | Auto | Informational (bridge vs awsvpc) |
| Health check grace period | `.services[0].healthCheckGracePeriodSeconds` | Auto | `initialDelaySeconds` hint |
| Deployment config | `.services[0].deploymentConfiguration` | Auto | `strategy.rollingUpdate` |
| Status | `.services[0].status` | Auto | Validation — must be `ACTIVE` before proceeding |

**Validation rule:** If `.services[0].status` is not `ACTIVE`, halt extraction and report status. Do not migrate inactive services without explicit confirmation.

**Error handling:**

| Condition | Response |
|---|---|
| Service not found | "Service not found in cluster. Run `aws ecs list-services --cluster <CLUSTER> --profile <PROFILE> --region us-east-1` to list available services." |
| Multiple services returned | Use `[0]` index but log a warning — `describe-services` accepts a list; confirm only one service was requested. |

---

### 3c. Describe Task Definition

**Purpose:** Extract the container runtime configuration — image, resource limits, environment variables, secrets references, health checks, and IAM roles.

```bash
aws ecs describe-task-definition \
  --task-definition <TASK_DEFINITION_ARN> \
  --profile <PROFILE> \
  --region us-east-1
```

Use the `taskDefinition` ARN returned from step 3b.

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Container image | `.taskDefinition.containerDefinitions[0].image` | Auto | `image.repository` + `image.tag` |
| CPU | `.taskDefinition.containerDefinitions[0].cpu` | Auto | `resources.requests.cpu` (ECS units → K8s millicores: `256` CPU units = `256m`) |
| Memory (hard limit) | `.taskDefinition.containerDefinitions[0].memory` | Auto | `resources.limits.memory` |
| Memory reservation (soft limit) | `.taskDefinition.containerDefinitions[0].memoryReservation` | Auto | `resources.requests.memory` |
| Port mappings | `.taskDefinition.containerDefinitions[0].portMappings` | Auto | `service.port`, `service.targetPort` |
| Environment variables | `.taskDefinition.containerDefinitions[0].environment` | Auto | `env:` block in values.yaml — see redaction rules |
| Secrets (SSM refs) | `.taskDefinition.containerDefinitions[0].secrets` | **Hybrid** | IRSA policy SSM paths — extract PATHS only, REDACT values |
| Health check | `.taskDefinition.containerDefinitions[0].healthCheck` | Auto | `readinessProbe` / `livenessProbe` |
| Task role ARN | `.taskDefinition.taskRoleArn` | Auto | XIRSARole policyDocument source |
| Execution role ARN | `.taskDefinition.executionRoleArn` | Auto | Informational — not needed in EKS |
| Log configuration | `.taskDefinition.containerDefinitions[0].logConfiguration` | Auto | Drop — Promtail handles log collection in EKS |
| Container count | `len(.taskDefinition.containerDefinitions)` | Auto | Sidecar detection trigger |
| Essential flag | `.taskDefinition.containerDefinitions[*].essential` | Auto | Primary container identification |
| Entry point / command | `.taskDefinition.containerDefinitions[0].entryPoint` | **Hybrid** | May require custom `command:` in Deployment |
| Volumes | `.taskDefinition.volumes` | **Hybrid** | EFS volumes → manual-required; others → review |

**Unit conversions:**

| ECS Field | ECS Unit | K8s Equivalent | Formula |
|---|---|---|---|
| `cpu` | ECS CPU units (1024 = 1 vCPU) | Millicores | `cpu_units` = `cpu_millicores` (1:1, e.g., 256 → `256m`) |
| `memory` | MiB | MiB | Pass through (e.g., 512 → `512Mi`) |
| `memoryReservation` | MiB | MiB | Pass through |

**Sidecar detection logic:**

Run this logic when `len(.taskDefinition.containerDefinitions)` > 1:

1. Filter containers by `essential: true` — this is the primary container.
2. For each non-essential container, check its `name` against the known sidecar list:

| Known Sidecar Name | Action |
|---|---|
| `xray-daemon` | Drop — not used in EKS |
| `datadog-agent` | Drop — handled by cluster-level DaemonSet |
| `cloudwatch-agent` | Drop — replaced by Promtail/Loki |
| `log-router` | Drop — replaced by Promtail |
| `aws-otel-collector` | Drop — replaced by cluster-level OTEL |

3. Unknown sidecar names → set migration status to `supported-with-prompts` and surface to the user for decision. Do not drop silently.

**Error handling:**

| Condition | Response |
|---|---|
| Task definition not found | ARN may be stale. Re-run step 3b to get the current task definition ARN. |
| Multiple container definitions, no `essential: true` | Flag as ambiguous — require human to identify primary container. |
| Volumes present (`taskDefinition.volumes` non-empty) | Flag volume type. EFS volumes are `manual-required`. Other volume types require review. |

---

### 3d. Describe Target Groups (ALB)

**Purpose:** Extract health check configuration from the ALB target group attached to the ECS service. These values map directly to Kubernetes readiness probe settings.

```bash
# Step 1: Extract the target group ARN from the service config
TARGET_GROUP_ARN=$(aws ecs describe-services \
  --cluster <CLUSTER> \
  --services <SERVICE_NAME> \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'services[0].loadBalancers[0].targetGroupArn' \
  --output text)

# Step 2: Describe the target group
aws elbv2 describe-target-groups \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --profile <PROFILE> \
  --region us-east-1
```

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Health check path | `.TargetGroups[0].HealthCheckPath` | Auto | `readinessProbe.path` |
| Health check interval | `.TargetGroups[0].HealthCheckIntervalSeconds` | Auto | `readinessProbe.periodSeconds` |
| Health check timeout | `.TargetGroups[0].HealthCheckTimeoutSeconds` | Auto | `readinessProbe.timeoutSeconds` |
| Healthy threshold | `.TargetGroups[0].HealthyThresholdCount` | Auto | `readinessProbe.successThreshold` |
| Unhealthy threshold | `.TargetGroups[0].UnhealthyThresholdCount` | Auto | `readinessProbe.failureThreshold` |
| Protocol | `.TargetGroups[0].Protocol` | Auto | Informational |
| Port | `.TargetGroups[0].Port` | Auto | Cross-check against container port from step 3c |

**Error handling:**

| Condition | Response |
|---|---|
| No load balancer on service | Skip this step. Service is internal-only. Set `ingress.enabled: false` in output. |
| `TARGET_GROUP_ARN` is `None` or empty | No ALB attached. Proceed without target group health check data. |
| Target group not found | ARN may be stale or TG deleted. Log warning and skip — do not halt migration. |

#### 3d.1. Describe Listener Rules (for ALB route parity)

**Purpose:** Extract listener rule behavior (host/path/header/query matching, redirect/forward actions, and default actions) for migrations where routing parity is critical, such as DEVOPS-5598.

```bash
# Step 1: Discover ALB ARN from target group
ALB_ARN=$(aws elbv2 describe-target-groups \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --profile <PROFILE> \
  --region us-east-1 \
  --query 'TargetGroups[0].LoadBalancerArns[0]' \
  --output text)

# Step 2: List listeners (typically HTTPS:443)
aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --profile <PROFILE> \
  --region us-east-1

# Step 3: For each listener ARN, extract rules
aws elbv2 describe-rules \
  --listener-arn <LISTENER_ARN> \
  --profile <PROFILE> \
  --region us-east-1
```

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Rule priority | `.Rules[*].Priority` | Auto | HTTPRoute precedence strategy |
| Host conditions | `.Rules[*].Conditions[?Field==\`host-header\`]` | Auto | `spec.hostnames` |
| Path conditions | `.Rules[*].Conditions[?Field==\`path-pattern\`]` | Auto | `spec.rules.matches.path` |
| Header conditions | `.Rules[*].Conditions[?Field==\`http-header\`]` | Auto | `spec.rules.matches.headers` |
| Query-string conditions | `.Rules[*].Conditions[?Field==\`query-string\`]` | **Hybrid** | Gateway extension/prompt-required mapping |
| Redirect actions | `.Rules[*].Actions[?Type==\`redirect\`]` | Auto | `RequestRedirect` filter |
| Forward actions | `.Rules[*].Actions[?Type==\`forward\`]` | Auto | `backendRefs` |
| Lambda target forwards | Rule action target points to Lambda | **Hybrid** | Backend CRD, Function URL, or API Gateway bridge |
| Default action | Listener default action | Auto | Catch-all HTTPRoute |

**Error handling:**

| Condition | Response |
|---|---|
| Listener discovery fails | Continue migration with warning; classify route mapping as `supported-with-prompts`. |
| Large rule set (>20 rules) | Group output by category (redirect/forward/lambda/default) before generation to prevent ordering errors. |
| Wildcard/path-glob/query wildcard rules detected | Mark as `supported-with-prompts`; require explicit translation confirmation. |

---

### 3e. Describe Scaling Policies

**Purpose:** Extract autoscaling configuration to populate HPA settings in the EKS deployment.

```bash
# Describe scalable targets (min/max replica bounds)
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids "service/<CLUSTER>/<SERVICE_NAME>" \
  --profile <PROFILE> \
  --region us-east-1

# Describe scaling policies (CPU/memory target tracking, step scaling)
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs \
  --resource-id "service/<CLUSTER>/<SERVICE_NAME>" \
  --profile <PROFILE> \
  --region us-east-1
```

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Min capacity | `.ScalableTargets[0].MinCapacity` | Auto | HPA `minReplicas` |
| Max capacity | `.ScalableTargets[0].MaxCapacity` | Auto | HPA `maxReplicas` |
| Target tracking CPU utilization | `.ScalingPolicies[*].TargetTrackingScalingPolicyConfiguration.TargetValue` (where metric is `ECSServiceAverageCPUUtilization`) | Auto | HPA `targetCPUUtilizationPercentage` |
| Target tracking memory utilization | `.ScalingPolicies[*].TargetTrackingScalingPolicyConfiguration.TargetValue` (where metric is `ECSServiceAverageMemoryUtilization`) | Auto | HPA `targetMemoryUtilizationPercentage` |
| Step scaling policies | `.ScalingPolicies[*].StepScalingPolicyConfiguration` | **Hybrid** | Not directly mappable to HPA — flag for manual review |

**No-scaling fallback:**

If `describe-scalable-targets` returns an empty `ScalableTargets` list:
- Set `hpa.enabled: false` in output.
- Use `desiredCount` from step 3b as the static replica count.

**Error handling:**

| Condition | Response |
|---|---|
| No scalable targets registered | Service has no autoscaling. Use static replicas from `desiredCount`. |
| Step scaling policies present | Flag as `hybrid` — step scaling has no direct HPA equivalent. Document thresholds in migration report for human review. |
| Custom CloudWatch metric scaling | Flag as `manual-required` — custom metrics require KEDA or manual HPA configuration. |

---

### 3f. CloudWatch Metrics for Right-Sizing (NEW)

**Purpose:** Analyze 7+ days of CPU and Memory utilization to right-size resource allocations for cost optimization (QA) or conservative stability (production).

```bash
# Extract CPU utilization metrics (7+ days)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<SERVICE_NAME> Name=ClusterName,Value=<CLUSTER> \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Maximum,Average \
  --extended-statistics p50,p95,p99 \
  --profile <PROFILE> \
  --region us-east-1

# Extract Memory utilization metrics (7+ days)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=<SERVICE_NAME> Name=ClusterName,Value=<CLUSTER> \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Maximum,Average \
  --extended-statistics p50,p95,p99 \
  --profile <PROFILE> \
  --region us-east-1
```

**Key metrics to extract:**

| Metric | Percentile | QA Usage | Production Usage |
|--------|------------|----------|------------------|
| CPU Utilization | p50 | Informational | Informational |
| CPU Utilization | p95 | Right-sizing base (+20% headroom) | - |
| CPU Utilization | p99 | - | Right-sizing base (+30% headroom) |
| Memory Utilization | p50 | Informational | Informational |
| Memory Utilization | p95 | Right-sizing base | - |
| Memory Utilization | p99 | - | Right-sizing base (+20% headroom) |
| Maximum | Both | Validate headroom sufficiency | Critical for stability |

**Right-sizing formulas:**

For **bg-qa** (cost-optimized):
- CPU requests: `min(current_ecs, ceil(p95 * current_allocation * 1.2 / 100))`
- Memory requests: `min(current_ecs, ceil(p95 * current_allocation / 100))`

For **bg-prod** (conservative):
- CPU requests: `max(current_ecs, ceil(p99 * current_allocation * 1.3 / 100))`
- Memory requests: `max(current_ecs, ceil(p99 * current_allocation * 1.2 / 100))`
- **Never reduce below current ECS values in production**

**Error handling:**

| Condition | Response |
|-----------|----------|
| No metrics available | Use current ECS values directly, note "No CloudWatch metrics for right-sizing" |
| < 24 hours of data | Use current ECS values, flag as LOW confidence |
| < 7 days of data | Use available data, flag as MEDIUM confidence |
| Metrics show consistent 100% utilization | Flag for investigation - may indicate undersized resources |
| p99 > 90% for CPU or Memory | Recommend increasing allocation, especially for production |

---

### 3g. List IAM Role Policies

**Purpose:** Extract the task role's IAM policy document to populate the XIRSARole `policyDocument` in the EKS deployment.

```bash
# Step 1: Extract the role name from the task role ARN
# ARN format: arn:aws:iam::AWS_ACCOUNT_ID:role/ecs/<ROLE_NAME>
# Note: ECS roles use an IAM path prefix of `ecs/`
# The role name as used in IAM APIs includes the path: ecs/<ROLE_NAME>

# Step 2: List attached managed policies
aws iam list-attached-role-policies \
  --role-name <ROLE_NAME_WITH_PATH> \
  --profile <PROFILE>

# Step 3: Get the policy metadata (to retrieve default version ID)
aws iam get-policy \
  --policy-arn <POLICY_ARN> \
  --profile <PROFILE>

# Step 4: Get the policy document for the default version
aws iam get-policy-version \
  --policy-arn <POLICY_ARN> \
  --version-id <DEFAULT_VERSION_ID> \
  --profile <PROFILE>
```

**IAM path prefix handling:**

ECS task roles use the IAM path prefix `ecs/`. The full role name when calling IAM APIs must include this path:

```
# ARN:  arn:aws:iam::AWS_ACCOUNT_ID:role/ecs/node10-api-node-ai-provider
# Role name for --role-name: ecs/node10-api-node-ai-provider
```

The `--role-name` parameter in `list-attached-role-policies` accepts the full path-qualified name.

**Key fields to extract:**

| Field | Path | Auto/Hybrid | Maps To |
|---|---|---|---|
| Policy ARN | `.AttachedPolicies[*].PolicyArn` | Auto | Reference — used to fetch policy document |
| Policy name | `.AttachedPolicies[*].PolicyName` | Auto | Reference |
| Default version ID | `.Policy.DefaultVersionId` | Auto | Input for `get-policy-version` |
| Policy document statements | `.PolicyVersion.Document.Statement` | **Hybrid** | XIRSARole `policyDocument` — requires least-privilege review |
| Resource ARNs in statements | `.Statement[*].Resource` | **Hybrid** | Check for overly broad wildcards before copying |

**Least-privilege rules:**

Apply these checks to every policy statement before including it in the XIRSARole output:

| Condition | Action |
|---|---|
| `Resource: "*"` on any statement | Flag for review. Suggest narrowing to specific resource ARNs. Do not copy as-is. |
| Broad action wildcards (e.g., `s3:*`, `sqs:*`) | Flag for review. Enumerate only the specific actions observed in use, if known. |
| `Effect: Deny` statements | Copy exactly — deny statements are always safe to carry over. |
| Inline policies (not managed) | Use `aws iam list-role-policies` to list, then `aws iam get-role-policy` to fetch. Apply the same least-privilege review. |

**Important:** Do not escalate privileges when migrating. Copy only the exact actions and resources that existed in ECS. Flag any ambiguity for human review rather than broadening scope.

**Error handling:**

| Condition | Response |
|---|---|
| `NoSuchEntity` on role | Role path encoding issue. Confirm the full path-qualified role name includes `ecs/` prefix: `ecs/<ROLE_NAME>`. |
| No attached policies | Task role may use inline policies only. Run `aws iam list-role-policies --role-name <ROLE_NAME>` to check. |
| Policy document has `NotAction` or `NotResource` | Flag as `hybrid` — inverse conditions require careful translation. |
| `aws iam get-policy-version` returns no document | Policy may be AWS-managed. Note the ARN and policy name; do not attempt to replicate AWS-managed policies verbatim. |

---

## Redaction Rules

All extraction output must pass through these rules before being written to any file, log, or report.

### Redaction Table

| Data Type | Rule | Example |
|---|---|---|
| SSM parameter values | Never retrieve or log. Extract parameter PATHS only. | Path `/bg/qa/service/db-password` is allowed; its resolved value is not. |
| Secrets Manager values | Never retrieve or log. Extract secret NAME or ARN only. | `arn:aws:secretsmanager:...` is allowed; the secret string is not. |
| AWS account ID in output | Replace with `AWS_ACCOUNT_ID` placeholder. | `048922418463` → `AWS_ACCOUNT_ID` |
| IAM session credentials | Never extract. Skip any `Credentials` blocks in API responses. | `AccessKeyId`, `SecretAccessKey`, `SessionToken` → always skip. |
| ECR image tags with commit SHAs | Allowed — not sensitive. | `1.0.1-901dd4280e5b...` may be logged as-is. |
| Environment variable values | Context-dependent — see decision tree below. | `DATABASE_URL=postgres://...` → REDACT; `PORT=3000` → KEEP. |

### Redaction Decision Tree

Apply in order. Stop at the first matching rule.

1. **Is the value a credential, password, token, or connection string?** → REDACT. Replace value with `<REDACTED>`.
2. **Is the value an infrastructure reference (ARN, SSM path, secret name, S3 bucket name)?** → KEEP. Infrastructure references are needed for policy mapping.
3. **Is the value a non-sensitive configuration value (port number, environment name, region, log level)?** → KEEP.
4. **Does the environment variable name contain any of the following substrings?** `PASSWORD`, `SECRET`, `TOKEN`, `KEY`, `CREDENTIAL`, `DSN`, `DATABASE_URL`, `CONN` → REDACT regardless of value.
5. **Unsure?** → REDACT and add a flag in the migration report for human review.

---

## Field Classification Summary

This table summarizes the classification of all fields extracted across all commands.

| Classification | Approximate Count | Description |
|---|---|---|
| `auto` | ~25 | Directly mappable without human input. Values are extracted and written to output as-is (after unit conversion where applicable). |
| `hybrid` | ~8 | Extractable programmatically, but the extracted value requires human confirmation, narrowing, or contextual judgment before use. Flagged in migration report. |
| `manual` | ~3 | Cannot be auto-extracted. Requires a human to supply the value or make a decision. Migration is blocked until resolved. Examples: EFS volume configuration, unknown sidecar containers, custom CloudWatch metric scaling. |

**Classification rules by field:**

| Field | Classification | Reason |
|---|---|---|
| `desiredCount` | `auto` | Direct numeric mapping |
| `cpu`, `memory`, `memoryReservation` | `auto` | Unit conversion is deterministic |
| `image` | `auto` | Parsed and split on last `:` |
| `portMappings` | `auto` | Direct numeric mapping |
| `environment` (non-sensitive keys) | `auto` | Copied to `env:` block |
| `healthCheck` | `auto` | Direct field mapping |
| `loadBalancers` | `auto` | Drives Gateway API config generation |
| `healthCheckGracePeriodSeconds` | `auto` | Maps to `initialDelaySeconds` |
| `deploymentConfiguration` | `auto` | Maps to `strategy.rollingUpdate` |
| Scaling min/max capacity | `auto` | Direct HPA mapping |
| Target tracking CPU/memory | `auto` | Direct HPA mapping |
| `secrets` (SSM paths) | `hybrid` | Paths extracted; values never retrieved; IRSA policy requires review |
| `entryPoint` / `command` | `hybrid` | May require wrapping in shell or restructuring |
| `volumes` | `hybrid` or `manual` | EFS → `manual`; other types → `hybrid` |
| IAM policy statements | `hybrid` | Copied but require least-privilege review |
| Resource ARNs with wildcards | `hybrid` | Require narrowing before use |
| Step scaling policies | `hybrid` | No direct HPA equivalent |
| EFS volume config | `manual` | Requires PV/PVC setup — not auto-generatable |
| Unknown sidecar containers | `manual` | Requires human decision on inclusion or replacement |
| Custom CloudWatch metric scaling | `manual` | Requires KEDA or manual HPA config |

---

## Error Handling Reference

| Error | Cause | Resolution |
|---|---|---|
| `InvalidParameterException: Cluster not found` | Wrong cluster name passed to `--cluster` | List clusters: `aws ecs list-clusters --profile <PROFILE> --region us-east-1` |
| `ServiceNotFoundException` | Service name is wrong or in a different cluster | List services: `aws ecs list-services --cluster <CLUSTER> --profile <PROFILE> --region us-east-1` |
| `NoSuchEntity: IAM role` | Role path encoding issue — `ecs/` prefix missing | Use full path-qualified role name: `ecs/node10-<SERVICE_NAME>` |
| `ExpiredTokenException` | SSO session has expired | Re-authenticate: `aws sso login --profile <PROFILE>` |
| `AccessDeniedException` | Executing principal is missing required IAM permissions | Required: `ecs:Describe*`, `ecs:List*`, `elbv2:Describe*`, `iam:Get*`, `iam:List*`, `application-autoscaling:Describe*` |
| `ResourceNotFoundException` (elbv2) | Target group ARN is stale or deleted | Skip ALB health check extraction. Set `ingress.enabled: false`. |
| `ObjectNotFoundException` (autoscaling) | Service has no registered scalable target | No autoscaling configured. Use static replica count from `desiredCount`. |
| Pagination `nextToken` present | Result set is truncated | Re-run command with `--next-token <TOKEN>` until `nextToken` is absent from response. |
