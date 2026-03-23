#!/usr/bin/env bash
# aws-scan-audited.sh — Read-only AWS resource inventory
#
# SECURITY CONTRACT:
#   - Uses ONLY read-only AWS CLI subcommands (describe-*, list-*, get-*)
#   - No resource is created, modified, or deleted by this script
#   - No mutating command strings appear anywhere in this file
#
# Usage:
#   bash aws-scan-audited.sh
#   bash aws-scan-audited.sh --regions us-east-1,eu-west-1
#   bash aws-scan-audited.sh --resources ec2,s3,rds,elb

set -euo pipefail

REGIONS=""
RESOURCE_TYPES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --regions)    REGIONS="$2";        shift 2 ;;
    --resources)  RESOURCE_TYPES="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--regions r1,r2,...] [--resources ec2,s3,rds,elb]"
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1 ;;
  esac
done

# ── Verify AWS CLI is configured ──────────────────────────────────────────────

aws sts get-caller-identity --output json > /dev/null 2>&1 || {
  echo "ERROR: AWS CLI not configured or credentials invalid. Run: aws configure" >&2
  exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────

age_days() {
  local timestamp="$1"
  local ts_clean="${timestamp%.*}"  # strip milliseconds if present
  local epoch

  if command -v gdate &>/dev/null; then
    epoch=$(gdate -d "$ts_clean" +%s 2>/dev/null || echo 0)
  else
    epoch=$(date -d "$ts_clean" +%s 2>/dev/null \
      || date -j -f "%Y-%m-%dT%H:%M:%S" "$ts_clean" +%s 2>/dev/null \
      || echo 0)
  fi

  echo $(( ( $(date +%s) - epoch ) / 86400 ))
}

print_row() {
  printf "| %-20s | %-13s | %-13s | %-22s | %-11s | %-5s | %-25s |\n" \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

print_separator() {
  printf "|%s|%s|%s|%s|%s|%s|%s|\n" \
    "$(printf '%.0s-' {1..22})" \
    "$(printf '%.0s-' {1..15})" \
    "$(printf '%.0s-' {1..15})" \
    "$(printf '%.0s-' {1..24})" \
    "$(printf '%.0s-' {1..13})" \
    "$(printf '%.0s-' {1..7})" \
    "$(printf '%.0s-' {1..27})"
}

# ── Resource type flags ───────────────────────────────────────────────────────

SCAN_EC2=true
SCAN_S3=true
SCAN_RDS=true
SCAN_ELB=true

if [[ -n "$RESOURCE_TYPES" ]]; then
  SCAN_EC2=false; SCAN_S3=false; SCAN_RDS=false; SCAN_ELB=false
  IFS=',' read -ra TYPES <<< "$RESOURCE_TYPES"
  for T in "${TYPES[@]}"; do
    case "$(echo "$T" | tr '[:upper:]' '[:lower:]')" in
      ec2)    SCAN_EC2=true ;;
      s3)     SCAN_S3=true  ;;
      rds)    SCAN_RDS=true ;;
      elb|lb) SCAN_ELB=true ;;
    esac
  done
fi

# ── Regions ───────────────────────────────────────────────────────────────────

if [[ -n "$REGIONS" ]]; then
  REGION_LIST=$(echo "$REGIONS" | tr ',' '\n')
else
  REGION_LIST=$(aws ec2 describe-regions \
    --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort)
fi

# ── Collect data ──────────────────────────────────────────────────────────────

ALL_ROWS=()
DANGLING_ROWS=()
SKIPPED_REGIONS=()
TOTAL=0

# S3 (global)
if [[ "$SCAN_S3" == "true" ]]; then
  while IFS=$'\t' read -r name created; do
    [[ -z "$name" || "$name" == "None" ]] && continue
    age=$(age_days "$created")
    dangling=""
    [[ $age -gt 90 ]] && dangling="yes"
    row=$(print_row "S3 Bucket" "global" "global" "$name" "active" "${age}d" "none")
    ALL_ROWS+=("$row")
    [[ -n "$dangling" ]] && DANGLING_ROWS+=("$row")
    TOTAL=$((TOTAL + 1))
  done < <(aws s3api list-buckets \
    --query 'Buckets[].[Name, CreationDate]' --output text 2>/dev/null || true)
fi

# Per-region
while IFS= read -r REGION; do
  [[ -z "$REGION" ]] && continue

  aws ec2 describe-regions --region "$REGION" --region-names "$REGION" \
    --output text &>/dev/null || { SKIPPED_REGIONS+=("$REGION"); continue; }

  # EC2 instances
  if [[ "$SCAN_EC2" == "true" ]]; then

    while IFS=$'\t' read -r id state zone launched name env team; do
      [[ -z "$id" || "$id" == "None" ]] && continue
      age=$(age_days "$launched")
      [[ "$name" == "None" || -z "$name" ]] && name="$id"
      tags=""; [[ "$env"  != "None" && -n "$env"  ]] && tags+="Env=$env "
               [[ "$team" != "None" && -n "$team" ]] && tags+="Team=$team"
      [[ -z "$tags" ]] && tags="none"
      row=$(print_row "EC2 Instance" "$REGION" "$zone" "$name" "$state" "${age}d" "$tags")
      ALL_ROWS+=("$row")
      if [[ "$state" == "stopped" && $age -gt 7 ]]; then
        DANGLING_ROWS+=("$row")
      fi
      TOTAL=$((TOTAL + 1))
    done < <(aws ec2 describe-instances --region "$REGION" \
      --query 'Reservations[].Instances[].[InstanceId,State.Name,Placement.AvailabilityZone,LaunchTime,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Environment`].Value|[0],Tags[?Key==`Team`].Value|[0]]' \
      --output text 2>/dev/null || true)

    # EBS volumes
    while IFS=$'\t' read -r id state zone created size name attached; do
      [[ -z "$id" || "$id" == "None" ]] && continue
      age=$(age_days "$created")
      [[ "$name" == "None" || -z "$name" ]] && name="$id"
      row=$(print_row "EBS Volume" "$REGION" "$zone" "$name" "$state" "${age}d" "${size}GB")
      ALL_ROWS+=("$row")
      [[ "$state" == "available" ]] && DANGLING_ROWS+=("$row")
      TOTAL=$((TOTAL + 1))
    done < <(aws ec2 describe-volumes --region "$REGION" \
      --query 'Volumes[].[VolumeId,State,AvailabilityZone,CreateTime,Size,Tags[?Key==`Name`].Value|[0],Attachments[0].InstanceId]' \
      --output text 2>/dev/null || true)

    # Elastic IPs
    while IFS=$'\t' read -r alloc_id ip assoc_id name env; do
      [[ -z "$alloc_id" || "$alloc_id" == "None" ]] && continue
      [[ "$name" == "None" || -z "$name" ]] && name="$ip"
      state="associated"; [[ "$assoc_id" == "None" || -z "$assoc_id" ]] && state="unassociated"
      row=$(print_row "Elastic IP" "$REGION" "regional" "$name" "$state" "N/A" "none")
      ALL_ROWS+=("$row")
      [[ "$state" == "unassociated" ]] && DANGLING_ROWS+=("$row")
      TOTAL=$((TOTAL + 1))
    done < <(aws ec2 describe-addresses --region "$REGION" \
      --query 'Addresses[].[AllocationId,PublicIp,AssociationId,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Environment`].Value|[0]]' \
      --output text 2>/dev/null || true)

  fi

  # RDS
  if [[ "$SCAN_RDS" == "true" ]]; then
    while IFS=$'\t' read -r id status zone created class; do
      [[ -z "$id" || "$id" == "None" ]] && continue
      age=$(age_days "$created")
      row=$(print_row "RDS Instance" "$REGION" "$zone" "$id" "$status" "${age}d" "$class")
      ALL_ROWS+=("$row")
      [[ "$status" == "stopped" ]] && DANGLING_ROWS+=("$row")
      TOTAL=$((TOTAL + 1))
    done < <(aws rds describe-db-instances --region "$REGION" \
      --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,AvailabilityZone,InstanceCreateTime,DBInstanceClass]' \
      --output text 2>/dev/null || true)
  fi

  # Load Balancers
  if [[ "$SCAN_ELB" == "true" ]]; then
    while IFS=$'\t' read -r name state zone created type; do
      [[ -z "$name" || "$name" == "None" ]] && continue
      age=$(age_days "$created")
      row=$(print_row "Load Balancer" "$REGION" "$zone" "$name" "$state" "${age}d" "$type")
      ALL_ROWS+=("$row")
      [[ "$state" != "active" ]] && DANGLING_ROWS+=("$row")
      TOTAL=$((TOTAL + 1))
    done < <(aws elbv2 describe-load-balancers --region "$REGION" \
      --query 'LoadBalancers[].[LoadBalancerName,State.Code,AvailabilityZones[0].ZoneName,CreatedTime,Type]' \
      --output text 2>/dev/null || true)
  fi

done <<< "$REGION_LIST"

# ── Output ────────────────────────────────────────────────────────────────────

REGION_COUNT=$(echo "$REGION_LIST" | wc -l | tr -d ' ')

echo ""
echo "AWS RESOURCES INVENTORY"
echo "======================="
echo "Scan completed : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Regions scanned: $REGION_COUNT"
echo "Total resources: $TOTAL"

if [[ ${#SKIPPED_REGIONS[@]} -gt 0 ]]; then
  echo "Skipped regions: ${SKIPPED_REGIONS[*]} (access denied)"
fi

echo ""
echo "POTENTIALLY DANGLING RESOURCES"
echo "-------------------------------"
if [[ ${#DANGLING_ROWS[@]} -eq 0 ]]; then
  echo "None found."
else
  print_row "Type" "Region" "Zone" "Name" "Status" "Age" "Tags/Info"
  print_separator
  for row in "${DANGLING_ROWS[@]}"; do echo "$row"; done
fi

echo ""
echo "ALL RESOURCES"
echo "-------------"
if [[ ${#ALL_ROWS[@]} -eq 0 ]]; then
  echo "No resources found."
else
  print_row "Type" "Region" "Zone" "Name" "Status" "Age" "Tags/Info"
  print_separator
  for row in "${ALL_ROWS[@]}"; do echo "$row"; done
fi

echo ""
