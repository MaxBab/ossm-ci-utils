# Test Configuration Management

This directory contains the parser script for skip test configuration used in Istio integration tests. The configuration YAML files are stored in the [openshift-service-mesh/istio](https://github.com/openshift-service-mesh/istio) repository under `prow/skip_tests/` on each branch.

## Table of Contents

- [Overview](#overview)
- [Files](#files)
- [Configuration Structure](#configuration-structure)
  - [Supported Test Suites](#supported-test-suites)
  - [The `skip_in` Field (Required)](#the-skip_in-field-required)
- [Usage](#usage)
- [Parsing Configuration Script](#parsing-configuration-script)
  - [Requirements](#requirements)
  - [Using parse-test-config.sh Script](#using-parse-test-configsh-script-to-set-correct-env)
  - [Stream Filtering Behavior](#stream-filtering-behavior)

## Overview

The configuration system manages test execution parameters for the `integ-suite-ocp.sh` script:

```bash
integ-suite-ocp.sh ${test_suite} ${skip_tests} ${skip_subsuites} ${run_tests_only}
```

## Files

**In this repository (ci-utils):**
- **parse-test-config.sh** - Parser script to extract configuration and set environment variables
- **test-config-full.yaml** - Configuration for full test runs (depricated, will be removed)
- **test-config-smoke.yaml** - Configuration for full test runs (depricated, will be removed)

**In [openshift-service-mesh/istio](https://github.com/openshift-service-mesh/istio) repository (per branch):**
- **prow/skip_tests/skip_tests_full.yaml** - Configuration for full test runs
- **prow/skip_tests/skip_tests_smoke.yaml** - Configuration for smoke test runs

## Configuration Structure

Each YAML file contains configuration for all test suites:

```yaml
test_suites:
  <suite_name>:
    skip_tests:
      - name: "test_name"
        reason: "Why this test is skipped"
        skip_in: ['midstream_sail', 'downstream', 'midstream_helm']     # Required: specify where to skip
    skip_subsuites:
      - name: "subsuite_name"
        reason: "Why this subsuite is skipped"
        skip_in: ['downstream']                  # Required: specify where to skip
    run_tests_only:
      - name: "test_name"
        reason: "Why only this test runs"
        skip_in: ['midstream_sail']              # Required: specify where to run
```

### Supported Test Suites

- `pilot`
- `security`
- `ambient`
- `telemetry`
- `helm`

### The `skip_in` Field (Required)

The `skip_in` field is **required** for all test entries and specifies where a test should be skipped or run. This enables different test configurations for midstream_sail, midstream_helm, and downstream environments.

**Values:**
- `['midstream_sail']` - Skip/run only in midstream_sail testing
- `['midstream_helm']` - Skip/run only in midstream_helm testing
- `['downstream']` - Skip/run only in downstream testing
- `['midstream_sail', 'midstream_helm']` - Skip/run in both midstream environments
- `['midstream_sail', 'downstream']` - Skip/run in midstream_sail and downstream
- `['midstream_helm', 'downstream']` - Skip/run in midstream_helm and downstream
- `['midstream_sail', 'midstream_helm', 'downstream']` - Skip/run in all environments

**Examples:**

```yaml
skip_tests:
  # Skip only in downstream
  - name: "TestAuthz_CustomServer"
    reason: "Feature not available in downstream"
    skip_in: ['downstream']

  # Skip only in midstream_sail
  - name: "TestGatewayConformance"
    reason: "Requires setup only available in downstream"
    skip_in: ['midstream_sail']

  # Skip only in midstream_helm
  - name: "TestHelmSpecific"
    reason: "Test not applicable to helm-based installations"
    skip_in: ['midstream_helm']

  # Skip in both midstream environments
  - name: "TestCNIVersionSkew"
    reason: "Not supported in midstream environments"
    skip_in: ['midstream_sail', 'midstream_helm']

  # Skip in all environments
  - name: "TestBroken"
    reason: "Known issue across all environments"
    skip_in: ['midstream_sail', 'midstream_helm', 'downstream']
```

## Usage

The workflow is:
1. Checkout the istio repository (which contains the config YAML files in `prow/skip_tests/`)
2. Download the parser script from this repository
3. Run the parser with the config file

See section about [Parsing Configuration script](#parsing-configuration-script) for more info.

## Parsing Configuration script

### Requirements

- **yq** (YAML processor) must be installed
  - macOS: `brew install yq`
  - Linux: `snap install yq` or download from https://github.com/mikefarah/yq


```bash
./parse-test-config.sh <config_file> <suite> <stream>
```

**Parameters:**
- `config_file` - Path to YAML configuration file (e.g., `prow/skip_tests/skip_tests_full.yaml` in openshift-service-mesh/istio repo)
- `suite` - Test suite name (pilot, security, ambient, telemetry, or helm)
- `stream` - **Required**. Filter tests by stream: `midstream_sail`, `midstream_helm`, or `downstream`

**Examples:**

```bash
# Parse full tests for security suite in midstream_sail
./parse-test-config.sh prow/skip_tests/skip_tests_full.yaml security midstream_sail

# Parse full tests for pilot suite in midstream_helm
./parse-test-config.sh prow/skip_tests/skip_tests_full.yaml pilot midstream_helm

# Parse smoke tests for pilot in downstream
./parse-test-config.sh prow/skip_tests/skip_tests_smoke.yaml pilot downstream
```

**Output:**

```
SKIP_PARSER_SKIP_TESTS='TestGateway/managed-owner|TestGatewayConformance'
SKIP_PARSER_SKIP_SUBSUITES=''
SKIP_PARSER_RUN_TESTS_ONLY=''
SKIP_PARSER_SUITE='pilot'
```

### Using parse-test-config.sh script to set correct ENV

```bash
# After checking out openshift-service-mesh/istio repository

# Download parser script from ci-utils
curl -sLO https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/skip_tests/parse-test-config.sh
chmod +x ./parse-test-config.sh

# Parse and execute for midstream_sail (full tests)
eval $(./parse-test-config.sh prow/skip_tests/skip_tests_full.yaml security midstream_sail)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"

# Parse and execute for midstream_helm (full tests)
eval $(./parse-test-config.sh prow/skip_tests/skip_tests_full.yaml security midstream_helm)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"

# Parse and execute for downstream (smoke tests)
eval $(./parse-test-config.sh prow/skip_tests/skip_tests_smoke.yaml security downstream)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"
```

### Stream Filtering Behavior

The parser returns only tests where the `skip_in` field contains the specified stream value.

**Example Configuration:**
```yaml
security:
  skip_tests:
    - name: "TestA"
      skip_in: ['midstream_sail']
    - name: "TestB"
      skip_in: ['midstream_helm']
    - name: "TestC"
      skip_in: ['downstream']
    - name: "TestD"
      skip_in: ['midstream_sail', 'midstream_helm']
    - name: "TestE"
      skip_in: ['midstream_sail', 'downstream']
    - name: "TestF"
      skip_in: ['midstream_sail', 'midstream_helm', 'downstream']
```

**Filter Results:**
- `midstream_sail` parameter returns: `TestA|TestD|TestE|TestF`
- `midstream_helm` parameter returns: `TestB|TestD|TestF`
- `downstream` parameter returns: `TestC|TestE|TestF`
