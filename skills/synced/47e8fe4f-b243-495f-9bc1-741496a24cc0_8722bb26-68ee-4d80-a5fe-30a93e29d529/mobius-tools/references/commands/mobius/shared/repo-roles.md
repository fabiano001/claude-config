# Repository Roles — Plain-Language Reference

This file provides jargon-free descriptions of each repository in the Mobius
platform. The agent reads this when generating the "Changes by repository"
section of the Why Summary.

**Usage:** Look up only the repos that were touched by the current command.
Do not include repos that were not modified or checked.

---

## iac-eks-argocd
**One-line role:** the deployment control center

This repo is the brain of the deployment system. It knows about every service,
every cluster, and who has permission to deploy what. When you add a new service,
you register it here so the deployment system knows it exists. When you add a new
cluster, you register it here so the system knows where to deploy things.

Think of it like a phone directory: services can't be reached (deployed) until
they're listed here.

**Common changes by command type:**
- *add-service*: Creates the discovery rule (ApplicationSet) that tells the deployment system to watch for your service's config files, and grants deployment permissions to its namespace.
- *new-hub*: Creates an entirely new deployment control center for a new region or isolation boundary.
- *new-spoke*: Registers a new cluster so the hub knows it can send deployments there. Includes secure credentials for cross-cluster communication.
- *new-project*: Creates or updates team permission boundaries — which repos and namespaces a team is allowed to deploy to.
- *migrate-ecs-service*: Same as add-service — registers the migrated service with the deployment system.

---

## helm-charts
**One-line role:** where application service configurations live

This repo holds the actual settings for your application services: what container
image to run, how much CPU and memory each service needs, which environments to
deploy to, and how to connect to cloud resources like databases and storage.
Engineers own their service configurations here.

When you want to change how a service behaves (new environment variable, more
memory, a new endpoint), this is the repo you edit.

**Common changes by command type:**
- *add-service*: Creates the full service configuration — base settings plus environment-specific overrides for QA and production.
- *migrate-ecs-service*: Same as add-service, but the configuration is auto-generated from the existing ECS service settings.

---

## iac-eks-addons
**One-line role:** where platform service configurations live

Similar to helm-charts, but specifically for platform-level services (monitoring
agents, certificate managers, DNS controllers) rather than application-level
services. If helm-charts is "your team's services," iac-eks-addons is "the
platform team's services."

**Common changes by command type:**
- *add-service*: Creates the service configuration if the service is a platform addon rather than a team application.
- *new-spoke*: Creates environment-specific configurations for all platform services that need to run on the new cluster.

---

## iac-eks-crossplane
**One-line role:** the cloud resource provisioning system

This repo manages how the platform creates cloud resources (databases, storage
buckets, message queues, identity roles) automatically from simple configuration
files. Instead of filing a ticket asking someone to create an S3 bucket, engineers
add a short config file and the system creates it automatically.

**Common changes by command type:**
- *new-hub*: Registers the cloud resource system with the new hub so it can provision AWS resources for services on that hub's clusters.
- *new-spoke*: Connects the new cluster to the cloud resource provisioning system.
- *new-xrd*: Registers a new type of cloud resource that teams can self-service.

---

## iac-eks-observability
**One-line role:** monitoring and alerting configuration

This repo configures the monitoring stack: dashboards, alerts, log collection,
and metrics. It ensures you can see what your services are doing and get notified
when something goes wrong.

**Common changes by command type:**
- *new-hub*: Sets up monitoring for the new hub cluster.
- *new-spoke*: Extends monitoring to cover the new spoke cluster.

---

## terraform-stack-monitoring-ng
**One-line role:** monitoring infrastructure (cloud resources)

While iac-eks-observability configures the monitoring *software*, this repo
creates the cloud *infrastructure* for monitoring: the storage for metrics,
the databases for dashboards, and the cloud permissions for the monitoring
stack to operate.

**Common changes by command type:**
- *new-hub*: Creates monitoring infrastructure for the new hub.
- *new-spoke*: Extends monitoring infrastructure to cover the new cluster.

---

## iac-terragrunt-core-infra
**One-line role:** creates the actual cloud infrastructure

This repo provisions the foundational AWS resources: the servers (EKS clusters),
networking (VPCs, subnets), DNS configuration, and security policies. It's the
physical foundation that everything else runs on. Changes here are the most
impactful — they affect the actual cloud infrastructure.

**Common changes by command type:**
- *new-hub*: Provisions the cloud infrastructure for the new hub cluster.
- *new-spoke*: Provisions the cloud infrastructure for the new spoke cluster, including networking and cross-account security trust.

---

## terraform-module-core-irsa
**One-line role:** manages AWS permissions for services

This repo defines how services get secure access to AWS resources (databases,
S3 buckets, secrets). Instead of storing passwords in code, services use
identity-based permissions — the platform verifies "who they are" and grants
access automatically. This repo defines those identity-to-permission mappings.

**Common changes by command type:**
- *add-service*: May be referenced when a service needs AWS access — the IRSA claim in the service repo points to permission definitions managed here.

---

## terraform-module-eks
**One-line role:** EKS cluster configuration template

This repo defines how Kubernetes clusters are built — the template that specifies
cluster version, node sizes, networking plugins, and security settings. When a
new cluster is created, it uses this template to ensure consistency.

**Common changes by command type:**
- *new-hub*: The hub cluster is built using this template.
- *new-spoke*: The spoke cluster is built using this template.

---

## terraform-module-delegated-zone
**One-line role:** DNS delegation for clusters

This repo manages how domain names (like `service.example.com`) are routed
to the correct cluster. When a new cluster is created, DNS delegation ensures
traffic for that cluster's services reaches the right place.

**Common changes by command type:**
- *new-hub*: Creates DNS delegation for the new hub's domain.
- *new-spoke*: Creates DNS delegation for the new spoke's domain.

---

## crossplane-xrd-irsa-role
**One-line role:** self-service AWS permissions template

Lets services request AWS permissions by adding a short configuration file.
Instead of filing a ticket, an engineer writes "I need access to S3" and the
platform creates the secure permission automatically.

---

## crossplane-xrd-s3-bucket
**One-line role:** self-service storage bucket template

Lets services request S3 storage buckets by adding a short configuration file.
The platform creates the bucket with proper encryption, access policies, and
lifecycle rules automatically.

---

## crossplane-xrd-sqs-eventbridge
**One-line role:** self-service message queue template

Lets services request message queues (SQS) and event routing (EventBridge) by
adding a short configuration file. Used for asynchronous communication between
services.

---

## crossplane-xrd-ingress-acm-certificate
**One-line role:** self-service SSL certificate template

Lets services request SSL/TLS certificates for their public endpoints. The
platform provisions the certificate, validates domain ownership, and renews
it automatically.

---

## crossplane-xrd-gateway-nlb-listener
**One-line role:** self-service network load balancer template

Lets services request network-level load balancer listeners for high-throughput
or non-HTTP traffic. Creates the AWS load balancer configuration automatically.

---

## crossplane-xrd-generated-aws-secret
**One-line role:** self-service secret generation template

Lets services request auto-generated secrets (passwords, API keys) that are
stored securely in AWS Secrets Manager and injected into the service automatically.

---

## crossplane-xrd-github-oidc
**One-line role:** self-service GitHub Actions permissions template

Lets CI/CD pipelines in GitHub Actions securely access AWS resources without
storing long-lived credentials. Creates the identity trust between GitHub and
AWS automatically.

---

## crossplane-xrd-karpenter-node-role
**One-line role:** self-service node scaling permissions template

Lets the auto-scaling system (Karpenter) provision new servers with the correct
AWS permissions. Ensures new servers can pull container images, access shared
storage, and join the cluster securely.

---

## argocd-env-generator
**One-line role:** environment scaffolding tool

A command-line tool that generates the boilerplate configuration files for a
new environment across multiple repos. Used internally by some commands to
stamp out consistent configurations.

---

## mobius-tools
**One-line role:** the platform toolkit and documentation

This repo (the one you're using right now) contains the command-line tools,
documentation, and ecosystem map for the platform. It doesn't deploy anything
itself, but it tracks the relationships between all the other repos and provides
validators, impact analysis, and the research protocol.

**Common changes by command type:**
- *new-xrd*: Updates the dependency graph to include the new resource template repo.
- *refresh-docs*: Scans all repos and updates documentation that has drifted.
- *validate-graph*: Checks this repo's dependency graph against all repo frontmatter.
- *trace-impact*: Uses this repo's dependency graph to calculate blast radius.
