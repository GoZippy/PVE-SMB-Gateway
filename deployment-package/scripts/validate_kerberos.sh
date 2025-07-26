#!/bin/bash
# SMB Gateway Kerberos Ticket Validation Script
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
RENEW_TICKET=0

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --domain <domain>     AD domain (required)"
    echo "  -u, --username <user>     AD username (default: Administrator)"
    echo "  -p, --password <pass>     AD password (required)"
    echo "  -m, --mode <mode>         Mode: native, lxc, or vm (default: native)"
    echo "  -c, --container <id>      Container ID (required for LXC mode)"
    echo "  -r, --renew               Renew ticket if it exists"
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
        -r|--renew)
            RENEW_TICKET=1
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

if [ -z "$PASSWORD" ]; then
    echo "Error: Password is required"
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
results["username"]=$USERNAME
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

# Check if krb5.conf exists
verbose "Checking Kerberos configuration..."
KRB5_CONF=$(execute_cmd "cat /etc/krb5.conf 2>/dev/null" || echo "error")
if [[ "$KRB5_CONF" == *"error"* ]] || [[ "$KRB5_CONF" == *"No such file"* ]]; then
    results["krb5_conf"]="missing"
    results["krb5_conf_details"]="Kerberos configuration file (/etc/krb5.conf) not found"
    verbose "Kerberos configuration file not found"
    
    # Create a temporary krb5.conf
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
    
    results["krb5_conf"]="created"
    results["krb5_conf_details"]="Temporary Kerberos configuration file created"
else
    results["krb5_conf"]="found"
    results["krb5_conf_details"]="Kerberos configuration file exists"
    verbose "Kerberos configuration file found"
    
    # Check if domain is configured in krb5.conf
    REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
    if [[ "$KRB5_CONF" == *"$REALM"* ]]; then
        results["realm_config"]="found"
        results["realm_config_details"]="Realm $REALM is configured in krb5.conf"
        verbose "Realm $REALM is configured in krb5.conf"
    else
        results["realm_config"]="missing"
        results["realm_config_details"]="Realm $REALM is not configured in krb5.conf"
        verbose "Realm $REALM is not configured in krb5.conf"
    fi
fi

# Check for existing tickets
verbose "Checking for existing Kerberos tickets..."
KLIST_RESULT=$(execute_cmd "klist 2>&1" || echo "error")
if [[ "$KLIST_RESULT" == *"No credentials cache found"* ]] || [[ "$KLIST_RESULT" == *"error"* ]]; then
    results["existing_tickets"]="none"
    results["existing_tickets_details"]="No Kerberos tickets found"
    verbose "No existing Kerberos tickets found"
else
    results["existing_tickets"]="found"
    results["existing_tickets_details"]="$KLIST_RESULT"
    verbose "Existing Kerberos tickets found"
    
    # Check if we need to renew tickets
    if [ $RENEW_TICKET -eq 1 ]; then
        verbose "Renewing Kerberos tickets..."
        KINIT_RENEW_RESULT=$(execute_cmd "echo '$PASSWORD' | kinit -R $USERNAME@$REALM 2>&1" || echo "error")
        if [[ "$KINIT_RENEW_RESULT" == *"error"* ]] || [[ "$KINIT_RENEW_RESULT" == *"not renewable"* ]]; then
            results["ticket_renewal"]="failed"
            results["ticket_renewal_details"]="Failed to renew Kerberos tickets: $KINIT_RENEW_RESULT"
            verbose "Failed to renew Kerberos tickets"
        else
            results["ticket_renewal"]="success"
            results["ticket_renewal_details"]="Successfully renewed Kerberos tickets"
            verbose "Successfully renewed Kerberos tickets"
        fi
    else
        # Destroy existing tickets
        verbose "Destroying existing Kerberos tickets..."
        execute_cmd "kdestroy 2>/dev/null" || true
        results["existing_tickets"]="destroyed"
        results["existing_tickets_details"]="Existing tickets were destroyed"
    fi
fi

# Get a new Kerberos ticket
if [ "${results[existing_tickets]}" = "none" ] || [ "${results[existing_tickets]}" = "destroyed" ]; then
    verbose "Getting new Kerberos ticket for $USERNAME@$REALM..."
    REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
    KINIT_RESULT=$(execute_cmd "echo '$PASSWORD' | kinit $USERNAME@$REALM 2>&1" || echo "error")
    if [[ "$KINIT_RESULT" == *"error"* ]] || [[ "$KINIT_RESULT" == *"Password incorrect"* ]]; then
        results["kinit"]="failed"
        results["kinit_details"]="Failed to get Kerberos ticket: $KINIT_RESULT"
        verbose "Failed to get Kerberos ticket"
    else
        results["kinit"]="success"
        results["kinit_details"]="Successfully obtained Kerberos ticket"
        verbose "Successfully obtained Kerberos ticket"
    fi
fi

# List tickets
verbose "Listing Kerberos tickets..."
KLIST_RESULT=$(execute_cmd "klist 2>&1" || echo "error")
if [[ "$KLIST_RESULT" == *"No credentials cache found"* ]] || [[ "$KLIST_RESULT" == *"error"* ]]; then
    results["tickets"]="none"
    results["tickets_details"]="No Kerberos tickets found after authentication attempt"
    verbose "No Kerberos tickets found after authentication attempt"
else
    results["tickets"]="found"
    results["tickets_details"]="$KLIST_RESULT"
    verbose "Kerberos tickets: $KLIST_RESULT"
    
    # Extract ticket information
    if [[ "$KLIST_RESULT" == *"krbtgt/$REALM@$REALM"* ]]; then
        results["tgt"]="valid"
        results["tgt_details"]="Valid Ticket Granting Ticket (TGT) found"
        verbose "Valid Ticket Granting Ticket (TGT) found"
    else
        results["tgt"]="missing"
        results["tgt_details"]="No valid Ticket Granting Ticket (TGT) found"
        verbose "No valid Ticket Granting Ticket (TGT) found"
    fi
    
    # Extract expiration time
    EXPIRY=$(echo "$KLIST_RESULT" | grep -oP '(?<=expires: ).*(?=,)' | head -1)
    if [ -n "$EXPIRY" ]; then
        results["expiry"]="$EXPIRY"
        verbose "Ticket expires: $EXPIRY"
    fi
}

# Test service ticket acquisition
if [ "${results[tickets]}" = "found" ]; then
    verbose "Testing service ticket acquisition..."
    
    # Try to get a service ticket for LDAP
    KVNO_RESULT=$(execute_cmd "kvno ldap/$DOMAIN 2>&1" || echo "error")
    if [[ "$KVNO_RESULT" == *"error"* ]] || [[ "$KVNO_RESULT" == *"not found"* ]]; then
        results["service_ticket"]="failed"
        results["service_ticket_details"]="Failed to acquire service ticket: $KVNO_RESULT"
        verbose "Failed to acquire service ticket"
    else
        results["service_ticket"]="success"
        results["service_ticket_details"]="Successfully acquired service ticket: $KVNO_RESULT"
        verbose "Successfully acquired service ticket"
    fi
fi

# Determine overall status
if [[ "${results[tickets]}" == "found" ]] && [[ "${results[tgt]}" == "valid" ]]; then
    if [ -n "${results[service_ticket]}" ] && [[ "${results[service_ticket]}" == "success" ]]; then
        results["overall_status"]="success"
        results["overall_message"]="Kerberos authentication is working properly"
    else
        results["overall_status"]="partial"
        results["overall_message"]="Kerberos TGT is valid but service ticket acquisition failed"
    fi
elif [[ "${results[kinit]}" == "success" ]] && [[ "${results[tickets]}" != "found" ]]; then
    results["overall_status"]="partial"
    results["overall_message"]="Kerberos authentication succeeded but no tickets were found"
else
    results["overall_status"]="failed"
    results["overall_message"]="Kerberos authentication failed"
fi

# Output results
if [ $JSON_OUTPUT -eq 1 ]; then
    # Output in JSON format
    echo "{"
    echo "  \"timestamp\": \"${results[timestamp]}\","
    echo "  \"domain\": \"${results[domain]}\","
    echo "  \"username\": \"${results[username]}\","
    echo "  \"mode\": \"${results[mode]}\","
    echo "  \"overall_status\": \"${results[overall_status]}\","
    echo "  \"overall_message\": \"${results[overall_message]}\","
    echo "  \"kerberos\": {"
    
    # Configuration
    echo "    \"configuration\": {"
    echo "      \"krb5_conf\": \"${results[krb5_conf]}\","
    echo "      \"details\": \"${results[krb5_conf_details]}\""
    if [ -n "${results[realm_config]}" ]; then
        echo "      ,\"realm_config\": \"${results[realm_config]}\","
        echo "      \"realm_details\": \"${results[realm_config_details]}\""
    fi
    echo "    },"
    
    # Authentication
    echo "    \"authentication\": {"
    if [ -n "${results[existing_tickets]}" ]; then
        echo "      \"existing_tickets\": \"${results[existing_tickets]}\","
        echo "      \"existing_details\": \"${results[existing_tickets_details]}\","
    fi
    if [ -n "${results[ticket_renewal]}" ]; then
        echo "      \"ticket_renewal\": \"${results[ticket_renewal]}\","
        echo "      \"renewal_details\": \"${results[ticket_renewal_details]}\","
    fi
    if [ -n "${results[kinit]}" ]; then
        echo "      \"kinit\": \"${results[kinit]}\","
        echo "      \"kinit_details\": \"${results[kinit_details]}\","
    fi
    echo "      \"tickets\": \"${results[tickets]}\","
    echo "      \"tickets_details\": \"${results[tickets_details]}\""
    echo "    },"
    
    # Ticket details
    echo "    \"ticket_details\": {"
    if [ -n "${results[tgt]}" ]; then
        echo "      \"tgt\": \"${results[tgt]}\","
        echo "      \"tgt_details\": \"${results[tgt_details]}\","
    }
    if [ -n "${results[expiry]}" ]; then
        echo "      \"expiry\": \"${results[expiry]}\","
    }
    if [ -n "${results[service_ticket]}" ]; then
        echo "      \"service_ticket\": \"${results[service_ticket]}\","
        echo "      \"service_details\": \"${results[service_ticket_details]}\""
    } else {
        echo "      \"service_ticket\": \"not_tested\""
    }
    echo "    }"
    
    echo "  }"
    echo "}"
else
    # Output in human-readable format
    echo "Kerberos Ticket Validation Results"
    echo "----------------------------------------"
    echo "Domain: ${results[domain]}"
    echo "Username: ${results[username]}"
    echo "Mode: ${results[mode]}"
    echo "Overall Status: ${results[overall_status]}"
    echo "Message: ${results[overall_message]}"
    echo ""
    
    echo "Kerberos Configuration:"
    echo "  Status: ${results[krb5_conf]}"
    echo "  Details: ${results[krb5_conf_details]}"
    if [ -n "${results[realm_config]}" ]; then
        echo "  Realm Configuration: ${results[realm_config]}"
        echo "  Realm Details: ${results[realm_config_details]}"
    fi
    echo ""
    
    echo "Authentication:"
    if [ -n "${results[existing_tickets]}" ]; then
        echo "  Existing Tickets: ${results[existing_tickets]}"
        echo "  Details: ${results[existing_tickets_details]}"
    fi
    if [ -n "${results[ticket_renewal]}" ]; then
        echo "  Ticket Renewal: ${results[ticket_renewal]}"
        echo "  Details: ${results[ticket_renewal_details]}"
    fi
    if [ -n "${results[kinit]}" ]; then
        echo "  Kinit: ${results[kinit]}"
        echo "  Details: ${results[kinit_details]}"
    fi
    echo "  Tickets: ${results[tickets]}"
    echo "  Details: ${results[tickets_details]}"
    echo ""
    
    echo "Ticket Details:"
    if [ -n "${results[tgt]}" ]; then
        echo "  TGT: ${results[tgt]}"
        echo "  Details: ${results[tgt_details]}"
    fi
    if [ -n "${results[expiry]}" ]; then
        echo "  Expiry: ${results[expiry]}"
    fi
    if [ -n "${results[service_ticket]}" ]; then
        echo "  Service Ticket: ${results[service_ticket]}"
        echo "  Details: ${results[service_ticket_details]}"
    } else {
        echo "  Service Ticket: not tested"
    }
    echo ""
fi

# Exit with appropriate status code
if [ "${results[overall_status]}" = "success" ]; then
    exit 0
elif [ "${results[overall_status]}" = "partial" ]; then
    exit 1
else
    exit 2
fi