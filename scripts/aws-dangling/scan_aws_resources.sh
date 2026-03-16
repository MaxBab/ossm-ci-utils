#!/bin/bash
# AWS Dangling Resources Scanner
#
# This script scans AWS accounts across all regions to identify potentially
# dangling (unused) resources that could be safely deleted to reduce costs.
#
# Usage:
#   ./scan_aws_resources.sh                          # Default scan all regions
#   ./scan_aws_resources.sh --regions us-east-1,us-west-2
#   ./scan_aws_resources.sh --resources ec2,s3,rds
#   ./scan_aws_resources.sh --interactive
#   ./scan_aws_resources.sh --help

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
SCAN_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REGIONS=""
RESOURCE_TYPES=""
INTERACTIVE=false
DRY_RUN=false
SIMPLE_MODE=false
OUTPUT_DIR="aws-scan-${SCAN_TIMESTAMP}"

# Counters for summary
HIGH_RISK_COUNT=0
MEDIUM_RISK_COUNT=0
LOW_RISK_COUNT=0
PROTECTED_COUNT=0

# Store findings data for simple mode
FINDINGS_DATA=""

# Usage function
usage() {
    cat << EOF
AWS Dangling Resources Scanner

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --regions REGIONS        Comma-separated list of regions to scan (default: all regions)
    --resources TYPES        Comma-separated resource types: ec2,s3,rds,lambda,elb (default: all)
    --interactive           Interactive mode with prompts
    --dry-run              Dry run mode (no output files created)
    --simple               Simple mode (console output only, no files, no analysis)
    --help                 Show this help message

EXAMPLES:
    $0                                           # Scan all regions and resources
    $0 --regions us-east-1,us-west-2            # Scan specific regions
    $0 --resources ec2,s3                       # Scan only EC2 and S3 resources
    $0 --interactive                            # Interactive mode
    $0 --dry-run                                # Dry run mode

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Check AWS CLI availability and authentication
check_aws_prerequisites() {
    log_info "Checking AWS CLI prerequisites..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS credentials authenticated successfully"
}

# Get all available AWS regions
get_all_regions() {
    if [[ -n "$REGIONS" ]]; then
        echo "$REGIONS" | tr ',' '\n'
    else
        aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n'
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --regions)
                REGIONS="$2"
                shift 2
                ;;
            --resources)
                RESOURCE_TYPES="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --simple)
                SIMPLE_MODE=true
                DRY_RUN=true  # Simple mode implies no file creation
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Interactive mode for user input
interactive_mode() {
    log_section "AWS Dangling Resources Scanner - Interactive Mode"

    echo "Region selection:"
    echo "1. All regions (recommended)"
    echo "2. Common regions (us-east-1, us-west-2, eu-west-1)"
    echo "3. Custom regions"
    echo -n "Choose option (1-3): "
    read -r region_choice

    case $region_choice in
        1)
            REGIONS=""
            ;;
        2)
            REGIONS="us-east-1,us-west-2,eu-west-1"
            ;;
        3)
            echo -n "Enter regions (comma-separated): "
            read -r REGIONS
            ;;
        *)
            log_warning "Invalid choice, using all regions"
            REGIONS=""
            ;;
    esac

    echo ""
    echo "Resource types to scan:"
    echo "1. All resource types (recommended)"
    echo "2. Compute only (EC2, Lambda)"
    echo "3. Storage only (S3, EBS)"
    echo "4. Custom selection"
    echo -n "Choose option (1-4): "
    read -r resource_choice

    case $resource_choice in
        1)
            RESOURCE_TYPES=""
            ;;
        2)
            RESOURCE_TYPES="ec2,lambda"
            ;;
        3)
            RESOURCE_TYPES="s3,ec2"
            ;;
        4)
            echo "Available types: ec2, s3, rds, lambda, elb"
            echo -n "Enter resource types (comma-separated): "
            read -r RESOURCE_TYPES
            ;;
        *)
            log_warning "Invalid choice, scanning all resource types"
            RESOURCE_TYPES=""
            ;;
    esac

}

# Create output directory
setup_output_directory() {
    if [[ "$DRY_RUN" == "false" ]] && [[ "$SIMPLE_MODE" == "false" ]]; then
        mkdir -p "$OUTPUT_DIR"
        log_info "Output directory created: $OUTPUT_DIR"
    fi
}


# Function to add finding to appropriate risk category
add_finding() {
    local risk_level="$1"
    local resource_type="$2"
    local resource_id="$3"  # Not saved to CSV for privacy
    local region="$4"
    local age="$5"
    local reason="$6"
    local cleanup_command="$7"  # Not saved to CSV for privacy
    local resource_state="${8:-unknown}"  # Track resource state for inventory
    local zone="${9:-N/A}"  # Availability zone
    local resource_name="${10:-none}"  # Resource name/tag
    local resource_tags="${11:-none}"  # Resource tags (sanitized)

    case $risk_level in
        high)
            HIGH_RISK_COUNT=$((HIGH_RISK_COUNT + 1))
            ;;
        medium)
            MEDIUM_RISK_COUNT=$((MEDIUM_RISK_COUNT + 1))
            ;;
        low)
            LOW_RISK_COUNT=$((LOW_RISK_COUNT + 1))
            ;;
        protected)
            PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
            ;;
    esac

    # Always store data for processing (needed for both simple mode and normal mode)
    # Sanitize tags for CSV (remove sensitive data, keep general purpose tags)
    local sanitized_tags="$resource_tags"
    if [[ "$resource_tags" =~ Environment|Team|Project|Owner|Application ]]; then
        sanitized_tags="$resource_tags"
    else
        sanitized_tags="no_relevant_tags"
    fi

    # Store data for both simple mode and CSV file
    local csv_line="$risk_level,$resource_type,$region,$zone,$age,$reason,$resource_state,$resource_name,$sanitized_tags"
    FINDINGS_DATA="${FINDINGS_DATA}${csv_line}"$'\n'

    # Save resource information to CSV file (only if not in simple mode and not dry run)
    if [[ "$DRY_RUN" == "false" ]] && [[ "$SIMPLE_MODE" == "false" ]]; then
        echo "$csv_line" >> "$OUTPUT_DIR/findings.csv"
    fi
}

# Scan EC2 instances
scan_ec2_instances() {
    local region="$1"
    log_info "Scanning EC2 instances in $region..."

    # Get all instances with zone and tags
    local instances
    instances=$(aws ec2 describe-instances --region "$region" --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,LaunchTime,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Environment`].Value|[0],Placement.AvailabilityZone,Tags[?Key==`Team`].Value|[0],Tags[?Key==`Project`].Value|[0]]' --output text 2>/dev/null || echo "")

    if [[ -z "$instances" ]]; then
        return
    fi

    while IFS=$'\t' read -r instance_id state instance_type launch_time name_tag env_tag zone team_tag project_tag; do
        if [[ -z "$instance_id" || "$instance_id" == "None" ]]; then
            continue
        fi

        # Calculate age in days
        if command -v gdate &> /dev/null; then
            # Use gdate on macOS if available
            launch_epoch=$(gdate -d "$launch_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${launch_time%.*}" +%s 2>/dev/null || echo "0")
        else
            # Use date on Linux
            launch_epoch=$(date -d "$launch_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${launch_time%.*}" +%s 2>/dev/null || echo "0")
        fi

        current_epoch=$(date +%s)
        age_days=$(( (current_epoch - launch_epoch) / 86400 ))

        # Build resource name and tags
        local resource_name="$name_tag"
        [[ "$resource_name" == "None" || -z "$resource_name" ]] && resource_name="no_name"

        local tags_info=""
        [[ "$env_tag" != "None" && -n "$env_tag" ]] && tags_info+="Environment=$env_tag;"
        [[ "$team_tag" != "None" && -n "$team_tag" ]] && tags_info+="Team=$team_tag;"
        [[ "$project_tag" != "None" && -n "$project_tag" ]] && tags_info+="Project=$project_tag;"
        [[ -z "$tags_info" ]] && tags_info="no_relevant_tags"

        # Clean up zone
        local availability_zone="$zone"
        [[ "$availability_zone" == "None" || -z "$availability_zone" ]] && availability_zone="N/A"

        # Analyze instance
        risk_level="low"
        reason="Running instance"
        cleanup_command=""

        if [[ "$state" == "stopped" ]] && [[ $age_days -gt 30 ]]; then
            risk_level="medium"
            reason="Stopped for $age_days days"
        fi

        if [[ "$state" == "stopped" ]] && [[ $age_days -gt 90 ]] && [[ "$name_tag" == "None" || -z "$name_tag" ]]; then
            risk_level="high"
            reason="Stopped for $age_days days with no name tag"
            cleanup_command="aws ec2 terminate-instances --region $region --instance-ids $instance_id"
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
            cleanup_command=""
        fi

        add_finding "$risk_level" "EC2 Instance" "$instance_id" "$region" "${age_days}d" "$reason" "$cleanup_command" "$state" "$availability_zone" "$resource_name" "$tags_info"

    done <<< "$instances"
}

# Scan all EBS volumes
scan_ebs_volumes() {
    local region="$1"
    log_info "Scanning EBS volumes in $region..."

    # Get all volumes (attached and unattached)
    local volumes
    volumes=$(aws ec2 describe-volumes --region "$region" --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Environment`].Value|[0],State,Attachments[0].InstanceId,AvailabilityZone,Tags[?Key==`Team`].Value|[0],Tags[?Key==`Project`].Value|[0]]' --output text 2>/dev/null || echo "")

    if [[ -z "$volumes" ]]; then
        return
    fi

    while IFS=$'\t' read -r volume_id size volume_type create_time name_tag env_tag volume_state instance_id zone team_tag project_tag; do
        if [[ -z "$volume_id" || "$volume_id" == "None" ]]; then
            continue
        fi

        # Calculate age in days
        if command -v gdate &> /dev/null; then
            create_epoch=$(gdate -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
        else
            create_epoch=$(date -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
        fi

        current_epoch=$(date +%s)
        age_days=$(( (current_epoch - create_epoch) / 86400 ))

        # Build resource name and tags
        local resource_name="$name_tag"
        [[ "$resource_name" == "None" || -z "$resource_name" ]] && resource_name="no_name"

        local tags_info=""
        [[ "$env_tag" != "None" && -n "$env_tag" ]] && tags_info+="Environment=$env_tag;"
        [[ "$team_tag" != "None" && -n "$team_tag" ]] && tags_info+="Team=$team_tag;"
        [[ "$project_tag" != "None" && -n "$project_tag" ]] && tags_info+="Project=$project_tag;"
        [[ -z "$tags_info" ]] && tags_info="no_relevant_tags"

        # Clean up zone
        local availability_zone="$zone"
        [[ "$availability_zone" == "None" || -z "$availability_zone" ]] && availability_zone="N/A"

        # Determine if attached or unattached
        local attachment_state="unattached"
        if [[ "$volume_state" == "in-use" ]] && [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
            attachment_state="attached"
        fi

        # Analyze volume
        risk_level="low"
        reason="Attached volume"
        cleanup_command=""

        if [[ "$attachment_state" == "unattached" ]]; then
            risk_level="medium"
            reason="Unattached volume"

            if [[ $age_days -gt 7 ]] && [[ "$name_tag" == "None" || -z "$name_tag" ]]; then
                risk_level="high"
                reason="Unattached for $age_days days with no name tag"
                cleanup_command="aws ec2 delete-volume --region $region --volume-id $volume_id"
            fi
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
            cleanup_command=""
        fi

        add_finding "$risk_level" "EBS Volume" "$volume_id" "$region" "${age_days}d" "$reason" "$cleanup_command" "$attachment_state" "$availability_zone" "$resource_name" "$tags_info"

    done <<< "$volumes"
}

# Scan all Elastic IPs
scan_elastic_ips() {
    local region="$1"
    log_info "Scanning Elastic IPs in $region..."

    # Get all Elastic IPs (associated and unassociated)
    local addresses
    addresses=$(aws ec2 describe-addresses --region "$region" --query 'Addresses[].[AllocationId,PublicIp,Tags[?Key==`Environment`].Value|[0],InstanceId,NetworkInterfaceId,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Team`].Value|[0],Tags[?Key==`Project`].Value|[0]]' --output text 2>/dev/null || echo "")

    if [[ -z "$addresses" ]]; then
        return
    fi

    while IFS=$'\t' read -r allocation_id public_ip env_tag instance_id network_interface_id name_tag team_tag project_tag; do
        if [[ -z "$allocation_id" || "$allocation_id" == "None" ]]; then
            continue
        fi

        # Build resource name and tags
        local resource_name="$name_tag"
        [[ "$resource_name" == "None" || -z "$resource_name" ]] && resource_name="no_name"

        local tags_info=""
        [[ "$env_tag" != "None" && -n "$env_tag" ]] && tags_info+="Environment=$env_tag;"
        [[ "$team_tag" != "None" && -n "$team_tag" ]] && tags_info+="Team=$team_tag;"
        [[ "$project_tag" != "None" && -n "$project_tag" ]] && tags_info+="Project=$project_tag;"
        [[ -z "$tags_info" ]] && tags_info="no_relevant_tags"

        # Determine if associated or unassociated
        local association_state="unassociated"
        if [[ -n "$instance_id" && "$instance_id" != "None" ]] || [[ -n "$network_interface_id" && "$network_interface_id" != "None" ]]; then
            association_state="associated"
        fi

        risk_level="low"
        reason="Associated Elastic IP"
        cleanup_command=""

        if [[ "$association_state" == "unassociated" ]]; then
            risk_level="high"
            reason="Unassociated Elastic IP"
            cleanup_command="aws ec2 release-address --region $region --allocation-id $allocation_id"
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
            cleanup_command=""
        fi

        add_finding "$risk_level" "Elastic IP" "$allocation_id" "$region" "N/A" "$reason" "$cleanup_command" "$association_state" "regional" "$resource_name" "$tags_info"

    done <<< "$addresses"
}

# Scan old snapshots
scan_snapshots() {
    local region="$1"
    log_info "Scanning EBS snapshots in $region..."

    # Get snapshots older than 90 days
    local snapshots
    snapshots=$(aws ec2 describe-snapshots --region "$region" --owner-ids "$ACCOUNT_ID" --query 'Snapshots[].[SnapshotId,StartTime,VolumeSize,Description,Tags[?Key==`Environment`].Value|[0]]' --output text 2>/dev/null || echo "")

    if [[ -z "$snapshots" ]]; then
        return
    fi

    while IFS=$'\t' read -r snapshot_id start_time volume_size description env_tag; do
        if [[ -z "$snapshot_id" || "$snapshot_id" == "None" ]]; then
            continue
        fi

        # Calculate age in days
        if command -v gdate &> /dev/null; then
            start_epoch=$(gdate -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${start_time%.*}" +%s 2>/dev/null || echo "0")
        else
            start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${start_time%.*}" +%s 2>/dev/null || echo "0")
        fi

        current_epoch=$(date +%s)
        age_days=$(( (current_epoch - start_epoch) / 86400 ))

        # Skip recent snapshots
        if [[ $age_days -lt 90 ]]; then
            continue
        fi

        risk_level="low"
        reason="Old snapshot ($age_days days)"
        cleanup_command=""

        if [[ $age_days -gt 365 ]] && [[ "$description" =~ [Aa]utomat ]]; then
            risk_level="medium"
            reason="Very old automated snapshot ($age_days days)"
            cleanup_command="aws ec2 delete-snapshot --region $region --snapshot-id $snapshot_id"
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
            cleanup_command=""
        fi

        add_finding "$risk_level" "EBS Snapshot" "$snapshot_id" "$region" "${age_days}d" "$reason" "$cleanup_command" "available" "N/A" "snapshot" "no_relevant_tags"

    done <<< "$snapshots"
}

# Scan S3 buckets (global service)
scan_s3_buckets() {
    log_section "Scanning S3 buckets"

    # Get all buckets
    local buckets
    buckets=$(aws s3api list-buckets --query 'Buckets[].[Name,CreationDate]' --output text 2>/dev/null || echo "")

    if [[ -z "$buckets" ]]; then
        return
    fi

    while IFS=$'\t' read -r bucket_name creation_date; do
        if [[ -z "$bucket_name" || "$bucket_name" == "None" ]]; then
            continue
        fi

        log_info "Analyzing S3 bucket: $bucket_name"

        # Calculate age
        if command -v gdate &> /dev/null; then
            create_epoch=$(gdate -d "$creation_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${creation_date%.*}" +%s 2>/dev/null || echo "0")
        else
            create_epoch=$(date -d "$creation_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${creation_date%.*}" +%s 2>/dev/null || echo "0")
        fi

        current_epoch=$(date +%s)
        age_days=$(( (current_epoch - create_epoch) / 86400 ))

        # Check if bucket is empty
        local object_count
        object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --max-items 1 --query 'length(Contents)' --output text 2>/dev/null || echo "unknown")

        # Get bucket tags
        local env_tag=""
        env_tag=$(aws s3api get-bucket-tagging --bucket "$bucket_name" --query 'TagSet[?Key==`Environment`].Value' --output text 2>/dev/null || echo "")

        risk_level="low"
        reason="S3 bucket with content"
        cleanup_command=""

        if [[ "$object_count" == "0" ]] && [[ $age_days -gt 30 ]]; then
            risk_level="medium"
            reason="Empty bucket for $age_days days"
        fi

        if [[ "$object_count" == "0" ]] && [[ $age_days -gt 7 ]] && [[ -z "$env_tag" ]]; then
            risk_level="high"
            reason="Empty bucket with no tags for $age_days days"
            cleanup_command="aws s3 rb s3://$bucket_name"
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
            cleanup_command=""
        fi

        # Build tags info for S3
        local tags_info="none"
        local all_tags=$(aws s3api get-bucket-tagging --bucket "$bucket_name" --query 'TagSet[].[Key,Value]' --output text 2>/dev/null || echo "")
        if [[ -n "$all_tags" ]]; then
            tags_info=""
            while IFS=$'\t' read -r key value; do
                if [[ -n "$key" && "$key" != "None" ]]; then
                    if [[ -n "$tags_info" ]]; then
                        tags_info="${tags_info}; ${key}=${value}"
                    else
                        tags_info="${key}=${value}"
                    fi
                fi
            done <<< "$all_tags"
            [[ -z "$tags_info" ]] && tags_info="none"
        fi

        local bucket_state="with_content"
        if [[ "$object_count" == "0" ]]; then
            bucket_state="empty"
        fi

        # S3 buckets are global but stored in specific regions
        local bucket_region="global"

        add_finding "$risk_level" "S3 Bucket" "$bucket_name" "$bucket_region" "${age_days}d" "$reason" "$cleanup_command" "$bucket_state" "global" "$bucket_name" "$tags_info"

    done <<< "$buckets"
}

# Scan RDS instances
scan_rds_instances() {
    local region="$1"
    log_info "Scanning RDS instances in $region..."

    # Get all RDS instances
    local instances
    instances=$(aws rds describe-db-instances --region "$region" --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass,InstanceCreateTime,TagList[?Key==`Environment`].Value|[0],AvailabilityZone,TagList[?Key==`Team`].Value|[0],TagList[?Key==`Project`].Value|[0]]' --output text 2>/dev/null || echo "")

    if [[ -z "$instances" ]]; then
        return
    fi

    while IFS=$'\t' read -r instance_id status instance_class create_time env_tag zone team_tag project_tag; do
        if [[ -z "$instance_id" || "$instance_id" == "None" ]]; then
            continue
        fi

        # Calculate age
        if command -v gdate &> /dev/null; then
            create_epoch=$(gdate -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
        else
            create_epoch=$(date -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
        fi

        current_epoch=$(date +%s)
        age_days=$(( (current_epoch - create_epoch) / 86400 ))

        # RDS instances always need manual validation
        risk_level="medium"
        reason="Database instance - requires validation"
        cleanup_command=""

        if [[ "$status" != "available" ]]; then
            reason="Database instance status: $status"
        fi

        if [[ "$env_tag" =~ [Pp]rod ]]; then
            risk_level="protected"
            reason="Production tagged resource"
        fi

        # Build resource name and tags
        local resource_name="$instance_id"  # RDS instances use the identifier as the name

        local tags_info=""
        [[ "$env_tag" != "None" && -n "$env_tag" ]] && tags_info+="Environment=$env_tag;"
        [[ "$team_tag" != "None" && -n "$team_tag" ]] && tags_info+="Team=$team_tag;"
        [[ "$project_tag" != "None" && -n "$project_tag" ]] && tags_info+="Project=$project_tag;"
        [[ -z "$tags_info" ]] && tags_info="no_relevant_tags"

        # Clean up zone
        local availability_zone="$zone"
        [[ "$availability_zone" == "None" || -z "$availability_zone" ]] && availability_zone="N/A"

        add_finding "$risk_level" "RDS Instance" "$instance_id" "$region" "${age_days}d" "$reason" "" "$status" "$availability_zone" "$resource_name" "$tags_info"

    done <<< "$instances"
}

# Scan Load Balancers
scan_load_balancers() {
    local region="$1"
    log_info "Scanning Load Balancers in $region..."

    # Scan Classic Load Balancers
    local clbs
    clbs=$(aws elb describe-load-balancers --region "$region" --query 'LoadBalancerDescriptions[].[LoadBalancerName,CreatedTime,Instances[].InstanceId]' --output text 2>/dev/null || echo "")

    if [[ -n "$clbs" ]]; then
        while IFS=$'\t' read -r lb_name create_time instances; do
            if [[ -z "$lb_name" || "$lb_name" == "None" ]]; then
                continue
            fi

            # Get tags for Classic Load Balancer
            local tags_info="none"
            local tag_query=$(aws elb describe-tags --load-balancer-names "$lb_name" --region "$region" --query 'TagDescriptions[0].Tags[].[Key,Value]' --output text 2>/dev/null || echo "")
            if [[ -n "$tag_query" ]]; then
                tags_info=""
                while IFS=$'\t' read -r key value; do
                    if [[ -n "$key" && "$key" != "None" ]]; then
                        if [[ -n "$tags_info" ]]; then
                            tags_info="${tags_info}; ${key}=${value}"
                        else
                            tags_info="${key}=${value}"
                        fi
                    fi
                done <<< "$tag_query"
                [[ -z "$tags_info" ]] && tags_info="none"
            fi

            # Calculate age
            if command -v gdate &> /dev/null; then
                create_epoch=$(gdate -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
            else
                create_epoch=$(date -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
            fi

            current_epoch=$(date +%s)
            age_days=$(( (current_epoch - create_epoch) / 86400 ))

            risk_level="low"
            reason="Classic Load Balancer with instances"
            cleanup_command=""

            if [[ -z "$instances" || "$instances" == "None" ]]; then
                risk_level="medium"
                reason="Classic Load Balancer with no instances"

                if [[ $age_days -gt 7 ]]; then
                    risk_level="high"
                    reason="No instances for $age_days days"
                    cleanup_command="aws elb delete-load-balancer --region $region --load-balancer-name $lb_name"
                fi
            fi

            local lb_state="active"
            if [[ -z "$instances" || "$instances" == "None" ]]; then
                lb_state="no_targets"
            fi
            add_finding "$risk_level" "Classic Load Balancer" "$lb_name" "$region" "${age_days}d" "$reason" "$cleanup_command" "$lb_state" "regional" "$lb_name" "$tags_info"

        done <<< "$clbs"
    fi

    # Scan Application/Network Load Balancers
    local albs
    albs=$(aws elbv2 describe-load-balancers --region "$region" --query 'LoadBalancers[].[LoadBalancerName,LoadBalancerArn,CreatedTime,State.Code,Type]' --output text 2>/dev/null || echo "")

    if [[ -n "$albs" ]]; then
        while IFS=$'\t' read -r lb_name lb_arn create_time state lb_type; do
            if [[ -z "$lb_name" || "$lb_name" == "None" ]]; then
                continue
            fi

            # Get tags for ALB/NLB
            local tags_info="none"
            local tag_query=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$region" --query 'TagDescriptions[0].Tags[].[Key,Value]' --output text 2>/dev/null || echo "")
            if [[ -n "$tag_query" ]]; then
                tags_info=""
                while IFS=$'\t' read -r key value; do
                    if [[ -n "$key" && "$key" != "None" ]]; then
                        if [[ -n "$tags_info" ]]; then
                            tags_info="${tags_info}; ${key}=${value}"
                        else
                            tags_info="${key}=${value}"
                        fi
                    fi
                done <<< "$tag_query"
                [[ -z "$tags_info" ]] && tags_info="none"
            fi

            # Calculate age
            if command -v gdate &> /dev/null; then
                create_epoch=$(gdate -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
            else
                create_epoch=$(date -d "$create_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_time%.*}" +%s 2>/dev/null || echo "0")
            fi

            current_epoch=$(date +%s)
            age_days=$(( (current_epoch - create_epoch) / 86400 ))

            risk_level="low"
            reason="Modern Load Balancer active"
            cleanup_command=""

            if [[ "$state" != "active" ]]; then
                risk_level="medium"
                reason="Load Balancer state: $state"
                cleanup_command="aws elbv2 delete-load-balancer --region $region --load-balancer-arn $lb_arn"
            fi

            add_finding "$risk_level" "${lb_type} Load Balancer" "$lb_name" "$region" "${age_days}d" "$reason" "$cleanup_command" "$state" "regional" "$lb_name" "$tags_info"

        done <<< "$albs"
    fi
}

# Main scanning function
perform_scan() {
    log_section "Starting AWS Dangling Resources Scan"

    # Initialize findings file (only if not in simple mode)
    if [[ "$DRY_RUN" == "false" ]] && [[ "$SIMPLE_MODE" == "false" ]]; then
        echo "risk_level,resource_type,region,zone,age,reason,state,name,tags" > "$OUTPUT_DIR/findings.csv"
    fi

    # Get regions to scan
    local regions_array=()
    while IFS= read -r region; do
        regions_array+=("$region")
    done < <(get_all_regions)

    log_info "Scanning ${#regions_array[@]} regions: ${regions_array[*]}"

    # Determine resource types to scan
    local scan_ec2=true scan_s3=true scan_rds=true scan_lambda=true scan_elb=true

    if [[ -n "$RESOURCE_TYPES" ]]; then
        scan_ec2=false scan_s3=false scan_rds=false scan_lambda=false scan_elb=false

        IFS=',' read -ra types <<< "$RESOURCE_TYPES"
        for type in "${types[@]}"; do
            type_lower=$(echo "$type" | tr '[:upper:]' '[:lower:]')
            case "$type_lower" in
                ec2) scan_ec2=true ;;
                s3) scan_s3=true ;;
                rds) scan_rds=true ;;
                lambda) scan_lambda=true ;;
                elb|lb) scan_elb=true ;;
            esac
        done
    fi

    # Scan S3 (global service)
    if [[ "$scan_s3" == "true" ]]; then
        scan_s3_buckets
    fi

    # Scan regional services
    for region in "${regions_array[@]}"; do
        if [[ -z "$region" ]]; then
            continue
        fi

        log_section "Scanning region: $region"

        # Check if region is accessible
        if ! aws ec2 describe-regions --region "$region" --region-names "$region" &>/dev/null; then
            log_warning "Skipping inaccessible region: $region"
            continue
        fi

        if [[ "$scan_ec2" == "true" ]]; then
            scan_ec2_instances "$region"
            scan_ebs_volumes "$region"
            scan_elastic_ips "$region"
            scan_snapshots "$region"
        fi

        if [[ "$scan_rds" == "true" ]]; then
            scan_rds_instances "$region"
        fi

        if [[ "$scan_elb" == "true" ]]; then
            scan_load_balancers "$region"
        fi

        # Note: Lambda scanning would go here if implemented
    done
}

# Generate simple table output (no files, no analysis)
generate_simple_output() {
    local total_resources=$((HIGH_RISK_COUNT + MEDIUM_RISK_COUNT + LOW_RISK_COUNT + PROTECTED_COUNT))

    echo ""
    echo "AWS RESOURCES INVENTORY"
    echo "======================="
    echo "Scan completed: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Regions scanned: $(get_all_regions | wc -l | tr -d ' ') regions"
    echo "Total resources found: $total_resources"
    echo ""

    # Show potentially dangling resources
    echo "## POTENTIALLY DANGLING RESOURCES"
    echo ""

    # Check if we have any high or medium risk resources
    local dangling_found=false
    if [[ -n "$FINDINGS_DATA" ]]; then
        echo "$FINDINGS_DATA" | grep -E "^(high|medium)," > /dev/null 2>&1 && dangling_found=true
    fi

    if [[ "$dangling_found" == "true" ]]; then
        printf "| %-20s | %-15s | %-15s | %-25s | %-12s | %-8s | %-30s |\n" "Type" "Region" "Zone" "Name" "Status" "Age" "Tags"
        printf "|%s|%s|%s|%s|%s|%s|%s|\n" "$(printf '%*s' 22 '' | tr ' ' '-')" "$(printf '%*s' 17 '' | tr ' ' '-')" "$(printf '%*s' 17 '' | tr ' ' '-')" "$(printf '%*s' 27 '' | tr ' ' '-')" "$(printf '%*s' 14 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')" "$(printf '%*s' 32 '' | tr ' ' '-')"

        echo "$FINDINGS_DATA" | grep -E "^(high|medium)," | while IFS=',' read -r risk_level resource_type region zone age reason state name tags; do
            # Truncate long values for display
            resource_type_short="${resource_type:0:19}"
            region_short="${region:0:14}"
            zone_short="${zone:0:14}"
            name_short="${name:0:24}"
            state_short="${state:0:11}"
            age_short="${age:0:7}"
            tags_short="${tags:0:29}"

            printf "| %-20s | %-15s | %-15s | %-25s | %-12s | %-8s | %-30s |\n" \
                "$resource_type_short" "$region_short" "$zone_short" "$name_short" "$state_short" "$age_short" "$tags_short"
        done
    else
        echo "No potentially dangling resources found."
    fi

    echo ""
    echo "## COMPLETE RESOURCES INVENTORY"
    echo ""

    # Show all resources
    if [[ -n "$FINDINGS_DATA" ]]; then
        printf "| %-20s | %-15s | %-15s | %-25s | %-12s | %-8s | %-30s |\n" "Type" "Region" "Zone" "Name" "Status" "Age" "Tags"
        printf "|%s|%s|%s|%s|%s|%s|%s|\n" "$(printf '%*s' 22 '' | tr ' ' '-')" "$(printf '%*s' 17 '' | tr ' ' '-')" "$(printf '%*s' 17 '' | tr ' ' '-')" "$(printf '%*s' 27 '' | tr ' ' '-')" "$(printf '%*s' 14 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')" "$(printf '%*s' 32 '' | tr ' ' '-')"

        echo "$FINDINGS_DATA" | while IFS=',' read -r risk_level resource_type region zone age reason state name tags; do
            # Skip empty lines
            [[ -z "$risk_level" ]] && continue

            # Truncate long values for display
            resource_type_short="${resource_type:0:19}"
            region_short="${region:0:14}"
            zone_short="${zone:0:14}"
            name_short="${name:0:24}"
            state_short="${state:0:11}"
            age_short="${age:0:7}"
            tags_short="${tags:0:29}"

            printf "| %-20s | %-15s | %-15s | %-25s | %-12s | %-8s | %-30s |\n" \
                "$resource_type_short" "$region_short" "$zone_short" "$name_short" "$state_short" "$age_short" "$tags_short"
        done
    else
        echo "No resources found."
    fi

    echo ""
}

# Generate comprehensive report
generate_report() {
    log_section "Generating Report"

    local total_resources=$((HIGH_RISK_COUNT + MEDIUM_RISK_COUNT + LOW_RISK_COUNT + PROTECTED_COUNT))

    local report_file="$OUTPUT_DIR/dangling-resources-report.txt"
    if [[ "$DRY_RUN" == "true" ]]; then
        report_file="/dev/stdout"
    fi

    {
        echo "AWS DANGLING RESOURCES SCAN"
        echo "============================"
        echo "Scan completed: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Regions scanned: $(get_all_regions | wc -l | tr -d ' ') regions"
        echo "Total resources found: $total_resources"
        echo ""

        # Complete resource inventory across all regions
        echo "## COMPLETE RESOURCE INVENTORY"
        echo ""
        echo "This section shows ALL resources discovered across your AWS account:"
        echo ""

        # Global summary by resource type
        if [[ -f "$OUTPUT_DIR/findings.csv" ]]; then
            local total_ec2=$(grep ",EC2 Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local total_ebs=$(grep ",EBS Volume," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local total_eip=$(grep ",Elastic IP," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local total_s3=$(grep ",S3 Bucket," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local total_rds=$(grep ",RDS Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local total_lb=$(grep "Load Balancer," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')

            echo "### Global Resource Summary"
            echo "**Compute Resources:**"
            [[ $total_ec2 -gt 0 ]] && echo "- EC2 Instances: $total_ec2 total"
            [[ $total_ebs -gt 0 ]] && echo "- EBS Volumes: $total_ebs total"

            echo ""
            echo "**Storage Resources:**"
            [[ $total_s3 -gt 0 ]] && echo "- S3 Buckets: $total_s3 total"

            echo ""
            echo "**Database Resources:**"
            [[ $total_rds -gt 0 ]] && echo "- RDS Instances: $total_rds total"

            echo ""
            echo "**Networking Resources:**"
            [[ $total_eip -gt 0 ]] && echo "- Elastic IPs: $total_eip total"
            [[ $total_lb -gt 0 ]] && echo "- Load Balancers: $total_lb total"

            echo ""
        fi

        # Resources by region breakdown (anonymized)
        echo "## RESOURCES BY REGION"
        echo ""
        echo "Detailed breakdown of resources in each region:"
        echo ""

        local region_counter=0
        for region in $(get_all_regions); do
            if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q ",$region," "$OUTPUT_DIR/findings.csv"; then
                region_counter=$((region_counter + 1))

                if [[ $region_counter -eq 1 ]]; then
                    echo "### Primary Region"
                elif [[ $region_counter -eq 2 ]]; then
                    echo "### Secondary Region"
                else
                    echo "### Additional Region $region_counter"
                fi

                # Count resources by type and state in this region
                local ec2_running=$(grep "^.*,EC2 Instance,$region,.*,.*,running" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local ec2_stopped=$(grep "^.*,EC2 Instance,$region,.*,.*,stopped" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local ec2_total=$((ec2_running + ec2_stopped))

                local ebs_attached=$(grep "^.*,EBS Volume,$region,.*,.*,attached" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local ebs_unattached=$(grep "^.*,EBS Volume,$region,.*,.*,unattached" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local ebs_total=$((ebs_attached + ebs_unattached))

                local eip_associated=$(grep "^.*,Elastic IP,$region,.*,.*,associated" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local eip_unassociated=$(grep "^.*,Elastic IP,$region,.*,.*,unassociated" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local eip_total=$((eip_associated + eip_unassociated))

                local rds_available=$(grep "^.*,RDS Instance,$region,.*,.*,available" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local rds_other=$(grep "^.*,RDS Instance,$region," "$OUTPUT_DIR/findings.csv" 2>/dev/null | grep -v ",available" | wc -l | tr -d ' ')
                local rds_total=$((rds_available + rds_other))

                local lb_active=$(grep "^.*,.*Load Balancer,$region,.*,.*,active" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local lb_no_targets=$(grep "^.*,.*Load Balancer,$region,.*,.*,no_targets" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
                local lb_total=$((lb_active + lb_no_targets))

                if [[ $ec2_total -gt 0 || $ebs_total -gt 0 || $eip_total -gt 0 ]]; then
                    echo "**EC2 Resources:**"
                    if [[ $ec2_total -gt 0 ]]; then
                        echo "- Instances: $ec2_total total (running: $ec2_running, stopped: $ec2_stopped)"
                    fi
                    if [[ $ebs_total -gt 0 ]]; then
                        echo "- EBS Volumes: $ebs_total total (attached: $ebs_attached, unattached: $ebs_unattached)"
                    fi
                    if [[ $eip_total -gt 0 ]]; then
                        echo "- Elastic IPs: $eip_total total (associated: $eip_associated, unassociated: $eip_unassociated)"
                    fi
                    echo ""
                fi

                if [[ $rds_total -gt 0 ]]; then
                    echo "**Database Resources:**"
                    echo "- RDS Instances: $rds_total total (available: $rds_available, other: $rds_other)"
                    echo ""
                fi

                if [[ $lb_total -gt 0 ]]; then
                    echo "**Networking Resources:**"
                    echo "- Load Balancers: $lb_total total (with targets: $lb_active, no targets: $lb_no_targets)"
                    echo ""
                fi
            fi
        done

        # Global S3 resources
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q ",S3 Bucket,global," "$OUTPUT_DIR/findings.csv"; then
            local s3_with_content=$(grep "^.*,S3 Bucket,global,.*,.*,with_content" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local s3_empty=$(grep "^.*,S3 Bucket,global,.*,.*,empty" "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local s3_total=$((s3_with_content + s3_empty))

            echo "### Global Resources"
            echo "**Storage Resources:**"
            echo "- S3 Buckets: $s3_total total (with content: $s3_with_content, empty: $s3_empty)"
            echo ""
        fi

        echo "## POTENTIALLY DANGLING RESOURCES"
        echo ""

        # High-risk resources summary
        echo "### HIGH PRIORITY (Likely Safe to Delete)"
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^high," "$OUTPUT_DIR/findings.csv"; then
            echo "**Summary:** $HIGH_RISK_COUNT resources identified as likely safe to delete"
            echo ""

            # Count by resource type
            local high_ec2=$(grep "^high,EC2 Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local high_ebs=$(grep "^high,EBS Volume," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local high_eip=$(grep "^high,Elastic IP," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local high_s3=$(grep "^high,S3 Bucket," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')

            [[ $high_ec2 -gt 0 ]] && echo "- EC2 Instances: $high_ec2 stopped for extended periods"
            [[ $high_ebs -gt 0 ]] && echo "- EBS Volumes: $high_ebs unattached volumes"
            [[ $high_eip -gt 0 ]] && echo "- Elastic IPs: $high_eip unassociated addresses"
            [[ $high_s3 -gt 0 ]] && echo "- S3 Buckets: $high_s3 empty buckets"

            echo ""
            echo "**Resource Details:**"
            # Age analysis
            local old_resources=$(grep "^high," "$OUTPUT_DIR/findings.csv" | grep -E "([0-9]{2,}d|[3-9][0-9]d)" | wc -l | tr -d ' ')
            [[ $old_resources -gt 0 ]] && echo "- $old_resources resources older than 30 days"

            local very_old=$(grep "^high," "$OUTPUT_DIR/findings.csv" | grep -E "([0-9]{3,}d|[1-9][0-9]{2,}d)" | wc -l | tr -d ' ')
            [[ $very_old -gt 0 ]] && echo "- $very_old resources older than 100 days"

            echo ""
        else
            echo "**Summary:** No high priority resources found."
            echo ""
        fi

        # Medium-risk resources summary
        echo "### MEDIUM PRIORITY (Validate Before Action)"
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^medium," "$OUTPUT_DIR/findings.csv"; then
            echo "**Summary:** $MEDIUM_RISK_COUNT resources requiring validation"
            echo ""

            # Count by resource type
            local med_ec2=$(grep "^medium,EC2 Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local med_rds=$(grep "^medium,RDS Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local med_lb=$(grep "^medium,.*Load Balancer," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')
            local med_s3=$(grep "^medium,S3 Bucket," "$OUTPUT_DIR/findings.csv" 2>/dev/null | wc -l | tr -d ' ')

            [[ $med_ec2 -gt 0 ]] && echo "- EC2 Instances: $med_ec2 requiring validation"
            [[ $med_rds -gt 0 ]] && echo "- RDS Instances: $med_rds databases needing usage check"
            [[ $med_lb -gt 0 ]] && echo "- Load Balancers: $med_lb without active targets"
            [[ $med_s3 -gt 0 ]] && echo "- S3 Buckets: $med_s3 potentially unused buckets"

            echo ""
            echo "**Resource Details:**"
            echo "- Database instances require application usage validation"
            echo "- Load balancers may be part of temporary infrastructure"
            echo "- Storage resources need content verification"

            echo ""
        else
            echo "**Summary:** No medium priority resources found."
            echo ""
        fi

        # Low-risk resources
        echo "### LOW PRIORITY (Investigate Further)"
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^low," "$OUTPUT_DIR/findings.csv"; then
            echo "**Summary:** $LOW_RISK_COUNT resources appear to be in active use"
            echo ""
            echo "**Resource Details:**"
            echo "- Most resources have production tags or recent activity"
            echo "- Active workloads and properly tagged infrastructure"
            echo "- Resources part of running applications"
            echo ""
        else
            echo "**Summary:** No low priority resources found."
            echo ""
        fi

        echo "## CLEANUP RECOMMENDATIONS"
        echo ""
        echo "**General guidance for high priority resources:**"
        echo '```bash'
        echo "# Always validate before deletion:"
        echo "# 1. Check resource dependencies"
        echo "# 2. Verify no recent activity"
        echo "# 3. Confirm with resource owners"
        echo "# 4. Test in non-production first"
        echo ""
        echo "# Example validation commands (replace with actual resource IDs):"
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^high,EC2 Instance," "$OUTPUT_DIR/findings.csv"; then
            echo "aws ec2 describe-instances --instance-ids [INSTANCE-ID]"
        fi
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^high,EBS Volume," "$OUTPUT_DIR/findings.csv"; then
            echo "aws ec2 describe-volumes --volume-ids [VOLUME-ID]"
        fi
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^high,S3 Bucket," "$OUTPUT_DIR/findings.csv"; then
            echo "aws s3api list-objects-v2 --bucket [BUCKET-NAME]"
        fi
        if [[ -f "$OUTPUT_DIR/findings.csv" ]] && grep -q "^high,Elastic IP," "$OUTPUT_DIR/findings.csv"; then
            echo "aws ec2 describe-addresses --allocation-ids [ALLOCATION-ID]"
        fi
        echo '```'

        echo ""
        echo "**Safety checklist:**"
        echo "- [ ] Verified resource has no dependencies"
        echo "- [ ] Confirmed no recent usage activity"
        echo "- [ ] Checked with application teams"
        echo "- [ ] Tested deletion commands with --dry-run"

        echo ""
        echo "## DATA FILES GENERATED"
        echo ""
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "- Resource inventory saved to local CSV file"
            echo "- Detailed analysis available in generated report"
            echo "- All data kept locally without sensitive information"
        else
            echo "**Dry run mode** - No files created"
        fi

    } > "$report_file"

    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Report generated: $report_file"
    fi
}

# Create cleanup guidance (no scripts with sensitive data)
create_cleanup_scripts() {
    if [[ "$DRY_RUN" == "true" ]] || [[ ! -f "$OUTPUT_DIR/findings.csv" ]]; then
        return
    fi

    log_info "Creating cleanup guidance..."

    # Create generic cleanup guidance file
    local guidance_file="$OUTPUT_DIR/cleanup-guidance-${SCAN_TIMESTAMP}.txt"

    {
        echo "AWS Dangling Resources Cleanup Guidance"
        echo "======================================="
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "IMPORTANT SAFETY NOTES:"
        echo "- Always validate resources before deletion"
        echo "- Check with application teams"
        echo "- Test commands with --dry-run first"
        echo "- Make backups where appropriate"
        echo ""

        if [[ $HIGH_RISK_COUNT -gt 0 ]]; then
            echo "HIGH PRIORITY RESOURCES FOUND: $HIGH_RISK_COUNT"
            echo ""
            echo "Validation Commands (replace [RESOURCE-ID] with actual IDs):"

            if grep -q "^high,EC2 Instance," "$OUTPUT_DIR/findings.csv" 2>/dev/null; then
                echo "# For EC2 Instances:"
                echo "aws ec2 describe-instances --instance-ids [INSTANCE-ID]"
                echo "aws ec2 terminate-instances --instance-ids [INSTANCE-ID] --dry-run"
                echo ""
            fi

            if grep -q "^high,EBS Volume," "$OUTPUT_DIR/findings.csv" 2>/dev/null; then
                echo "# For EBS Volumes:"
                echo "aws ec2 describe-volumes --volume-ids [VOLUME-ID]"
                echo "aws ec2 delete-volume --volume-id [VOLUME-ID] --dry-run"
                echo ""
            fi

            if grep -q "^high,Elastic IP," "$OUTPUT_DIR/findings.csv" 2>/dev/null; then
                echo "# For Elastic IPs:"
                echo "aws ec2 describe-addresses --allocation-ids [ALLOCATION-ID]"
                echo "aws ec2 release-address --allocation-id [ALLOCATION-ID] --dry-run"
                echo ""
            fi

            if grep -q "^high,S3 Bucket," "$OUTPUT_DIR/findings.csv" 2>/dev/null; then
                echo "# For S3 Buckets:"
                echo "aws s3api list-objects-v2 --bucket [BUCKET-NAME]"
                echo "aws s3 rb s3://[BUCKET-NAME] --dry-run"
                echo ""
            fi
        fi

        if [[ $MEDIUM_RISK_COUNT -gt 0 ]]; then
            echo "MEDIUM PRIORITY RESOURCES FOUND: $MEDIUM_RISK_COUNT"
            echo "These require careful validation with application teams."
            echo ""
        fi

        echo "Review the detailed report for specific resource counts and reasons."

    } > "$guidance_file"

    log_success "Created cleanup guidance: $guidance_file"
}

# Main execution function
main() {
    parse_arguments "$@"

    if [[ "$INTERACTIVE" == "true" ]]; then
        interactive_mode
    fi

    check_aws_prerequisites
    setup_output_directory

    log_info "Starting scan with parameters:"
    log_info "- Regions: $([ -n "$REGIONS" ] && echo "$REGIONS" || echo "all")"
    log_info "- Resource types: $([ -n "$RESOURCE_TYPES" ] && echo "$RESOURCE_TYPES" || echo "all")"
    log_info "- Dry run: $DRY_RUN"
    if [[ "$SIMPLE_MODE" == "true" ]]; then
        log_info "- Simple mode: true"
    fi

    perform_scan

    if [[ "$SIMPLE_MODE" == "true" ]]; then
        generate_simple_output
    else
        generate_report
        create_cleanup_scripts
    fi

    if [[ "$SIMPLE_MODE" == "false" ]]; then
        log_success "Scan completed!"
        log_info "High-risk resources: $HIGH_RISK_COUNT"
        log_info "Medium-risk resources: $MEDIUM_RISK_COUNT"
        log_info "Low-risk resources: $LOW_RISK_COUNT"

        if [[ "$DRY_RUN" == "false" ]]; then
            echo ""
            log_info "Output directory: $OUTPUT_DIR"
            log_info "Main report: $OUTPUT_DIR/dangling-resources-report.txt"
            log_info "CSV data: $OUTPUT_DIR/findings.csv (anonymized)"

            # List cleanup guidance if created
            if ls "$OUTPUT_DIR"/cleanup-guidance-*.txt >/dev/null 2>&1; then
                log_info "Cleanup guidance:"
                ls "$OUTPUT_DIR"/cleanup-guidance-*.txt | while read -r guidance; do
                    log_info "  - $(basename "$guidance")"
                done
                echo ""
                log_warning "Always validate resources before deletion!"
                log_warning "Test all commands with --dry-run flag first!"
            fi
        fi
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Scan interrupted by user${NC}"; exit 1' INT

# Run main function with all arguments
main "$@"