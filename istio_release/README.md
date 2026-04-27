# Cherry-Pick List Generator

This script automates the generation of cherry-pick lists for OSSM (OpenShift Service Mesh) release branches based on downstream changes tracked in the [openshift-service-mesh/.github](https://github.com/openshift-service-mesh/.github) repository.

## Overview

When creating a new OSSM release branch (which is based on upstream Istio), this script helps identify which downstream-specific commits need to be cherry-picked from the previous release. It fetches commit metadata from the `.github` repository and generates:

1. A shell script with `git cherry-pick` commands
2. A report of commits that have already synced from upstream
3. Organized lists of permanent and pending-upstream commits

## How It Works

The script:

1. Fetches a YAML file from `openshift-service-mesh/.github/main/downstream-changes/istio_release-<VERSION>.yaml`
2. Parses two types of commits:
   - **Permanent downstream changes** (`isPermanent: true`) - Changes that will always remain OSSM-specific
   - **Pending upstream sync** (`isPendingUpstreamSync: true`) - Changes awaiting upstream merge
3. For pending commits, checks if they already exist in the target branch (indicating successful upstream sync)
4. Sorts all commits chronologically (oldest first) to maintain dependencies
5. Generates executable cherry-pick scripts and reports

## Prerequisites

- `yq` v4.x or higher ([installation](https://github.com/mikefarah/yq))
- `curl`
- `git`
- Access to the repository with git history

## Installation

### From istio Repository

When working on a new release branch, download the script from the `ci-utils` repository:

```bash
cd /path/to/istio-ossm

# Download the script
curl -sSfL https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/scripts/generate_cherrypick_list.sh -o generate_cherrypick_list.sh

# Make it executable
chmod +x generate_cherrypick_list.sh
```

## Usage

### Basic Syntax

```bash
./generate_cherrypick_list.sh --target <RELEASE_VERSION> [--source <SOURCE_VERSION>]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--target` | Yes | Target release version you're working on |
| `--source` | No | Source release version to fetch commits from (auto-calculated as N-1 if not provided) |

### Examples

#### Example 1: Normal Release (Sequential Versions)

Creating release-1.29 based on release-1.28:

```bash
./generate_cherrypick_list.sh --target 1.29
```

The script automatically calculates the source version as `1.28` (N-1).

#### Example 2: Skipping Versions

Creating release-1.30 but the previous OSSM release was 1.28 (skipping 1.29):

```bash
./generate_cherrypick_list.sh --target 1.30 --source 1.28
```

#### Example 3: Using release- Prefix

The script accepts version with or without the `release-` prefix:

```bash
./generate_cherrypick_list.sh --target release-1.29
```

## Output

### Generated Files

#### 1. Cherry-Pick Script
`cherry-pick-to-release-<VERSION>.sh`

Executable shell script containing all `git cherry-pick` commands in chronological order:

```bash
#!/bin/bash
# Auto-generated cherry-pick script
...

# PERMANENT DOWNSTREAM CHANGES
git cherry-pick abc123def456...
git cherry-pick 789ghi012jkl...

# PENDING UPSTREAM SYNC
git cherry-pick mno345pqr678...
```

Execute it with:
```bash
./cherry-pick-to-release-1.30.sh
```

#### 2. Upstream Sync Report (if applicable)
`upstream-sync-report-<VERSION>.txt`

Lists commits that were marked as "pending upstream sync" but are already present in the target branch, indicating successful upstream synchronization.

### Terminal Output

The script displays:
- Summary statistics (permanent, pending, synced commits)
- Detailed commit lists organized by type
- Status messages during processing

Example output:
```
INFO: Starting cherry-pick list generation...
INFO: Target release version: release-1.30
INFO: Source release version (explicit): release-1.28

INFO: Fetching YAML from: https://raw.githubusercontent.com/...
SUCCESS: YAML file fetched successfully

INFO: Parsing permanent downstream commits...
SUCCESS: Found and sorted permanent commits by date (oldest first)

INFO: Parsing pending-upstream-sync commits...
SUCCESS: Found and sorted pending commits by date (oldest first)

==========================================
Cherry-Pick Summary
==========================================
Permanent downstream changes:          5
Pending upstream sync (not in target): 3
Pending upstream sync (already synced): 2
------------------------------------------
Total commits to cherry-pick:          8
==========================================

SUCCESS: Cherry-pick script generated: cherry-pick-to-release-1.30.sh
SUCCESS: Upstream sync report generated: upstream-sync-report-1.30.txt
```

## Workflow: Creating a New Release Branch

### Step 1: Create Cherry-pick Branch from Release Branch

```bash
# Prepare cherry-pick branch
git checkout release-1.30
git checkout -b ossm-cherry-picks-for-release-1.30
```

### Step 2: Download and Run the Script

```bash
# Download from ci-utils
curl -sSfL https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/scripts/generate_cherrypick_list.sh -o generate_cherrypick_list.sh
chmod +x generate_cherrypick_list.sh

# Generate cherry-pick list
# If previous OSSM release was 1.28 and you're creating 1.30:
./generate_cherrypick_list.sh --target 1.30 --source 1.28
```

### Step 3: Review Generated Output

Review the cherry-pick script and upstream sync report:

```bash
# Review what will be cherry-picked
cat cherry-pick-to-release-1.30.sh

# Review what already synced from upstream
cat upstream-sync-report-1.30.txt
```

### Step 4: Execute Cherry-Picks

```bash
# Execute the generated script
./cherry-pick-to-release-1.30.sh
```

### Step 5: Handle Conflicts (if any)

If cherry-pick conflicts occur:

```bash
# Resolve conflicts manually
git status
# ... edit conflicting files ...
git add <resolved-files>
git cherry-pick --continue
```

### Step 6: Push to Remote

```bash
git push origin ossm-cherry-picks-for-release-1.30
```

## Error Handling

### Missing YAML File

If the source version YAML file doesn't exist:

```
ERROR: Failed to fetch YAML file from https://...
  Possible reasons:
  - File does not exist for branch 'release-1.28'
  - Network connectivity issue
  - GitHub API rate limit exceeded

  If you are skipping versions (e.g., 1.28 -> 1.30), specify the source version:
    generate_cherrypick_list.sh --target 1.30 --source <SOURCE_VERSION>
```

**Solution**: Verify the correct source version exists at [openshift-service-mesh/.github/downstream-changes](https://github.com/openshift-service-mesh/.github/tree/main/downstream-changes)

### Missing Dependency

```
ERROR: yq is not installed. Please install yq v4.x from https://github.com/mikefarah/yq
```

**Solution**: Install the missing dependency

### Invalid Version Format

```
ERROR: Invalid version format: 1.29.0. Expected format: '1.29' or 'release-1.29'
```

**Solution**: Use MAJOR.MINOR format only (e.g., `1.29`, not `1.29.0`)

## Commit Ordering

Commits are sorted chronologically (oldest first) to preserve dependencies. If commit B depends on commit A, commit A will be cherry-picked first. This ordering is based on commit timestamps from the git repository.

## Support

For issues or questions:
- File an issue in the [openshift-service-mesh/ci-utils](https://github.com/openshift-service-mesh/ci-utils/issues) repository
- Contact the OSSM team
