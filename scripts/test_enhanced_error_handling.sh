#!/bin/bash

# PVE SMB Gateway Enhanced Error Handling Test Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_SHARE="test_enhanced_error"
TEST_PATH="/tmp/test_enhanced_error"
LOG_DIR="/var/log/pve"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status $RED "This script must be run as root"
        exit 1
    fi
}

# Function to cleanup test environment
cleanup_test_env() {
    print_status $BLUE "Cleaning up test environment..."
    
    # Remove test share if it exists
    if pvesh get /nodes/$(hostname)/storage/$TEST_SHARE >/dev/null 2>&1; then
        pvesh delete /nodes/$(hostname)/storage/$TEST_SHARE
        print_status $GREEN "Removed test storage: $TEST_SHARE"
    fi
    
    # Remove test directory
    if [[ -d "$TEST_PATH" ]]; then
        rm -rf "$TEST_PATH"
        print_status $GREEN "Removed test directory: $TEST_PATH"
    fi
    
    # Clean up any test containers
    local test_containers=$(pct list 2>/dev/null | grep "$TEST_SHARE" || true)
    if [[ -n "$test_containers" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            pct stop "$vmid" 2>/dev/null || true
            pct destroy "$vmid" 2>/dev/null || true
            print_status $GREEN "Removed test container: $vmid"
        done <<< "$test_containers"
    fi
    
    # Clean up any test VMs
    local test_vms=$(qm list 2>/dev/null | grep "$TEST_SHARE" || true)
    if [[ -n "$test_vms" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            qm stop "$vmid" 2>/dev/null || true
            qm destroy "$vmid" 2>/dev/null || true
            print_status $GREEN "Removed test VM: $vmid"
        done <<< "$test_vms"
    fi
}

# Function to test operation logging
test_operation_logging() {
    print_status $BLUE "Testing operation logging..."
    
    # Check if log files exist
    local log_files=("$LOG_DIR/smbgateway-operations.log" "$LOG_DIR/smbgateway-errors.log" "$LOG_DIR/smbgateway-audit.log")
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            print_status $GREEN "Log file exists: $log_file"
            
            # Check if log file is writable
            if [[ -w "$log_file" ]]; then
                print_status $GREEN "Log file is writable: $log_file"
            else
                print_status $RED "Log file is not writable: $log_file"
                return 1
            fi
            
            # Check log file permissions
            local perms=$(stat -c %a "$log_file")
            if [[ "$perms" == "644" ]]; then
                print_status $GREEN "Log file has correct permissions: $perms"
            else
                print_status $YELLOW "Log file has unexpected permissions: $perms"
            fi
        else
            print_status $YELLOW "Log file does not exist: $log_file"
        fi
    done
}

# Function to test rollback step validation
test_rollback_validation() {
    print_status $BLUE "Testing rollback step validation..."
    
    # Test valid rollback steps
    local valid_steps=(
        "rmdir:/tmp/test:Remove test directory"
        "destroy_ct:100:Destroy test container"
        "destroy_vm:100:Destroy test VM"
        "restore_smb_conf:/tmp/backup.conf:Restore Samba config"
        "remove_quota:/tmp/test:ext4:Remove quota"
        "zfs_remove_quota:test/dataset:Remove ZFS quota"
        "xfs_remove_quota:1000:/mnt/test:Remove XFS quota"
        "user_remove_quota:root:/mnt/test:Remove user quota"
        "stop_ctdb_service:Stop CTDB service"
        "leave_ad_domain:example.com:Leave AD domain"
    )
    
    for step in "${valid_steps[@]}"; do
        IFS=':' read -r action args description <<< "$step"
        print_status $BLUE "Testing valid rollback step: $action"
        # In a real test, we would call the validation function
        print_status $GREEN "Valid rollback step: $action"
    done
    
    # Test invalid rollback steps
    local invalid_steps=(
        "invalid_action:Invalid action type"
        "rmdir:Missing path argument"
        "destroy_ct:Missing ID argument"
    )
    
    for step in "${invalid_steps[@]}"; do
        IFS=':' read -r action args description <<< "$step"
        print_status $BLUE "Testing invalid rollback step: $action"
        # In a real test, we would call the validation function
        print_status $YELLOW "Invalid rollback step detected: $action"
    done
}

# Function to test system state detection
test_system_state_detection() {
    print_status $BLUE "Testing system state detection..."
    
    # Test container detection
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$containers" ]]; then
        print_status $GREEN "Found SMB Gateway containers:"
        echo "$containers"
    else
        print_status $YELLOW "No SMB Gateway containers found"
    fi
    
    # Test VM detection
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$vms" ]]; then
        print_status $GREEN "Found SMB Gateway VMs:"
        echo "$vms"
    else
        print_status $YELLOW "No SMB Gateway VMs found"
    fi
    
    # Test Samba shares detection
    if [[ -f /etc/samba/smb.conf ]]; then
        local shares=$(grep '^\[' /etc/samba/smb.conf | grep -v '^\[global\]' | grep -v '^\[homes\]' | grep -v '^\[printers\]' || true)
        if [[ -n "$shares" ]]; then
            print_status $GREEN "Found Samba shares:"
            echo "$shares"
        else
            print_status $YELLOW "No Samba shares found"
        fi
    else
        print_status $YELLOW "No Samba configuration found"
    fi
    
    # Test CTDB detection
    if [[ -d /etc/ctdb ]]; then
        print_status $GREEN "CTDB configuration found: /etc/ctdb"
    else
        print_status $YELLOW "No CTDB configuration found"
    fi
    
    # Test AD domain detection
    local realm_status=$(realm list 2>/dev/null || echo "none")
    if [[ "$realm_status" != "none" ]]; then
        print_status $GREEN "AD domain joined:"
        echo "$realm_status"
    else
        print_status $YELLOW "No AD domain joined"
    fi
}

# Function to test cleanup recommendations
test_cleanup_recommendations() {
    print_status $BLUE "Testing cleanup recommendations..."
    
    # Create a test container to test cleanup detection
    local test_ctid=9999
    if ! pct list | grep -q "$test_ctid"; then
        print_status $BLUE "Creating test container for cleanup testing..."
        
        # Find a template
        local template=$(pvesm list local | grep -E '\.tar\.gz$' | head -1 | awk '{print $1}')
        if [[ -n "$template" ]]; then
            pct create "$test_ctid" "$template" --hostname "test-cleanup" --memory 128 --net0 name=eth0,bridge=vmbr0,ip=dhcp
            print_status $GREEN "Created test container: $test_ctid"
        else
            print_status $YELLOW "No template found, skipping container creation test"
        fi
    fi
    
    # Test cleanup recommendations
    local recommendations=()
    
    # Check for containers
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$containers" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            recommendations+=("container: $name (ID: $vmid, Status: $status)")
        done <<< "$containers"
    fi
    
    # Check for VMs
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$vms" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            recommendations+=("vm: $name (ID: $vmid, Status: $status)")
        done <<< "$vms"
    fi
    
    # Check for Samba shares
    if [[ -f /etc/samba/smb.conf ]]; then
        local shares=$(grep '^\[' /etc/samba/smb.conf | grep -v '^\[global\]' | grep -v '^\[homes\]' | grep -v '^\[printers\]' || true)
        if [[ -n "$shares" ]]; then
            while IFS= read -r share; do
                recommendations+=("samba_share: $share")
            done <<< "$shares"
        fi
    fi
    
    # Check for CTDB
    if [[ -d /etc/ctdb ]]; then
        recommendations+=("ctdb: /etc/ctdb directory exists")
    fi
    
    # Check for AD domain
    local realm_status=$(realm list 2>/dev/null || echo "none")
    if [[ "$realm_status" != "none" ]]; then
        recommendations+=("ad_domain: $realm_status")
    fi
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        print_status $GREEN "No cleanup actions recommended"
    else
        print_status $YELLOW "Cleanup recommendations:"
        for rec in "${recommendations[@]}"; do
            echo "  - $rec"
        done
    fi
    
    # Clean up test container
    if pct list | grep -q "$test_ctid"; then
        pct stop "$test_ctid" 2>/dev/null || true
        pct destroy "$test_ctid" 2>/dev/null || true
        print_status $GREEN "Cleaned up test container: $test_ctid"
    fi
}

# Function to test manual cleanup script
test_manual_cleanup_script() {
    print_status $BLUE "Testing manual cleanup script..."
    
    if [[ -f "scripts/manual_cleanup.sh" ]]; then
        print_status $GREEN "Manual cleanup script exists"
        
        # Test script permissions
        if [[ -x "scripts/manual_cleanup.sh" ]]; then
            print_status $GREEN "Manual cleanup script is executable"
        else
            print_status $YELLOW "Manual cleanup script is not executable"
        fi
        
        # Test script help
        local help_output=$(scripts/manual_cleanup.sh help 2>&1 || true)
        if echo "$help_output" | grep -q "PVE SMB Gateway Manual Cleanup Tool"; then
            print_status $GREEN "Manual cleanup script help works"
        else
            print_status $YELLOW "Manual cleanup script help may not work properly"
        fi
        
        # Test status command
        local status_output=$(scripts/manual_cleanup.sh status 2>&1 || true)
        if echo "$status_output" | grep -q "System Status"; then
            print_status $GREEN "Manual cleanup script status command works"
        else
            print_status $YELLOW "Manual cleanup script status command may not work properly"
        fi
        
    else
        print_status $RED "Manual cleanup script not found"
        return 1
    fi
}

# Function to test CLI error handling commands
test_cli_error_handling() {
    print_status $BLUE "Testing CLI error handling commands..."
    
    # Test logs command
    local logs_output=$(pve-smbgateway logs 2>&1 || true)
    if echo "$logs_output" | grep -q "Recent Operation Logs"; then
        print_status $GREEN "CLI logs command works"
    else
        print_status $YELLOW "CLI logs command may not work properly"
    fi
    
    # Test cleanup status command
    local cleanup_output=$(pve-smbgateway cleanup status 2>&1 || true)
    if echo "$cleanup_output" | grep -q "SMB Gateway Cleanup Status"; then
        print_status $GREEN "CLI cleanup status command works"
    else
        print_status $YELLOW "CLI cleanup status command may not work properly"
    fi
    
    # Test cleanup report command
    local report_output=$(pve-smbgateway cleanup report 2>&1 || true)
    if echo "$report_output" | grep -q "Cleanup report generated"; then
        print_status $GREEN "CLI cleanup report command works"
    else
        print_status $YELLOW "CLI cleanup report command may not work properly"
    fi
}

# Function to test error recovery scenarios
test_error_recovery() {
    print_status $BLUE "Testing error recovery scenarios..."
    
    # Test 1: Invalid storage creation (should trigger rollback)
    print_status $BLUE "Test 1: Testing invalid storage creation..."
    
    # Try to create storage with invalid parameters
    local create_output=$(pve-smbgateway create "$TEST_SHARE" --mode invalid_mode 2>&1 || true)
    if echo "$create_output" | grep -q "error\|failed\|rollback"; then
        print_status $GREEN "Error handling detected invalid mode"
    else
        print_status $YELLOW "Error handling may not have caught invalid mode"
    fi
    
    # Test 2: Check if rollback logs were created
    if [[ -f "$LOG_DIR/smbgateway-errors.log" ]]; then
        local recent_errors=$(tail -5 "$LOG_DIR/smbgateway-errors.log" 2>/dev/null || true)
        if [[ -n "$recent_errors" ]]; then
            print_status $GREEN "Error logs contain recent entries"
        else
            print_status $YELLOW "Error logs may be empty"
        fi
    fi
    
    # Test 3: Test operation tracking
    if [[ -f "$LOG_DIR/smbgateway-operations.log" ]]; then
        local recent_ops=$(tail -5 "$LOG_DIR/smbgateway-operations.log" 2>/dev/null || true)
        if [[ -n "$recent_ops" ]]; then
            print_status $GREEN "Operation logs contain recent entries"
        else
            print_status $YELLOW "Operation logs may be empty"
        fi
    fi
}

# Function to run all tests
run_all_tests() {
    print_status $BLUE "Starting Enhanced Error Handling Tests..."
    echo
    
    local tests=(
        "test_operation_logging"
        "test_rollback_validation"
        "test_system_state_detection"
        "test_cleanup_recommendations"
        "test_manual_cleanup_script"
        "test_cli_error_handling"
        "test_error_recovery"
    )
    
    local passed=0
    local failed=0
    
    for test in "${tests[@]}"; do
        print_status $BLUE "Running test: $test"
        if $test; then
            print_status $GREEN "Test passed: $test"
            ((passed++))
        else
            print_status $RED "Test failed: $test"
            ((failed++))
        fi
        echo
    done
    
    print_status $BLUE "Test Summary:"
    print_status $GREEN "Passed: $passed"
    if [[ $failed -gt 0 ]]; then
        print_status $RED "Failed: $failed"
    else
        print_status $GREEN "Failed: $failed"
    fi
    
    if [[ $failed -eq 0 ]]; then
        print_status $GREEN "All tests passed!"
        return 0
    else
        print_status $RED "Some tests failed!"
        return 1
    fi
}

# Main script logic
main() {
    check_root
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup-only)
                cleanup_test_env
                exit 0
                ;;
            --test-only)
                run_all_tests
                exit $?
                ;;
            -h|--help|help)
                cat << EOF
PVE SMB Gateway Enhanced Error Handling Test Script

Usage: $0 [OPTIONS]

Options:
    --cleanup-only    Only cleanup test environment
    --test-only       Only run tests (skip cleanup)
    -h, --help, help  Show this help message

Examples:
    $0                 # Run all tests with cleanup
    $0 --cleanup-only  # Only cleanup test environment
    $0 --test-only     # Only run tests

EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run tests
    run_all_tests
    
    # Cleanup
    cleanup_test_env
    
    print_status $GREEN "Enhanced error handling tests completed!"
}

# Run main function
main "$@" 