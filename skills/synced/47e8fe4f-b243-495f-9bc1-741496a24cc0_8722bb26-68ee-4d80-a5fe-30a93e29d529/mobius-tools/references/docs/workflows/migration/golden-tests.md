# Migration Golden Tests

> End-to-end validation of the ECS-to-EKS migration workflow using representative
> sample intakes for each service family.

---

## Purpose

Golden tests verify that the migration intake validator and parity checker work
correctly across all supported service families. They serve as:

1. **Regression tests** - Ensure validator changes don't break existing patterns
2. **Documentation** - Show complete, valid intake examples for each family
3. **Onboarding** - Help new engineers understand what a properly filled intake looks like

---

## Service Families Covered

| Family | Sample Fixture | Characteristics |
|--------|----------------|-----------------|
| `api-node` | `api-node-sample-intake.yaml` | HTTP service with ALB, Gateway enabled, IRSA |
| `portal-react` | `portal-react-sample-intake.yaml` | Frontend app with static asset serving, no IRSA |
| `webapp-react` | `webapp-react-sample-intake.yaml` | React webapp family with multi-host listener parity |
| `webapp-node` | `webapp-node-sample-intake.yaml` | Node webapp family with SSM+S3 IAM dependencies |
| Listener-heavy | `listener-rules-sample.yaml` | ALB with 72+ rules (DEVOPS-5598 pattern) |

---

## Running Golden Tests

### Quick Run (All Tests)

```bash
bash scripts/run-migration-golden-tests.sh
```

This runs:
1. Intake validator against all sample intakes
2. Reports pass/fail summary
3. Exits non-zero if any test fails

### Individual Fixture Validation

```bash
npx mobius-validate-intake migration docs/workflows/migration/fixtures/api-node-sample-intake.yaml
npx mobius-validate-intake migration docs/workflows/migration/fixtures/portal-react-sample-intake.yaml
npx mobius-validate-intake migration docs/workflows/migration/fixtures/webapp-react-sample-intake.yaml
npx mobius-validate-intake migration docs/workflows/migration/fixtures/webapp-node-sample-intake.yaml
```

### Listener Rules Parity Check (Dry Run)

The listener rules fixture can be used with the parity checker in dry-run mode
to verify rule counting logic:

```bash
npx mobius-validate-intake migration-parity \
  docs/workflows/migration/fixtures/api-node-sample-intake.yaml \
  --overlay-dir docs/workflows/migration/fixtures \
  --listener-rules-file docs/workflows/migration/fixtures/listener-rules-sample.yaml
```

---

## Fixture Descriptions

### api-node-sample-intake.yaml

Represents a typical Node.js API service:
- HTTP service on port 3000
- ALB with health check at /health
- HPA enabled (2-10 replicas, CPU target 70%)
- IRSA for SSM parameter access
- Gateway API HTTPRoute for external traffic
- Classification: `fully-compatible`

### portal-react-sample-intake.yaml

Represents a React frontend portal:
- Static asset serving on port 80
- ALB with health check at /
- Fixed replica count (no HPA)
- No IRSA needed (no AWS API calls)
- Gateway API HTTPRoute for external traffic
- Classification: `fully-compatible`

### webapp-react-sample-intake.yaml

Represents a `webapp-react-*` family service (bg-qa reference pattern):
- HTTP service on port 80
- ALB host rules mapped to Gateway hostnames
- HPA enabled (2-5 replicas, CPU target 60%)
- IRSA for SSM reads
- Sidecar caveat documented (`nginx` + `xray` in ECS)
- Classification: `supported-with-prompts`

### webapp-node-sample-intake.yaml

Represents a `webapp-node-*` family service (bg-qa reference pattern):
- HTTP service on port 80 with `/fsbo/healthcheck`
- HPA enabled (2-4 replicas, CPU target 40%)
- IRSA for multiple SSM paths plus S3 object reads
- Multi-domain host parity from ALB listener rules
- Sidecar caveat documented (`nginx` + `xray` in ECS)
- Classification: `supported-with-prompts`

### listener-rules-sample.yaml

Represents ALB listener rule category counts for a DEVOPS-5598-style migration:
- 45 redirect rules (host/path redirects)
- 20 forward rules (backend routing)
- 5 lambda rules (serverless targets)
- 2 default rules (catch-all)
- Total: 72 rules

This fixture is used with `--listener-rules-file` flag in parity checks.

---

## Expected Test Results

All sample intakes are designed to pass validation:

| Fixture | Expected Result |
|---------|-----------------|
| `api-node-sample-intake.yaml` | PASS |
| `portal-react-sample-intake.yaml` | PASS |
| `webapp-react-sample-intake.yaml` | PASS |
| `webapp-node-sample-intake.yaml` | PASS |

The golden test script reports:

```
============================================================
Migration Golden Tests
============================================================

Testing: api-node-sample-intake.yaml
[PASS] Intake validation passed

Testing: portal-react-sample-intake.yaml
[PASS] Intake validation passed

Testing: webapp-react-sample-intake.yaml
[PASS] Intake validation passed

Testing: webapp-node-sample-intake.yaml
[PASS] Intake validation passed

============================================================
Summary: 4 passed, 0 failed
RESULT: PASS - All golden tests passed
============================================================
```

---

## Adding New Golden Tests

To add a new service family golden test:

1. **Create the fixture**:
   ```bash
   cp docs/workflows/migration/migrate-ecs-intake.yaml \
      docs/workflows/migration/fixtures/<family>-sample-intake.yaml
   ```

2. **Fill all required fields** with realistic values that represent the family

3. **Set all gate booleans to true**:
   - `extraction_completed: true`
   - `mapping_applied: true`
   - `classification_completed: true`
   - `hybrid_fields_reviewed: true`
   - `blockers_resolved: true`

4. **Validate the fixture passes**:
   ```bash
   npx mobius-validate-intake migration \
     docs/workflows/migration/fixtures/<family>-sample-intake.yaml
   ```

5. **Add to the test runner** (if not auto-discovered):
   Edit `scripts/run-migration-golden-tests.sh` to include the new fixture.

---

## Troubleshooting

### Test Fails with "field is EMPTY"

The fixture is missing a required field. Check the validator output for the
specific field and update the fixture.

### Test Fails with "invalid enum value"

The fixture has an invalid value for an enum field. Check valid values in
`docs/workflows/migration/migrate-ecs-intake.yaml` comments.

### Test Fails with "gate boolean not true"

Ensure all five gate booleans are set to `true` in the fixture:
- `extraction_completed`
- `mapping_applied`
- `classification_completed`
- `hybrid_fields_reviewed`
- `blockers_resolved`

### Parity Check Skips All Checks

The parity checker needs a real overlay directory with `values.yaml` files.
Golden tests run the intake validator only by default. For full parity testing,
you need generated artifacts or mock overlay directories.
