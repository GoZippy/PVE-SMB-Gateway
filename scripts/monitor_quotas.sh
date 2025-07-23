#!/bin/bash
# SMB Gateway Quota Monitoring Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-quota-monitor.log"
QUOTA_DIR="/etc/pve/smbgateway/quotas"
WARN_THRESHOLD=80
CRITICAL_THRESHOLD=90
NOTICE_THRESHOLD=75
NOTIFY_EMAIL=""
NOTIFY_WEBHOOK=""
VERBOSE=0
JSON_OUTPUT=0
PROMETHEUS_OUTPUT=0
ENFORCE_QUOTAS=0
ENFORCE_THRESHOLD=95

# Function to log messages
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ $VERBOSE -eq 1 ]; then
        echo "[$timestamp] $1"
    fi
    echo "[$timestamp] $1" >> $LOG_FILE
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -w, --warn <percent>      Warning threshold percentage (default: 80)"
    echo "  -c, --critical <percent>  Critical threshold percentage (default: 90)"
    echo "  -n, --notice <percent>    Notice threshold percentage (default: 75)"
    echo "  -e, --email <address>     Email address for notifications"
    echo "  -u, --webhook <url>       Webhook URL for notifications"
    echo "  -j, --json                Output results in JSON format"
    echo "  -p, --prometheus          Output results in Prometheus format"
    echo "  -f, --enforce             Enforce quotas by blocking writes when threshold is exceeded"
    echo "  -t, --enforce-threshold <percent> Threshold for enforcing quotas (default: 95)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -w|--warn)
            WARN_THRESHOLD="$2"
            shift
            shift
            ;;
        -c|--critical)
            CRITICAL_THRESHOLD="$2"
            shift
            shift
            ;;
        -n|--notice)
            NOTICE_THRESHOLD="$2"
            shift
            shift
            ;;
        -e|--email)
            NOTIFY_EMAIL="$2"
            shift
            shift
            ;;
        -u|--webhook)
            NOTIFY_WEBHOOK="$2"
            shift
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=1
            shift
            ;;
        -p|--prometheus)
            PROMETHEUS_OUTPUT=1
            shift
            ;;
        -f|--enforce)
            ENFORCE_QUOTAS=1
            shift
            ;;
        -t|--enforce-threshold)
            ENFORCE_THRESHOLD="$2"
            shift
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Initialize log file
echo "SMB Gateway Quota Monitoring" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Notice Threshold: $NOTICE_THRESHOLD%" >> $LOG_FILE
echo "Warning Threshold: $WARN_THRESHOLD%" >> $LOG_FILE
echo "Critical Threshold: $CRITICAL_THRESHOLD%" >> $LOG_FILE
if [ -n "$NOTIFY_EMAIL" ]; then
    echo "Notification Email: $NOTIFY_EMAIL" >> $LOG_FILE
fi
if [ -n "$NOTIFY_WEBHOOK" ]; then
    echo "Notification Webhook: $NOTIFY_WEBHOOK" >> $LOG_FILE
fi
if [ $ENFORCE_QUOTAS -eq 1 ]; then
    echo "Quota Enforcement: Enabled (Threshold: $ENFORCE_THRESHOLD%)" >> $LOG_FILE
fi
echo "----------------------------------------" >> $LOG_FILE

# Create quota directory if it doesn't exist
mkdir -p $QUOTA_DIR

# Function to get filesystem type
get_fs_type() {
    local path=$1
    
    # Get filesystem type
    local df_output=$(df -T "$path" 2>/dev/null | tail -1)
    local fs_type=$(echo "$df_output" | awk '{print $2}')
    
    if [ -n "$fs_type" ]; then
        echo "$fs_type"
        return
    fi
    
    # Check if it's a ZFS dataset
    zfs list "$path" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "zfs"
        return
    fi
    
    # Default to ext4
    echo "ext4"
}

# Function to get quota usage
get_quota_usage() {
    local path=$1
    local quota=$2
    
    # Get filesystem type
    local fs_type=$(get_fs_type "$path")
    
    case "$fs_type" in
        zfs)
            get_zfs_quota_usage "$path" "$quota"
            ;;
        xfs)
            get_xfs_quota_usage "$path" "$quota"
            ;;
        *)
            get_user_quota_usage "$path" "$quota"
            ;;
    esac
}

# Function to get ZFS quota usage
get_zfs_quota_usage() {
    local path=$1
    local quota=$2
    
    # Get ZFS dataset name
    local dataset=$(zfs list | grep "$path" | awk '{print $1}')
    
    if [ -n "$dataset" ]; then
        # Get ZFS quota and used space
        local zfs_quota=$(zfs get -H -o value quota "$dataset")
        local used=$(zfs get -H -o value used "$dataset")
        
        # If quota is not set in ZFS, use the one from the config
        if [ "$zfs_quota" = "none" ]; then
            zfs_quota=$quota
        fi
        
        # Convert to bytes
        local quota_bytes=$(human_to_bytes "$zfs_quota")
        local used_bytes=$(human_to_bytes "$used")
        
        # Calculate percentage
        local percent=0
        if [ $quota_bytes -gt 0 ]; then
            percent=$((used_bytes * 100 / quota_bytes))
        fi
        
        echo "$used $zfs_quota $percent"
    else
        echo "unknown $quota 0"
    fi
}

# Function to get XFS quota usage
get_xfs_quota_usage() {
    local path=$1
    local quota=$2
    
    # Get mount point
    local mount_point=$(df "$path" | tail -1 | awk '{print $6}')
    
    # Find project ID
    local project_id=""
    if [ -f "/etc/projects" ]; then
        project_id=$(grep -E "^[0-9]+:$path$" /etc/projects | cut -d: -f1)
    fi
    
    if [ -n "$project_id" ]; then
        # Get quota usage
        local quota_output=$(xfs_quota -x -c "report -p" "$mount_point" | grep "#$project_id")
        local used_blocks=$(echo "$quota_output" | awk '{print $2}')
        local quota_blocks=$(echo "$quota_output" | awk '{print $3}')
        
        # Convert to bytes (blocks are 1KB)
        local used_bytes=$((used_blocks * 1024))
        local quota_bytes=$((quota_blocks * 1024))
        
        # Calculate percentage
        local percent=0
        if [ $quota_bytes -gt 0 ]; then
            percent=$((used_bytes * 100 / quota_bytes))
        fi
        
        echo "$(bytes_to_human $used_bytes) $(bytes_to_human $quota_bytes) $percent"
    else
        echo "unknown $quota 0"
    fi
}

# Function to get user quota usage
get_user_quota_usage() {
    local path=$1
    local quota=$2
    
    # Get mount point
    local mount_point=$(df "$path" | tail -1 | awk '{print $6}')
    
    # Get quota usage
    local quota_output=$(quota -u root | tail -1)
    local used_blocks=$(echo "$quota_output" | awk '{print $2}')
    local quota_blocks=$(echo "$quota_output" | awk '{print $3}')
    
    # Convert to bytes (blocks are 1KB)
    local used_bytes=$((used_blocks * 1024))
    local quota_bytes=$((quota_blocks * 1024))
    
    # Calculate percentage
    local percent=0
    if [ $quota_bytes -gt 0 ]; then
        percent=$((used_bytes * 100 / quota_bytes))
    fi
    
    echo "$(bytes_to_human $used_bytes) $(bytes_to_human $quota_bytes) $percent"
}

# Function to convert human-readable size to bytes
human_to_bytes() {
    local human=$1
    
    if [[ $human =~ ^([0-9]+)([KMGT]?)$ ]]; then
        local size=${BASH_REMATCH[1]}
        local unit=${BASH_REMATCH[2]}
        
        case "$unit" in
            K)
                echo $((size * 1024))
                ;;
            M)
                echo $((size * 1024 * 1024))
                ;;
            G)
                echo $((size * 1024 * 1024 * 1024))
                ;;
            T)
                echo $((size * 1024 * 1024 * 1024 * 1024))
                ;;
            *)
                echo $size
                ;;
        esac
    else
        echo 0
    fi
}

# Function to convert bytes to human-readable size
bytes_to_human() {
    local bytes=$1
    
    if [ $bytes -ge $((1024 * 1024 * 1024 * 1024)) ]; then
        echo "$(echo "scale=1; $bytes / (1024 * 1024 * 1024 * 1024)" | bc)T"
    elif [ $bytes -ge $((1024 * 1024 * 1024)) ]; then
        echo "$(echo "scale=1; $bytes / (1024 * 1024 * 1024)" | bc)G"
    elif [ $bytes -ge $((1024 * 1024)) ]; then
        echo "$(echo "scale=1; $bytes / (1024 * 1024)" | bc)M"
    elif [ $bytes -ge 1024 ]; then
        echo "$(echo "scale=1; $bytes / 1024" | bc)K"
    else
        echo "${bytes}B"
    fi
}

# Function to send email notification
send_email_notification() {
    local subject=$1
    local message=$2
    
    if [ -n "$NOTIFY_EMAIL" ]; then
        echo "$message" | mail -s "$subject" "$NOTIFY_EMAIL"
        log "Email notification sent to $NOTIFY_EMAIL"
    fi
}

# Function to send webhook notification
send_webhook_notification() {
    local subject=$1
    local message=$2
    
    if [ -n "$NOTIFY_WEBHOOK" ]; then
        # Format message as JSON
        local json_message=$(cat <<EOF
{
  "title": "$subject",
  "message": "$message",
  "timestamp": "$(date -Iseconds)"
}
EOF
)
        
        # Send webhook
        curl -s -X POST -H "Content-Type: application/json" -d "$json_message" "$NOTIFY_WEBHOOK" >/dev/null
        log "Webhook notification sent to $NOTIFY_WEBHOOK"
    fi
}

# Function to send notifications
send_notification() {
    local subject=$1
    local message=$2
    
    send_email_notification "$subject" "$message"
    send_webhook_notification "$subject" "$message"
}

# Function to enforce quota
enforce_quota() {
    local path=$1
    local percent=$2
    local readonly=$3
    
    if [ $ENFORCE_QUOTAS -eq 1 ] && [ $percent -ge $ENFORCE_THRESHOLD ]; then
        if [ "$readonly" != "true" ]; then
            log "Enforcing quota on $path by setting read-only mode"
            
            # Get filesystem type
            local fs_type=$(get_fs_type "$path")
            
            case "$fs_type" in
                zfs)
                    # For ZFS, set readonly property
                    local dataset=$(zfs list | grep "$path" | awk '{print $1}')
                    if [ -n "$dataset" ]; then
                        zfs set readonly=on "$dataset"
                        log "Set ZFS dataset $dataset to read-only mode"
                        return 0
                    fi
                    ;;
                *)
                    # For other filesystems, use mount -o remount,ro
                    local mount_point=$(df "$path" | tail -1 | awk '{print $6}')
                    if [ -n "$mount_point" ]; then
                        mount -o remount,ro "$mount_point"
                        log "Remounted $mount_point as read-only"
                        return 0
                    fi
                    ;;
            esac
        fi
    elif [ $ENFORCE_QUOTAS -eq 1 ] && [ $percent -lt $ENFORCE_THRESHOLD ] && [ "$readonly" = "true" ]; then
        log "Removing quota enforcement on $path by setting read-write mode"
        
        # Get filesystem type
        local fs_type=$(get_fs_type "$path")
        
        case "$fs_type" in
            zfs)
                # For ZFS, set readonly property
                local dataset=$(zfs list | grep "$path" | awk '{print $1}')
                if [ -n "$dataset" ]; then
                    zfs set readonly=off "$dataset"
                    log "Set ZFS dataset $dataset back to read-write mode"
                    return 0
                fi
                ;;
            *)
                # For other filesystems, use mount -o remount,rw
                local mount_point=$(df "$path" | tail -1 | awk '{print $6}')
                if [ -n "$mount_point" ]; then
                    mount -o remount,rw "$mount_point"
                    log "Remounted $mount_point as read-write"
                    return 0
                fi
                ;;
        esac
    fi
    
    return 1
}

# Function to check if filesystem is readonly
is_readonly() {
    local path=$1
    
    # Get filesystem type
    local fs_type=$(get_fs_type "$path")
    
    case "$fs_type" in
        zfs)
            # For ZFS, check readonly property
            local dataset=$(zfs list | grep "$path" | awk '{print $1}')
            if [ -n "$dataset" ]; then
                local readonly=$(zfs get -H -o value readonly "$dataset")
                if [ "$readonly" = "on" ]; then
                    echo "true"
                    return
                fi
            fi
            ;;
        *)
            # For other filesystems, check mount options
            local mount_point=$(df "$path" | tail -1 | awk '{print $6}')
            if [ -n "$mount_point" ]; then
                local mount_options=$(mount | grep " $mount_point " | awk '{print $6}' | tr -d '()')
                if [[ $mount_options == *"ro"* ]]; then
                    echo "true"
                    return
                fi
            fi
            ;;
    esac
    
    echo "false"
}

# Initialize results array
declare -A results
results["timestamp"]=$(date -Iseconds)
results["notice_threshold"]=$NOTICE_THRESHOLD
results["warning_threshold"]=$WARN_THRESHOLD
results["critical_threshold"]=$CRITICAL_THRESHOLD
results["enforce_threshold"]=$ENFORCE_THRESHOLD
results["enforce_enabled"]=$ENFORCE_QUOTAS
results["shares"]=0
results["notices"]=0
results["warnings"]=0
results["criticals"]=0
results["enforced"]=0

# Get list of shares from storage.cfg
SHARES=()
if [ -f "/etc/pve/storage.cfg" ]; then
    while read -r line; do
        if [[ $line =~ ^storage\ ([^\ ]+)$ ]]; then
            STORAGE_ID=${BASH_REMATCH[1]}
            
            # Check if it's an SMB Gateway storage
            TYPE=$(grep -A1 "storage $STORAGE_ID" /etc/pve/storage.cfg | grep "type smbgateway" | wc -l)
            if [ $TYPE -eq 1 ]; then
                # Get share name and path
                SHARENAME=$(grep -A10 "storage $STORAGE_ID" /etc/pve/storage.cfg | grep "sharename" | head -1 | awk '{print $2}')
                PATH=$(grep -A10 "storage $STORAGE_ID" /etc/pve/storage.cfg | grep "path" | head -1 | awk '{print $2}')
                QUOTA=$(grep -A10 "storage $STORAGE_ID" /etc/pve/storage.cfg | grep "quota" | head -1 | awk '{print $2}')
                
                if [ -n "$SHARENAME" ] && [ -n "$PATH" ] && [ -n "$QUOTA" ]; then
                    SHARES+=("$STORAGE_ID:$SHARENAME:$PATH:$QUOTA")
                fi
            fi
        fi
    done < "/etc/pve/storage.cfg"
fi

# Check quota usage for each share
SHARE_COUNT=0
NOTICE_COUNT=0
WARNING_COUNT=0
CRITICAL_COUNT=0
ENFORCED_COUNT=0
NOTICES=""
WARNINGS=""
CRITICALS=""
ENFORCED=""

for SHARE_INFO in "${SHARES[@]}"; do
    IFS=':' read -r STORAGE_ID SHARENAME PATH QUOTA <<< "$SHARE_INFO"
    
    log "Checking quota for share $SHARENAME ($PATH)"
    
    # Get quota usage
    USAGE=$(get_quota_usage "$PATH" "$QUOTA")
    IFS=' ' read -r USED LIMIT PERCENT <<< "$USAGE"
    
    log "Usage: $USED of $LIMIT ($PERCENT%)"
    
    # Store result
    results["share_$SHARE_COUNT"]="$SHARENAME"
    results["path_$SHARE_COUNT"]="$PATH"
    results["quota_$SHARE_COUNT"]="$LIMIT"
    results["used_$SHARE_COUNT"]="$USED"
    results["percent_$SHARE_COUNT"]="$PERCENT"
    
    # Check if filesystem is readonly
    READONLY=$(is_readonly "$PATH")
    results["readonly_$SHARE_COUNT"]=$READONLY
    
    # Check thresholds
    if [ $PERCENT -ge $CRITICAL_THRESHOLD ]; then
        results["status_$SHARE_COUNT"]="critical"
        CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
        CRITICALS="$CRITICALS\n$SHARENAME: $USED of $LIMIT ($PERCENT%)"
        
        # Try to enforce quota if enabled
        if enforce_quota "$PATH" $PERCENT "$READONLY"; then
            ENFORCED_COUNT=$((ENFORCED_COUNT + 1))
            ENFORCED="$ENFORCED\n$SHARENAME: Enforced quota at $PERCENT%"
            results["enforced_$SHARE_COUNT"]=1
        else
            results["enforced_$SHARE_COUNT"]=0
        fi
    elif [ $PERCENT -ge $WARN_THRESHOLD ]; then
        results["status_$SHARE_COUNT"]="warning"
        WARNING_COUNT=$((WARNING_COUNT + 1))
        WARNINGS="$WARNINGS\n$SHARENAME: $USED of $LIMIT ($PERCENT%)"
        results["enforced_$SHARE_COUNT"]=0
        
        # Remove enforcement if percent dropped below threshold
        if [ "$READONLY" = "true" ]; then
            enforce_quota "$PATH" $PERCENT "$READONLY"
        fi
    elif [ $PERCENT -ge $NOTICE_THRESHOLD ]; then
        results["status_$SHARE_COUNT"]="notice"
        NOTICE_COUNT=$((NOTICE_COUNT + 1))
        NOTICES="$NOTICES\n$SHARENAME: $USED of $LIMIT ($PERCENT%)"
        results["enforced_$SHARE_COUNT"]=0
        
        # Remove enforcement if percent dropped below threshold
        if [ "$READONLY" = "true" ]; then
            enforce_quota "$PATH" $PERCENT "$READONLY"
        fi
    else
        results["status_$SHARE_COUNT"]="ok"
        results["enforced_$SHARE_COUNT"]=0
        
        # Remove enforcement if percent dropped below threshold
        if [ "$READONLY" = "true" ]; then
            enforce_quota "$PATH" $PERCENT "$READONLY"
        fi
    fi
    
    SHARE_COUNT=$((SHARE_COUNT + 1))
done

results["shares"]=$SHARE_COUNT
results["notices"]=$NOTICE_COUNT
results["warnings"]=$WARNING_COUNT
results["criticals"]=$CRITICAL_COUNT
results["enforced"]=$ENFORCED_COUNT

# Send notifications if needed
if [ $CRITICAL_COUNT -gt 0 ]; then
    SUBJECT="CRITICAL: SMB Gateway Quota Alert"
    MESSAGE="The following shares have reached critical quota usage:\n$CRITICALS"
    if [ $ENFORCED_COUNT -gt 0 ]; then
        MESSAGE="$MESSAGE\n\nQuota enforcement has been applied to the following shares:\n$ENFORCED"
    fi
    send_notification "$SUBJECT" "$MESSAGE"
elif [ $WARNING_COUNT -gt 0 ]; then
    SUBJECT="WARNING: SMB Gateway Quota Alert"
    MESSAGE="The following shares have reached warning quota usage:\n$WARNINGS"
    send_notification "$SUBJECT" "$MESSAGE"
elif [ $NOTICE_COUNT -gt 0 ]; then
    SUBJECT="NOTICE: SMB Gateway Quota Alert"
    MESSAGE="The following shares have reached notice quota usage:\n$NOTICES"
    send_notification "$SUBJECT" "$MESSAGE"
fi

# Output results
if [ $JSON_OUTPUT -eq 1 ]; then
    # Output in JSON format
    echo "{"
    echo "  \"timestamp\": \"${results[timestamp]}\","
    echo "  \"notice_threshold\": ${results[notice_threshold]},"
    echo "  \"warning_threshold\": ${results[warning_threshold]},"
    echo "  \"critical_threshold\": ${results[critical_threshold]},"
    echo "  \"enforce_threshold\": ${results[enforce_threshold]},"
    echo "  \"enforce_enabled\": ${results[enforce_enabled]},"
    echo "  \"shares\": ${results[shares]},"
    echo "  \"notices\": ${results[notices]},"
    echo "  \"warnings\": ${results[warnings]},"
    echo "  \"criticals\": ${results[criticals]},"
    echo "  \"enforced\": ${results[enforced]},"
    echo "  \"share_details\": ["
    
    for ((i=0; i<SHARE_COUNT; i++)); do
        if [ $i -gt 0 ]; then
            echo "    ,"
        fi
        echo "    {"
        echo "      \"name\": \"${results[share_$i]}\","
        echo "      \"path\": \"${results[path_$i]}\","
        echo "      \"quota\": \"${results[quota_$i]}\","
        echo "      \"used\": \"${results[used_$i]}\","
        echo "      \"percent\": ${results[percent_$i]},"
        echo "      \"status\": \"${results[status_$i]}\","
        echo "      \"readonly\": ${results[readonly_$i]},"
        echo "      \"enforced\": ${results[enforced_$i]}"
        echo "    }"
    done
    
    echo "  ]"
    echo "}"
else
    # Output in human-readable format
    echo "SMB Gateway Quota Monitoring Results"
    echo "----------------------------------------"
    echo "Shares: ${results[shares]}"
    echo "Notices: ${results[notices]}"
    echo "Warnings: ${results[warnings]}"
    echo "Criticals: ${results[criticals]}"
    echo "Enforced: ${results[enforced]}"
    echo ""
    
    if [ $SHARE_COUNT -gt 0 ]; then
        printf "%-20s %-30s %-10s %-10s %-10s %-10s %-10s\n" "Share" "Path" "Quota" "Used" "Percent" "Status" "Enforced"
        echo "---------------------------------------------------------------------------------------------------------------------"
        
        for ((i=0; i<SHARE_COUNT; i++)); do
            ENFORCED_STATUS="No"
            if [ "${results[enforced_$i]}" = "1" ]; then
                ENFORCED_STATUS="Yes"
            fi
            
            printf "%-20s %-30s %-10s %-10s %-10s %-10s %-10s\n" \
                "${results[share_$i]}" \
                "${results[path_$i]}" \
                "${results[quota_$i]}" \
                "${results[used_$i]}" \
                "${results[percent_$i]}%" \
                "${results[status_$i]}" \
                "$ENFORCED_STATUS"
        done
    else
        echo "No shares found with quotas configured."
    fi
fi

exit 0# O
utput in Prometheus format if requested
if [ $PROMETHEUS_OUTPUT -eq 1 ]; then
    echo "# HELP smb_gateway_quota_percent Quota usage percentage"
    echo "# TYPE smb_gateway_quota_percent gauge"
    for ((i=0; i<SHARE_COUNT; i++)); do
        echo "smb_gateway_quota_percent{share=\"${results[share_$i]}\",path=\"${results[path_$i]}\",status=\"${results[status_$i]}\"} ${results[percent_$i]}"
    done
    
    echo "# HELP smb_gateway_quota_bytes_used Quota usage in bytes"
    echo "# TYPE smb_gateway_quota_bytes_used gauge"
    for ((i=0; i<SHARE_COUNT; i++)); do
        # Convert human-readable size to bytes
        USED_BYTES=$(human_to_bytes "${results[used_$i]}")
        echo "smb_gateway_quota_bytes_used{share=\"${results[share_$i]}\",path=\"${results[path_$i]}\",status=\"${results[status_$i]}\"} $USED_BYTES"
    done
    
    echo "# HELP smb_gateway_quota_bytes_total Quota limit in bytes"
    echo "# TYPE smb_gateway_quota_bytes_total gauge"
    for ((i=0; i<SHARE_COUNT; i++)); do
        # Convert human-readable size to bytes
        QUOTA_BYTES=$(human_to_bytes "${results[quota_$i]}")
        echo "smb_gateway_quota_bytes_total{share=\"${results[share_$i]}\",path=\"${results[path_$i]}\",status=\"${results[status_$i]}\"} $QUOTA_BYTES"
    done
    
    echo "# HELP smb_gateway_quota_enforced Whether quota enforcement is active"
    echo "# TYPE smb_gateway_quota_enforced gauge"
    for ((i=0; i<SHARE_COUNT; i++)); do
        echo "smb_gateway_quota_enforced{share=\"${results[share_$i]}\",path=\"${results[path_$i]}\",status=\"${results[status_$i]}\"} ${results[enforced_$i]}"
    done
    
    echo "# HELP smb_gateway_quota_readonly Whether filesystem is in readonly mode"
    echo "# TYPE smb_gateway_quota_readonly gauge"
    for ((i=0; i<SHARE_COUNT; i++)); do
        READONLY_VALUE=0
        if [ "${results[readonly_$i]}" = "true" ]; then
            READONLY_VALUE=1
        fi
        echo "smb_gateway_quota_readonly{share=\"${results[share_$i]}\",path=\"${results[path_$i]}\",status=\"${results[status_$i]}\"} $READONLY_VALUE"
    done
    
    echo "# HELP smb_gateway_quota_status_count Number of shares in each status"
    echo "# TYPE smb_gateway_quota_status_count gauge"
    echo "smb_gateway_quota_status_count{status=\"ok\"} $(( SHARE_COUNT - NOTICE_COUNT - WARNING_COUNT - CRITICAL_COUNT ))"
    echo "smb_gateway_quota_status_count{status=\"notice\"} ${results[notices]}"
    echo "smb_gateway_quota_status_count{status=\"warning\"} ${results[warnings]}"
    echo "smb_gateway_quota_status_count{status=\"critical\"} ${results[criticals]}"
    echo "smb_gateway_quota_status_count{status=\"enforced\"} ${results[enforced]}"
fi