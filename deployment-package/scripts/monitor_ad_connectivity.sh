#!/bin/bash
# SMB Gateway Active Directory Connectivity Monitoring Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-ad-connectivity.log"
DOMAIN=""
MODE="native"
CONTAINER_ID=""
SHARE_NAME=""
VERBOSE=0
NOTIFY=1
MAX_LOG_SIZE=10485760  # 10MB

# Function to log messages
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ $VERBOSE -eq 1 ]; then
        echo "[$timestamp] $1"
    fi
    echo "[$timestamp] $1" >> $LOG_FILE
    
    # Rotate log if it gets too large
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --domain <domain>     AD domain to monitor"
    echo "  -s, --share <n>           Share name to monitor"
    echo "  -m, --mode <mode>         Mode: native, lxc, or vm (default: native)"
    echo "  -c, --container <id>      Container ID (required for LXC mode)"
    echo "  -n, --no-notify           Disable notifications"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--domain)
            DOMAIN="$2"
            shift
            shift
            ;;
        -s|--share)
            SHARE_NAME="$2"
            shift
            shift
            ;;
        -m|--mode)
            MODE="$2"
            shift
            shift
            ;;
        -c|--container)
            CONTAINER_ID="$2"
            shift
            shift
            ;;
        -n|--no-notify)
            NOTIFY=0
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
if [ "$MODE" = "lxc" ] && [ -z "$CONTAINER_ID" ]; then
    echo "Error: Container ID is required for LXC mode"
    usage
fi

# If no domain is specified but share is, try to extract domain from share config
if [ -z "$DOMAIN" ] && [ -n "$SHARE_NAME" ]; then
    if [ -f "/etc/pve/storage.cfg" ]; then
        DOMAIN=$(grep -A10 "storage $SHARE_NAME" /etc/pve/storage.cfg | grep "ad_domain" | head -1 | awk '{print $2}')
    fi
fi

# Exit if no domain is specified
if [ -z "$DOMAIN" ]; then
    if [ $VERBOSE -eq 1 ]; then
        echo "No domain specified, exiting"
    fi
    exit 0
fi

# Initialize log file if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    echo "SMB Gateway AD Connectivity Monitoring" > $LOG_FILE
    echo "Date: $(date)" >> $LOG_FILE
    echo "Domain: $DOMAIN" >> $LOG_FILE
    if [ -n "$SHARE_NAME" ]; then
        echo "Share: $SHARE_NAME" >> $LOG_FILE
    fi
    echo "Mode: $MODE" >> $LOG_FILE
    if [ "$MODE" = "lxc" ]; then
        echo "Container ID: $CONTAINER_ID" >> $LOG_FILE
    fi
    echo "----------------------------------------" >> $LOG_FILE
fi

# Function to execute commands based on mode
execute_cmd() {
    if [ "$MODE" = "native" ]; then
        eval "$@"
    elif [ "$MODE" = "lxc" ]; then
        pct exec $CONTAINER_ID -- bash -c "$@"
    elif [ "$MODE" = "vm" ]; then
        # For VM mode, we need to extract VM ID from storage config
        if [ -n "$SHARE_NAME" ] && [ -f "/etc/pve/storage.cfg" ]; then
            local VMID=$(grep -A10 "storage $SHARE_NAME" /etc/pve/storage.cfg | grep "vmid" | head -1 | awk '{print $2}')
            if [ -n "$VMID" ]; then
                qm guest exec $VMID -- bash -c "$@"
            else
                echo "Error: Could not determine VM ID for share $SHARE_NAME"
                return 1
            fi
        else
            echo "Error: Share name is required for VM mode"
            return 1
        fi
    else
        echo "Error: Unsupported mode $MODE"
        return 1
    fi
}

# Function to check DNS resolution
check_dns() {
    log "Checking DNS resolution for $DOMAIN"
    
    # Check if we can resolve the domain
    local DNS_RESULT=$(execute_cmd "host $DOMAIN 2>&1" || echo "error")
    if [[ "$DNS_RESULT" == *"not found"* ]] || [[ "$DNS_RESULT" == *"error"* ]]; then
        log "DNS resolution failed for $DOMAIN"
        return 1
    else
        log "DNS resolution successful for $DOMAIN"
        return 0
    fi
}

# Function to check network connectivity
check_connectivity() {
    log "Checking network connectivity to $DOMAIN"
    
    # Try to ping the domain
    local PING_RESULT=$(execute_cmd "ping -c 1 -W 2 $DOMAIN 2>&1" || echo "error")
    if [[ "$PING_RESULT" == *"error"* ]] || [[ "$PING_RESULT" == *"100% packet loss"* ]]; then
        log "Cannot ping $DOMAIN"
        return 1
    else
        log "Successfully pinged $DOMAIN"
        return 0
    fi
}

# Function to check LDAP connectivity
check_ldap() {
    log "Checking LDAP connectivity to $DOMAIN"
    
    # Check if we can connect to LDAP port
    local LDAP_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 389 2>&1" || echo "error")
    if [[ "$LDAP_RESULT" == *"error"* ]] || [[ "$LDAP_RESULT" == *"failed"* ]]; then
        log "Cannot connect to LDAP port on $DOMAIN"
        return 1
    else
        log "Successfully connected to LDAP port on $DOMAIN"
        return 0
    fi
}

# Function to check Kerberos connectivity
check_kerberos() {
    log "Checking Kerberos connectivity to $DOMAIN"
    
    # Check if we can connect to Kerberos port
    local KERBEROS_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 88 2>&1" || echo "error")
    if [[ "$KERBEROS_RESULT" == *"error"* ]] || [[ "$KERBEROS_RESULT" == *"failed"* ]]; then
        log "Cannot connect to Kerberos port on $DOMAIN"
        return 1
    else
        log "Successfully connected to Kerberos port on $DOMAIN"
        return 0
    fi
}

# Function to check domain membership
check_domain_membership() {
    log "Checking domain membership"
    
    # Check domain membership with net ads info
    local NET_ADS_INFO=$(execute_cmd "net ads info 2>&1" || echo "error")
    if [[ "$NET_ADS_INFO" == *"No credentials cache found"* ]] || [[ "$NET_ADS_INFO" == *"error"* ]]; then
        log "Not joined to domain $DOMAIN"
        return 1
    else
        log "Joined to domain $DOMAIN"
        return 0
    fi
}

# Function to check Kerberos tickets
check_kerberos_tickets() {
    log "Checking Kerberos tickets"
    
    # Check if we have valid Kerberos tickets
    local KLIST_RESULT=$(execute_cmd "klist 2>&1" || echo "error")
    if [[ "$KLIST_RESULT" == *"No credentials cache found"* ]] || [[ "$KLIST_RESULT" == *"error"* ]]; then
        log "No Kerberos tickets found"
        return 1
    else
        log "Kerberos tickets found"
        
        # Check if tickets are expired
        if [[ "$KLIST_RESULT" == *"krbtgt"* ]] && [[ "$KLIST_RESULT" != *"EXPIRED"* ]]; then
            log "Valid Kerberos tickets found"
            return 0
        else
            log "Expired Kerberos tickets found"
            return 1
        fi
    fi
}

# Function to send notification
send_notification() {
    local status=$1
    local message=$2
    
    if [ $NOTIFY -eq 1 ]; then
        # Log the notification
        log "Notification: $message"
        
        # Create status file for UI to read
        local STATUS_DIR="/var/lib/pve-smbgateway/status"
        mkdir -p $STATUS_DIR
        
        local STATUS_FILE="$STATUS_DIR/${SHARE_NAME:-default}_ad_status.json"
        
        echo "{" > $STATUS_FILE
        echo "  \"timestamp\": \"$(date -Iseconds)\"," >> $STATUS_FILE
        echo "  \"domain\": \"$DOMAIN\"," >> $STATUS_FILE
        if [ -n "$SHARE_NAME" ]; then
            echo "  \"share\": \"$SHARE_NAME\"," >> $STATUS_FILE
        fi
        echo "  \"status\": \"$status\"," >> $STATUS_FILE
        echo "  \"message\": \"$message\"" >> $STATUS_FILE
        echo "}" >> $STATUS_FILE
        
        # If we have a share name, update the smb.conf with a comment
        if [ -n "$SHARE_NAME" ]; then
            local SMB_CONF=$(execute_cmd "cat /etc/samba/smb.conf 2>/dev/null" || echo "error")
            if [[ "$SMB_CONF" != *"error"* ]] && [[ "$SMB_CONF" == *"[$SHARE_NAME]"* ]]; then
                # Update the share section with a comment about AD status
                execute_cmd "sed -i '/\\[$SHARE_NAME\\]/a\\  # AD Status: $status - $message ($(date))' /etc/samba/smb.conf"
                execute_cmd "sed -i '/\\[$SHARE_NAME\\]/ {n;/^  # AD Status:/d}' /etc/samba/smb.conf"
                
                # Restart Samba to apply changes
                execute_cmd "systemctl restart smbd"
            fi
        fi
    fi
}

# Run all checks
DNS_OK=0
CONN_OK=0
LDAP_OK=0
KERB_OK=0
DOMAIN_OK=0
TICKETS_OK=0

check_dns
DNS_OK=$?

if [ $DNS_OK -eq 0 ]; then
    check_connectivity
    CONN_OK=$?
    
    if [ $CONN_OK -eq 0 ]; then
        check_ldap
        LDAP_OK=$?
        
        check_kerberos
        KERB_OK=$?
        
        check_domain_membership
        DOMAIN_OK=$?
        
        check_kerberos_tickets
        TICKETS_OK=$?
    fi
fi

# Determine overall status
if [ $DNS_OK -eq 0 ] && [ $CONN_OK -eq 0 ] && [ $LDAP_OK -eq 0 ] && [ $KERB_OK -eq 0 ] && [ $DOMAIN_OK -eq 0 ] && [ $TICKETS_OK -eq 0 ]; then
    log "AD connectivity is healthy"
    send_notification "healthy" "AD connectivity is healthy"
    exit 0
elif [ $DNS_OK -ne 0 ] || [ $CONN_OK -ne 0 ]; then
    log "AD domain $DOMAIN is unreachable"
    send_notification "unreachable" "AD domain $DOMAIN is unreachable, using local authentication fallback"
    exit 1
elif [ $LDAP_OK -ne 0 ] || [ $KERB_OK -ne 0 ]; then
    log "AD services on $DOMAIN are not responding"
    send_notification "services_down" "AD services on $DOMAIN are not responding, using local authentication fallback"
    exit 1
elif [ $DOMAIN_OK -ne 0 ]; then
    log "Not joined to AD domain $DOMAIN"
    send_notification "not_joined" "Not joined to AD domain $DOMAIN, using local authentication fallback"
    exit 1
elif [ $TICKETS_OK -ne 0 ]; then
    log "No valid Kerberos tickets for $DOMAIN"
    send_notification "no_tickets" "No valid Kerberos tickets for $DOMAIN, using local authentication fallback"
    exit 1
else
    log "AD connectivity has issues"
    send_notification "issues" "AD connectivity has issues, using local authentication fallback"
    exit 1
fi