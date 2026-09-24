# ECS → EKS Mapping Matrix

> Reference document for ECS-to-EKS service migration in the Mobius platform.
> Used by `/mobius:migrate-ecs-service` command and app team self-service migrations.

---

## Quick Reference Table

| ECS Concept | EKS Equivalent | Notes |
|---|---|---|
| Task Definition | Deployment (in Helm chart) | Family template charts in `helm-charts/` |
| Container Definition | Pod spec container | Single primary container per Deployment |
| Service | Deployment + Service + HTTPRoute | 3 K8s resources per ECS service |
| Task Role | IRSA via XIRSARole Crossplane claim | `aws.bgrp.io/v1alpha1 XIRSARole` in `argocd/<service>/base/xirsarole.yaml` |
| Execution Role | Not needed | EKS nodes use instance profiles; pods use IRSA |
| ECS Cluster | EKS Namespace | Services grouped by namespace (e.g., `api-node`) |
| Desired Count | `deployment.replicas` in values.yaml | HPA overrides if auto-scaling enabled |
| Container Port | `service.port` + `service.targetPort` in values.yaml | ClusterIP Service |
| Host Port (bridge mode) | Not applicable | EKS uses overlay networking (Cilium) |
| awslogs log driver | Promtail/Loki (already deployed) | No config needed — Promtail auto-discovers pods |
| X-Ray sidecar | Drop — OTel Collector exists | Platform-wide OpenTelemetry in EKS |
| Datadog sidecar | Drop — OTel Collector exists | Same as X-Ray |
| ALB + Target Group | Gateway API HTTPRoute | `gateway.enabled: true` in values.yaml, uses Envoy Gateway |
| ALB Health Check | readinessProbe + livenessProbe | Translate health check path + interval |
| SSM Parameter Store secrets | IRSA policy for SSM read | XIRSARole policyDocument grants `ssm:GetParameter*` |
| Secrets Manager secrets | ExternalSecrets or IRSA | Depends on ExternalSecrets operator availability |
| Environment variables | `env:` block in values.yaml | Map from task definition `environment` |
| .env files | `envFiles:` block in values.yaml | Rendered as ConfigMap, mounted into container |
| CPU Units | K8s CPU requests/limits | 128 ECS units = `128m` K8s CPU |
| Memory (MiB) | K8s memory requests/limits | 256 MiB = `256Mi` |
| Auto Scaling (target tracking) | HPA (Horizontal Pod Autoscaler) | CPU target → HPA `targetCPUUtilizationPercentage` |
| Auto Scaling (step) | Not directly mapped | Flag for manual review |
| ECS Exec | `kubectl exec` | Native K8s capability |
| ECR Image | Same ECR image reference | ECR pull-through or direct `<account>.dkr.ecr.<region>.amazonaws.com/<repo>` |
| Service Discovery (Cloud Map) | K8s Service DNS | Automatic `<svc>.<ns>.svc.cluster.local` |
| EFS Volumes | PersistentVolumeClaim + EFS CSI | `manual-required` — needs Karpenter NodePool config |
| App Mesh | Cilium Service Mesh | `manual-required` — different mesh model |
| Scheduled Tasks | CronJob | `supported-with-prompts` — different template |

---

## Detailed Sections

### Compute Resources

#### CPU Conversion

ECS CPU units map directly to Kubernetes millicores using the formula:

```
K8s_CPU = ECS_CPU_units / 1000
```

| ECS CPU Units | K8s CPU Request |
|---|---|
| 128 | `128m` |
| 256 | `256m` |
| 512 | `512m` |
| 1024 | `1` |
| 2048 | `2` |
| 4096 | `4` |

#### Memory Conversion

ECS memory (MiB) maps directly to Kubernetes memory (Mi):

```
K8s_Memory = ECS_Memory_MiB + "Mi"
```

| ECS Memory (MiB) | K8s Memory |
|---|---|
| 256 | `256Mi` |
| 512 | `512Mi` |
| 1024 | `1Gi` |
| 2048 | `2Gi` |
| 4096 | `4Gi` |

#### Limits Strategy

- **Requests**: Set to the ECS soft limit (task-level CPU/memory if no container-level reservation is set).
- **Limits**: Set to 2x requests, or use the ECS hard limit if one is defined. Prefer not setting CPU limits in K8s to avoid throttling; set memory limits to prevent OOM-kills.

#### Concrete Example

ECS task definition:
```json
{
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [{
    "cpu": 128,
    "memory": 256,
    "memoryReservation": 128
  }]
}
```

Resulting values.yaml:
```yaml
resources:
  requests:
    cpu: "128m"
    memory: "128Mi"
  limits:
    cpu: "256m"
    memory: "512Mi"
```

---

### Networking

#### Bridge Mode with Dynamic Host Ports

ECS bridge mode assigns random host ports at task launch. EKS uses Cilium overlay networking where each pod gets its own IP. Every container port becomes a fixed ClusterIP Service port — no port conflicts, no dynamic allocation.

- ECS: `hostPort: 0` (dynamic) + `containerPort: 3000` → EKS: ClusterIP Service `port: 3000`, `targetPort: 3000`

#### ALB → Gateway API HTTPRoute

ECS services behind an Application Load Balancer are replaced by a Gateway API `HTTPRoute` resource routed through the cluster-wide Envoy Gateway.

Enable in values.yaml:
```yaml
gateway:
  enabled: true
  hostname: api-node-ai-provider.qa.svc.bgrp.io
  path: /
  port: 3000
```

The hostname convention is: `<service>.<env>.svc.bgrp.io`

#### Health Check Mapping

| ECS ALB Field | K8s Probe Field | Notes |
|---|---|---|
| `healthCheckPath` | `probe.path` | Same HTTP path |
| `healthCheckIntervalSeconds` | `periodSeconds` | Same unit (seconds) |
| `healthCheckTimeoutSeconds` | `timeoutSeconds` | Same unit (seconds) |
| `healthyThresholdCount` | `successThreshold` | Same count |
| `unhealthyThresholdCount` | `failureThreshold` | Same count |
| `healthCheckPort` | `probe.port` | Usually same as `containerPort` |

Both `readinessProbe` and `livenessProbe` should be populated from the ECS health check. Use the same path and interval for both unless there is a specific reason to differentiate.

#### Concrete Example (api-node-ai-provider)

ECS:
```json
{
  "loadBalancers": [{
    "targetGroupArn": "arn:aws:...",
    "containerPort": 3000
  }],
  "healthCheckGracePeriodSeconds": 30
}
```

K8s values.yaml:
```yaml
service:
  port: 3000
  targetPort: 3000

gateway:
  enabled: true
  hostname: api-node-ai-provider.qa.svc.bgrp.io
  path: /
  port: 3000

readinessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 30
  failureThreshold: 3
```

---

### ALB Listener Rules (DEVOPS-5598)

For BoatTrader-style migrations, ALB listener rules are a first-class mapping input. DEVOPS-5598 tracks a production migration with 72 ALB listener rules (redirect, forward, lambda, and default catch-all) that must be preserved during transition to Gateway API.

#### Rule Type Mapping

| ALB Listener Rule Pattern | Gateway API Equivalent | Notes |
|---|---|---|
| Host-based redirect | `HTTPRoute` + `RequestRedirect` filter | Preserve host and path behavior exactly (including path drop/preserve semantics) |
| Path-based redirect | `HTTPRoute` + `RequestRedirect` filter | Validate ordering when multiple prefixes overlap |
| Host+path forward | `HTTPRoute` `matches` + `backendRefs` | Use explicit precedence (more specific matches first) |
| Header-based forward | `HTTPRoute` header match + `backendRefs` | Example: feature-flag routing using request header |
| Default catch-all | Lowest-priority catch-all `HTTPRoute` | Must remain last to avoid shadowing specific rules |
| Lambda target forward | Envoy Gateway Backend CRD or API Gateway/Function URL bridge | `supported-with-prompts` until backend pattern is confirmed |

#### Known Translation Gaps

| ALB Feature | Migration Handling |
|---|---|
| Wildcard host variants (for example, image subdomain variants) | Expand to explicit `hostnames` list or use approved wildcard hostname strategy |
| Glob-style path matching (for example, `*.js`) | Convert to Gateway-compatible regex/path strategy and verify behavior with test cases |
| Query-string wildcard redirects | Implement with Envoy/Gateway extension strategy and mark as `supported-with-prompts` |
| Shared listener used by many teams | Split into team-scoped `HTTPRoute` resources with clear ownership and deterministic ordering |

#### Cutover Guidance for Listener-Heavy Services

Use phased migration with rollback-safe traffic control:
1. Deploy Gateway + route objects in parallel with existing ALB.
2. Validate parity for redirects/forwards before traffic shift.
3. Shift traffic using weighted DNS records.
4. Keep rollback path as DNS weight reversal (<5 minutes target).

When the source service uses many ALB listener rules, parity checks must validate:
- Rule count parity by category (redirect/forward/lambda/default).
- Match condition parity (host, path, header, query behavior).
- Redirect target parity (hostname/path/status code).

---

### IAM / IRSA

#### ECS Task Role → XIRSARole

ECS Task Roles are replaced by IRSA (IAM Roles for Service Accounts) provisioned via a Crossplane `XIRSARole` claim. The XIRSARole controller creates:

1. An IAM Role with an OIDC trust policy scoped to the pod's ServiceAccount
2. A Kubernetes ServiceAccount annotated with the IAM role ARN
3. The IAM policy document attached to the role

File location: `helm-charts/argocd/<service>/base/xirsarole.yaml`

The `clusterName` and `clusterPrefix` fields are left as placeholders in `base/` and overridden by each environment overlay in `overlays/<env>/kustomization.yaml`.

#### Concrete Example (api-node-ai-provider)

```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XIRSARole
metadata:
  name: api-node-ai-provider
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  component: api-node-ai-provider
  clusterName: placeholder  # Overridden by overlay
  clusterPrefix: placeholder
  serviceAccount:
    name: api-node-ai-provider
    namespace: api-node
  policyDocument:
    Version: "2012-10-17"
    Statement:
      - Effect: Allow
        Action:
          - ssm:GetParameter
          - ssm:GetParameters
          - ssm:GetParametersByPath
        Resource: "arn:aws:ssm:AWS_REGION:AWS_ACCOUNT_ID:parameter/api/api-node-ai-provider/*"
```

Replace `AWS_REGION` and `AWS_ACCOUNT_ID` with template placeholders resolved at overlay time, or hardcode the correct values for the target environment overlay.

#### ECS Execution Role

ECS Execution Roles (used for ECR image pulls and CloudWatch log publishing) are not needed in EKS. ECR access is granted to EKS worker nodes via the node instance profile. Log forwarding is handled by Promtail at the platform level. No execution role equivalent is created during migration.

---

### Environment Variables

#### Mapping ECS `environment` to values.yaml `env:`

ECS task definition `environment` array maps directly to the `env:` block in values.yaml:

ECS:
```json
{
  "environment": [
    { "name": "PORT", "value": "3000" },
    { "name": "AWS_REGION", "value": "us-east-1" },
    { "name": "NODE_ENV", "value": "production" }
  ]
}
```

values.yaml:
```yaml
env:
  PORT: "3000"
  AWS_REGION: "us-east-1"
  NODE_ENV: "production"
```

#### Mapping ECS `secrets` (SSM References)

ECS `secrets` entries that reference SSM Parameter Store paths do not translate to K8s secrets directly. Instead, the application reads SSM parameters at runtime using the AWS SDK (e.g., `@dmm/lib-node-parameter-store-cache`). The XIRSARole policy document must grant `ssm:GetParameter*` access to the relevant SSM path prefix.

No values.yaml entry is needed for SSM-backed secrets — the app fetches them using its IRSA-granted role at startup.

#### Variables to DROP

Remove these from `env:` during migration — they are ECS-specific or replaced by platform infrastructure:

| Variable | Reason to Drop |
|---|---|
| `AWS_XRAY_DAEMON_ADDRESS` | OTel Collector replaces X-Ray; no daemon address needed |
| `ECS_CONTAINER_METADATA_URI` | ECS-specific metadata endpoint; not present in EKS |
| `ECS_CONTAINER_METADATA_URI_V4` | ECS-specific metadata endpoint; not present in EKS |

#### Variables to TRANSFORM

| Variable | Action |
|---|---|
| `NODE_ENV` | Move to per-overlay `envFiles` so qa, staging, and production each get the correct value |
| `PORT` | Keep as-is; also set as `service.port` and `service.targetPort` in values.yaml |
| `AWS_REGION` | Keep as-is; value does not change between ECS and EKS |

#### .env Files → envFiles

ECS tasks that reference `.env` files via volume mounts or build-time injection use the `envFiles:` block in values.yaml. The Helm chart renders these as a ConfigMap and mounts them into the container:

```yaml
envFiles:
  - name: app-env
    mountPath: /app/.env
    data:
      NODE_ENV: qa
      LOG_LEVEL: info
```

---

### Observability

#### Logging

No action required. Promtail is deployed platform-wide and auto-discovers all pods via label selectors. Logs are shipped to Loki. Remove the `awslogs` log driver configuration from the task definition — it has no equivalent in the Helm chart values.

#### Tracing

Drop the X-Ray daemon sidecar container. The platform-wide OTel Collector handles distributed tracing. If the application uses the AWS X-Ray SDK, it must be reconfigured to export to the OTel Collector endpoint (`http://otel-collector.observability.svc.cluster.local:4318`). This is an application-level change, not a platform config change.

#### Metrics

Drop the Datadog agent sidecar. The platform uses Prometheus for metrics collection. If the application exposes a `/metrics` endpoint in Prometheus format, a `ServiceMonitor` can be added to the Helm chart values to enable scraping. This step is optional and depends on the application's observability requirements.

No platform-level metrics configuration is required for basic CPU/memory metrics — kube-state-metrics and node-exporter are already deployed.

---

### Scaling

#### ECS Desired Count → Deployment Replicas

The ECS service `desiredCount` maps to `deployment.replicas` in values.yaml:

```yaml
deployment:
  replicas: 2
```

When HPA is enabled, this value acts as the initial replica count and may be overridden at runtime by the autoscaler.

#### Target Tracking → HPA

| ECS Auto Scaling Field | HPA Equivalent |
|---|---|
| `TargetValue` (CPU %) | `targetCPUUtilizationPercentage` |
| `TargetValue` (Memory %) | `targetMemoryUtilizationPercentage` |
| `MinCapacity` | `minReplicas` |
| `MaxCapacity` | `maxReplicas` |

values.yaml with HPA:
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

#### Step Scaling

ECS step scaling policies have no direct K8s equivalent in the standard HPA model. Services using step scaling must be flagged for manual review. Options include KEDA (Kubernetes Event-Driven Autoscaling) for custom metric-based scaling or custom HPA behavior policies.

---

### Sidecars

| Sidecar | Action | Reason |
|---|---|---|
| X-Ray daemon | Drop | OTel Collector platform-wide |
| Datadog agent | Drop | OTel Collector platform-wide |
| CloudWatch agent | Drop | Promtail/Loki for logs |
| Custom log router (e.g., Fluent Bit) | Drop | Promtail auto-discovers |
| App-specific sidecar | Keep (`supported-with-prompts`) | Ask which container is the primary |

When an app-specific sidecar is present, confirm which container is the primary workload before generating the Helm chart. The Helm chart supports a single primary container with optional init containers. Sidecars require additional configuration in the pod spec template.

---

## ArgoCD Wiring Structure

The migration generates the following file tree. All files are committed to `helm-charts/` and `iac-eks-argocd/` repositories.

```
helm-charts/
├── argocd/<service>/
│   ├── base/
│   │   ├── kustomization.yaml    # resources: [xirsarole.yaml]
│   │   └── xirsarole.yaml        # Crossplane XIRSARole claim
│   └── overlays/<env>/
│       ├── config.yaml           # ApplicationSet discovery file
│       ├── values.yaml           # Helm values override
│       └── kustomization.yaml    # namespace: crossplane-system, resources: [../../base]

iac-eks-argocd/
└── applicationsets/<group>/
    ├── <service>.yaml            # 3-source ApplicationSet (Helm + values ref + Kustomize)
    └── kustomization.yaml        # includes all service AppSets in group
```

The `config.yaml` file in each overlay is the ApplicationSet discovery file used by the Git File Generator. Its presence in an overlay directory is sufficient for ArgoCD to deploy the service to that environment.

The ApplicationSet in `iac-eks-argocd/applicationsets/<group>/<service>.yaml` uses three sources:
1. The Helm chart from `helm-charts/` (chart definition)
2. The overlay `values.yaml` from `helm-charts/` (environment-specific values)
3. The Kustomize overlay from `helm-charts/` (XIRSARole and namespace binding)

---

## Non-Standard Features Quick Reference

| Feature | Classification | Handling |
|---|---|---|
| EFS volumes | manual-required | Needs PVC + EFS CSI + Karpenter NodePool |
| GPU requirements | manual-required | Needs Karpenter GPU NodePool |
| App Mesh | manual-required | Cilium handles mesh in EKS; different model |
| Multiple app containers | supported-with-prompts | Ask which is the primary container |
| Batch/scheduled jobs | supported-with-prompts | Use CronJob/Job template |
| Shared ALB rules (path-based routing) | supported-with-prompts | Map each rule to a separate HTTPRoute |
| Secrets Manager refs | supported-with-prompts | ExternalSecrets operator or IRSA + SDK |
| Step scaling policies | supported-with-prompts | Evaluate KEDA or manual HPA behavior tuning |

**Classification key:**

- `manual-required` — Cannot be automated. The migration command halts and requires a human engineer to design and implement the EKS equivalent before proceeding.
- `supported-with-prompts` — The migration command pauses and asks the engineer clarifying questions before generating the relevant configuration.
