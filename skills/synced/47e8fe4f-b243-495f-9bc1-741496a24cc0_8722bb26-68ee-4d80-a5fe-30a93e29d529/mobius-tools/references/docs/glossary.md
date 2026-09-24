# Mobius Glossary

## Core Terms

| Term | Meaning |
|------|---------|
| **ACM** | AWS Certificate Manager. Provisions and manages TLS certificates used by NLB listeners and ALB Ingress. Crossplane can provision ACM certs via the `crossplane-xrd-ingress-acm-certificate` XRD. |
| **addon** | Internal path/model term used in repo structure and workflow docs, usually the same unit as service deployment |
| **AppProject** | An ArgoCD resource that defines a permission boundary — which repos a team can pull from, which clusters and namespaces they can deploy to, and which resource kinds are allowed. Created by `/mobius:new-project`. |
| **ApplicationSet** | An ArgoCD resource that automatically creates deployments by scanning repos for config files. When you add a `config.yaml`, the ApplicationSet finds it and deploys your service. |
| **base** | The shared foundation of a service's deployment config. Contains the Helm chart reference and default settings. Each environment overlay builds on top of this. |
| **claim** | A request for a cloud resource written in YAML. For example, an XIRSARole claim asks the platform to create an AWS IAM role for your service. |
| **composition** | Crossplane implementation backing an XRD claim |
| **config.yaml** | A small file that tells ArgoCD "deploy this service in this environment." Placing a `config.yaml` in an overlay folder IS the deployment trigger. |
| **Crossplane** | A Kubernetes tool that provisions AWS resources (IAM roles, S3 buckets, etc.) by writing YAML instead of Terraform or clicking in the AWS console. |
| **dependency graph** | `ecosystem/dependency-graph.yaml`, canonical reference model for repo relationships |
| **environment** | A deployment target like `bg-qa` (QA) or `bg-prod` (production). Each environment maps to an EKS cluster with its own settings. |
| **Envoy Gateway** | The ingress controller that routes external traffic to services running in the cluster. Handles TLS termination and HTTP routing. |
| **GitOps** | A deployment model where merging code to `main` IS the deployment. No manual `kubectl apply` or CI/CD deploy step — ArgoCD watches the repo and syncs automatically. |
| **Helm chart** | A package format for Kubernetes applications. Think of it as a template that gets filled in with your environment-specific values. |
| **hub** | ArgoCD control-plane cluster that manages spoke clusters |
| **hub-spoke** | The platform's ArgoCD topology. A hub cluster runs the ArgoCD control plane and manages one or more spoke clusters via cross-account IAM trust. See [ArgoCD Hub-Spoke](architecture/argocd-hub-spoke.md). |
| **IRSA** | IAM Roles for Service Accounts. Lets your Kubernetes pod assume an AWS IAM role, so it can access AWS resources like S3 or SQS without hardcoded credentials. |
| **KCL** | Kusion Configuration Language. A programming language used to write Crossplane resource definitions. You don't need to know KCL unless you're building new platform resources. |
| **Karpenter** | A Kubernetes node autoscaler that provisions EC2 instances on demand. The platform manages Karpenter node roles via the `crossplane-xrd-karpenter-node-role` XRD. |
| **kustomization.yaml** | The manifest file that Kustomize reads to discover resources, patches, and generators in a directory. Each base and overlay has one. ArgoCD uses these to build the final manifests for deployment. |
| **Kustomize** | A tool that layers environment-specific config on top of a shared base. The base has defaults; each overlay patches what's different for that environment. |
| **namespace** | An isolated area within a Kubernetes cluster. Services typically get their own namespace to avoid name collisions and set resource boundaries. |
| **NLB** | Network Load Balancer (AWS). Handles TCP/TLS traffic routing to Envoy Gateway pods. Each hub has NLB listeners provisioned via the `crossplane-xrd-gateway-nlb-listener` XRD. |
| **OCI** | Open Container Initiative. A packaging format used to publish Crossplane compositions to the JFrog registry. Relevant mainly to platform builders. |
| **OIDC** | OpenID Connect. Used in two contexts: (1) EKS OIDC providers that enable IRSA by letting Kubernetes service accounts assume AWS IAM roles, and (2) GitHub OIDC federation for CI/CD access to AWS. |
| **overlay** | An environment-specific configuration folder (e.g., `overlays/bg-qa/`). Contains the `config.yaml` that triggers deployment plus any value overrides for that environment. |
| **project (ArgoCD)** | A permission boundary in ArgoCD. Defines which repos a service can pull from and which namespaces it can deploy to. |
| **resolver** | `scripts/resolve-deps.sh`, which discovers/clones/freshens dependency repos and updates local access settings |
| **Route53** | AWS DNS service. The platform uses Route53 hosted zones for service DNS records, with cross-account delegation managed by the `terraform-module-delegated-zone` module. |
| **service deployment** | Engineer-facing term for shipping an app/addon workload to EKS via GitOps |
| **service repo** | The Git repository where your service's deployment configuration lives. For platform services, usually `iac-eks-addons`. For application teams, your team's own repo. |
| **spoke** | Managed EKS cluster registered to a hub |
| **sync wave** | ArgoCD's ordering mechanism. Resources with lower wave numbers deploy before higher ones. Ensures dependencies are ready before the things that need them. |
| **values.yaml** | Helm values file that configures a service's deployment. In Mobius, each overlay has a `values.yaml` that overrides the base chart defaults for that environment. |
| **XIRSARole** | A Crossplane claim that creates an AWS IAM role for your service's Kubernetes pod. The most commonly used self-service resource on the platform. |
| **XRD** | Crossplane Composite Resource Definition exposed as self-service platform API |

## Term Mapping: Service vs Addon

- Use **service** (or **service deployment**) as the primary term in commands, docs, and conversation.
- Use **addon** only when referencing concrete directory paths (e.g., `argocd/{addon}/overlays/{env}/config.yaml`).
- The command `/mobius:add-service` is the standard entry point for creating new EKS service deployments; `/mobius:update-service` is the entry point for changing one that already exists (add an AWS resource/IAM, bump the chart, add an environment).

Example:

- Command: `/mobius:add-service cert-manager`
- Intent: "Add a service deployment to EKS."
- Path: `argocd/{addon}/overlays/{env}/config.yaml`

---

## Finding Your Way

If you're new to the platform, start with the [Engineer's Guide](engineer-guide.md)
which uses these terms in context. For the full documentation map, see
[Docs Mind Map](ecosystem-start-here.md).
