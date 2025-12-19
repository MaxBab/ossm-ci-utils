# OSSM Release Confidence Score AI Helper

## Overview

This AI helper implements the Next-Gen OSSM Release Process by calculating a data-driven release confidence score (1-10) for OSSM builds. It leverages AI to analyze test results from Report Portal and other sources to enable faster, more informed release decisions.

## Project Context

**Jira Epic**: [OSSM-11131](https://issues.redhat.com/browse/OSSM-11131)
**Owner**: Francisco Herrera

### Goals
- Establish data-driven quality gates for releases
- Accelerate time-to-release while maintaining quality
- Maximize automation efficiency in testing
- Reduce manual interventions and redundant steps

### Current Challenges
- High time release cycle
- Uncertain release confidence based on manual assessment
- Over-testing in midstream/downstream without clear metrics
- Manual steps consuming significant time

## Technical Architecture

### Data Sources
1. **Report Portal**: Primary source for test execution data
   - Pass/fail rates across all stages
   - Flaky test identification
   - Test duration and performance metrics
   - Critical defect tracking

2. **Version Tracking**: Component version correlation
   - OSSM Operator version
   - Istio version
   - Sail Operator version
   - Build ID and timestamps

3. **Future Integration** (via Apache DevLake WIP):
   - Jira issue data
   - Historical release trends

### Integration Method
- **MCP Server**: Use Report Portal MCP server for standardized data access
- **AI-Driven Analysis**: Prompts and reasoning for score calculation
- **Quality Gates**: Automated decision points based on confidence thresholds

## Test Scope-Based Confidence Calculation

### Test Scope Determination

Before calculating confidence, the system determines the required test scope based on the nature of changes:

**FULL Scope Triggers:**
- New minor OSSM version releases (3.1, 3.2, 3.3, etc.)

**CORE Scope Triggers:**
- Code changes in istio/proxy/ztunnel midstream repos
- Istio patch version updates (e.g., 1.26.5 → 1.26.6)
- CVE fixes in our codebase
- Code changes in sail operator repo

**BASIC Scope Triggers:**
- Auto base image updates in Konflux

### Core Factors (Weighted)

1. **Test Pass Rate (25% weight)**
   - Overall percentage of passing tests across required scope
   - Stage-specific pass rates (upstream, midstream, downstream)
   - Platform-specific pass rates
   - Threshold: >95% excellent, >85% good, <85% concerning

2. **Test Coverage Completeness (25% weight)**
   - Percentage of required test matrix actually executed
   - Platform coverage vs required platforms
   - Environment coverage vs required environments
   - Test suite coverage vs required test suites
   - Threshold: 100% required, >90% acceptable, <90% concerning

3. **Flaky Test Ratio (20% weight)**
   - Percentage of tests with inconsistent results
   - Historical flakiness patterns
   - Threshold: <5% excellent, <15% acceptable, >15% problematic

4. **Critical Defects (20% weight)**
   - Number of blocking/P0 test failures
   - Security-related failures
   - Performance regression indicators

5. **Version Stability (10% weight)**
   - Major vs minor vs patch release assessment
   - Pre-release indicators (RC, beta, alpha)
   - Component version compatibility

### Testing Stages Coverage

- **Upstream Testing**: Source repository validation
- **Midstream Testing**: OpenShift integration testing
- **Downstream Testing**: Final release validation

### Test Matrix Requirements by Scope

**FULL Scope Requirements:**
- **Test Suites**: O+II+KI+KU+KO+U+GIE (where applicable)
- **Platforms**: OSP, AWS, ROSA, ARO, IBM Z & P
- **Environments**: Normal, FIPS, Disconnected, IPv6, DualStack, ARM
- **OCP Coverage**: All compatible versions for OSSM version

**CORE Scope Requirements:**
- **Test Suites**: O+II+KI+KU+KO+U
- **Platforms**: AWS, ROSA, ARO, IBM Z & P
- **Environments**: Normal, FIPS, ARM
- **OCP Coverage**: Primary versions

**BASIC Scope Requirements:**
- **Test Suites**: O+II+KI+KU
- **Platforms**: AWS, ROSA, IBM Z & P
- **Environments**: Normal, FIPS
- **OCP Coverage**: Latest primary versions

## Usage Patterns

### Basic Usage
```bash
/ossm-confidence
```
Then provide:
- Build ID or release candidate
- **Type of changes in the build** (to determine FULL/CORE/BASIC scope)
- Target confidence threshold
- OSSM version being tested
- Specific testing stage focus (optional)

### Advanced Analysis
- Test scope compliance validation
- Platform-specific test coverage analysis
- Historical trend comparison
- Stage-specific deep dive
- Component version impact assessment
- Flaky test investigation
- Missing test matrix identification

## Output Format

### Summary View
- Overall confidence score (1-10)
- **Test scope determination and compliance status**
- Pass/fail breakdown by stage and platform
- Critical issues requiring attention
- **Missing test coverage items**
- Release recommendation (GO/NO-GO/SCOPE NOT MET)

### Detailed Analysis
- Weighted score breakdown
- **Test matrix compliance analysis**
- Stage-specific metrics by platform and environment
- **Platform and environment coverage gaps**
- Flaky test identification
- **Scope-specific test suite execution status**
- Historical comparison
- Actionable recommendations


---

*This helper is part of the Next-Gen OSSM Release Process initiative to enhance delivery pipeline efficiency through AI-driven quality gates and data-driven decision making.*