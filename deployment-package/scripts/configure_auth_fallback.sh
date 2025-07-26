#!/bin/bash
# SMB Gateway Authentication Fallback Configuration Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-auth-fallback.log"
SHARE_NAME=""
MODE="native"
CONTAINER_ID=""
LOCAL_USER=""
LOCAL_PASSWORD=""
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
    echo "  -s, --share <name>        Share name (required)"
    echo "  -m, --mode <mode>         Mode: native, lxc, or vm (default: native)"
    echo "  -c, --container <id>      Container ID (required for LXC mode)"
    echo "  -u, --user <username>     Local user to create (default: smbuser)"
    echo "  -p, --password <pass>     Password for local user (default: random)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
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
        -u|--user)
            LOCAL_USER="$2"
            shift
            shift
            ;;
        -p|--password)
            LOCAL_PASSWORD="$2"
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
if [ -z "$SHARE_NAME" ]; then
    echo "Error: Share name is required"
    usage
fi

if [ "$MODE" = "lxc" ] && [ -z "$CONTAINER_ID" ]; then
    echo "Error: Container ID is required for LXC mode"
    usage
fi

# Set default local user if not provided
if [ -z "$LOCAL_USER" ]; then
    LOCAL_USER="smbuser"
fi

# Generate random password if not provided
if [ -z "$LOCAL_PASSWORD" ]; then
    LOCAL_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 12)
fi

# Initialize log file
echo "SMB Gateway Authentication Fallback Configuration" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Share: $SHARE_NAME" >> $LOG_FILE
echo "Mode: $MODE" >> $LOG_FILE
if [ "$MODE" = "lxc" ]; then
    echo "Container ID: $CONTAINER_ID" >> $LOG_FILE
fi
echo "Local User: $LOCAL_USER" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

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

# Check if share exists in smb.conf
log "Checking if share $SHARE_NAME exists in smb.conf"
SMB_CONF=$(execute_cmd "cat /etc/samba/smb.conf 2>/dev/null" || echo "error")
if [[ "$SMB_CONF" == *"error"* ]] || [[ "$SMB_CONF" == *"No such file"* ]]; then
    log "Error: Samba configuration file not found"
    exit 1
fi

if [[ "$SMB_CONF" != *"[$SHARE_NAME]"* ]]; then
    log "Error: Share $SHARE_NAME not found in smb.conf"
    exit 1
fi

# Check if AD integration is configured
log "Checking if AD integration is configured"
if [[ "$SMB_CONF" == *"security = ads"* ]]; then
    log "AD integration is configured"
    AD_CONFIGURED=1
else
    log "AD integration is not configured"
    AD_CONFIGURED=0
fi

# Create local user
log "Creating local user $LOCAL_USER"
USER_EXISTS=$(execute_cmd "id -u $LOCAL_USER 2>/dev/null" || echo "error")
if [[ "$USER_EXISTS" == "error" ]] || [[ "$USER_EXISTS" == *"no such user"* ]]; then
    log "Creating user $LOCAL_USER"
    execute_cmd "useradd -m -s /bin/bash $LOCAL_USER"
    execute_cmd "echo '$LOCAL_USER:$LOCAL_PASSWORD' | chpasswd"
else
    log "User $LOCAL_USER already exists"
fi

# Add user to Samba
log "Adding user $LOCAL_USER to Samba"
execute_cmd "echo -e '$LOCAL_PASSWORD\n$LOCAL_PASSWORD' | smbpasswd -a $LOCAL_USER"

# Update smb.conf with fallback authentication
log "Updating smb.conf with fallback authentication"

# Backup original config
SMB_CONF_BACKUP="/etc/samba/smb.conf.backup.$(date +%s)"
execute_cmd "cp /etc/samba/smb.conf $SMB_CONF_BACKUP"
log "Backed up smb.conf to $SMB_CONF_BACKUP"

# Update global section
if [ $AD_CONFIGURED -eq 1 ]; then
    # Add hybrid authentication configuration
    log "Configuring hybrid authentication (AD + local)"
    
    # Check if we need to update global section
    if [[ "$SMB_CONF" != *"auth methods"* ]]; then
        # Add auth methods to global section
        execute_cmd "sed -i '/\[global\]/a\\  auth methods = kerberos winbind sam' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind offline logon = yes' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind use default domain = yes' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind refresh tickets = yes' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind enum users = yes' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind enum groups = yes' /etc/samba/smb.conf"
        
        # Add authentication switching capability
        log "Adding authentication method switching capability"
        execute_cmd "sed -i '/\[global\]/a\\  # Authentication switching capability' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  auth methods = kerberos winbind sam' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  # Allow fallback to local authentication when AD is unavailable' /etc/samba/smb.conf"
        execute_cmd "sed -i '/\[global\]/a\\  winbind offline logon = yes' /etc/samba/smb.conf"
    fi
else
    # Configure local authentication only
    log "Configuring local authentication"
    
    # Check if we need to update global section
    if [[ "$SMB_CONF" != *"security = user"* ]]; then
        execute_cmd "sed -i '/\[global\]/a\\  security = user' /etc/samba/smb.conf"
    fi
fi

# Update share section
log "Updating share $SHARE_NAME configuration"

# Add valid users configuration to share
if [[ "$SMB_CONF" != *"[$SHARE_NAME]"*"valid users"* ]]; then
    # Add valid users line after share definition
    execute_cmd "sed -i '/\[$SHARE_NAME\]/a\\  valid users = $LOCAL_USER @\"DOMAIN USERS\"' /etc/samba/smb.conf"
fi

# Add force user configuration to share
if [[ "$SMB_CONF" != *"[$SHARE_NAME]"*"force user"* ]]; then
    # Add force user line after share definition
    execute_cmd "sed -i '/\[$SHARE_NAME\]/a\\  force user = $LOCAL_USER' /etc/samba/smb.conf"
fi

# Restart Samba services
log "Restarting Samba services"
execute_cmd "systemctl restart smbd"
execute_cmd "systemctl restart nmbd"

# Add enhanced warning systems for AD connectivity issues
log "Creating AD connectivity monitoring script"
WARNING_SCRIPT="/usr/local/bin/check_ad_connectivity.sh"

execute_cmd "cat > $WARNING_SCRIPT << 'EOF'
#!/bin/bash
# AD Connectivity Check Script

DOMAIN=\$(grep -A5 '\[global\]' /etc/samba/smb.conf | grep 'realm' | awk '{print \$3}')
SHARE_NAME=\"$SHARE_NAME\"
LOG_FILE=\"/var/log/ad-connectivity.log\"

if [ -z \"\$DOMAIN\" ]; then
    # No AD domain configured, nothing to check
    exit 0
fi

# Function to log messages
log() {
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    echo \"[\$timestamp] \$1\" >> \$LOG_FILE
}

# Initialize log file if it doesn't exist
if [ ! -f \"\$LOG_FILE\" ]; then
    echo \"AD Connectivity Monitoring Log\" > \$LOG_FILE
    echo \"Date: \$(date)\" >> \$LOG_FILE
    echo \"Domain: \$DOMAIN\" >> \$LOG_FILE
    echo \"Share: \$SHARE_NAME\" >> \$LOG_FILE
    echo \"----------------------------------------\" >> \$LOG_FILE
fi

# Check if we can ping the domain
log \"Checking connectivity to \$DOMAIN\"
ping -c 1 -W 2 \$DOMAIN > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    log \"WARNING: Cannot connect to AD domain \$DOMAIN. Using local authentication fallback.\"
    echo \"WARNING: Cannot connect to AD domain \$DOMAIN. Using local authentication fallback.\" >&2
    exit 1
fi

# Check if we can connect to LDAP port
log \"Checking LDAP service on \$DOMAIN\"
nc -z -w 2 \$DOMAIN 389 > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    log \"WARNING: Cannot connect to LDAP service on \$DOMAIN. Using local authentication fallback.\"
    echo \"WARNING: Cannot connect to LDAP service on \$DOMAIN. Using local authentication fallback.\" >&2
    exit 1
fi

# Check if we can connect to Kerberos port
log \"Checking Kerberos service on \$DOMAIN\"
nc -z -w 2 \$DOMAIN 88 > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    log \"WARNING: Cannot connect to Kerberos service on \$DOMAIN. Using local authentication fallback.\"
    echo \"WARNING: Cannot connect to Kerberos service on \$DOMAIN. Using local authentication fallback.\" >&2
    exit 1
fi

# Check domain membership
log \"Checking domain membership\"
net ads info > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    log \"WARNING: Not joined to domain \$DOMAIN or domain controller unreachable. Using local authentication fallback.\"
    echo \"WARNING: Not joined to domain \$DOMAIN or domain controller unreachable. Using local authentication fallback.\" >&2
    exit 1
fi

# Check Kerberos tickets
log \"Checking Kerberos tickets\"
klist > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    log \"WARNING: No valid Kerberos tickets found. Using local authentication fallback.\"
    echo \"WARNING: No valid Kerberos tickets found. Using local authentication fallback.\" >&2
    exit 1
fi

log \"AD connectivity is healthy\"
exit 0
EOF"

execute_cmd "chmod +x $WARNING_SCRIPT"

# Create more comprehensive monitoring script
log "Creating comprehensive AD monitoring script"
MONITOR_SCRIPT="/usr/local/bin/monitor_ad_connectivity.sh"

# Copy the monitor script from the host to the target
if [ "$MODE" = "native" ]; then
    # For native mode, just copy the script
    if [ -f "/usr/share/pve-smbgateway/scripts/monitor_ad_connectivity.sh" ]; then
        execute_cmd "cp /usr/share/pve-smbgateway/scripts/monitor_ad_connectivity.sh $MONITOR_SCRIPT"
    elif [ -f "scripts/monitor_ad_connectivity.sh" ]; then
        execute_cmd "cp scripts/monitor_ad_connectivity.sh $MONITOR_SCRIPT"
    else
        log "Warning: Could not find monitor_ad_connectivity.sh script"
    fi
elif [ "$MODE" = "lxc" ]; then
    # For LXC mode, push the script to the container
    if [ -f "/usr/share/pve-smbgateway/scripts/monitor_ad_connectivity.sh" ]; then
        pct push $CONTAINER_ID /usr/share/pve-smbgateway/scripts/monitor_ad_connectivity.sh $MONITOR_SCRIPT
    elif [ -f "scripts/monitor_ad_connectivity.sh" ]; then
        pct push $CONTAINER_ID scripts/monitor_ad_connectivity.sh $MONITOR_SCRIPT
    else
        log "Warning: Could not find monitor_ad_connectivity.sh script"
    fi
fi

# Make the script executable
execute_cmd "chmod +x $MONITOR_SCRIPT"

# Create cron job to check AD connectivity
log "Creating cron job to check AD connectivity"
CRON_FILE="/etc/cron.d/monitor-ad-connectivity"

execute_cmd "cat > $CRON_FILE << EOF
# Monitor AD connectivity every 5 minutes
*/5 * * * * root $MONITOR_SCRIPT --domain \$(grep -A5 '\[global\]' /etc/samba/smb.conf | grep 'realm' | awk '{print \$3}') --share $SHARE_NAME > /dev/null 2>> /var/log/ad-connectivity.log
EOF"

# Create status directory for monitoring results
execute_cmd "mkdir -p /var/lib/pve-smbgateway/status"

log "Authentication fallback configuration completed"
log "Local user: $LOCAL_USER"
log "Password: $LOCAL_PASSWORD"
log "Connectivity check script: $WARNING_SCRIPT"
log "Connectivity check log: /var/log/ad-connectivity.log"

echo "Authentication fallback configuration completed"
echo "Local user: $LOCAL_USER"
echo "Password: $LOCAL_PASSWORD"

exit 0