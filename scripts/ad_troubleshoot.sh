#!/bin/bash
# SMB Gateway Active Directory Troubleshooting Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-ad-troubleshoot.log"
DOMAIN=""
MODE="native"
CONTAINER_ID=""
SHARE_NAME=""
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
    echo "  -d, --domain <domain>     AD domain to troubleshoot"
    echo "  -s, --share <name>        Share name to troubleshoot"
    echo "  -m, --mode <mode>         Mode: native, lxc, or vm (default: native)"
    echo "  -c, --container <id>      Container ID (required for LXC mode)"
    echo "  -j, --json                Output results in JSON format"
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

# Initialize log file
echo "SMB Gateway AD Troubleshooting" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
if [ -n "$DOMAIN" ]; then
    echo "Domain: $DOMAIN" >> $LOG_FILE
fi
if [ -n "$SHARE_NAME" ]; then
    echo "Share: $SHARE_NAME" >> $LOG_FILE
fi
echo "Mode: $MODE" >> $LOG_FILE
if [ "$MODE" = "lxc" ]; then
    echo "Container ID: $CONTAINER_ID" >> $LOG_FILE
fi
echo "----------------------------------------" >> $LOG_FILE

# Initialize results array
declare -A results
results["timestamp"]=$(date -Iseconds)
results["mode"]=$MODE
if [ -n "$DOMAIN" ]; then
    results["domain"]=$DOMAIN
fi
if [ -n "$SHARE_NAME" ]; then
    results["share"]=$SHARE_NAME
fi
results["overall_status"]="unknown"

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
    log "Checking DNS resolution"
    results["dns_resolution"]="unknown"
    
    if [ -z "$DOMAIN" ]; then
        log "No domain specified, skipping DNS checks"
        results["dns_resolution"]="skipped"
        results["dns_details"]="No domain specified"
        return
    }
    
    # Check if we can resolve the domain
    local DNS_RESULT=$(execute_cmd "host $DOMAIN 2>&1" || echo "error")
    if [[ "$DNS_RESULT" == *"not found"* ]] || [[ "$DNS_RESULT" == *"error"* ]]; then
        log "DNS resolution failed for $DOMAIN"
        results["dns_resolution"]="failed"
        results["dns_details"]="Cannot resolve domain $DOMAIN"
    else
        log "DNS resolution successful for $DOMAIN"
        results["dns_resolution"]="success"
        results["dns_details"]="Domain $DOMAIN resolves to: $DNS_RESULT"
        
        # Check SRV records for domain controllers
        local SRV_RESULT=$(execute_cmd "host -t SRV _ldap._tcp.$DOMAIN 2>&1" || echo "error")
        if [[ "$SRV_RESULT" == *"not found"* ]] || [[ "$SRV_RESULT" == *"error"* ]]; then
            log "SRV record lookup failed for _ldap._tcp.$DOMAIN"
            results["srv_lookup"]="failed"
            results["srv_details"]="Cannot find SRV records for domain controllers"
        else
            log "SRV record lookup successful for _ldap._tcp.$DOMAIN"
            results["srv_lookup"]="success"
            results["srv_details"]="Found domain controllers: $SRV_RESULT"
        fi
    fi
}

# Function to check network connectivity
check_connectivity() {
    log "Checking network connectivity"
    results["network_connectivity"]="unknown"
    
    if [ -z "$DOMAIN" ]; then
        log "No domain specified, skipping connectivity checks"
        results["network_connectivity"]="skipped"
        results["connectivity_details"]="No domain specified"
        return
    }
    
    # Try to ping the domain
    local PING_RESULT=$(execute_cmd "ping -c 1 -W 2 $DOMAIN 2>&1" || echo "error")
    if [[ "$PING_RESULT" == *"error"* ]] || [[ "$PING_RESULT" == *"100% packet loss"* ]]; then
        log "Cannot ping $DOMAIN"
        results["network_connectivity"]="failed"
        results["connectivity_details"]="Cannot ping domain $DOMAIN"
    else
        log "Successfully pinged $DOMAIN"
        results["network_connectivity"]="success"
        results["connectivity_details"]="Domain $DOMAIN is reachable"
        
        # Check if we can connect to LDAP port
        local LDAP_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 389 2>&1" || echo "error")
        if [[ "$LDAP_RESULT" == *"error"* ]] || [[ "$LDAP_RESULT" == *"failed"* ]]; then
            log "Cannot connect to LDAP port on $DOMAIN"
            results["ldap_connectivity"]="failed"
            results["ldap_details"]="Cannot connect to LDAP port (389) on $DOMAIN"
        else
            log "Successfully connected to LDAP port on $DOMAIN"
            results["ldap_connectivity"]="success"
            results["ldap_details"]="LDAP port (389) on $DOMAIN is reachable"
        fi
        
        # Check if we can connect to Kerberos port
        local KERBEROS_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 88 2>&1" || echo "error")
        if [[ "$KERBEROS_RESULT" == *"error"* ]] || [[ "$KERBEROS_RESULT" == *"failed"* ]]; then
            log "Cannot connect to Kerberos port on $DOMAIN"
            results["kerberos_connectivity"]="failed"
            results["kerberos_details"]="Cannot connect to Kerberos port (88) on $DOMAIN"
        else
            log "Successfully connected to Kerberos port on $DOMAIN"
            results["kerberos_connectivity"]="success"
            results["kerberos_details"]="Kerberos port (88) on $DOMAIN is reachable"
        fi
    fi
}

# Function to check Kerberos configuration
check_kerberos() {
    log "Checking Kerberos configuration"
    results["kerberos_config"]="unknown"
    
    # Check if krb5.conf exists
    local KRB5_CONF=$(execute_cmd "cat /etc/krb5.conf 2>&1" || echo "error")
    if [[ "$KRB5_CONF" == *"error"* ]] || [[ "$KRB5_CONF" == *"No such file"* ]]; then
        log "Kerberos configuration file not found"
        results["kerberos_config"]="missing"
        results["kerberos_details"]="Kerberos configuration file (/etc/krb5.conf) not found"
    else
        log "Kerberos configuration file found"
        results["kerberos_config"]="found"
        
        # Check if domain is configured in krb5.conf
        if [ -n "$DOMAIN" ]; then
            local REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
            if [[ "$KRB5_CONF" == *"$REALM"* ]]; then
                log "Domain $DOMAIN is configured in krb5.conf"
                results["kerberos_domain"]="configured"
                results["kerberos_details"]="Domain $DOMAIN is properly configured in krb5.conf"
            else
                log "Domain $DOMAIN is not configured in krb5.conf"
                results["kerberos_domain"]="not_configured"
                results["kerberos_details"]="Domain $DOMAIN is not configured in krb5.conf"
            fi
        fi
        
        # Check if keytab file exists
        local KEYTAB_CHECK=$(execute_cmd "ls -la /etc/krb5.keytab 2>&1" || echo "error")
        if [[ "$KEYTAB_CHECK" == *"error"* ]] || [[ "$KEYTAB_CHECK" == *"No such file"* ]]; then
            log "Kerberos keytab file not found"
            results["kerberos_keytab"]="missing"
        else
            log "Kerberos keytab file found"
            results["kerberos_keytab"]="found"
            
            # Check keytab entries
            local KEYTAB_ENTRIES=$(execute_cmd "klist -k /etc/krb5.keytab 2>&1" || echo "error")
            if [[ "$KEYTAB_ENTRIES" == *"error"* ]] || [[ "$KEYTAB_ENTRIES" == *"No such file"* ]]; then
                log "Cannot list keytab entries"
                results["keytab_entries"]="error"
            else
                log "Keytab entries: $KEYTAB_ENTRIES"
                results["keytab_entries"]="found"
                results["keytab_details"]="$KEYTAB_ENTRIES"
            fi
        fi
    fi
}

# Function to check Samba configuration
check_samba() {
    log "Checking Samba configuration"
    results["samba_config"]="unknown"
    
    # Check if smb.conf exists
    local SMB_CONF=$(execute_cmd "cat /etc/samba/smb.conf 2>&1" || echo "error")
    if [[ "$SMB_CONF" == *"error"* ]] || [[ "$SMB_CONF" == *"No such file"* ]]; then
        log "Samba configuration file not found"
        results["samba_config"]="missing"
        results["samba_details"]="Samba configuration file (/etc/samba/smb.conf) not found"
    else
        log "Samba configuration file found"
        results["samba_config"]="found"
        
        # Check if security = ads is configured
        if [[ "$SMB_CONF" == *"security = ads"* ]]; then
            log "Samba is configured for Active Directory"
            results["samba_ad_mode"]="configured"
            results["samba_details"]="Samba is configured for Active Directory authentication"
        else
            log "Samba is not configured for Active Directory"
            results["samba_ad_mode"]="not_configured"
            results["samba_details"]="Samba is not configured for Active Directory authentication"
        fi
        
        # Check if domain is configured in smb.conf
        if [ -n "$DOMAIN" ]; then
            local REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
            local WORKGROUP=$(echo "$DOMAIN" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')
            
            if [[ "$SMB_CONF" == *"realm = $REALM"* ]]; then
                log "Domain realm is properly configured in smb.conf"
                results["samba_realm"]="configured"
            else
                log "Domain realm is not properly configured in smb.conf"
                results["samba_realm"]="not_configured"
            fi
            
            if [[ "$SMB_CONF" == *"workgroup = $WORKGROUP"* ]]; then
                log "Domain workgroup is properly configured in smb.conf"
                results["samba_workgroup"]="configured"
            else
                log "Domain workgroup is not properly configured in smb.conf"
                results["samba_workgroup"]="not_configured"
            fi
        fi
        
        # Check if share exists in smb.conf
        if [ -n "$SHARE_NAME" ]; then
            if [[ "$SMB_CONF" == *"[$SHARE_NAME]"* ]]; then
                log "Share $SHARE_NAME is configured in smb.conf"
                results["share_config"]="found"
            else
                log "Share $SHARE_NAME is not configured in smb.conf"
                results["share_config"]="not_found"
            fi
        fi
    fi
    
    # Check Samba service status
    local SMBD_STATUS=$(execute_cmd "systemctl is-active smbd 2>&1" || echo "error")
    if [[ "$SMBD_STATUS" == "active" ]]; then
        log "Samba service is running"
        results["samba_service"]="running"
    else
        log "Samba service is not running"
        results["samba_service"]="not_running"
    fi
    
    # Check Winbind service status
    local WINBIND_STATUS=$(execute_cmd "systemctl is-active winbind 2>&1" || echo "error")
    if [[ "$WINBIND_STATUS" == "active" ]]; then
        log "Winbind service is running"
        results["winbind_service"]="running"
    else
        log "Winbind service is not running"
        results["winbind_service"]="not_running"
    fi
}

# Function to check domain membership
check_domain_membership() {
    log "Checking domain membership"
    results["domain_membership"]="unknown"
    
    if [ -z "$DOMAIN" ]; then
        log "No domain specified, skipping domain membership checks"
        results["domain_membership"]="skipped"
        results["membership_details"]="No domain specified"
        return
    }
    
    # Check domain membership with net ads info
    local NET_ADS_INFO=$(execute_cmd "net ads info 2>&1" || echo "error")
    if [[ "$NET_ADS_INFO" == *"No credentials cache found"* ]] || [[ "$NET_ADS_INFO" == *"error"* ]]; then
        log "Not joined to domain $DOMAIN"
        results["domain_membership"]="not_joined"
        results["membership_details"]="Not joined to domain $DOMAIN"
    else
        log "Joined to domain $DOMAIN"
        results["domain_membership"]="joined"
        results["membership_details"]="$NET_ADS_INFO"
        
        # Check domain users
        local DOMAIN_USERS=$(execute_cmd "wbinfo -u | head -5 2>&1" || echo "error")
        if [[ "$DOMAIN_USERS" == *"error"* ]] || [[ "$DOMAIN_USERS" == *"failed"* ]]; then
            log "Cannot list domain users"
            results["domain_users"]="error"
        else
            log "Domain users: $DOMAIN_USERS"
            results["domain_users"]="success"
            results["users_details"]="$DOMAIN_USERS"
        fi
        
        # Check domain groups
        local DOMAIN_GROUPS=$(execute_cmd "wbinfo -g | head -5 2>&1" || echo "error")
        if [[ "$DOMAIN_GROUPS" == *"error"* ]] || [[ "$DOMAIN_GROUPS" == *"failed"* ]]; then
            log "Cannot list domain groups"
            results["domain_groups"]="error"
        else
            log "Domain groups: $DOMAIN_GROUPS"
            results["domain_groups"]="success"
            results["groups_details"]="$DOMAIN_GROUPS"
        fi
    fi
}

# Function to check authentication
check_authentication() {
    log "Checking authentication"
    results["authentication"]="unknown"
    
    if [ -z "$DOMAIN" ]; then
        log "No domain specified, skipping authentication checks"
        results["authentication"]="skipped"
        results["auth_details"]="No domain specified"
        return
    }
    
    # Check if we can get a Kerberos ticket
    local KINIT_TEST=$(execute_cmd "echo 'test_password' | kinit test_user@$(echo $DOMAIN | tr '[:lower:]' '[:upper:]') 2>&1" || echo "error")
    if [[ "$KINIT_TEST" != *"Password incorrect"* ]] && [[ "$KINIT_TEST" != *"Client not found"* ]]; then
        log "Kerberos authentication is not working properly"
        results["kerberos_auth"]="error"
        results["kerberos_auth_details"]="Unexpected response from kinit: $KINIT_TEST"
    else
        log "Kerberos authentication mechanism is working"
        results["kerberos_auth"]="success"
        results["kerberos_auth_details"]="Kerberos authentication mechanism is properly configured"
    fi
    
    # Check if we can authenticate with wbinfo
    local WBINFO_TEST=$(execute_cmd "wbinfo -a test_user%test_password 2>&1" || echo "error")
    if [[ "$WBINFO_TEST" == *"error"* ]] && [[ "$WBINFO_TEST" != *"NT_STATUS_LOGON_FAILURE"* ]]; then
        log "Winbind authentication is not working properly"
        results["winbind_auth"]="error"
        results["winbind_auth_details"]="Unexpected response from wbinfo: $WBINFO_TEST"
    else
        log "Winbind authentication mechanism is working"
        results["winbind_auth"]="success"
        results["winbind_auth_details"]="Winbind authentication mechanism is properly configured"
    fi
}

# Function to check nsswitch configuration
check_nsswitch() {
    log "Checking nsswitch configuration"
    results["nsswitch_config"]="unknown"
    
    # Check if nsswitch.conf exists
    local NSSWITCH_CONF=$(execute_cmd "cat /etc/nsswitch.conf 2>&1" || echo "error")
    if [[ "$NSSWITCH_CONF" == *"error"* ]] || [[ "$NSSWITCH_CONF" == *"No such file"* ]]; then
        log "nsswitch.conf file not found"
        results["nsswitch_config"]="missing"
        results["nsswitch_details"]="nsswitch.conf file not found"
    else
        log "nsswitch.conf file found"
        results["nsswitch_config"]="found"
        
        # Check if winbind is configured in nsswitch.conf
        if [[ "$NSSWITCH_CONF" == *"winbind"* ]]; then
            log "Winbind is configured in nsswitch.conf"
            results["nsswitch_winbind"]="configured"
            results["nsswitch_details"]="Winbind is properly configured in nsswitch.conf"
        else
            log "Winbind is not configured in nsswitch.conf"
            results["nsswitch_winbind"]="not_configured"
            results["nsswitch_details"]="Winbind is not configured in nsswitch.conf"
        fi
    fi
}

# Run all checks
check_dns
check_connectivity
check_kerberos
check_samba
check_domain_membership
check_authentication
check_nsswitch

# Determine overall status
if [[ "${results[domain_membership]}" == "joined" ]] && 
   [[ "${results[samba_config]}" == "found" ]] && 
   [[ "${results[samba_ad_mode]}" == "configured" ]] && 
   [[ "${results[samba_service]}" == "running" ]] && 
   [[ "${results[winbind_service]}" == "running" ]]; then
    results["overall_status"]="healthy"
    results["overall_message"]="AD integration is properly configured and working"
elif [[ "${results[domain_membership]}" == "not_joined" ]] || 
     [[ "${results[samba_ad_mode]}" != "configured" ]]; then
    results["overall_status"]="not_configured"
    results["overall_message"]="AD integration is not properly configured"
else
    results["overall_status"]="issues"
    results["overall_message"]="AD integration has configuration issues"
fi

# Output results
if [ $JSON_OUTPUT -eq 1 ]; then
    # Output in JSON format
    echo "{"
    echo "  \"timestamp\": \"${results[timestamp]}\","
    echo "  \"mode\": \"${results[mode]}\","
    if [ -n "$DOMAIN" ]; then
        echo "  \"domain\": \"${results[domain]}\","
    fi
    if [ -n "$SHARE_NAME" ]; then
        echo "  \"share\": \"${results[share]}\","
    fi
    echo "  \"overall_status\": \"${results[overall_status]}\","
    echo "  \"overall_message\": \"${results[overall_message]}\","
    echo "  \"checks\": {"
    
    # DNS checks
    echo "    \"dns\": {"
    echo "      \"resolution\": \"${results[dns_resolution]}\","
    if [ -n "${results[dns_details]}" ]; then
        echo "      \"details\": \"${results[dns_details]}\","
    fi
    if [ -n "${results[srv_lookup]}" ]; then
        echo "      \"srv_lookup\": \"${results[srv_lookup]}\","
        echo "      \"srv_details\": \"${results[srv_details]}\""
    else
        echo "      \"srv_lookup\": \"skipped\""
    fi
    echo "    },"
    
    # Network checks
    echo "    \"network\": {"
    echo "      \"connectivity\": \"${results[network_connectivity]}\","
    if [ -n "${results[connectivity_details]}" ]; then
        echo "      \"details\": \"${results[connectivity_details]}\","
    fi
    if [ -n "${results[ldap_connectivity]}" ]; then
        echo "      \"ldap\": \"${results[ldap_connectivity]}\","
        echo "      \"kerberos\": \"${results[kerberos_connectivity]}\""
    else
        echo "      \"ldap\": \"skipped\","
        echo "      \"kerberos\": \"skipped\""
    fi
    echo "    },"
    
    # Kerberos checks
    echo "    \"kerberos\": {"
    echo "      \"config\": \"${results[kerberos_config]}\","
    if [ -n "${results[kerberos_domain]}" ]; then
        echo "      \"domain_config\": \"${results[kerberos_domain]}\","
    fi
    if [ -n "${results[kerberos_keytab]}" ]; then
        echo "      \"keytab\": \"${results[kerberos_keytab]}\","
        if [ -n "${results[keytab_entries]}" ]; then
            echo "      \"keytab_entries\": \"${results[keytab_entries]}\""
        else
            echo "      \"keytab_entries\": \"unknown\""
        fi
    else
        echo "      \"keytab\": \"unknown\""
    fi
    echo "    },"
    
    # Samba checks
    echo "    \"samba\": {"
    echo "      \"config\": \"${results[samba_config]}\","
    if [ -n "${results[samba_ad_mode]}" ]; then
        echo "      \"ad_mode\": \"${results[samba_ad_mode]}\","
    fi
    if [ -n "${results[samba_realm]}" ]; then
        echo "      \"realm\": \"${results[samba_realm]}\","
        echo "      \"workgroup\": \"${results[samba_workgroup]}\","
    fi
    if [ -n "${results[share_config]}" ]; then
        echo "      \"share_config\": \"${results[share_config]}\","
    fi
    echo "      \"service\": \"${results[samba_service]}\","
    echo "      \"winbind\": \"${results[winbind_service]}\""
    echo "    },"
    
    # Domain membership checks
    echo "    \"domain_membership\": {"
    echo "      \"status\": \"${results[domain_membership]}\","
    if [ -n "${results[membership_details]}" ]; then
        echo "      \"details\": \"${results[membership_details]}\","
    fi
    if [ -n "${results[domain_users]}" ]; then
        echo "      \"users\": \"${results[domain_users]}\","
        echo "      \"groups\": \"${results[domain_groups]}\""
    else
        echo "      \"users\": \"unknown\","
        echo "      \"groups\": \"unknown\""
    fi
    echo "    },"
    
    # Authentication checks
    echo "    \"authentication\": {"
    echo "      \"status\": \"${results[authentication]}\","
    if [ -n "${results[kerberos_auth]}" ]; then
        echo "      \"kerberos\": \"${results[kerberos_auth]}\","
        echo "      \"winbind\": \"${results[winbind_auth]}\""
    else
        echo "      \"kerberos\": \"unknown\","
        echo "      \"winbind\": \"unknown\""
    fi
    echo "    },"
    
    # NSSwitch checks
    echo "    \"nsswitch\": {"
    echo "      \"config\": \"${results[nsswitch_config]}\","
    if [ -n "${results[nsswitch_winbind]}" ]; then
        echo "      \"winbind\": \"${results[nsswitch_winbind]}\""
    else
        echo "      \"winbind\": \"unknown\""
    fi
    echo "    }"
    
    echo "  }"
    echo "}"
else
    # Output in human-readable format
    echo "SMB Gateway AD Troubleshooting Results"
    echo "----------------------------------------"
    echo "Mode: ${results[mode]}"
    if [ -n "$DOMAIN" ]; then
        echo "Domain: ${results[domain]}"
    fi
    if [ -n "$SHARE_NAME" ]; then
        echo "Share: ${results[share]}"
    fi
    echo "Overall Status: ${results[overall_status]}"
    echo "Message: ${results[overall_message]}"
    echo ""
    
    echo "DNS Checks:"
    echo "  Resolution: ${results[dns_resolution]}"
    if [ -n "${results[dns_details]}" ]; then
        echo "  Details: ${results[dns_details]}"
    fi
    if [ -n "${results[srv_lookup]}" ]; then
        echo "  SRV Lookup: ${results[srv_lookup]}"
        echo "  SRV Details: ${results[srv_details]}"
    fi
    echo ""
    
    echo "Network Checks:"
    echo "  Connectivity: ${results[network_connectivity]}"
    if [ -n "${results[connectivity_details]}" ]; then
        echo "  Details: ${results[connectivity_details]}"
    fi
    if [ -n "${results[ldap_connectivity]}" ]; then
        echo "  LDAP Connectivity: ${results[ldap_connectivity]}"
        echo "  Kerberos Connectivity: ${results[kerberos_connectivity]}"
    fi
    echo ""
    
    echo "Kerberos Checks:"
    echo "  Configuration: ${results[kerberos_config]}"
    if [ -n "${results[kerberos_domain]}" ]; then
        echo "  Domain Configuration: ${results[kerberos_domain]}"
    fi
    if [ -n "${results[kerberos_keytab]}" ]; then
        echo "  Keytab: ${results[kerberos_keytab]}"
        if [ -n "${results[keytab_entries]}" ]; then
            echo "  Keytab Entries: ${results[keytab_entries]}"
        fi
    fi
    echo ""
    
    echo "Samba Checks:"
    echo "  Configuration: ${results[samba_config]}"
    if [ -n "${results[samba_ad_mode]}" ]; then
        echo "  AD Mode: ${results[samba_ad_mode]}"
    fi
    if [ -n "${results[samba_realm]}" ]; then
        echo "  Realm Configuration: ${results[samba_realm]}"
        echo "  Workgroup Configuration: ${results[samba_workgroup]}"
    fi
    if [ -n "${results[share_config]}" ]; then
        echo "  Share Configuration: ${results[share_config]}"
    fi
    echo "  Samba Service: ${results[samba_service]}"
    echo "  Winbind Service: ${results[winbind_service]}"
    echo ""
    
    echo "Domain Membership:"
    echo "  Status: ${results[domain_membership]}"
    if [ -n "${results[membership_details]}" ]; then
        echo "  Details: ${results[membership_details]}"
    fi
    if [ -n "${results[domain_users]}" ]; then
        echo "  Domain Users: ${results[domain_users]}"
        echo "  Domain Groups: ${results[domain_groups]}"
    fi
    echo ""
    
    echo "Authentication:"
    echo "  Status: ${results[authentication]}"
    if [ -n "${results[kerberos_auth]}" ]; then
        echo "  Kerberos Authentication: ${results[kerberos_auth]}"
        echo "  Winbind Authentication: ${results[winbind_auth]}"
    fi
    echo ""
    
    echo "NSSwitch Configuration:"
    echo "  Status: ${results[nsswitch_config]}"
    if [ -n "${results[nsswitch_winbind]}" ]; then
        echo "  Winbind Configuration: ${results[nsswitch_winbind]}"
    fi
    echo ""
    
    echo "Detailed log available at: $LOG_FILE"
fi

exit 0