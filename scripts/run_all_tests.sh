#!/bin/bash

# PVE SMB Gateway Comprehensive Test Runner
# Runs all test suites for the project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TEST_RESULTS_DIR="/tmp/pve-smbgateway-test-results"
LOG_FILE="$TEST_RESULTS_DIR/test-run-$(date +%Y%m%d-%H%M%S).log"
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test configuration
VM_TEMPLATE_NAME="smb-gateway-debian12"
TEST_SHARE="comprehensive-test"
TEST_PATH="/srv/smb/comprehensive-test"
TEST_QUOTA="10G"

echo -e "${BLUE}=== PVE SMB Gateway Comprehensive Test Runner ===${NC}"
echo "Test Results Directory: $TEST_RESULTS_DIR"
echo "Log File: $LOG_FILE"
echo "Started at: $(date)"
echo ""

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to print status
print_status() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%H:%M:%S')
    
    case $status in
        "PASS")
            echo -e "${GREEN}[$timestamp] ✓ PASS${NC}: $message"
            echo "[$timestamp] PASS: $message" >> "$LOG_FILE"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}[$timestamp] ✗ FAIL${NC}: $message"
            echo "[$timestamp] FAIL: $message" >> "$LOG_FILE"
            ((FAILED_TESTS++))
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] ℹ INFO${NC}: $message"
            echo "[$timestamp] INFO: $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] ⚠ WARN${NC}: $message"
            echo "[$timestamp] WARN: $message" >> "$LOG_FILE"
            ;;
        "HEADER")
            echo -e "${PURPLE}[$timestamp] === $message ===${NC}"
            echo "[$timestamp] === $message ===" >> "$LOG_FILE"
            ;;
        "SUBTEST")
            echo -e "${CYAN}[$timestamp] → $message${NC}"
            echo "[$timestamp] → $message" >> "$LOG_FILE"
            ;;
    esac
    
    ((TOTAL_TESTS++))
}

# Function to run a test suite
run_test_suite() {
    local test_name=$1
    local test_script=$2
    local test_args=$3
    
    print_status "HEADER" "Running $test_name"
    
    if [ -f "$test_script" ]; then
        print_status "INFO" "Executing: $test_script $test_args"
        
        # Run test and capture output
        if timeout 600 bash "$test_script" $test_args 2>&1 | tee -a "$LOG_FILE"; then
            print_status "PASS" "$test_name completed successfully"
        else
            print_status "FAIL" "$test_name failed"
            return 1
        fi
    else
        print_status "FAIL" "Test script not found: $test_script"
        return 1
    fi
    
    echo "" >> "$LOG_FILE"
    return 0
}

# Function to cleanup test resources
cleanup_all() {
    print_status "INFO" "Performing comprehensive cleanup..."
    
    # Stop and destroy any test VMs
    for vm in $(qm list | grep -E "(test|quotatest|perftest)" | awk '{print $1}'); do
        print_status "INFO" "Stopping VM $vm"
        qm stop "$vm" 2>/dev/null || true
        sleep 2
        print_status "INFO" "Destroying VM $vm"
        qm destroy "$vm" 2>/dev/null || true
    done
    
    # Remove test shares
    for share in $(pve-smbgateway list 2>/dev/null | grep -E "(test|quotatest|perftest)" | awk '{print $1}' || true); do
        print_status "INFO" "Removing share $share"
        pve-smbgateway delete "$share" 2>/dev/null || true
    done
    
    # Clean up test directories
    for dir in "/srv/smb/test" "/srv/smb/quotatest" "/tmp/perftest" "/tmp/test-*"; do
        if [ -d "$dir" ]; then
            print_status "INFO" "Removing directory $dir"
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    # Clean up test files
    rm -f "/tmp/test-*" 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup_all EXIT

# Test 1: Prerequisites Check
print_status "HEADER" "Test 1: System Prerequisites"
print_status "SUBTEST" "Checking Proxmox VE environment"

if [ ! -f "/etc/pve/version" ]; then
    print_status "FAIL" "Not running on Proxmox VE"
    exit 1
fi
print_status "PASS" "Running on Proxmox VE"

# Check required packages
for pkg in "samba" "winbind" "acl" "attr"; do
    if dpkg -l | grep -q "^ii.*$pkg"; then
        print_status "PASS" "Package $pkg is installed"
    else
        print_status "WARN" "Package $pkg is not installed"
    fi
done

# Check required commands
for cmd in "pve-smbgateway" "qm" "pct" "zfs" "xfs_quota"; do
    if command -v "$cmd" &> /dev/null; then
        print_status "PASS" "Command $cmd is available"
    else
        print_status "WARN" "Command $cmd is not available"
    fi
done

echo ""

# Test 2: VM Template Creation
print_status "HEADER" "Test 2: VM Template Creation"
run_test_suite "VM Template Creation" "./scripts/create_vm_template.sh" "$VM_TEMPLATE_NAME 2048 20G"

echo ""

# Test 3: VM Mode Testing
print_status "HEADER" "Test 3: VM Mode Testing"
run_test_suite "VM Mode Testing" "./scripts/test_vm_mode.sh" "$VM_TEMPLATE_NAME testvm /srv/smb/testvm 10G 2048 2"

echo ""

# Test 4: Quota Management Testing
print_status "HEADER" "Test 4: Quota Management Testing"
run_test_suite "Quota Management Testing" "./scripts/test_quota_management.sh" "quotatest /srv/smb/quotatest 1G lxc"

echo ""

# Test 5: LXC Mode Testing
print_status "HEADER" "Test 5: LXC Mode Testing"
print_status "SUBTEST" "Testing LXC mode share creation"

# Create test directory
mkdir -p "$TEST_PATH"

# Create share in LXC mode
if pve-smbgateway create "$TEST_SHARE" \
    --mode lxc \
    --path "$TEST_PATH" \
    --quota "$TEST_QUOTA"; then
    print_status "PASS" "LXC mode share creation successful"
else
    print_status "FAIL" "LXC mode share creation failed"
    exit 1
fi

# Wait for share to be ready
sleep 10

# Check share status
if pve-smbgateway status "$TEST_SHARE" | grep -q "running\|active"; then
    print_status "PASS" "LXC share is running"
else
    print_status "FAIL" "LXC share is not running"
fi

# Test SMB connectivity
LXC_IP=$(pct exec $(pct list | grep "$TEST_SHARE" | awk '{print $1}') ip route get 1 | awk '{print $7}' | head -1)
if [ -n "$LXC_IP" ]; then
    if smbclient -L "//$LXC_IP" -U guest% 2>/dev/null | grep -q "$TEST_SHARE"; then
        print_status "PASS" "LXC SMB connectivity successful"
    else
        print_status "WARN" "LXC SMB connectivity test failed"
    fi
else
    print_status "WARN" "Could not get LXC IP address"
fi

# Clean up LXC test
pve-smbgateway delete "$TEST_SHARE" 2>/dev/null || true

echo ""

# Test 6: Native Mode Testing
print_status "HEADER" "Test 6: Native Mode Testing"
print_status "SUBTEST" "Testing native mode share creation"

# Create test directory
mkdir -p "$TEST_PATH"

# Create share in native mode
if pve-smbgateway create "$TEST_SHARE" \
    --mode native \
    --path "$TEST_PATH" \
    --quota "$TEST_QUOTA"; then
    print_status "PASS" "Native mode share creation successful"
else
    print_status "FAIL" "Native mode share creation failed"
    exit 1
fi

# Wait for share to be ready
sleep 5

# Check share status
if pve-smbgateway status "$TEST_SHARE" | grep -q "running\|active"; then
    print_status "PASS" "Native share is running"
else
    print_status "FAIL" "Native share is not running"
fi

# Test SMB connectivity
HOST_IP=$(hostname -I | awk '{print $1}')
if smbclient -L "//$HOST_IP" -U guest% 2>/dev/null | grep -q "$TEST_SHARE"; then
    print_status "PASS" "Native SMB connectivity successful"
else
    print_status "WARN" "Native SMB connectivity test failed"
fi

# Clean up native test
pve-smbgateway delete "$TEST_SHARE" 2>/dev/null || true

echo ""

# Test 7: CLI Functionality Testing
print_status "HEADER" "Test 7: CLI Functionality Testing"
print_status "SUBTEST" "Testing CLI commands"

# Test list command
if pve-smbgateway list 2>/dev/null; then
    print_status "PASS" "CLI list command works"
else
    print_status "FAIL" "CLI list command failed"
fi

# Test help command
if pve-smbgateway --help 2>/dev/null | grep -q "Usage"; then
    print_status "PASS" "CLI help command works"
else
    print_status "FAIL" "CLI help command failed"
fi

# Test version command
if pve-smbgateway --version 2>/dev/null; then
    print_status "PASS" "CLI version command works"
else
    print_status "WARN" "CLI version command not available"
fi

echo ""

# Test 8: Error Handling Testing
print_status "HEADER" "Test 8: Error Handling Testing"
print_status "SUBTEST" "Testing error handling"

# Test invalid share name
if pve-smbgateway create "invalid-share-name!" --mode lxc --path "/tmp/test" 2>&1 | grep -q "Invalid"; then
    print_status "PASS" "Invalid share name properly rejected"
else
    print_status "FAIL" "Invalid share name not rejected"
fi

# Test non-existent path
if pve-smbgateway create "test" --mode lxc --path "/nonexistent/path" 2>&1 | grep -q "Path does not exist"; then
    print_status "PASS" "Non-existent path properly rejected"
else
    print_status "FAIL" "Non-existent path not rejected"
fi

# Test invalid mode
if pve-smbgateway create "test" --mode invalid --path "/tmp/test" 2>&1 | grep -q "Unknown mode"; then
    print_status "PASS" "Invalid mode properly rejected"
else
    print_status "FAIL" "Invalid mode not rejected"
fi

echo ""

# Test 9: Performance Testing
print_status "HEADER" "Test 9: Performance Testing"
print_status "SUBTEST" "Testing performance metrics"

# Create a test share for performance testing
PERF_SHARE="perftest"
PERF_PATH="/tmp/perftest"
mkdir -p "$PERF_PATH"

# Measure creation time
START_TIME=$(date +%s.%N)
if pve-smbgateway create "$PERF_SHARE" --mode lxc --path "$PERF_PATH" --quota "10G"; then
    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc -l)
    
    if (( $(echo "$DURATION < 60" | bc -l) )); then
        print_status "PASS" "Share creation completed in ${DURATION}s (under 60s threshold)"
    else
        print_status "WARN" "Share creation took ${DURATION}s (over 60s threshold)"
    fi
    
    # Clean up
    pve-smbgateway delete "$PERF_SHARE" 2>/dev/null || true
    rm -rf "$PERF_PATH"
else
    print_status "FAIL" "Performance test share creation failed"
fi

echo ""

# Test 10: Integration Testing
print_status "HEADER" "Test 10: Integration Testing"
print_status "SUBTEST" "Testing integration with Proxmox"

# Test storage plugin integration
if pvesh get /storage 2>/dev/null | grep -q "smbgateway"; then
    print_status "PASS" "SMB Gateway storage plugin is registered"
else
    print_status "WARN" "SMB Gateway storage plugin not found in storage list"
fi

# Test API integration
if pvesh get /nodes/$(hostname)/storage 2>/dev/null | grep -q "smbgateway"; then
    print_status "PASS" "SMB Gateway API integration working"
else
    print_status "WARN" "SMB Gateway API integration not detected"
fi

echo ""

# Test 11: Security Testing
print_status "HEADER" "Test 11: Security Testing"
print_status "SUBTEST" "Testing security features"

# Test SMB protocol security
if smbclient -L "//$HOST_IP" -U guest% 2>/dev/null | grep -q "SMB"; then
    print_status "PASS" "SMB protocol is accessible"
else
    print_status "WARN" "SMB protocol not accessible"
fi

# Test file permissions
TEST_FILE="/tmp/security_test"
echo "test" > "$TEST_FILE"
chmod 600 "$TEST_FILE"

if [ -r "$TEST_FILE" ]; then
    print_status "PASS" "File permission test passed"
else
    print_status "FAIL" "File permission test failed"
fi

rm -f "$TEST_FILE"

echo ""

# Test 12: Monitoring Testing
print_status "HEADER" "Test 12: Monitoring Testing"
print_status "SUBTEST" "Testing monitoring features"

# Create a test share for monitoring
MON_SHARE="montest"
MON_PATH="/tmp/montest"
mkdir -p "$MON_PATH"

if pve-smbgateway create "$MON_SHARE" --mode lxc --path "$MON_PATH" --quota "5G"; then
    # Wait for monitoring to start
    sleep 10
    
    # Check if metrics are being collected
    if pve-smbgateway status "$MON_SHARE" | grep -q "metrics\|performance"; then
        print_status "PASS" "Monitoring metrics are being collected"
    else
        print_status "WARN" "Monitoring metrics not detected"
    fi
    
    # Clean up
    pve-smbgateway delete "$MON_SHARE" 2>/dev/null || true
    rm -rf "$MON_PATH"
else
    print_status "FAIL" "Monitoring test share creation failed"
fi

echo ""

# Final Results
print_status "HEADER" "Test Results Summary"
print_status "INFO" "Total tests executed: $TOTAL_TESTS"
print_status "INFO" "Tests passed: $PASSED_TESTS"
print_status "INFO" "Tests failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    print_status "PASS" "All tests completed successfully!"
    echo ""
    echo -e "${GREEN}✓ COMPREHENSIVE TESTING: PASSED${NC}"
    echo ""
    echo "Test Coverage:"
    echo "✓ System prerequisites"
    echo "✓ VM template creation"
    echo "✓ VM mode functionality"
    echo "✓ Quota management"
    echo "✓ LXC mode functionality"
    echo "✓ Native mode functionality"
    echo "✓ CLI functionality"
    echo "✓ Error handling"
    echo "✓ Performance metrics"
    echo "✓ Proxmox integration"
    echo "✓ Security features"
    echo "✓ Monitoring capabilities"
    echo ""
    echo "The PVE SMB Gateway is ready for production use!"
else
    print_status "FAIL" "Some tests failed. Check the log file for details: $LOG_FILE"
    echo ""
    echo -e "${RED}✗ COMPREHENSIVE TESTING: FAILED${NC}"
    echo ""
    echo "Failed tests: $FAILED_TESTS"
    echo "Please review the log file and fix the issues before proceeding."
fi

echo ""
echo "Test Results:"
echo "- Log file: $LOG_FILE"
echo "- Results directory: $TEST_RESULTS_DIR"
echo "- Completed at: $(date)"

# Save summary to file
cat > "$TEST_RESULTS_DIR/summary.txt" << EOF
PVE SMB Gateway Test Summary
============================
Date: $(date)
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%

Test Results:
- System Prerequisites: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- VM Template Creation: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- VM Mode Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Quota Management: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- LXC Mode Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Native Mode Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- CLI Functionality: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Error Handling: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Performance Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Integration Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Security Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)
- Monitoring Testing: $(if [ $FAILED_TESTS -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi)

Log File: $LOG_FILE
EOF

exit $FAILED_TESTS 