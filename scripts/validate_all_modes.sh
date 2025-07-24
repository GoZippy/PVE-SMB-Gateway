#!/bin/bash

# PVE SMB Gateway - Comprehensive Mode Validation Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test results
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}  PVE SMB Gateway Validation${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
}

# Function to record test results
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$result" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        print_success "$test_name: $message"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_error "$test_name: $message"
    fi
    
    TEST_RESULTS+=("$test_name|$result|$message")
}

# Function to check if running on Proxmox
check_proxmox_environment() {
    print_status "Checking Proxmox environment..."
    
    if [[ ! -f "/etc/pve/version" ]]; then
        print_warning "Not running on Proxmox VE host"
        print_status "Some tests may be limited"
        return 1
    fi
    
    local pve_version=$(pveversion -v | head -1 | cut -d' ' -f2)
    print_success "Proxmox VE $pve_version detected"
    return 0
}

# Function to check plugin installation
check_plugin_installation() {
    print_status "Checking plugin installation..."
    
    # Check if plugin files exist
    if [[ -f "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm" ]]; then
        record_test "Plugin Files" "PASS" "Plugin files installed"
    else
        record_test "Plugin Files" "FAIL" "Plugin files not found"
        return 1
    fi
    
    # Check if CLI tool exists
    if command -v pve-smbgateway &> /dev/null; then
        record_test "CLI Tool" "PASS" "CLI tool available"
    else
        record_test "CLI Tool" "FAIL" "CLI tool not found"
        return 1
    fi
    
    # Check if web interface integration works
    if [[ -f "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js" ]]; then
        record_test "Web Interface" "PASS" "Web interface files installed"
    else
        record_test "Web Interface" "FAIL" "Web interface files not found"
        return 1
    fi
    
    return 0
}

# Function to test LXC mode
test_lxc_mode() {
    print_status "Testing LXC mode..."
    
    local test_share="test-lxc-validation"
    local test_path="/tmp/test-lxc-validation"
    
    # Clean up any existing test share
    pve-smbgateway delete "$test_share" 2>/dev/null || true
    rm -rf "$test_path" 2>/dev/null || true
    
    # Create test directory
    mkdir -p "$test_path"
    
    # Test LXC share creation
    if pve-smbgateway create "$test_share" --mode lxc --path "$test_path" --quota 1G 2>/dev/null; then
        record_test "LXC Creation" "PASS" "LXC share created successfully"
        
        # Test share status
        if pve-smbgateway status "$test_share" >/dev/null 2>&1; then
            record_test "LXC Status" "PASS" "LXC share status accessible"
        else
            record_test "LXC Status" "FAIL" "LXC share status failed"
        fi
        
        # Test SMB connectivity (if possible)
        if command -v smbclient &> /dev/null; then
            local hostname=$(hostname)
            if timeout 10 smbclient "//$hostname/$test_share" -U guest -c "ls" 2>/dev/null; then
                record_test "LXC SMB Access" "PASS" "SMB access working"
            else
                record_test "LXC SMB Access" "WARN" "SMB access test skipped (no guest access)"
            fi
        else
            record_test "LXC SMB Access" "WARN" "smbclient not available for testing"
        fi
        
        # Cleanup
        pve-smbgateway delete "$test_share" 2>/dev/null || true
        rm -rf "$test_path" 2>/dev/null || true
        
    else
        record_test "LXC Creation" "FAIL" "LXC share creation failed"
        return 1
    fi
}

# Function to test Native mode
test_native_mode() {
    print_status "Testing Native mode..."
    
    local test_share="test-native-validation"
    local test_path="/tmp/test-native-validation"
    
    # Clean up any existing test share
    pve-smbgateway delete "$test_share" 2>/dev/null || true
    rm -rf "$test_path" 2>/dev/null || true
    
    # Create test directory
    mkdir -p "$test_path"
    
    # Test Native share creation
    if pve-smbgateway create "$test_share" --mode native --path "$test_path" --quota 1G 2>/dev/null; then
        record_test "Native Creation" "PASS" "Native share created successfully"
        
        # Test share status
        if pve-smbgateway status "$test_share" >/dev/null 2>&1; then
            record_test "Native Status" "PASS" "Native share status accessible"
        else
            record_test "Native Status" "FAIL" "Native share status failed"
        fi
        
        # Test Samba service
        if systemctl is-active smbd >/dev/null 2>&1; then
            record_test "Native Samba Service" "PASS" "Samba service running"
        else
            record_test "Native Samba Service" "FAIL" "Samba service not running"
        fi
        
        # Cleanup
        pve-smbgateway delete "$test_share" 2>/dev/null || true
        rm -rf "$test_path" 2>/dev/null || true
        
    else
        record_test "Native Creation" "FAIL" "Native share creation failed"
        return 1
    fi
}

# Function to test VM mode
test_vm_mode() {
    print_status "Testing VM mode..."
    
    local test_share="test-vm-validation"
    local test_path="/tmp/test-vm-validation"
    
    # Clean up any existing test share
    pve-smbgateway delete "$test_share" 2>/dev/null || true
    rm -rf "$test_path" 2>/dev/null || true
    
    # Create test directory
    mkdir -p "$test_path"
    
    # Check if VM templates are available
    local template_found=false
    for template in $(pvesh get /nodes/$(hostname)/storage/local/content 2>/dev/null | grep -E "smb-gateway|debian.*cloud" || true); do
        if [[ "$template" =~ smb-gateway ]] || [[ "$template" =~ debian.*cloud ]]; then
            template_found=true
            break
        fi
    done
    
    if [[ "$template_found" == false ]]; then
        print_warning "No suitable VM template found, attempting to create one..."
        
        # Try to create VM template
        if [[ -f "$PROJECT_ROOT/scripts/create_vm_template.sh" ]]; then
            if "$PROJECT_ROOT/scripts/create_vm_template.sh" --template-name test-smb-gateway 2>/dev/null; then
                record_test "VM Template Creation" "PASS" "VM template created"
                template_found=true
            else
                record_test "VM Template Creation" "FAIL" "VM template creation failed"
                record_test "VM Mode" "SKIP" "VM mode test skipped (no template)"
                return 0
            fi
        else
            record_test "VM Template Creation" "FAIL" "Template creation script not found"
            record_test "VM Mode" "SKIP" "VM mode test skipped (no template)"
            return 0
        fi
    fi
    
    # Test VM share creation
    if pve-smbgateway create "$test_share" --mode vm --path "$test_path" --vm-memory 1024 --quota 1G 2>/dev/null; then
        record_test "VM Creation" "PASS" "VM share created successfully"
        
        # Test share status
        if pve-smbgateway status "$test_share" >/dev/null 2>&1; then
            record_test "VM Status" "PASS" "VM share status accessible"
        else
            record_test "VM Status" "FAIL" "VM share status failed"
        fi
        
        # Cleanup
        pve-smbgateway delete "$test_share" 2>/dev/null || true
        rm -rf "$test_path" 2>/dev/null || true
        
    else
        record_test "VM Creation" "FAIL" "VM share creation failed"
        return 1
    fi
}

# Function to test CLI functionality
test_cli_functionality() {
    print_status "Testing CLI functionality..."
    
    # Test help command
    if pve-smbgateway --help >/dev/null 2>&1; then
        record_test "CLI Help" "PASS" "Help command works"
    else
        record_test "CLI Help" "FAIL" "Help command failed"
    fi
    
    # Test list command
    if pve-smbgateway list >/dev/null 2>&1; then
        record_test "CLI List" "PASS" "List command works"
    else
        record_test "CLI List" "FAIL" "List command failed"
    fi
    
    # Test version command (if available)
    if pve-smbgateway --version >/dev/null 2>&1; then
        record_test "CLI Version" "PASS" "Version command works"
    else
        record_test "CLI Version" "WARN" "Version command not available"
    fi
}

# Function to test error handling
test_error_handling() {
    print_status "Testing error handling..."
    
    # Test invalid share creation
    if ! pve-smbgateway create "invalid-share" --mode invalid 2>/dev/null; then
        record_test "Error Handling" "PASS" "Invalid mode properly rejected"
    else
        record_test "Error Handling" "FAIL" "Invalid mode not rejected"
    fi
    
    # Test duplicate share creation
    local test_share="test-duplicate"
    local test_path="/tmp/test-duplicate"
    
    mkdir -p "$test_path"
    
    if pve-smbgateway create "$test_share" --mode lxc --path "$test_path" --quota 1G 2>/dev/null; then
        if ! pve-smbgateway create "$test_share" --mode lxc --path "$test_path" --quota 1G 2>/dev/null; then
            record_test "Duplicate Handling" "PASS" "Duplicate share properly rejected"
        else
            record_test "Duplicate Handling" "FAIL" "Duplicate share not rejected"
        fi
        
        # Cleanup
        pve-smbgateway delete "$test_share" 2>/dev/null || true
        rm -rf "$test_path" 2>/dev/null || true
    else
        record_test "Duplicate Handling" "SKIP" "Initial share creation failed"
    fi
}

# Function to test installer
test_installer() {
    print_status "Testing installer..."
    
    # Check if installer script exists
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        record_test "Installer Script" "PASS" "Installer script exists"
        
        # Test installer help
        if "$PROJECT_ROOT/installer/run-installer.sh" --help >/dev/null 2>&1; then
            record_test "Installer Help" "PASS" "Installer help works"
        else
            record_test "Installer Help" "FAIL" "Installer help failed"
        fi
        
        # Test system check
        if "$PROJECT_ROOT/installer/run-installer.sh" --check-only >/dev/null 2>&1; then
            record_test "Installer System Check" "PASS" "System check works"
        else
            record_test "Installer System Check" "FAIL" "System check failed"
        fi
        
    else
        record_test "Installer Script" "FAIL" "Installer script not found"
    fi
    
    # Check if GUI installer exists
    if [[ -f "$PROJECT_ROOT/installer/pve-smbgateway-installer.py" ]]; then
        record_test "GUI Installer" "PASS" "GUI installer exists"
        
        # Test Python syntax
        if python3 -m py_compile "$PROJECT_ROOT/installer/pve-smbgateway-installer.py" 2>/dev/null; then
            record_test "GUI Installer Syntax" "PASS" "Python syntax valid"
        else
            record_test "GUI Installer Syntax" "FAIL" "Python syntax errors"
        fi
        
    else
        record_test "GUI Installer" "FAIL" "GUI installer not found"
    fi
}

# Function to test build system
test_build_system() {
    print_status "Testing build system..."
    
    # Check if Makefile exists
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        record_test "Makefile" "PASS" "Makefile exists"
        
        # Test make targets
        if make -C "$PROJECT_ROOT" -n deb >/dev/null 2>&1; then
            record_test "Make Deb" "PASS" "Debian package build target works"
        else
            record_test "Make Deb" "FAIL" "Debian package build target failed"
        fi
        
        if make -C "$PROJECT_ROOT" -n clean >/dev/null 2>&1; then
            record_test "Make Clean" "PASS" "Clean target works"
        else
            record_test "Make Clean" "FAIL" "Clean target failed"
        fi
        
    else
        record_test "Makefile" "FAIL" "Makefile not found"
    fi
    
    # Check if debian packaging files exist
    local debian_files=("control" "changelog" "install" "copyright" "compat")
    for file in "${debian_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/debian/$file" ]]; then
            record_test "Debian $file" "PASS" "Debian $file exists"
        else
            record_test "Debian $file" "FAIL" "Debian $file missing"
        fi
    done
}

# Function to test documentation
test_documentation() {
    print_status "Testing documentation..."
    
    # Check for key documentation files
    local doc_files=(
        "README.md"
        "docs/ARCHITECTURE.md"
        "docs/USER_GUIDE.md"
        "docs/DEV_GUIDE.md"
        "docs/INSTALLER_GUIDE.md"
        "ALPHA_RELEASE_NOTES.md"
    )
    
    for file in "${doc_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            record_test "Documentation $file" "PASS" "$file exists"
        else
            record_test "Documentation $file" "FAIL" "$file missing"
        fi
    done
    
    # Check for license files
    if [[ -f "$PROJECT_ROOT/LICENSE" ]]; then
        record_test "License" "PASS" "LICENSE file exists"
    else
        record_test "License" "FAIL" "LICENSE file missing"
    fi
    
    if [[ -f "$PROJECT_ROOT/docs/COMMERCIAL_LICENSE.md" ]]; then
        record_test "Commercial License" "PASS" "Commercial license exists"
    else
        record_test "Commercial License" "FAIL" "Commercial license missing"
    fi
}

# Function to generate test report
generate_report() {
    echo
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}  Validation Report${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
    
    echo "Test Summary:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    echo
    
    echo "Detailed Results:"
    echo "================="
    
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r test_name result_status message <<< "$result"
        
        if [[ "$result_status" == "PASS" ]]; then
            echo -e "  ${GREEN}✓${NC} $test_name: $message"
        elif [[ "$result_status" == "FAIL" ]]; then
            echo -e "  ${RED}✗${NC} $test_name: $message"
        elif [[ "$result_status" == "WARN" ]]; then
            echo -e "  ${YELLOW}⚠${NC} $test_name: $message"
        elif [[ "$result_status" == "SKIP" ]]; then
            echo -e "  ${BLUE}○${NC} $test_name: $message"
        fi
    done
    
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        print_success "All critical tests passed! The PVE SMB Gateway is ready for use."
        exit 0
    else
        print_warning "$FAILED_TESTS test(s) failed. Please review the issues above."
        exit 1
    fi
}

# Main function
main() {
    print_header
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
    fi
    
    # Check Proxmox environment
    check_proxmox_environment
    
    # Run all tests
    check_plugin_installation
    test_cli_functionality
    test_lxc_mode
    test_native_mode
    test_vm_mode
    test_error_handling
    test_installer
    test_build_system
    test_documentation
    
    # Generate report
    generate_report
}

# Run main function
main "$@" 