#!/bin/bash

# PVE SMB Gateway Pre-flight Safety Check
# Validates system readiness before live testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== PVE SMB Gateway Pre-flight Safety Check ===${NC}"
echo "This script validates system readiness before live testing"
echo "Started at: $(date)"
echo ""

# Test counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "PASS")
            echo -e "${GREEN}✓ PASS${NC}: $message"
            ((PASSED_CHECKS++))
            ;;
        "FAIL")
            echo -e "${RED}✗ FAIL${NC}: $message"
            ((FAILED_CHECKS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠ WARN${NC}: $message"
            ((WARNINGS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ INFO${NC}: $message"
            ;;
        "HEADER")
            echo -e "${PURPLE}=== $message ===${NC}"
            ;;
    esac
    
    ((TOTAL_CHECKS++))
}

# Function to check if running on Proxmox
check_proxmox_environment() {
    print_status "HEADER" "Proxmox Environment Check"
    
    if [ ! -f "/etc/pve/version" ]; then
        print_status "FAIL" "Not running on Proxmox VE"
        return 1
    fi
    print_status "PASS" "Running on Proxmox VE"
    
    # Check Proxmox version
    PVE_VERSION=$(cat /etc/pve/version 2>/dev/null || echo "unknown")
    print_status "INFO" "Proxmox version: $PVE_VERSION"
    
    # Check if cluster is configured
    if [ -f "/etc/pve/corosync.conf" ]; then
        print_status "PASS" "Cluster configuration detected"
        CLUSTER_NODES=$(grep -c "^[[:space:]]*node {" /etc/pve/corosync.conf 2>/dev/null || echo "0")
        print_status "INFO" "Cluster nodes: $CLUSTER_NODES"
    else
        print_status "WARN" "No cluster configuration detected (single node)"
    fi
}

# Function to check system resources
check_system_resources() {
    print_status "HEADER" "System Resources Check"
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    AVAIL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    
    if [ "$AVAIL_MEM" -gt 1024 ]; then
        print_status "PASS" "Sufficient memory available (${AVAIL_MEM}MB free)"
    else
        print_status "WARN" "Low memory available (${AVAIL_MEM}MB free, ${TOTAL_MEM}MB total)"
    fi
    
    # Check available disk space
    ROOT_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$ROOT_USAGE" -lt 80 ]; then
        print_status "PASS" "Sufficient disk space on root (${ROOT_USAGE}% used)"
    else
        print_status "WARN" "High disk usage on root (${ROOT_USAGE}% used)"
    fi
    
    # Check CPU load
    CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$CPU_LOAD < 2.0" | bc -l) )); then
        print_status "PASS" "CPU load is acceptable ($CPU_LOAD)"
    else
        print_status "WARN" "High CPU load ($CPU_LOAD)"
    fi
}

# Function to check required packages
check_required_packages() {
    print_status "HEADER" "Required Packages Check"
    
    # Core packages
    for pkg in "samba" "winbind" "acl" "attr"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            print_status "PASS" "Package $pkg is installed"
        else
            print_status "FAIL" "Package $pkg is not installed"
        fi
    done
    
    # Perl modules
    for module in "DBI" "DBD::SQLite" "JSON::PP" "File::Path" "File::Basename" "Sys::Hostname"; do
        if perl -M"$module" -e "1" 2>/dev/null; then
            print_status "PASS" "Perl module $module is available"
        else
            print_status "FAIL" "Perl module $module is not available"
        fi
    done
    
    # Optional packages
    for pkg in "xfsprogs" "quota"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            print_status "PASS" "Optional package $pkg is installed"
        else
            print_status "WARN" "Optional package $pkg is not installed (some features may be limited)"
        fi
    done
}

# Function to check required commands
check_required_commands() {
    print_status "HEADER" "Required Commands Check"
    
    # Proxmox commands
    for cmd in "qm" "pct" "pvesh"; do
        if command -v "$cmd" &> /dev/null; then
            print_status "PASS" "Command $cmd is available"
        else
            print_status "FAIL" "Command $cmd is not available"
        fi
    done
    
    # SMB commands
    for cmd in "smbclient" "smbpasswd"; do
        if command -v "$cmd" &> /dev/null; then
            print_status "PASS" "Command $cmd is available"
        else
            print_status "FAIL" "Command $cmd is not available"
        fi
    done
    
    # Filesystem commands
    for cmd in "zfs" "xfs_quota" "quota"; do
        if command -v "$cmd" &> /dev/null; then
            print_status "PASS" "Command $cmd is available"
        else
            print_status "WARN" "Command $cmd is not available (some quota features may be limited)"
        fi
    done
}

# Function to check network configuration
check_network_configuration() {
    print_status "HEADER" "Network Configuration Check"
    
    # Check if we have network connectivity
    if ping -c 3 8.8.8.8 &> /dev/null; then
        print_status "PASS" "Internet connectivity available"
    else
        print_status "WARN" "No internet connectivity (template downloads may fail)"
    fi
    
    # Check SMB ports
    for port in 139 445; do
        if netstat -tln | grep -q ":$port "; then
            print_status "WARN" "Port $port is already in use (SMB conflict possible)"
        else
            print_status "PASS" "Port $port is available"
        fi
    done
    
    # Check firewall
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        print_status "WARN" "UFW firewall is active (may block SMB traffic)"
    elif command -v iptables &> /dev/null && iptables -L | grep -q "REJECT"; then
        print_status "WARN" "IPTables rules detected (may block SMB traffic)"
    else
        print_status "PASS" "No restrictive firewall detected"
    fi
}

# Function to check storage configuration
check_storage_configuration() {
    print_status "HEADER" "Storage Configuration Check"
    
    # Check available storage
    STORAGE_LIST=$(pvesh get /storage 2>/dev/null | grep -o '"storage":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    if [ -n "$STORAGE_LIST" ]; then
        print_status "PASS" "Storage backends configured"
        echo "$STORAGE_LIST" | while read storage; do
            print_status "INFO" "Storage backend: $storage"
        done
    else
        print_status "WARN" "No storage backends configured"
    fi
    
    # Check ZFS pools
    if command -v zfs &> /dev/null; then
        ZFS_POOLS=$(zpool list -H -o name 2>/dev/null || echo "")
        if [ -n "$ZFS_POOLS" ]; then
            print_status "PASS" "ZFS pools available"
            echo "$ZFS_POOLS" | while read pool; do
                print_status "INFO" "ZFS pool: $pool"
            done
        else
            print_status "WARN" "No ZFS pools configured"
        fi
    fi
    
    # Check available space for test shares
    TEST_DIR="/srv/smb"
    if [ -d "$TEST_DIR" ]; then
        AVAIL_SPACE=$(df "$TEST_DIR" | tail -1 | awk '{print $4}')
        AVAIL_GB=$((AVAIL_SPACE / 1024 / 1024))
        if [ "$AVAIL_GB" -gt 10 ]; then
            print_status "PASS" "Sufficient space for test shares (${AVAIL_GB}GB available)"
        else
            print_status "WARN" "Limited space for test shares (${AVAIL_GB}GB available)"
        fi
    else
        print_status "INFO" "Test directory $TEST_DIR will be created"
    fi
}

# Function to check service status
check_service_status() {
    print_status "HEADER" "Service Status Check"
    
    # Check Proxmox services
    for service in "pveproxy" "pvedaemon" "pvestatd"; do
        if systemctl is-active --quiet "$service"; then
            print_status "PASS" "Service $service is running"
        else
            print_status "FAIL" "Service $service is not running"
        fi
    done
    
    # Check Samba services
    for service in "smbd" "nmbd"; do
        if systemctl is-active --quiet "$service"; then
            print_status "WARN" "Samba service $service is already running (may conflict)"
        else
            print_status "PASS" "Samba service $service is not running"
        fi
    done
}

# Function to check security settings
check_security_settings() {
    print_status "HEADER" "Security Settings Check"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_status "PASS" "Running with root privileges"
    else
        print_status "FAIL" "Not running with root privileges"
    fi
    
    # Check SELinux
    if command -v sestatus &> /dev/null && sestatus | grep -q "SELinux status.*enabled"; then
        print_status "WARN" "SELinux is enabled (may interfere with SMB)"
    else
        print_status "PASS" "SELinux is not enabled"
    fi
    
    # Check AppArmor
    if command -v aa-status &> /dev/null && aa-status | grep -q "apparmor module is loaded"; then
        print_status "WARN" "AppArmor is enabled (may interfere with SMB)"
    else
        print_status "PASS" "AppArmor is not enabled"
    fi
}

# Function to check plugin installation
check_plugin_installation() {
    print_status "HEADER" "Plugin Installation Check"
    
    # Check if plugin files exist
    PLUGIN_FILE="/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm"
    if [ -f "$PLUGIN_FILE" ]; then
        print_status "PASS" "SMB Gateway plugin is installed"
    else
        print_status "FAIL" "SMB Gateway plugin is not installed"
    fi
    
    # Check CLI tool
    CLI_TOOL="/usr/sbin/pve-smbgateway"
    if [ -f "$CLI_TOOL" ] && [ -x "$CLI_TOOL" ]; then
        print_status "PASS" "SMB Gateway CLI tool is installed and executable"
    else
        print_status "FAIL" "SMB Gateway CLI tool is not installed or not executable"
    fi
    
    # Check web interface
    WEB_FILE="/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js"
    if [ -f "$WEB_FILE" ]; then
        print_status "PASS" "SMB Gateway web interface is installed"
    else
        print_status "FAIL" "SMB Gateway web interface is not installed"
    fi
}

# Function to check test environment
check_test_environment() {
    print_status "HEADER" "Test Environment Check"
    
    # Check if we're in a test environment
    if [ -f "/etc/pve/test-environment" ] || [ "$HOSTNAME" = "test"* ] || [ "$HOSTNAME" = "dev"* ]; then
        print_status "PASS" "Test environment detected"
    else
        print_status "WARN" "This appears to be a production environment"
        echo ""
        echo -e "${YELLOW}⚠ WARNING: This appears to be a production environment!${NC}"
        echo "Please ensure you have:"
        echo "1. Recent backups of your Proxmox configuration"
        echo "2. A rollback plan in case of issues"
        echo "3. Tested this plugin in a non-production environment first"
        echo ""
        read -p "Do you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Aborting pre-flight check"
            exit 1
        fi
    fi
    
    # Check available test resources
    if [ -d "/tmp" ] && [ -w "/tmp" ]; then
        print_status "PASS" "Temporary directory is writable"
    else
        print_status "FAIL" "Temporary directory is not writable"
    fi
}

# Function to generate recommendations
generate_recommendations() {
    print_status "HEADER" "Recommendations"
    
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "${RED}❌ CRITICAL ISSUES DETECTED${NC}"
        echo "Please fix the following issues before testing:"
        echo "1. Install missing packages and dependencies"
        echo "2. Ensure all required services are running"
        echo "3. Fix network and storage configuration issues"
        echo ""
    fi
    
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ WARNINGS DETECTED${NC}"
        echo "Consider addressing the following warnings:"
        echo "1. Install optional packages for full functionality"
        echo "2. Configure firewall rules for SMB traffic"
        echo "3. Ensure sufficient system resources"
        echo ""
    fi
    
    if [ $FAILED_CHECKS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ SYSTEM READY FOR TESTING${NC}"
        echo "All critical checks passed. The system is ready for live testing."
        echo ""
        echo "Recommended next steps:"
        echo "1. Run the comprehensive test suite: ./scripts/run_all_tests.sh"
        echo "2. Test with a small, non-critical share first"
        echo "3. Monitor system resources during testing"
        echo "4. Have a rollback plan ready"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting pre-flight safety check...${NC}"
    echo ""
    
    check_proxmox_environment
    echo ""
    
    check_system_resources
    echo ""
    
    check_required_packages
    echo ""
    
    check_required_commands
    echo ""
    
    check_network_configuration
    echo ""
    
    check_storage_configuration
    echo ""
    
    check_service_status
    echo ""
    
    check_security_settings
    echo ""
    
    check_plugin_installation
    echo ""
    
    check_test_environment
    echo ""
    
    # Summary
    print_status "HEADER" "Pre-flight Check Summary"
    print_status "INFO" "Total checks: $TOTAL_CHECKS"
    print_status "INFO" "Passed: $PASSED_CHECKS"
    print_status "INFO" "Failed: $FAILED_CHECKS"
    print_status "INFO" "Warnings: $WARNINGS"
    
    echo ""
    generate_recommendations
    
    # Exit with appropriate code
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "${RED}Pre-flight check failed. Please fix critical issues before testing.${NC}"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Pre-flight check completed with warnings. Review recommendations before testing.${NC}"
        exit 0
    else
        echo -e "${GREEN}Pre-flight check passed. System is ready for testing.${NC}"
        exit 0
    fi
}

# Run main function
main "$@" 