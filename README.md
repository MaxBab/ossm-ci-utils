# ci-utils

Shared utilities to standardize and simplify build, test, and deployment pipelines for the OSSM team.

## Table of Contents

- [Claude Code Plugin](#claude-code-plugin)
  - [Installation](#installation)
  - [Commands](#commands)
- [Repository Structure](#repository-structure)
  - [report\_portal/](#report_portal)
  - [skip\_tests/](#skip_tests)
  - [scripts/](#scripts)
  - [ai-helpers/](#ai-helpers)
  - [plugins/](#plugins)

---

## Claude Code Plugin

This repository is a **Claude Code skills marketplace**. Team members can install the `ossm-ci` plugin into any project to get AI-powered CI utilities as slash commands.

### Installation

From any project directory with Claude Code:

```bash
/plugin install ossm-ci@openshift-service-mesh/ci-utils
```

### Commands

#### `/ossm-ci:confidence`
Calculates a data-driven release confidence score (1–10) for an OSSM build by analyzing test results from Report Portal. Determines the required test scope (FULL/CORE/BASIC), validates test matrix coverage across platforms and environments, and provides a scored breakdown with a GO/NO-GO release recommendation.

**Requires:** Report Portal MCP server configured in Claude Code.

---

#### `/ossm-ci:generate-e2e-tests`
Generates production-ready Go E2E tests using BDD Ginkgo from a project's documentation. Validates documentation quality against a scoring threshold (7/10 minimum), extracts hidden tags for retry/timeout/validation logic, and produces organized test files with helpers.

Run from the **root of the target project**. Copy the config template to get started:
```bash
cp <ci-utils>/plugins/ossm-ci/skills/generate-e2e-tests/documentation-e2e-generator.yaml ./documentation-e2e-generator.yaml
```

---

#### `/ossm-ci:aws-scan`
Inventories AWS resources across all regions and presents two clean tables: potentially dangling resources and a complete resource inventory. No analysis, no file generation — raw data only for the user to act on.

**Requires:** AWS CLI configured with valid credentials. The command uses the script at [`scripts/aws-dangling/scan_aws_resources.sh`](scripts/aws-dangling/scan_aws_resources.sh).

---

#### `/ossm-ci:prow-metrics`
Collects and presents Prow CI execution data for OSSM repositories (istio, proxy, sail-operator, ztunnel). Shows summary statistics, median execution times by job type, infrastructure usage, failed/pending jobs, and exports a TSV file for Excel import.

The command uses the script at [`scripts/prow-metrics/collect_ossm_data.py`](scripts/prow-metrics/collect_ossm_data.py).

---

## Repository Structure

### `report_portal/`

A **centralized, generic script** used by CI jobs across all OSSM repositories to send JUnit XML test results to Report Portal via Data Router. Instead of each repository maintaining its own reporting logic, they all reference this single script, ensuring consistent test reporting across the team.

**Key features:**
- Works with any CI system (GitHub Actions, GitLab CI, Jenkins, Prow)
- Supports credentials via environment variables or mounted secret files
- Dry-run mode for safe configuration testing
- Credentials are never logged — always redacted in output

See [`report_portal/README.md`](report_portal/README.md) for full environment variable reference and CI examples.

---

### `skip_tests/`

Centralized YAML configuration that controls which Istio integration tests are skipped or run across different CI streams and branches. All test runners (midstream_sail, midstream_helm, downstream) consume these files to ensure consistent test execution across environments.

**Files:**
| File | Purpose |
|------|---------|
| `test-config-full.yaml` | Skip configuration for full test suite runs (nightly, release validation) |
| `test-config-smoke.yaml` | Skip configuration for smoke/quick validation runs |
| `parse-test-config.sh` | Parser that reads a config file and sets environment variables for `integ-suite-ocp.sh` |

**How it works:** CI jobs download the config and parser from this repo, run the parser for their stream and branch, and pass the resulting environment variables to the test runner:

```bash
curl -O https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/skip_tests/test-config-full.yaml
curl -O https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/skip_tests/parse-test-config.sh
chmod +x ./parse-test-config.sh

eval $(./parse-test-config.sh test-config-full.yaml security midstream_sail main)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"
```

See [`skip_tests/README.md`](skip_tests/README.md) for full configuration reference.

---

### `scripts/`

Backend scripts used by the `ossm-ci` Claude Code plugin commands. These scripts handle the data collection and are invoked by the AI commands rather than being run manually.

| Script | Used by | Description |
|--------|---------|-------------|
| `scripts/aws-dangling/scan_aws_resources.sh` | `/ossm-ci:aws-scan` | Scans all AWS regions for EC2, S3, RDS, ELB, and other resources |
| `scripts/prow-metrics/collect_ossm_data.py` | `/ossm-ci:prow-metrics` | Collects Prow CI job data for OSSM repositories from the OpenShift Prow API |

Both scripts can also be run directly if needed. See the READMEs in each subdirectory for standalone usage.

---

### `ai-helpers/`

Configuration and documentation supporting the `/ossm-ci:confidence` plugin command.

| File | Description |
|------|-------------|
| `ossm-config.json` | Confidence score weights, test scope matrix, OCP version mappings, and Report Portal project settings |
| `ossm-release-confidence.md` | Architecture documentation for the Next-Gen OSSM Release Process initiative (Jira Epic: OSSM-11131) |

---

### `plugins/`

The Claude Code skills marketplace structure. Contains the `ossm-ci` plugin with all commands and skills installable via `/plugin install`.

```
plugins/
└── ossm-ci/
    ├── commands/         # Slash command definitions
    │   ├── confidence.md
    │   ├── generate-e2e-tests.md
    │   ├── aws-scan.md
    │   └── prow-metrics.md
    └── skills/
        └── generate-e2e-tests/
            ├── SKILL.md                          # Full skill implementation
            └── documentation-e2e-generator.yaml  # Config template
```
