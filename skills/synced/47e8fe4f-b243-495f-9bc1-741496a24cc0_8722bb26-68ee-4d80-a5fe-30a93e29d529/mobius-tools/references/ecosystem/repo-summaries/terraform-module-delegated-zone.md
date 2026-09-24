# terraform-module-delegated-zone

**Role**: DNS delegation Terraform module — cross-account Route53 zones and ACM
certificates.

**Tier**: infrastructure

## What It Does

Creates Route53 hosted zones in spoke AWS accounts and wires NS delegation
records back to the parent zone. Also provisions ACM certificates for the
delegated domains and validates them via DNS. This enables each account/cluster
to own its own DNS namespace while keeping a single root domain.

## Key Files

| File | Purpose |
|------|---------|
| `README.md` | Module documentation and usage examples |

## Upstream (depends on)

*(none)* — standalone Terraform module.

## Downstream (consumed by)

- **iac-terragrunt-core-infra** — calls this module to set up per-account DNS delegation

## Critical Conventions

- Zone delegation uses NS records in the parent hosted zone
- ACM certificates are validated via Route53 DNS (not email)
- One delegated zone per account/environment pair
