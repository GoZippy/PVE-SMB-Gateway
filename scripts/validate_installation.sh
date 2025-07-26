#!/bin/bash

# PVE SMB Gateway - Installation Validation Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/tmp/pve-smbgateway-validation.log"
ERROR_COUNT=0
WARNING_COUNT=0

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
            ((ERROR_COUNT++))
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            echo "[$timestamp] WARNING: $message" >> "$LOG_FILE"
            ((WARNING_COUNT++))
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            echo "[$timestamp] INFO: $message" >> "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            echo "[$timestamp] SUCCESS: $message" >> "$LOG_FILE"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check file syntax
check_perl_syntax() {
    local file=$1
    log_message "INFO" "Checking Perl syntax for $file"
    
    if perl -c "$file" 2>/dev/null; then
        log_message "SUCCESS" "Perl syntax OK for $file"
        return 0
    else
        log_message "ERROR" "Perl syntax error in $file"
        return 1
    fi
}

# Function to check module dependencies
check_perl_module() {
    local module=$1
    log_message "INFO" "Checking Perl module: $module"
    
    if perl -e "use $module; 1" 2>/dev/null; then
        log_message "SUCCESS" "Perl module $module is available"
        return 0
    else
        log_message "ERROR" "Perl module $module is missing"
        return 1
    fi
}

# Function to check system package
check_system_package() {
    local package=$1
    log_message "INFO" "Checking system package: $package"
    
    if dpkg -l | grep -q "^ii.*$package"; then
        log_message "SUCCESS" "System package $package is installed"
        return 0
    else
        log_message "WARNING" "System package $package is not installed"
        return 1
    fi
}

# Function to check file permissions
check_file_permissions() {
    local file=$1
    local expected_perms=$2
    log_message "INFO" "Checking permissions for $file"
    
    if [ -f "$file" ]; then
        local actual_perms=$(stat -c %a "$file")
        if [ "$actual_perms" = "$expected_perms" ]; then
            log_message "SUCCESS" "File permissions OK for $file ($actual_perms)"
            return 0
        else
            log_message "WARNING" "File permissions mismatch for $file (expected: $expected_perms, actual: $actual_perms)"
            return 1
        fi
    else
        log_message "ERROR" "File $file does not exist"
        return 1
    fi
}

# Function to check directory structure
check_directory_structure() {
    log_message "INFO" "Checking directory structure"
    
    local required_dirs=(
        "PVE/Storage/Custom"
        "PVE/SMBGateway"
        "sbin"
        "scripts"
        "www/ext6/pvemanager6"
        "debian"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_message "SUCCESS" "Directory $dir exists"
        else
            log_message "ERROR" "Directory $dir is missing"
        fi
    done
}

# Function to check required files
check_required_files() {
    log_message "INFO" "Checking required files"
    
    local required_files=(
        "PVE/Storage/Custom/SMBGateway.pm"
        "PVE/SMBGateway/Monitor.pm"
        "PVE/SMBGateway/Backup.pm"
        "PVE/SMBGateway/Security.pm"
        "PVE/SMBGateway/QuotaManager.pm"
        "PVE/SMBGateway/CLI.pm"
        "sbin/pve-smbgateway"
        "sbin/pve-smbgateway-enhanced"
        "debian/control"
        "debian/install"
        "debian/postinst"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            log_message "SUCCESS" "File $file exists"
        else
            log_message "ERROR" "File $file is missing"
        fi
    done
}

# Function to check Perl syntax for all files
check_all_perl_syntax() {
    log_message "INFO" "Checking Perl syntax for all files"
    
    local perl_files=(
        "PVE/Storage/Custom/SMBGateway.pm"
        "PVE/SMBGateway/Monitor.pm"
        "PVE/SMBGateway/Backup.pm"
        "PVE/SMBGateway/Security.pm"
        "PVE/SMBGateway/QuotaManager.pm"
        "PVE/SMBGateway/CLI.pm"
        "sbin/pve-smbgateway"
        "sbin/pve-smbgateway-enhanced"
    )
    
    for file in "${perl_files[@]}"; do
        if [ -f "$file" ]; then
            check_perl_syntax "$file"
        fi
    done
}

# Function to check Perl module dependencies
check_perl_dependencies() {
    log_message "INFO" "Checking Perl module dependencies"
    
    local perl_modules=(
        "PVE::Storage::Plugin"
        "PVE::Tools"
        "PVE::Exception"
        "PVE::JSONSchema"
        "DBI"
        "JSON::PP"
        "Time::HiRes"
        "File::Path"
        "File::Basename"
        "Sys::Hostname"
        "Getopt::Long"
        "Pod::Usage"
    )
    
    for module in "${perl_modules[@]}"; do
        check_perl_module "$module"
    done
}

# Function to check system package dependencies
check_system_dependencies() {
    log_message "INFO" "Checking system package dependencies"
    
    local system_packages=(
        "samba"
        "pve-manager"
        "perl"
        "libdbi-perl"
        "libdbd-sqlite3-perl"
        "libjson-pp-perl"
        "libfile-path-perl"
        "libfile-basename-perl"
        "libsys-hostname-perl"
        "quota"
        "xfsprogs"
        "libtime-hires-perl"
        "libgetopt-long-perl"
        "libpod-usage-perl"
    )
    
    for package in "${system_packages[@]}"; do
        check_system_package "$package"
    done
}

# Function to check Proxmox environment
check_proxmox_environment() {
    log_message "INFO" "Checking Proxmox environment"
    
    # Check if we're on a Proxmox system
    if [ -f "/etc/pve/version" ]; then
        log_message "SUCCESS" "Running on Proxmox VE system"
    else
        log_message "ERROR" "Not running on Proxmox VE system"
        return 1
    fi
    
    # Check Proxmox version
    if command_exists pveversion; then
        local pve_version=$(pveversion -v | head -1)
        log_message "INFO" "Proxmox version: $pve_version"
    else
        log_message "ERROR" "pveversion command not found"
        return 1
    fi
    
    # Check if we're root
    if [ "$EUID" -eq 0 ]; then
        log_message "SUCCESS" "Running as root"
    else
        log_message "ERROR" "Must run as root"
        return 1
    fi
}

# Function to check network configuration
check_network_config() {
    log_message "INFO" "Checking network configuration"
    
    # Check if we can resolve localhost
    if ping -c 1 localhost >/dev/null 2>&1; then
        log_message "SUCCESS" "Localhost connectivity OK"
    else
        log_message "ERROR" "Localhost connectivity failed"
    fi
    
    # Check if we can reach external network
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_message "SUCCESS" "External network connectivity OK"
    else
        log_message "WARNING" "External network connectivity failed"
    fi
}

# Function to check storage configuration
check_storage_config() {
    log_message "INFO" "Checking storage configuration"
    
    # Check available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ "$available_gb" -gt 1 ]; then
        log_message "SUCCESS" "Available disk space: ${available_gb}GB"
    else
        log_message "WARNING" "Low disk space: ${available_gb}GB"
    fi
    
    # Check if we have a local storage
    if pvesm status | grep -q "local"; then
        log_message "SUCCESS" "Local storage available"
    else
        log_message "WARNING" "No local storage found"
    fi
}

# Function to check service status
check_service_status() {
    log_message "INFO" "Checking service status"
    
    local services=("pveproxy" "pvedaemon" "pvestatd")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_message "SUCCESS" "Service $service is running"
        else
            log_message "ERROR" "Service $service is not running"
        fi
    done
}

# Function to check configuration files
check_config_files() {
    log_message "INFO" "Checking configuration files"
    
    # Check Samba configuration
    if [ -f "/etc/samba/smb.conf" ]; then
        log_message "SUCCESS" "Samba configuration exists"
        check_file_permissions "/etc/samba/smb.conf" "644"
    else
        log_message "WARNING" "Samba configuration not found"
    fi
    
    # Check if we can write to /etc/pve
    if [ -w "/etc/pve" ]; then
        log_message "SUCCESS" "Can write to /etc/pve"
    else
        log_message "ERROR" "Cannot write to /etc/pve"
    fi
}

# Function to run integration tests
run_integration_tests() {
    log_message "INFO" "Running integration tests"
    
    # Test module loading
    if perl -e "use PVE::Storage::Custom::SMBGateway; 1" 2>/dev/null; then
        log_message "SUCCESS" "Main plugin module loads successfully"
    else
        log_message "ERROR" "Main plugin module failed to load"
    fi
    
    # Test QuotaManager module
    if perl -e "use PVE::SMBGateway::QuotaManager; 1" 2>/dev/null; then
        log_message "SUCCESS" "QuotaManager module loads successfully"
    else
        log_message "ERROR" "QuotaManager module failed to load"
    fi
    
    # Test CLI tool syntax
    if [ -f "sbin/pve-smbgateway" ]; then
        if perl -c "sbin/pve-smbgateway" 2>/dev/null; then
            log_message "SUCCESS" "CLI tool syntax OK"
        else
            log_message "ERROR" "CLI tool syntax error"
        fi
    fi
}

# Function to generate summary report
generate_summary_report() {
    log_message "INFO" "Generating summary report"
    
    echo ""
    echo "=========================================="
    echo "PVE SMB Gateway - Validation Summary"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    echo "Results:"
    echo "- Errors: $ERROR_COUNT"
    echo "- Warnings: $WARNING_COUNT"
    echo ""
    
    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
        echo "The plugin is ready for installation."
        return 0
    else
        echo -e "${RED}❌ VALIDATION FAILED${NC}"
        echo "Please fix the errors before installation."
        return 1
    fi
}

# Main validation function
main() {
    echo "=========================================="
    echo "PVE SMB Gateway - Installation Validation"
    echo "=========================================="
    echo "This script validates the plugin before installation."
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Clear log file
    > "$LOG_FILE"
    
    # Run all validation checks
    check_directory_structure
    check_required_files
    check_all_perl_syntax
    check_perl_dependencies
    check_system_dependencies
    check_proxmox_environment
    check_network_config
    check_storage_config
    check_service_status
    check_config_files
    run_integration_tests
    
    # Generate summary
    generate_summary_report
    
    return $?
}

# Run main function
main "$@" 