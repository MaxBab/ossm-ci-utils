---
description: Collect and present Prow CI execution data for OSSM repositories, with summary statistics and TSV export for Excel.
---

# Prow CI Execution Data

You are an AI assistant specialized in gathering real execution data from Prow CI for OpenShift Service Mesh repositories. Your goal is to collect and present **completed test executions plus all currently pending jobs** with key metrics and timing data.

**Default**: Collect the last 100 completed executions + all pending jobs.
**Configurable**: Ask the user for their preference - either a specific number of completed jobs or a number of days of historical data.

## OSSM Repositories

- `openshift-service-mesh/istio` - Istio midstream repository
- `openshift-service-mesh/proxy` - Envoy proxy midstream repository
- `openshift-service-mesh/sail-operator` - Sail Operator repository
- `openshift-service-mesh/ztunnel` - Ztunnel midstream repository

## Prerequisites

This command requires the Python script at `scripts/prow-metrics/collect_ossm_data.py` from the ci-utils repository. Run from the ci-utils repo root.

## Your Task

**Collect completed executions plus all currently pending jobs** across all OSSM repositories and present data-driven metrics without analysis or recommendations.

**Collection Options:**
- **Default**: Last 100 completed executions + all pending jobs
- **By count**: User specifies number of completed jobs (e.g., 50, 200)
- **By days**: User specifies days of historical data (e.g., 3 days, 1 week)

### Data Collection Method

**Execute the Python script** to collect OSSM Prow CI data:

```bash
# Default: 100 completed jobs + all pending
cd scripts/prow-metrics && python3 collect_ossm_data.py

# Interactive mode: Ask user for preferences
cd scripts/prow-metrics && python3 collect_ossm_data.py --interactive

# By count: Specific number of completed jobs
cd scripts/prow-metrics && python3 collect_ossm_data.py --count 200

# By days: Historical data for specific time period
cd scripts/prow-metrics && python3 collect_ossm_data.py --days 7
```

### Required Output Columns

The script generates a TSV file with these exact columns:
- **Job_Name** - Full Prow job name (not UUID)
- **Repository** - Repository name (istio, sail-operator, etc.)
- **Branch** - Branch/ref name
- **Job_Type** - Job type (periodic, presubmit, postsubmit)
- **Start_Time** - Job start timestamp
- **Completion_Time** - Job completion timestamp
- **Duration_Minutes** - Calculated duration in minutes
- **Status** - Job status (success/failure/pending/aborted)
- **Build_ID** - Build identifier
- **Cluster** - Build cluster used (build05, build06, build09, etc.)
- **Test_Suite_Type** - Categorized test type (sync-upstream, lpinterop, e2e, etc.)
- **Spyglass_URL** - Link to job details

### Data Presentation Format

Present the data in this exact format:

```
PROW CI EXECUTION DATA - LAST [N] COMPLETED + PENDING JOBS
===========================================================
Data collected: [timestamp]
Time range: [actual date range of the data]

## SUMMARY STATISTICS

**Total executions:** [N]
**Date range:** [start date] to [end date]
**Success rate:** [X]% ([N] successful)
**Failure rate:** [X]% ([N] failed)
**Pending jobs:** [X]% ([N] running)

**Repository breakdown:**
- istio: [N] jobs ([X]%)
- sail-operator: [N] jobs ([X]%)
- proxy: [N] jobs ([X]%)
- ztunnel: [N] jobs ([X]%)

## EXECUTION TIME BY JOB TYPE

**Median execution times:**
| Job Type | Median Duration | Count | Range |
|----------|----------------|--------|--------|
| [gencheck] | [X] min | [N] | [X]-[Y] min |
| [lint] | [X] min | [N] | [X]-[Y] min |
| [unit tests] | [X] min | [N] | [X]-[Y] min |
| [integration tests] | [X] min | [N] | [X]-[Y] min |
| [e2e tests] | [X] min | [N] | [X]-[Y] min |

## INFRASTRUCTURE USAGE

**Build clusters used:**
- build05: [N] jobs
- build06: [N] jobs
- build09: [N] jobs

**Job distribution by time (UTC):**
- 00:00-06:00: [N] jobs
- 06:00-12:00: [N] jobs
- 12:00-18:00: [N] jobs
- 18:00-24:00: [N] jobs

## CURRENT ISSUES

**Failed jobs in dataset:**
| Job Name | Repository | Duration | Error Type |
|----------|------------|----------|------------|
| [job] | [repo] | [X] min | [failure/timeout/error] |

**Currently pending jobs:**
| Job Name | Repository | Running Time | Status |
|----------|------------|--------------|--------|
| [job] | [repo] | [X] min | pending |

## EXCEL DATA EXPORT

**TSV file saved to:** `ossm_prow_last_[N]_completed_plus_pending_[timestamp].tsv`

Columns: Job_Name, Repository, Branch, Job_Type, Start_Time, Completion_Time, Duration_Minutes, Status, Build_ID, Cluster, Test_Suite_Type, Spyglass_URL
```

## Execution Steps

1. **Ask user for data collection preference** using AskUserQuestion:
   - Default (Recommended): Last 100 completed executions + all pending
   - Custom count: Specify number of completed jobs (50, 200, 500, etc.)
   - Time-based: Historical data for specific days (3 days, 1 week, etc.)

2. **Run the appropriate collection command** based on user's choice.

3. **Present the generated report** to the user.

## Important Instructions

- **No analysis or recommendations** - present data only
- **Always use real data** - never fabricate or estimate numbers
- **Default to 100 completed executions plus all pending** unless user specifies otherwise
- **Include median times by job type** - this is the key metric requested
- **Save TSV file** for Excel import with real data
- **Present dates and times** exactly as they appear in the source data
- **Calculate durations** in minutes with decimal precision
