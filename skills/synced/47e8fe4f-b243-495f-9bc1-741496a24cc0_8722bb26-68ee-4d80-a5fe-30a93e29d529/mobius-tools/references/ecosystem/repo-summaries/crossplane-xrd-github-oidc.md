# crossplane-xrd-github-oidc

**Role**: GitHub OIDC XRD (stub) — planned Crossplane XRD for federating
GitHub Actions with AWS IAM via OIDC. Currently incomplete.

**Tier**: xrd

## What It Does (Planned)

Intended to define the `GitHubOIDC` XRD that creates the AWS IAM OIDC Identity
Provider and IAM role trust policies needed for GitHub Actions to assume AWS
roles without static credentials. The composition would register the GitHub
OIDC provider in the AWS account and create the corresponding IAM role.

**Current Status**: This repo is a stub. The composition is not functional.
Do not reference this as a working example. Do not create claims against this XRD.

## Key Files

| File | Purpose |
|------|---------|
| `definition.yaml` | XRD schema (may be incomplete) |
| `composition.yaml` | Composition pipeline (not production-ready) |
| `crossplane.yaml` | Package metadata |
| `kcl/main.k` | Composition logic (incomplete) |

## Upstream (depends on)

- **iac-eks-crossplane** — would host the Configuration CR when complete

## Downstream (consumed by)

- Nothing currently — no production claims exist

## OCI Packages Published

None published to production — repo is not released.

## Critical Conventions

- **DO NOT** use this repo as a reference implementation
- **DO NOT** create GitHub OIDC claims against this XRD
- For GitHub Actions AWS access, use existing IRSA patterns until this is complete
- Track completion status before incorporating into any addon
