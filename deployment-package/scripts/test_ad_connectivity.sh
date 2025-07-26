#!/bin/bash
# SMB Gateway Active Directory Connectivity Test Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
DOMAIN=""
USERNAME="Administrator"
PASSWORD=""
MODE="native"
CONTAINER_ID=""
VERBOSE=0
JSON_OUTPUT=0

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --domain <domain>     AD domain to test (required)"
    echo "  -u, --username <user>     AD username (default: Administrator)"
    echo "  -p, --password <pass>     AD password (optional)"
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
        -u|--username)
            USERNAME="$2"
            shift
            shift
            ;;
        -p|--password)
            PASSWORD="$2"
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

# Check required parameters
if [ -z "$DOMAIN" ]; then
    echo "Error: Domain is required"
    usage
fi

if [ "$MODE" = "lxc" ] && [ -z "$CONTAINER_ID" ]; then
    echo "Error: Container ID is required for LXC mode"
    usage
fi

# Initialize results array
declare -A results
results["timestamp"]=$(date -Iseconds)
results["domain"]=$DOMAIN
results["mode"]=$MODE
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

# Function to print verbose output
verbose() {
    if [ $VERBOSE -eq 1 ]; then
        echo "$@"
    fi
}

# Test DNS resolution
verbose "Testing DNS resolution for $DOMAIN..."
DNS_RESULT=$(execute_cmd "host $DOMAIN 2>&1" || echo "error")
if [[ "$DNS_RESULT" == *"not found"* ]] || [[ "$DNS_RESULT" == *"error"* ]]; then
    results["dns_resolution"]="failed"
    results["dns_details"]="Cannot resolve domain $DOMAIN"
    verbose "DNS resolution failed for $DOMAIN"
else
    results["dns_resolution"]="success"
    results["dns_details"]="Domain $DOMAIN resolves to: $DNS_RESULT"
    verbose "DNS resolution successful for $DOMAIN"
fi

# Test SRV records
verbose "Testing SRV records for domain controllers..."
SRV_RESULT=$(execute_cmd "host -t SRV _ldap._tcp.$DOMAIN 2>&1" || echo "error")
if [[ "$SRV_RESULT" == *"not found"* ]] || [[ "$SRV_RESULT" == *"error"* ]]; then
    results["srv_lookup"]="failed"
    results["srv_details"]="Cannot find SRV records for domain controllers"
    verbose "SRV record lookup failed for _ldap._tcp.$DOMAIN"
else
    results["srv_lookup"]="success"
    results["srv_details"]="Found domain controllers: $SRV_RESULT"
    verbose "SRV record lookup successful for _ldap._tcp.$DOMAIN"
    
    # Extract domain controller from SRV record
    DC=$(echo "$SRV_RESULT" | grep -oP '(?<=has SRV record .* ).*(?=\.)' | head -1)
    if [ -n "$DC" ]; then
        results["domain_controller"]=$DC
        verbose "Found domain controller: $DC"
    fi
fi

# Test ping
verbose "Testing ping to $DOMAIN..."
PING_RESULT=$(execute_cmd "ping -c 1 -W 2 $DOMAIN 2>&1" || echo "error")
if [[ "$PING_RESULT" == *"error"* ]] || [[ "$PING_RESULT" == *"100% packet loss"* ]]; then
    results["ping"]="failed"
    results["ping_details"]="Cannot ping domain $DOMAIN"
    verbose "Cannot ping $DOMAIN"
else
    results["ping"]="success"
    results["ping_details"]="Domain $DOMAIN is reachable"
    verbose "Successfully pinged $DOMAIN"
fi

# Test LDAP connectivity
verbose "Testing LDAP connectivity to $DOMAIN..."
LDAP_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 389 2>&1" || echo "error")
if [[ "$LDAP_RESULT" == *"error"* ]] || [[ "$LDAP_RESULT" == *"failed"* ]]; then
    results["ldap_connectivity"]="failed"
    results["ldap_details"]="Cannot connect to LDAP port (389) on $DOMAIN"
    verbose "Cannot connect to LDAP port on $DOMAIN"
else
    results["ldap_connectivity"]="success"
    results["ldap_details"]="LDAP port (389) on $DOMAIN is reachable"
    verbose "Successfully connected to LDAP port on $DOMAIN"
fi

# Test Kerberos connectivity
verbose "Testing Kerberos connectivity to $DOMAIN..."
KERBEROS_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 88 2>&1" || echo "error")
if [[ "$KERBEROS_RESULT" == *"error"* ]] || [[ "$KERBEROS_RESULT" == *"failed"* ]]; then
    results["kerberos_connectivity"]="failed"
    results["kerberos_details"]="Cannot connect to Kerberos port (88) on $DOMAIN"
    verbose "Cannot connect to Kerberos port on $DOMAIN"
else
    results["kerberos_connectivity"]="success"
    results["kerberos_details"]="Kerberos port (88) on $DOMAIN is reachable"
    verbose "Successfully connected to Kerberos port on $DOMAIN"
fi

# Test Global Catalog connectivity
verbose "Testing Global Catalog connectivity to $DOMAIN..."
GC_RESULT=$(execute_cmd "nc -z -w 2 $DOMAIN 3268 2>&1" || echo "error")
if [[ "$GC_RESULT" == *"error"* ]] || [[ "$GC_RESULT" == *"failed"* ]]; then
    results["gc_connectivity"]="failed"
    results["gc_details"]="Cannot connect to Global Catalog port (3268) on $DOMAIN"
    verbose "Cannot connect to Global Catalog port on $DOMAIN"
else
    results["gc_connectivity"]="success"
    results["gc_details"]="Global Catalog port (3268) on $DOMAIN is reachable"
    verbose "Successfully connected to Global Catalog port on $DOMAIN"
fi

# Test authentication if password is provided
if [ -n "$PASSWORD" ]; then
    verbose "Testing authentication with $USERNAME@$DOMAIN..."
    
    # Create a temporary krb5.conf if it doesn't exist
    KRB5_CONF_CREATED=0
    if ! execute_cmd "test -f /etc/krb5.conf"; then
        verbose "Creating temporary krb5.conf..."
        REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
        KRB5_CONF="[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = true
    dns_lookup_kdc = true

[realms]
    $REALM = {
        kdc = $DOMAIN
        admin_server = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
"
        if [ "$MODE" = "native" ]; then
            echo "$KRB5_CONF" > /tmp/krb5.conf
            execute_cmd "cp /tmp/krb5.conf /etc/krb5.conf"
            rm /tmp/krb5.conf
        elif [ "$MODE" = "lxc" ]; then
            echo "$KRB5_CONF" > /tmp/krb5.conf
            pct push $CONTAINER_ID /tmp/krb5.conf /etc/krb5.conf
            rm /tmp/krb5.conf
        fi
        KRB5_CONF_CREATED=1
    fi
    
    # Test Kerberos authentication
    KINIT_RESULT=$(execute_cmd "echo '$PASSWORD' | kinit $USERNAME@$(echo $DOMAIN | tr '[:lower:]' '[:upper:]') 2>&1" || echo "error")
    if [[ "$KINIT_RESULT" == *"error"* ]] || [[ "$KINIT_RESULT" == *"Password incorrect"* ]]; then
        results["authentication"]="failed"
        results["auth_details"]="Kerberos authentication failed for $USERNAME@$DOMAIN"
        verbose "Kerberos authentication failed for $USERNAME@$DOMAIN"
    else
        results["authentication"]="success"
        results["auth_details"]="Kerberos authentication successful for $USERNAME@$DOMAIN"
        verbose "Kerberos authentication successful for $USERNAME@$DOMAIN"
        
        # List tickets
        KLIST_RESULT=$(execute_cmd "klist 2>&1" || echo "error")
        if [[ "$KLIST_RESULT" != *"error"* ]]; then
            results["tickets"]="found"
            results["tickets_details"]="$KLIST_RESULT"
            verbose "Kerberos tickets: $KLIST_RESULT"
        fi
        
        # Destroy ticket
        execute_cmd "kdestroy 2>/dev/null" || true
    fi
    
    # Clean up temporary krb5.conf if created
    if [ $KRB5_CONF_CREATED -eq 1 ]; then
        verbose "Removing temporary krb5.conf..."
        execute_cmd "rm -f /etc/krb5.conf" || true
    fi
fi

# Determine overall status
if [[ "${results[dns_resolution]}" == "success" ]] && 
   [[ "${results[srv_lookup]}" == "success" ]] && 
   [[ "${results[ping]}" == "success" ]] && 
   [[ "${results[ldap_connectivity]}" == "success" ]] && 
   [[ "${results[kerberos_connectivity]}" == "success" ]]; then
    results["overall_status"]="success"
    results["overall_message"]="All connectivity tests passed"
    
    if [ -n "$PASSWORD" ]; then
        if [[ "${results[authentication]}" == "success" ]]; then
            results["overall_message"]="All connectivity and authentication tests passed"
        else
            results["overall_status"]="partial"
            results["overall_message"]="Connectivity tests passed but authentication failed"
        fi
    fi
elif [[ "${results[dns_resolution]}" == "failed" ]]; then
    results["overall_status"]="failed"
    results["overall_message"]="DNS resolution failed, check DNS configuration"
else
    results["overall_status"]="partial"
    results["overall_message"]="Some connectivity tests failed"
fi

# Output results
if [ $JSON_OUTPUT -eq 1 ]; then
    # Output in JSON format
    echo "{"
    echo "  \"timestamp\": \"${results[timestamp]}\","
    echo "  \"domain\": \"${results[domain]}\","
    echo "  \"mode\": \"${results[mode]}\","
    echo "  \"overall_status\": \"${results[overall_status]}\","
    echo "  \"overall_message\": \"${results[overall_message]}\","
    echo "  \"tests\": {"
    
    # DNS resolution
    echo "    \"dns_resolution\": {"
    echo "      \"status\": \"${results[dns_resolution]}\","
    echo "      \"details\": \"${results[dns_details]}\""
    echo "    },"
    
    # SRV lookup
    echo "    \"srv_lookup\": {"
    echo "      \"status\": \"${results[srv_lookup]}\","
    echo "      \"details\": \"${results[srv_details]}\""
    if [ -n "${results[domain_controller]}" ]; then
        echo "      ,\"domain_controller\": \"${results[domain_controller]}\""
    fi
    echo "    },"
    
    # Ping
    echo "    \"ping\": {"
    echo "      \"status\": \"${results[ping]}\","
    echo "      \"details\": \"${results[ping_details]}\""
    echo "    },"
    
    # LDAP connectivity
    echo "    \"ldap_connectivity\": {"
    echo "      \"status\": \"${results[ldap_connectivity]}\","
    echo "      \"details\": \"${results[ldap_details]}\""
    echo "    },"
    
    # Kerberos connectivity
    echo "    \"kerberos_connectivity\": {"
    echo "      \"status\": \"${results[kerberos_connectivity]}\","
    echo "      \"details\": \"${results[kerberos_details]}\""
    echo "    },"
    
    # Global Catalog connectivity
    echo "    \"gc_connectivity\": {"
    echo "      \"status\": \"${results[gc_connectivity]}\","
    echo "      \"details\": \"${results[gc_details]}\""
    echo "    }"
    
    # Authentication if tested
    if [ -n "$PASSWORD" ]; then
        echo "    ,\"authentication\": {"
        echo "      \"status\": \"${results[authentication]}\","
        echo "      \"details\": \"${results[auth_details]}\""
        if [ -n "${results[tickets]}" ]; then
            echo "      ,\"tickets\": \"${results[tickets]}\""
        }
        echo "    }"
    fi
    
    echo "  }"
    echo "}"
else
    # Output in human-readable format
    echo "AD Connectivity Test Results for $DOMAIN"
    echo "----------------------------------------"
    echo "Overall Status: ${results[overall_status]}"
    echo "Message: ${results[overall_message]}"
    echo ""
    
    echo "DNS Resolution:"
    echo "  Status: ${results[dns_resolution]}"
    echo "  Details: ${results[dns_details]}"
    echo ""
    
    echo "SRV Lookup:"
    echo "  Status: ${results[srv_lookup]}"
    echo "  Details: ${results[srv_details]}"
    if [ -n "${results[domain_controller]}" ]; then
        echo "  Domain Controller: ${results[domain_controller]}"
    fi
    echo ""
    
    echo "Ping Test:"
    echo "  Status: ${results[ping]}"
    echo "  Details: ${results[ping_details]}"
    echo ""
    
    echo "LDAP Connectivity:"
    echo "  Status: ${results[ldap_connectivity]}"
    echo "  Details: ${results[ldap_details]}"
    echo ""
    
    echo "Kerberos Connectivity:"
    echo "  Status: ${results[kerberos_connectivity]}"
    echo "  Details: ${results[kerberos_details]}"
    echo ""
    
    echo "Global Catalog Connectivity:"
    echo "  Status: ${results[gc_connectivity]}"
    echo "  Details: ${results[gc_details]}"
    echo ""
    
    if [ -n "$PASSWORD" ]; then
        echo "Authentication:"
        echo "  Status: ${results[authentication]}"
        echo "  Details: ${results[auth_details]}"
        if [ -n "${results[tickets]}" ]; then
            echo "  Tickets: ${results[tickets]}"
        }
        echo ""
    fi
fi

# Exit with appropriate status code
if [ "${results[overall_status]}" = "success" ]; then
    exit 0
elif [ "${results[overall_status]}" = "partial" ]; then
    exit 1
else
    exit 2
fi