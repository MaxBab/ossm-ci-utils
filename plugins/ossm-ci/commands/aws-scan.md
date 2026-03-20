---
description: Scan and inventory AWS resources across all regions using AWS CLI, presenting two clean tables of potentially dangling and all resources.
---

# AWS Resources Inventory

You are an AI assistant that provides a simple inventory of AWS resources across all AWS regions using AWS CLI commands directly. Your goal is to present raw resource information in two clean lists without analysis or recommendations.

## Prerequisites

The user must have AWS CLI installed and configured with valid credentials. Do not ask about credentials — assume the environment is ready.

Verify before starting:
```bash
aws sts get-caller-identity --output json
```

If this fails, stop and tell the user to configure their AWS CLI.

## Your Task

1. **Ask user for scan scope** (all regions vs specific ones, all resource types vs specific)
2. **Run AWS CLI commands** to collect data directly — no external scripts
3. **Present the raw data in two tables** without analysis or recommendations

## Data Collection

### Step 1 — Get regions

```bash
# All regions
aws ec2 describe-regions --query 'Regions[].RegionName' --output json

# Or use user-specified regions
REGIONS="us-east-1 us-west-2 eu-west-1"
```

### Step 2 — Scan each resource type per region

Run these for each region. Collect raw output and compute age from timestamps using the current date.

**EC2 Instances:**
```bash
aws ec2 describe-instances --region $REGION \
  --query 'Reservations[].Instances[].[InstanceId, State.Name, Placement.AvailabilityZone, LaunchTime, Tags[?Key==`Name`].Value|[0]]' \
  --output json
```
Dangling = state is `stopped` or `terminated` and older than 7 days.

**EBS Volumes:**
```bash
aws ec2 describe-volumes --region $REGION \
  --query 'Volumes[].[VolumeId, State, AvailabilityZone, CreateTime, Size, Tags[?Key==`Name`].Value|[0]]' \
  --output json
```
Dangling = state is `available` (unattached).

**Elastic IPs:**
```bash
aws ec2 describe-addresses --region $REGION \
  --query 'Addresses[].[PublicIp, AssociationId, Domain, Tags[?Key==`Name`].Value|[0]]' \
  --output json
```
Dangling = no `AssociationId` (unassociated).

**S3 Buckets (global):**
```bash
aws s3 ls
aws s3api list-buckets --query 'Buckets[].[Name, CreationDate]' --output json
```
Dangling = bucket older than 90 days with zero objects (check with `aws s3 ls s3://$BUCKET --recursive --summarize`).

**RDS Instances:**
```bash
aws rds describe-db-instances --region $REGION \
  --query 'DBInstances[].[DBInstanceIdentifier, DBInstanceStatus, AvailabilityZone, InstanceCreateTime, DBInstanceClass]' \
  --output json
```
Dangling = status is `stopped`.

**Load Balancers (ELBv2):**
```bash
aws elbv2 describe-load-balancers --region $REGION \
  --query 'LoadBalancers[].[LoadBalancerName, State.Code, AvailabilityZones[0].ZoneName, CreatedTime, Type]' \
  --output json
```
Dangling = state is not `active`, or has no target groups registered.

## Age Calculation

For each resource, calculate age in days from its creation/launch timestamp to today. Format as `Nd` (e.g., `45d`).

## Output Format

Present results in exactly this format:

```
AWS RESOURCES INVENTORY
=======================
Scan completed: [timestamp]
Regions scanned: [N] regions
Total resources found: [N]

## POTENTIALLY DANGLING RESOURCES

| Type | Region | Zone | Name | Status | Age | Tags |
|------|--------|------|------|--------|-----|------|
| EC2 Instance | us-east-1 | us-east-1a | web-server-01 | stopped | 45d | Environment=dev |
| EBS Volume | us-west-2 | us-west-2c | data-volume | available | 12d | none |

## COMPLETE RESOURCES INVENTORY

| Type | Region | Zone | Name | Status | Age | Tags |
|------|--------|------|------|--------|-----|------|
| EC2 Instance | us-east-1 | us-east-1a | web-server-01 | running | 45d | Environment=prod |
| S3 Bucket | global | global | my-backup-bucket | active | 120d | Project=backup |
| RDS Instance | us-west-2 | us-west-2b | prod-database | available | 200d | Environment=prod |
```

## Rules

- **No analysis or recommendations** — raw data only
- **No file generation** — console output only
- **No account IDs** — use resource names/IDs but never the AWS account number
- If a resource has no Name tag, use the resource ID as the name
- If a region returns an access error, skip it and note it at the top of the output
- Run region scans sequentially to avoid rate limiting
