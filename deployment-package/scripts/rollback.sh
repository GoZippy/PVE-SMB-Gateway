#!/bin/bash

# PVE SMB Gateway Rollback Script
# Safely removes the plugin and restores system state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== PVE SMB Gateway Rollback Script ===${NC}"
echo "This script will safely remove the SMB Gateway plugin and restore system state"
echo "Started at: $(date)"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "PASS")
            echo -e "${GREEN}✓ PASS${NC}: $message"
            ;;
        "FAIL")
            echo -e "${RED}✗ FAIL${NC}: $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠ WARN${NC}: $message"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ INFO${NC}: $message"
            ;;
        "HEADER")
            echo -e "${PURPLE}=== $message ===${NC}"
            ;;
    esac
}

# Function to confirm rollback
confirm_rollback() {
    echo -e "${RED}⚠ WARNING: This will completely remove the SMB Gateway plugin!${NC}"
    echo ""
    echo "The following actions will be performed:"
    echo "1. Stop all SMB Gateway shares and services"
    echo "2. Remove plugin files from the system"
    echo "3. Clean up configuration and data files"
    echo "4. Restart Proxmox services"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed with the rollback? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Rollback cancelled"
        exit 0
    fi
    
    echo ""
    read -p "Type 'ROLLBACK' to confirm: " -r
    if [[ ! $REPLY =~ ^ROLLBACK$ ]]; then
        echo "Rollback cancelled"
        exit 0
    fi
    
    echo ""
    print_status "INFO" "Rollback confirmed. Proceeding..."
}

# Function to stop SMB Gateway services
stop_smbgateway_services() {
    print_status "HEADER" "Stopping SMB Gateway Services"
    
    # Stop metrics collection
    if systemctl is-active --quiet pve-smbgateway-metrics.timer; then
        print_status "INFO" "Stopping metrics collection timer"
        systemctl stop pve-smbgateway-metrics.timer 2>/dev/null || true
        systemctl disable pve-smbgateway-metrics.timer 2>/dev/null || true
    fi
    
    # Stop metrics service
    if systemctl is-active --quiet pve-smbgateway-metrics.service; then
        print_status "INFO" "Stopping metrics collection service"
        systemctl stop pve-smbgateway-metrics.service 2>/dev/null || true
        systemctl disable pve-smbgateway-metrics.service 2>/dev/null || true
    fi
    
    print_status "PASS" "SMB Gateway services stopped"
}

# Function to remove SMB Gateway shares
remove_smbgateway_shares() {
    print_status "HEADER" "Removing SMB Gateway Shares"
    
    # Get list of SMB Gateway shares
    SHARES=$(pve-smbgateway list 2>/dev/null | grep -v "Storage ID" | awk '{print $1}' || echo "")
    
    if [ -n "$SHARES" ]; then
        print_status "INFO" "Found SMB Gateway shares to remove:"
        echo "$SHARES" | while read share; do
            if [ -n "$share" ]; then
                print_status "INFO" "Removing share: $share"
                pve-smbgateway delete "$share" 2>/dev/null || print_status "WARN" "Failed to remove share $share"
            fi
        done
    else
        print_status "INFO" "No SMB Gateway shares found"
    fi
    
    print_status "PASS" "SMB Gateway shares removed"
}

# Function to remove plugin files
remove_plugin_files() {
    print_status "HEADER" "Removing Plugin Files"
    
    # Remove main plugin file
    if [ -f "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm" ]; then
        print_status "INFO" "Removing main plugin file"
        rm -f "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm"
    fi
    
    # Remove SMBGateway modules
    SMBGATEWAY_MODULES=(
        "/usr/share/perl5/PVE/SMBGateway/Monitor.pm"
        "/usr/share/perl5/PVE/SMBGateway/Backup.pm"
        "/usr/share/perl5/PVE/SMBGateway/Security.pm"
        "/usr/share/perl5/PVE/SMBGateway/CLI.pm"
        "/usr/share/perl5/PVE/SMBGateway/QuotaManager.pm"
    )
    
    for module in "${SMBGATEWAY_MODULES[@]}"; do
        if [ -f "$module" ]; then
            print_status "INFO" "Removing module: $module"
            rm -f "$module"
        fi
    done
    
    # Remove CLI tools
    CLI_TOOLS=(
        "/usr/sbin/pve-smbgateway"
        "/usr/sbin/pve-smbgateway-enhanced"
    )
    
    for tool in "${CLI_TOOLS[@]}"; do
        if [ -f "$tool" ]; then
            print_status "INFO" "Removing CLI tool: $tool"
            rm -f "$tool"
        fi
    done
    
    # Remove web interface files
    WEB_FILES=(
        "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js"
        "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway-dashboard.js"
        "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway-settings.js"
        "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway-theme.js"
        "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway-widgets.js"
    )
    
    for web_file in "${WEB_FILES[@]}"; do
        if [ -f "$web_file" ]; then
            print_status "INFO" "Removing web interface file: $web_file"
            rm -f "$web_file"
        fi
    done
    
    # Remove documentation
    if [ -d "/usr/share/doc/pve-smbgateway" ]; then
        print_status "INFO" "Removing documentation directory"
        rm -rf "/usr/share/doc/pve-smbgateway"
    fi
    
    # Remove scripts directory
    if [ -d "/usr/share/pve-smbgateway" ]; then
        print_status "INFO" "Removing scripts directory"
        rm -rf "/usr/share/pve-smbgateway"
    fi
    
    print_status "PASS" "Plugin files removed"
}

# Function to clean up configuration and data
cleanup_configuration() {
    print_status "HEADER" "Cleaning Up Configuration and Data"
    
    # Remove SMB Gateway configuration from storage.cfg
    if [ -f "/etc/pve/storage.cfg" ]; then
        print_status "INFO" "Cleaning up storage configuration"
        
        # Create backup of storage.cfg
        cp "/etc/pve/storage.cfg" "/etc/pve/storage.cfg.backup.$(date +%Y%m%d-%H%M%S)"
        
        # Remove SMB Gateway entries
        sed -i '/^smbgateway:/d' "/etc/pve/storage.cfg" 2>/dev/null || true
        sed -i '/^[[:space:]]*path.*smbgateway/d' "/etc/pve/storage.cfg" 2>/dev/null || true
        
        print_status "PASS" "Storage configuration cleaned"
    fi
    
    # Remove SMB Gateway data directories
    DATA_DIRS=(
        "/etc/pve/smbgateway"
        "/var/lib/pve/smbgateway"
        "/var/log/pve-smbgateway"
    )
    
    for dir in "${DATA_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            print_status "INFO" "Removing data directory: $dir"
            rm -rf "$dir"
        fi
    done
    
    # Remove systemd service files
    SYSTEMD_FILES=(
        "/etc/systemd/system/pve-smbgateway-metrics.service"
        "/etc/systemd/system/pve-smbgateway-metrics.timer"
    )
    
    for service_file in "${SYSTEMD_FILES[@]}"; do
        if [ -f "$service_file" ]; then
            print_status "INFO" "Removing systemd service: $service_file"
            rm -f "$service_file"
        fi
    done
    
    # Reload systemd
    if command -v systemctl &> /dev/null; then
        print_status "INFO" "Reloading systemd daemon"
        systemctl daemon-reload 2>/dev/null || true
    fi
    
    print_status "PASS" "Configuration and data cleaned"
}

# Function to restart Proxmox services
restart_proxmox_services() {
    print_status "HEADER" "Restarting Proxmox Services"
    
    # Restart Proxmox services
    PROXMOX_SERVICES=(
        "pveproxy"
        "pvedaemon"
        "pvestatd"
    )
    
    for service in "${PROXMOX_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            print_status "INFO" "Restarting service: $service"
            systemctl restart "$service" 2>/dev/null || print_status "WARN" "Failed to restart $service"
        fi
    done
    
    print_status "PASS" "Proxmox services restarted"
}

# Function to verify rollback
verify_rollback() {
    print_status "HEADER" "Verifying Rollback"
    
    # Check if plugin files are removed
    PLUGIN_FILE="/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm"
    if [ -f "$PLUGIN_FILE" ]; then
        print_status "FAIL" "Plugin file still exists: $PLUGIN_FILE"
    else
        print_status "PASS" "Plugin file removed"
    fi
    
    # Check if CLI tool is removed
    CLI_TOOL="/usr/sbin/pve-smbgateway"
    if [ -f "$CLI_TOOL" ]; then
        print_status "FAIL" "CLI tool still exists: $CLI_TOOL"
    else
        print_status "PASS" "CLI tool removed"
    fi
    
    # Check if web interface is removed
    WEB_FILE="/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js"
    if [ -f "$WEB_FILE" ]; then
        print_status "FAIL" "Web interface still exists: $WEB_FILE"
    else
        print_status "PASS" "Web interface removed"
    fi
    
    # Check if services are stopped
    if systemctl is-active --quiet pve-smbgateway-metrics.timer; then
        print_status "FAIL" "Metrics timer is still running"
    else
        print_status "PASS" "Metrics timer is stopped"
    fi
    
    # Check if Proxmox services are running
    for service in "pveproxy" "pvedaemon" "pvestatd"; do
        if systemctl is-active --quiet "$service"; then
            print_status "PASS" "Proxmox service $service is running"
        else
            print_status "FAIL" "Proxmox service $service is not running"
        fi
    done
    
    print_status "PASS" "Rollback verification completed"
}

# Function to generate rollback report
generate_rollback_report() {
    print_status "HEADER" "Rollback Report"
    
    local report_file="/tmp/smbgateway-rollback-$(date +%Y%m%d-%H%M%S).log"
    
    cat > "$report_file" << EOF
PVE SMB Gateway Rollback Report
===============================
Date: $(date)
Hostname: $(hostname)

Rollback Actions Performed:
1. Stopped SMB Gateway services
2. Removed SMB Gateway shares
3. Removed plugin files
4. Cleaned up configuration and data
5. Restarted Proxmox services
6. Verified rollback completion

Backup Files Created:
- /etc/pve/storage.cfg.backup.$(date +%Y%m%d-%H%M%S)

System Status:
- Proxmox services: $(systemctl is-active pveproxy pvedaemon pvestatd | grep -c "active")/3 running
- SMB Gateway plugin: Removed
- SMB Gateway services: Stopped

Next Steps:
1. Verify Proxmox web interface is accessible
2. Check that no SMB Gateway shares remain
3. Test normal Proxmox functionality
4. If issues occur, restore from backup

For support, contact: eric@gozippy.com
EOF
    
    print_status "INFO" "Rollback report saved to: $report_file"
    print_status "PASS" "Rollback completed successfully"
}

# Main execution
main() {
    echo -e "${BLUE}Starting SMB Gateway rollback process...${NC}"
    echo ""
    
    # Confirm rollback
    confirm_rollback
    
    # Execute rollback steps
    stop_smbgateway_services
    echo ""
    
    remove_smbgateway_shares
    echo ""
    
    remove_plugin_files
    echo ""
    
    cleanup_configuration
    echo ""
    
    restart_proxmox_services
    echo ""
    
    verify_rollback
    echo ""
    
    generate_rollback_report
    echo ""
    
    echo -e "${GREEN}✅ Rollback completed successfully!${NC}"
    echo ""
    echo "The SMB Gateway plugin has been completely removed from your system."
    echo "Proxmox services have been restarted and should be functioning normally."
    echo ""
    echo "If you experience any issues:"
    echo "1. Check the rollback report for details"
    echo "2. Restore from the backup file if needed"
    echo "3. Contact support if problems persist"
    echo ""
}

# Run main function
main "$@" 