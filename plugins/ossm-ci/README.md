# ossm-ci Plugin

Claude Code plugin providing CI utilities for the OpenShift Service Mesh (OSSM) team.

## Installation

```bash
/plugin install ossm-ci@ci-utils
```

## Commands

### `/ossm-ci:confidence`
Calculate a data-driven release confidence score (1-10) for an OSSM build using Report Portal test data.

Analyzes test results across FULL/CORE/BASIC scopes, validates test matrix coverage, and provides actionable release recommendations.

**Requirements:** Report Portal MCP server configured.

---

### `/ossm-ci:generate-e2e-tests`
Generate comprehensive Go E2E tests using BDD Ginkgo from project documentation.

Run from the **root of the target project**. Validates documentation quality (threshold: 7/10), applies hidden tags for retry/timeout logic, and produces organized test suites.

**Quick start:**
```bash
cp <ci-utils>/plugins/ossm-ci/skills/generate-e2e-tests/documentation-e2e-generator.yaml ./documentation-e2e-generator.yaml
# Customize, then:
/ossm-ci:generate-e2e-tests
```

See [`skills/generate-e2e-tests/SKILL.md`](skills/generate-e2e-tests/SKILL.md) for full implementation details.

---

### `/ossm-ci:aws-scan`
Inventory AWS resources across all regions, presenting two clean tables: potentially dangling resources and complete inventory.

**Requirements:** AWS CLI configured with valid credentials. Must be run from the ci-utils repo root (requires `scripts/aws-dangling/scan_aws_resources.sh`).

---

### `/ossm-ci:prow-metrics`
Collect and present Prow CI execution data for OSSM repositories (istio, proxy, sail-operator, ztunnel), with summary statistics and TSV export for Excel.

**Requirements:** Must be run from the ci-utils repo root (requires `scripts/prow-metrics/collect_ossm_data.py`).

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `generate-e2e-tests` | `/ossm-ci:generate-e2e-tests` | Documentation to Go E2E test generator |

## Notes

- `ossm-ci:confidence` and `ossm-ci:generate-e2e-tests` are fully portable and can be used from any project
- `ossm-ci:aws-scan` and `ossm-ci:prow-metrics` require scripts from this repository; run from the ci-utils repo root or after cloning it
