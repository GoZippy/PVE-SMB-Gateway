#!/bin/bash
# SMB Gateway HA Health Check Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-ha-health.log"
SHARE_NAME=""
CHECK_ALL=0
VERBOSE=0
JSON_OUTPUT=0

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
    echo "  -s, --share <name>       Share name to check"
    echo "  -a, --all                Check all HA-enabled shares"
    echo "  -j, --json               Output results in JSON format"
    echo "  -v, --verbose            Enable verbose output"
    echo "  -h, --help               Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--share)
            SHARE_NAME="$2"
            shift
            shift
            ;;
        -a|--all)
            CHECK_ALL=1
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=1
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

# Check parameters
if [ -z "$SHARE_NAME" ] && [ $CHECK_ALL -eq 0 ]; then
    echo "Error: Either share name or --all option is required"
    usage
fi

# Initialize log file
echo "SMB Gateway HA Health Check" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
if [ -n "$SHARE_NAME" ]; then
    echo "Share: $SHARE_NAME" >> $LOG_FILE
else
    echo "Checking all HA-enabled shares" >> $LOG_FILE
fi
echo "----------------------------------------" >> $LOG_FILE

# Function to check a single share
check_share() {
    local share=$1
    local results=()
    
    log "Checking HA health for share '$share'..."
    
    # Get share status
    local share_status=$(pve-smbgateway status $share 2>/dev/null || echo "error")
    if [[ "$share_status" != *"active"* ]]; then
        results+=("Share '$share' is not active")
        return 1
    fi
    
    # Get VIP status
    local vip_status=$(pve-smbgateway vip-status $share 2>/dev/null || echo "error")
    if [[ "$vip_status" != *"active"* ]]; then
        results+=("VIP for share '$share' is not active")
        return 1
    fi
    
    # Extract active node and VIP
    local active_node=$(echo "$vip_status" | grep -oP '(?<=Active node: )[^\n]*' || echo "unknown")
    local vip=$(echo "$vip_status" | grep -oP '(?<=VIP )[0-9.]+' || echo "unknown")
    
    # Check if VIP is pingable
    if [ "$vip" != "unknown" ]; then
        ping -c 1 -W 1 $vip > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            results+=("VIP $vip is not pingable")
            return 1
        fi
    else
        results+=("Could not determine VIP for share '$share'")
        return 1
    fi
    
    # Check CTDB status
    local ctdb_status=""
    if [ "$active_node" != "unknown" ]; then
        if [ "$active_node" = "$(hostname)" ]; then
            # Local node
            ctdb_status=$(ctdb status 2>/dev/null || echo "error")
        else
            # Remote node
            ctdb_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$active_node "ctdb status" 2>/dev/null || echo "error")
        fi
        
        if [[ "$ctdb_status" != *"OK"* ]]; then
            results+=("CTDB status is not OK on node $active_node")
            return 1
        fi
    else
        results+=("Could not determine active node for share '$share'")
        return 1
    fi
    
    # Check Samba service
    local smb_status=""
    if [ "$active_node" != "unknown" ]; then
        if [ "$active_node" = "$(hostname)" ]; then
            # Local node
            smb_status=$(systemctl is-active smbd 2>/dev/null || echo "inactive")
        else
            # Remote node
            smb_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$active_node "systemctl is-active smbd" 2>/dev/null || echo "inactive")
        fi
        
        if [ "$smb_status" != "active" ]; then
            results+=("Samba service is not active on node $active_node")
            return 1
        fi
    fi
    
    # Check if share is accessible via SMB
    if [ "$vip" != "unknown" ]; then
        # Create temporary mount point
        local tmp_mount="/tmp/smb-health-check-$$"
        mkdir -p $tmp_mount
        
        # Try to mount the share
        mount -t cifs //$vip/$share $tmp_mount -o guest,ro > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            rmdir $tmp_mount
            results+=("Share '$share' is not accessible via SMB")
            return 1
        }
        
        # Unmount the share
        umount $tmp_mount
        rmdir $tmp_mount
    fi
    
    # All checks passed
    log "Share '$share' HA health check passed"
    return 0
}

# Function to get all HA-enabled shares
get_ha_shares() {
    local shares=()
    local all_shares=$(pve-smbgateway list 2>/dev/null | grep -v "^Share ID" | grep -v "^-" | awk '{print $1}')
    
    for share in $all_shares; do
        # Check if share has HA enabled
        local vip_status=$(pve-smbgateway vip-status $share 2>/dev/null || echo "")
        if [[ "$vip_status" == *"VIP status for share"* ]]; then
            shares+=("$share")
        fi
    done
    
    echo "${shares[@]}"
}

# Main execution
if [ $JSON_OUTPUT -eq 1 ]; then
    # Initialize JSON output
    echo -n '{"timestamp":"'$(date -Iseconds)'","results":{'
fi

if [ $CHECK_ALL -eq 1 ]; then
    # Check all HA-enabled shares
    shares=($(get_ha_shares))
    
    if [ ${#shares[@]} -eq 0 ]; then
        if [ $JSON_OUTPUT -eq 1 ]; then
            echo '},"status":"warning","message":"No HA-enabled shares found"}'
        else
            echo "Warning: No HA-enabled shares found"
        fi
        exit 0
    fi
    
    all_healthy=1
    first_share=1
    
    for share in "${shares[@]}"; do
        if [ $JSON_OUTPUT -eq 1 ]; then
            if [ $first_share -eq 0 ]; then
                echo -n ','
            fi
            echo -n '"'$share'":{'
            first_share=0
        fi
        
        check_share "$share"
        result=$?
        
        if [ $result -ne 0 ]; then
            all_healthy=0
            if [ $JSON_OUTPUT -eq 1 ]; then
                echo -n '"status":"unhealthy","message":"'${results[0]}'"}'
            else
                echo "Share '$share' health check failed: ${results[0]}"
            fi
        else
            if [ $JSON_OUTPUT -eq 1 ]; then
                echo -n '"status":"healthy","message":"HA health check passed"}'
            else
                echo "Share '$share' health check passed"
            fi
        fi
    done
    
    if [ $JSON_OUTPUT -eq 1 ]; then
        if [ $all_healthy -eq 1 ]; then
            echo '},"status":"healthy","message":"All shares are healthy"}'
        else
            echo '},"status":"unhealthy","message":"One or more shares are unhealthy"}'
        fi
    else
        if [ $all_healthy -eq 1 ]; then
            echo "All shares are healthy"
        else
            echo "One or more shares are unhealthy"
            exit 1
        fi
    fi
else
    # Check specific share
    if [ $JSON_OUTPUT -eq 1 ]; then
        echo -n '"'$SHARE_NAME'":{'
    fi
    
    check_share "$SHARE_NAME"
    result=$?
    
    if [ $result -ne 0 ]; then
        if [ $JSON_OUTPUT -eq 1 ]; then
            echo -n '"status":"unhealthy","message":"'${results[0]}'"}'
            echo '},"status":"unhealthy","message":"'${results[0]}'"}'
        else
            echo "Share '$SHARE_NAME' health check failed: ${results[0]}"
            exit 1
        fi
    else
        if [ $JSON_OUTPUT -eq 1 ]; then
            echo -n '"status":"healthy","message":"HA health check passed"}'
            echo '},"status":"healthy","message":"HA health check passed"}'
        else
            echo "Share '$SHARE_NAME' health check passed"
        fi
    fi
fi

exit 0