# Test Configuration Management

This directory contains centralized info about skipping tests for Istio integration tests. All test runners (midstream, Jenkins, etc.) should use these configuration files to ensure consistency across environments.

## Table of Contents

- [Overview](#overview)
- [Files](#files)
- [Configuration Structure](#configuration-structure)
  - [Supported Test Suites](#supported-test-suites)
  - [The `skip_in` Field (Required)](#the-skip_in-field-required)
  - [The `skip_branches_only` Field (Optional)](#the-skip_branches_only-field-optional)
- [Usage](#usage)
- [Best Practices](#best-practices)
  - [Reason Field Guidelines](#reason-field-guidelines)
  - [Using skip_in Field Effectively](#using-skip_in-field-effectively)
  - [Using skip_branches_only Field Effectively](#using-skip_branches_only-field-effectively)
  - [When to Use Each Configuration](#when-to-use-each-configuration)
  - [Empty Arrays](#empty-arrays)
- [Parsing Configuration Script](#parsing-configuration-script)
  - [Requirements](#requirements)
  - [Using parse-test-config.sh Script](#using-parse-test-configsh-script-to-set-correct-env)
  - [Stream Filtering Behavior](#stream-filtering-behavior)
  - [Branch Filtering Behavior](#branch-filtering-behavior)
  - [Combined Filtering Logic](#combined-filtering-logic)

## Overview

The configuration system manages test execution parameters for the `integ-suite-ocp.sh` script:

```bash
integ-suite-ocp.sh ${test_suite} ${skip_tests} ${skip_subsuites} ${run_tests_only}
```

## Files

- **test-config-full.yaml** - Configuration for full test suite runs
- **test-config-smoke.yaml** - Configuration for smoke test runs
- **parse-test-config.sh** - Parser script to extract configuration, set ENVs and generate command

## Configuration Structure

Each YAML file contains configuration for all test suites:

```yaml
test_suites:
  <suite_name>:
    skip_tests:
      - name: "test_name"
        reason: "Why this test is skipped"
        skip_in: ['midstream', 'downstream']     # Required: specify where to skip
        skip_branches_only: ['master', 'main']   # Optional: skip only on these branches
    skip_subsuites:
      - name: "subsuite_name"
        reason: "Why this subsuite is skipped"
        skip_in: ['downstream']                  # Required: specify where to skip
        skip_branches_only: ['release-1.24']     # Optional: skip only on these branches
    run_tests_only:
      - name: "test_name"
        reason: "Why only this test runs"
        skip_in: ['midstream']                   # Required: specify where to run
        skip_branches_only: ['master']           # Optional: run only on these branches
```

### Supported Test Suites

- `pilot`
- `security`
- `ambient`
- `telemetry`
- `helm`

### The `skip_in` Field (Required)

The `skip_in` field is **required** for all test entries and specifies where a test should be skipped or run. This enables different test configurations for midstream and downstream environments.

**Values:**
- `['midstream']` - Skip/run only in midstream testing
- `['downstream']` - Skip/run only in downstream testing
- `['midstream', 'downstream']` - Skip/run in both environments

**Examples:**

```yaml
skip_tests:
  # Skip only in downstream
  - name: "TestAuthz_CustomServer"
    reason: "Feature not available in downstream"
    skip_in: ['downstream']

  # Skip only in midstream
  - name: "TestGatewayConformance"
    reason: "Requires setup only available in downstream"
    skip_in: ['midstream']

  # Skip in both (or omit skip_in entirely for same effect)
  - name: "TestCNIVersionSkew"
    reason: "Not supported in either environment"
    skip_in: ['midstream', 'downstream']
```

### The `skip_branches_only` Field (Optional)

In addition to `skip_in`, you can use the `skip_branches_only` field to control test skipping on specific branches.

When specified, the test is skipped **only** on the listed branches. If not specified, the test is skipped on **all** branches (when the stream matches).

**Use cases:**
 Tests that should be skipped only on specific branches (e.g., master/main)
 Feature tests that are broken only on certain release branches
 Tests that require branch-specific infrastructure
 Upgrade tests that don't apply to certain release branches

**Examples:**

```yaml
# Skip only on master branch in midstream
 name: "TestGateway"
 reason: "Gateway conformance tests fail on master due to API changes"
 skip_in: ['midstream']
 skip_branches_only: ['master']
  # Result: Skipped on master in midstream, runs on other branches in midstream

# Skip only on specific release branches
 name: "TestNewFeature"
  reason: "Feature not backported to these releases"
  skip_in: ['midstream']
  skip_branches_only: ['release-1.23', 'release-1.24']
  # Result: Skipped on release-1.23 and release-1.24 in midstream, runs on other branches

# Skip on all branches (no skip_branches_only field)
 name: "TestBroken"
  reason: "Test is broken everywhere"
  skip_in: ['midstream', 'downstream']
  # Result: Skipped on all branches in both streams
```

## Usage
The definition YAML files can be downloaded via curl and parsed directly in the environment.

The repository also contains a script that automatically parses the YAML file and sets the specific environment variables. You can use it instead of doing the parsing by yourself.
See section about [Parsing Configuration script](#parsing-configuration-script) for more info.

## Best Practices

### Reason Field Guidelines

Always provide clear, actionable reasons for skipping tests:

**Good reasons:**
- `"Requires external CA not configured in test environment"`
- `"Known flakiness in CI environment - tracking in JIRA-1234"`
- `"QUIC support not enabled in current test infrastructure"`
- `"Deprecated - will be removed in next release"`
- `"Scale tests run separately in performance suite"`

**Bad reasons:**
- `"Broken"` ❌ (not informative)
- `"TODO"` ❌ (no context)
- `"Doesn't work"` ❌ (not actionable)

### Using skip_in Field Effectively

**When to use `skip_in: ['midstream']`:**
- Test requires features only in downstream releases
- Test uses downstream-specific infrastructure or configurations
- Test validates downstream-only behavior

**When to use `skip_in: ['downstream']`:**
- Test requires upstream/development features not yet in downstream
- Test validates midstream-specific behavior
- Test uses experimental features

**When to use `skip_in: ['midstream', 'downstream']`:**
- Test is broken or incompatible in all environments
- Test requires infrastructure not available anywhere
- Consistent behavior across both streams

**Examples:**

```yaml
# Test is working only on midstream, not working on downstream
- name: "TestExperimentalAPI"
  reason: "Experimental API not released to downstream yet"
  skip_in: ['downstream']

# Broken everywhere
- name: "TestFlakyTest"
  reason: "Known flakiness in all environments - JIRA-1234"
  skip_in: ['midstream', 'downstream']
```

### Using skip_branches_only Field Effectively

**When to use `skip_branches_only`:**
- Test is broken only on specific branches
- Feature is not available on certain release branches
- Test requires branch-specific infrastructure

**When NOT to use `skip_branches_only`:**
- Test is broken on all branches (omit the field)
- Test behavior is consistent across all branches

**Examples:**

```yaml
# Skip test only on specific release branches - test is working all other branches
- name: "TestBackportedFix"
  reason: "Fix not backported to these releases"
  skip_in: ['midstream']
  skip_branches_only: ['release-1.23', 'release-1.24']

# Skip on all branches (no skip_branches_only), test is not working with our setup
- name: "TestBroken"
  reason: "Test is broken everywhere"
  skip_in: ['midstream', 'downstream']
```

### When to Use Each Configuration

**test-config-full.yaml:**
- Complete test coverage for release validation
- Nightly CI runs
- Pre-merge verification for critical changes
- Skip only tests that are truly incompatible with the environment

**test-config-smoke.yaml:**
- Quick validation during development
- Pre-merge checks for standard PRs
- Sanity checks before full test runs
- Use `run_tests_only` to limit scope to critical tests

### Empty Arrays

If a suite has no skipped tests or subsuites, use empty arrays:

```yaml
test_suites:
  ambient:
    skip_tests: []
    skip_subsuites: []
    run_tests_only: []
```

## Parsing Configuration script

### Requirements

- **yq** (YAML processor) must be installed
  - macOS: `brew install yq`
  - Linux: `snap install yq` or download from https://github.com/mikefarah/yq


```bash
./parse-test-config.sh <config_file> <suite> <stream> [branch]
```

**Parameters:**
- `config_file` - Path to YAML configuration file (test-config-full.yaml or test-config-smoke.yaml)
- `suite` - Test suite name (pilot, security, ambient, telemetry, or helm)
- `stream` - **Required**. Filter tests by stream: `midstream` or `downstream`
- `branch` - **Optional**. Branch name for branch-specific filtering (e.g., `master`, `release-1.24`)

**Examples:**

```bash
# Parse tests for security suite in midstream (no branch filtering)
./parse-test-config.sh test-config-full.yaml security midstream

# Parse tests for security suite in downstream (no branch filtering)
./parse-test-config.sh test-config-full.yaml security downstream

# Parse tests for pilot in midstream on master branch
./parse-test-config.sh test-config-full.yaml pilot midstream master

# Parse tests for helm in midstream on release-1.24 branch
./parse-test-config.sh test-config-full.yaml helm midstream release-1.24

# Parse smoke tests for pilot in downstream on main branch
./parse-test-config.sh test-config-smoke.yaml pilot downstream main
```

**Output (midstream):**

```
=== Setting Environment Variables ===
STREAM='midstream' (filtering tests for this stream)
SKIP_PARSER_SUITE='pilot'
SKIP_PARSER_SKIP_TESTS='TestGateway/managed-owner|TestGatewayConformance'
SKIP_PARSER_SKIP_SUBSUITES=''
SKIP_PARSER_RUN_TESTS_ONLY=''

Final command:
integ-suite-ocp.sh pilot 'TestGateway/managed-owner|TestGatewayConformance' '' ''
```

### Using parse-test-config.sh script to set correct ENV

```bash
# Download config file from central location
curl -O https://raw.githubusercontent.com/mkralik3/ci-utils/refs/heads/skiptests/skip_tests/test-config-full.yaml

# Download script for setting ENVs
curl -O https://raw.githubusercontent.com/mkralik3/ci-utils/refs/heads/skiptests/skip_tests/parse-test-config.sh
chmod +x ./parse-test-config.sh

# Parse and execute for midstream (no branch filtering)
eval $(./parse-test-config.sh test-config-full.yaml security midstream)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"

# With branch filtering for release branch in downstream
BRANCH_NAME="release-1.24"
eval $(./parse-test-config.sh test-config-full.yaml security downstream $BRANCH_NAME)
integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"
```

### Stream Filtering Behavior

The parser returns only tests where the `skip_in` field contains the specified stream value.

**Example Configuration:**
```yaml
security:
  skip_tests:
    - name: "TestA"
      skip_in: ['midstream']
    - name: "TestB"
      skip_in: ['downstream']
    - name: "TestC"
      skip_in: ['midstream', 'downstream']
```

**Filter Results (without branch filtering):**
- `midstream` parameter returns: `TestA|TestC`
- `downstream` parameter returns: `TestB|TestC`

### Branch Filtering Behavior

When a branch parameter is provided, the parser applies an additional filter on top of stream filtering using the `skip_branches_only` field.

**Example Configuration:**
```yaml
pilot:
  skip_tests:
    - name: "TestA"
      skip_in: ['midstream']
      skip_branches_only: ['master']
    - name: "TestB"
      skip_in: ['midstream']
      skip_branches_only: ['release-1.24']
    - name: "TestC"
      skip_in: ['midstream']
      skip_branches_only: ['master', 'release-1.24']
    - name: "TestD"
      skip_in: ['midstream']
```

**Filter Results:**
- `midstream master` returns: `TestA|TestC|TestD` (TestB - not in skip_branches_only for master)
- `midstream release-1.24` returns: `TestB|TestC|TestD` (TestA - not in skip_branches_only for release-1.24)
- `midstream release-1.23` returns: `TestD` (TestA, TestB, TestC - not in skip_branches_only for release-1.23)
- `midstream` (no branch) returns: `TestA|TestB|TestC|TestD` (all tests, branch filtering not applied)
