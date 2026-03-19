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
Inventory AWS resources across all regions, presenting two clean tables: potentially dangling resources and complete inventory. Uses AWS CLI commands directly — no external scripts required.

**Requirements:** AWS CLI configured with valid credentials.

---

### `/ossm-ci:prow-metrics`
Collect and present Prow CI execution data for OSSM repositories (istio, proxy, sail-operator, ztunnel), with summary statistics and TSV export for Excel. Fetches directly from the Prow API using an inline Python script — no external scripts required.

**Requirements:** `python3` and `jq` available in PATH.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `generate-e2e-tests` | `/ossm-ci:generate-e2e-tests` | Documentation to Go E2E test generator |

## Notes

All four commands are fully portable and work from any project after installation.
