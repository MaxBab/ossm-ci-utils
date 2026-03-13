# AWS Dangling Resources Scanner

Find unused AWS resources across your account. Simple bash script that scans everything and tells you what's probably safe to delete.

## What it does

- Scans all AWS regions for resources (EC2, S3, RDS, ELB, etc.)
- Identifies potentially unused/dangling resources
- Prioritizes them by deletion safety
- Keeps your data private (no account IDs exposed)

## Prerequisites

- AWS CLI installed and configured
- Basic read permissions (see IAM section below)

## Quick Start

```bash
# Scan everything (recommended first run)
./scan_aws_resources.sh --dry-run

# Actually run it and create reports
./scan_aws_resources.sh

# Interactive mode if you want guidance
./scan_aws_resources.sh --interactive
```

## Advanced Usage

```bash
# Specific regions only
./scan_aws_resources.sh --regions us-east-1,us-west-2

# Specific resource types
./scan_aws_resources.sh --resources ec2,s3,rds
```

## Required IAM Permissions

Attach this policy for read-only scanning:
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "ec2:Describe*",
            "s3:ListAllMyBuckets", "s3:ListBucket", "s3:GetBucketTagging",
            "rds:Describe*",
            "elasticloadbalancing:Describe*",
            "lambda:ListFunctions",
            "iam:ListRoles",
            "logs:DescribeLogGroups"
        ],
        "Resource": "*"
    }]
}
```

## What You Get

Three files with your results:
- `dangling-resources-report.txt` - Full summary with inventory and recommendations
- `findings.csv` - Detailed resource list for analysis
- `cleanup-guidance.txt` - Safety tips and cleanup commands

## Example Output

```
AWS DANGLING RESOURCES SCAN
============================
Total resources found: 47 across 3 regions

HIGH PRIORITY (Likely Safe to Delete):
- 2 unattached EBS volumes
- 1 unassociated Elastic IP
- 3 empty S3 buckets

MEDIUM PRIORITY (Validate First):
- 3 load balancers with no targets
- 2 stopped instances (>30 days old)
- 1 RDS instance (check usage!)
```

## Safety Features

- **Dry run mode** - test without creating files
- **Risk categories** - High/Medium/Low priority for safe cleanup
- **Production detection** - automatically flags prod-tagged resources
- **Privacy first** - no sensitive IDs in output

## What Gets Scanned

- **EC2**: Instances, volumes, snapshots, Elastic IPs
- **S3**: Buckets and basic content analysis
- **RDS**: Instances and snapshots
- **ELB**: All load balancer types
- **Lambda**: Functions (basic listing)

## Quick Safety Tips

1. Always run `--dry-run` first
2. Start with HIGH priority items (safest)
3. Double-check anything in production accounts
4. Validate RDS resources carefully - they usually have data!
5. Check with your team for MEDIUM priority items

## Troubleshooting

**Credentials issue?**
```bash
aws sts get-caller-identity  # Check if you're authenticated
```

**Permission errors?**
```bash
aws ec2 describe-regions  # Test basic permissions
```

**Can't access some regions?**
Use `--regions` to specify only the regions you can access.

## Claude Code Integration

Run as a skill:
```bash
/aws-dangling-resources
```
