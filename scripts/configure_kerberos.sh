#!/bin/bash
# SMB Gateway Kerberos Configuration Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-kerberos.log"
DOMAIN=""
USERNAME="Administrator"
PASSWORD=""
KEYTAB_FILE="/etc/krb5.keytab"
MODE="native"
CONTAINER_ID=""
VERBOSE=0

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
    echo "  -d, --domain <domain>     AD domain (required)"
    echo "  -u, --username <user>     AD username (default: Administrator)"
    echo "  -p, --password <pass>     AD password (required)"
    echo "  -k, --keytab <file>       Keytab file (default: /etc/krb5.keytab)"
    echo "  -m, --mode <mode>         Mode: native, lxc, or vm (default: native)"
    echo "  -c, --container <id>      Container ID (required for LXC mode)"
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
        -k|--keytab)
            KEYTAB_FILE="$2"
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

# Initialize log file
echo "SMB Gateway Kerberos Configuration" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Domain: $DOMAIN" >> $LOG_FILE
echo "Mode: $MODE" >> $LOG_FILE
if [ "$MODE" = "lxc" ]; then
    echo "Container ID: $CONTAINER_ID" >> $LOG_FILE
fi
echo "----------------------------------------" >> $LOG_FILE

# Convert domain to uppercase for realm
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
WORKGROUP=$(echo "$DOMAIN" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')

log "Configuring Kerberos for domain $DOMAIN (realm $REALM, workgroup $WORKGROUP)"

# Function to execute commands based on mode
execute_cmd() {
    if [ "$MODE" = "native" ]; then
        eval "$@"
    elif [ "$MODE" = "lxc" ]; then
        pct exec $CONTAINER_ID -- bash -c "$@"
    else
        echo "Error: Unsupported mode $MODE"
        exit 1
    fi
}

# Function to write file based on mode
write_file() {
    local content="$1"
    local target="$2"
    
    if [ "$MODE" = "native" ]; then
        echo "$content" > "$target"
    elif [ "$MODE" = "lxc" ]; then
        # Create temporary file
        local tmp_file="/tmp/kerberos-tmp-$$"
        echo "$content" > "$tmp_file"
        
        # Copy to container
        pct push $CONTAINER_ID "$tmp_file" "$target"
        
        # Clean up
        rm "$tmp_file"
    fi
}

# Install required packages
log "Installing required packages"
if [ "$MODE" = "native" ]; then
    apt-get update
    apt-get install -y krb5-user samba winbind libnss-winbind libpam-winbind
elif [ "$MODE" = "lxc" ]; then
    pct exec $CONTAINER_ID -- apt-get update
    pct exec $CONTAINER_ID -- apt-get install -y krb5-user samba winbind libnss-winbind libpam-winbind
fi

# Configure krb5.conf
log "Configuring krb5.conf"
KRB5_CONF="[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    $REALM = {
        kdc = $DOMAIN
        admin_server = $DOMAIN
        default_domain = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM

[appdefaults]
    pam = {
        ticket_lifetime = 24h
        renew_lifetime = 24h
        forwardable = true
        proxiable = false
        retain_after_close = false
        minimum_uid = 1000
        debug = false
    }
"

if [ "$MODE" = "native" ]; then
    write_file "$KRB5_CONF" "/etc/krb5.conf"
elif [ "$MODE" = "lxc" ]; then
    write_file "$KRB5_CONF" "/etc/krb5.conf"
fi

# Configure nsswitch.conf
log "Configuring nsswitch.conf"
execute_cmd "sed -i 's/^passwd:.*/passwd:         files systemd winbind/' /etc/nsswitch.conf"
execute_cmd "sed -i 's/^group:.*/group:          files systemd winbind/' /etc/nsswitch.conf"
execute_cmd "sed -i 's/^shadow:.*/shadow:         files winbind/' /etc/nsswitch.conf"

# Create Kerberos keytab
log "Creating Kerberos keytab"
if [ "$MODE" = "native" ]; then
    # Create a temporary password file
    echo "$PASSWORD" > /tmp/krb5pass
    
    # Create keytab
    KRB5_CONFIG=/etc/krb5.conf ktutil <<EOF
addent -password -p $USERNAME@$REALM -k 1 -e aes256-cts
/tmp/krb5pass
wkt $KEYTAB_FILE
quit
EOF
    
    # Clean up
    rm /tmp/krb5pass
    
    # Set permissions
    chmod 600 $KEYTAB_FILE
elif [ "$MODE" = "lxc" ]; then
    # Create a temporary password file in container
    pct exec $CONTAINER_ID -- bash -c "echo '$PASSWORD' > /tmp/krb5pass"
    
    # Create keytab in container
    pct exec $CONTAINER_ID -- bash -c "KRB5_CONFIG=/etc/krb5.conf ktutil <<EOF
addent -password -p $USERNAME@$REALM -k 1 -e aes256-cts
/tmp/krb5pass
wkt $KEYTAB_FILE
quit
EOF"
    
    # Clean up
    pct exec $CONTAINER_ID -- rm /tmp/krb5pass
    
    # Set permissions
    pct exec $CONTAINER_ID -- chmod 600 $KEYTAB_FILE
fi

# Configure Samba for Kerberos
log "Configuring Samba for Kerberos"
SMB_GLOBAL="[global]
   workgroup = $WORKGROUP
   realm = $REALM
   security = ads
   encrypt passwords = yes
   kerberos method = secrets and keytab
   dedicated keytab file = $KEYTAB_FILE
   idmap config * : backend = tdb
   idmap config * : range = 10000-20000
   winbind use default domain = yes
   winbind enum users = yes
   winbind enum groups = yes
   winbind refresh tickets = yes
   template shell = /bin/bash
   template homedir = /home/%U
   client signing = auto
   client use spnego = yes
   server signing = mandatory
   dns proxy = no
   log level = 1
"

# Update smb.conf
if [ "$MODE" = "native" ]; then
    # Backup original config
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
    
    # Extract share configurations
    grep -v "^\[global\]" /etc/samba/smb.conf | grep -v "^[[:space:]]*workgroup" | grep -v "^[[:space:]]*realm" | grep -v "^[[:space:]]*security" > /tmp/smb-shares
    
    # Create new config
    echo "$SMB_GLOBAL" > /etc/samba/smb.conf
    cat /tmp/smb-shares >> /etc/samba/smb.conf
    
    # Clean up
    rm /tmp/smb-shares
elif [ "$MODE" = "lxc" ]; then
    # Backup original config in container
    pct exec $CONTAINER_ID -- cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
    
    # Extract share configurations
    pct exec $CONTAINER_ID -- bash -c "grep -v '^\[global\]' /etc/samba/smb.conf | grep -v '^[[:space:]]*workgroup' | grep -v '^[[:space:]]*realm' | grep -v '^[[:space:]]*security' > /tmp/smb-shares"
    
    # Create new config
    pct exec $CONTAINER_ID -- bash -c "echo '$SMB_GLOBAL' > /etc/samba/smb.conf"
    pct exec $CONTAINER_ID -- bash -c "cat /tmp/smb-shares >> /etc/samba/smb.conf"
    
    # Clean up
    pct exec $CONTAINER_ID -- rm /tmp/smb-shares
fi

# Join domain if not already joined
log "Checking domain membership"
if [ "$MODE" = "native" ]; then
    NET_ADS_INFO=$(net ads info 2>&1 || true)
    if [[ "$NET_ADS_INFO" == *"No credentials cache found"* ]] || [[ "$NET_ADS_INFO" == *"error"* ]]; then
        log "Joining domain $DOMAIN"
        net ads join -U "$USERNAME%$PASSWORD"
    else
        log "Already joined to domain"
    fi
elif [ "$MODE" = "lxc" ]; then
    NET_ADS_INFO=$(pct exec $CONTAINER_ID -- net ads info 2>&1 || true)
    if [[ "$NET_ADS_INFO" == *"No credentials cache found"* ]] || [[ "$NET_ADS_INFO" == *"error"* ]]; then
        log "Joining domain $DOMAIN"
        pct exec $CONTAINER_ID -- net ads join -U "$USERNAME%$PASSWORD"
    else
        log "Already joined to domain"
    fi
fi

# Restart services
log "Restarting services"
if [ "$MODE" = "native" ]; then
    systemctl restart winbind
    systemctl restart smbd
    systemctl restart nmbd
elif [ "$MODE" = "lxc" ]; then
    pct exec $CONTAINER_ID -- systemctl restart winbind
    pct exec $CONTAINER_ID -- systemctl restart smbd
    pct exec $CONTAINER_ID -- systemctl restart nmbd
fi

# Verify Kerberos configuration
log "Verifying Kerberos configuration"
if [ "$MODE" = "native" ]; then
    # Create temporary credential cache
    echo "$PASSWORD" | kinit "$USERNAME@$REALM"
    
    # List tickets
    TICKETS=$(klist)
    log "Kerberos tickets: $TICKETS"
    
    # Test domain access
    DOMAIN_TEST=$(wbinfo -u | head -5)
    log "Domain users: $DOMAIN_TEST"
    
    # Destroy ticket
    kdestroy
elif [ "$MODE" = "lxc" ]; then
    # Create temporary credential cache in container
    pct exec $CONTAINER_ID -- bash -c "echo '$PASSWORD' | kinit '$USERNAME@$REALM'"
    
    # List tickets
    TICKETS=$(pct exec $CONTAINER_ID -- klist)
    log "Kerberos tickets: $TICKETS"
    
    # Test domain access
    DOMAIN_TEST=$(pct exec $CONTAINER_ID -- wbinfo -u | head -5)
    log "Domain users: $DOMAIN_TEST"
    
    # Destroy ticket
    pct exec $CONTAINER_ID -- kdestroy
fi

log "Kerberos configuration completed successfully"
log "See $LOG_FILE for detailed log"

exit 0