# ci-utils

Shared utilities to standardize and simplify build, test, and deployment pipelines for the OSSM team.

## Table of Contents

- [Claude Code Plugin](#claude-code-plugin)
  - [Installation](#installation)
    - [Step 1: Add the marketplace](#step-1-add-the-marketplace)
    - [Step 2: Install the plugin](#step-2-install-the-plugin)
    - [Step 3: Reload plugins](#step-3-reload-plugins)
  - [Commands](#commands)
- [Repository Structure](#repository-structure)
  - [report\_portal/](#report_portal)
  - [skip\_tests/](#skip_tests)
  - [scripts/](#scripts)
  - [ai-helpers/](#ai-helpers)
  - [plugins/](#plugins)
  - [images/](#images)

---

## Claude Code Plugin

This repository is a **Claude Code skills marketplace**. Team members can install the `ossm-ci` plugin into any project to get AI-powered CI utilities as slash commands.

### Installation

Plugins hosted on GitHub must be added as a marketplace first, then installed individually.

#### Step 1: Add the marketplace

```
/plugin marketplace add openshift-service-mesh/ci-utils
```

This registers the repo as a marketplace using the `name` field from its `.claude-plugin/marketplace.json`. The marketplace is registered as **`ci-utils`**.

#### Step 2: Install the plugin

```
/plugin install ossm-ci@ci-utils
```

#### Step 3: Reload plugins

```
/reload-plugins
```

> **What does NOT work**
>
> | Command | Why it fails |
> |---|---|
> | `/plugin install ossm-ci@openshift-service-mesh/ci-utils` | The `org/repo` format is not a registered marketplace name |
> | `/plugin install openshift-service-mesh/ci-utils` | Treated as a plugin name, not a marketplace |
>
> The target GitHub repo must contain `.claude-plugin/marketplace.json` with a `plugins` array listing available plugins.

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

**Requires:** AWS CLI configured with valid credentials.

---

#### `/ossm-ci:prow-metrics`
Collects and presents Prow CI execution data for OSSM repositories (istio, proxy, sail-operator, ztunnel). Shows summary statistics, median execution times by job type, infrastructure usage, failed/pending jobs, and exports a TSV file for Excel import. Fetches directly from the Prow API — works from any project.

**Requires:** `python3` available in PATH.

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

Standalone scripts for AWS resource scanning and Prow CI data collection. These can be run directly from the command line and are independent of the Claude Code plugin (the plugin commands use AWS CLI and the Prow API directly without these scripts).

| Script | Description |
|--------|-------------|
| `scripts/aws-dangling/scan_aws_resources.sh` | Scans all AWS regions for EC2, S3, RDS, ELB, and other resources. Generates a full report, CSV findings, and cleanup guidance. |
| `scripts/prow-metrics/collect_ossm_data.py` | Collects Prow CI job data for OSSM repositories and exports a TSV file for Excel import. |

See the READMEs in each subdirectory for standalone usage.

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

---

### `images/`

A container image providing a safe, isolated environment for running Claude Code skills that interact with external systems. Skills that need to execute commands against AWS, Kubernetes, or other tools should run inside this container rather than on the user's local machine.

| Image | Base | Use case |
|-------|------|----------|
| `Dockerfile.local` | Debian Bookworm Slim | Local development, kind, and OpenShift clusters |

See [`images/README.md`](images/README.md) for build and run instructions. Currently there is no CI automation to generate and publish this images, it can be built locally using the make target and you can push to `sail-dev` repository on [quay.io](https://quay.io/repository/sail-dev/ossm-ai-local?tab=tags) or your own registry.
