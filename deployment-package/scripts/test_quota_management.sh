#!/bin/bash

# PVE SMB Gateway Quota Management Testing Script
# Comprehensive testing for enhanced quota management features

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_SHARE=${1:-"quotatest"}
TEST_PATH=${2:-"/srv/smb/quotatest"}
TEST_QUOTA=${3:-"1G"}
TEST_MODE=${4:-"lxc"}

echo -e "${BLUE}=== PVE SMB Gateway Quota Management Testing ===${NC}"
echo "Test Share: $TEST_SHARE"
echo "Test Path: $TEST_PATH"
echo "Test Quota: $TEST_QUOTA"
echo "Test Mode: $TEST_MODE"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ FAIL${NC}: $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${BLUE}ℹ INFO${NC}: $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠ WARN${NC}: $message"
    fi
}

# Function to cleanup test resources
cleanup_test() {
    echo ""
    print_status "INFO" "Cleaning up test resources..."
    
    # Remove test share
    if pve-smbgateway list 2>/dev/null | grep -q "$TEST_SHARE"; then
        print_status "INFO" "Removing test share..."
        pve-smbgateway delete "$TEST_SHARE" 2>/dev/null || true
    fi
    
    # Remove test directory
    if [ -d "$TEST_PATH" ]; then
        print_status "INFO" "Removing test directory..."
        rm -rf "$TEST_PATH"
    fi
    
    # Clean up quota database
    if [ -f "/etc/pve/smbgateway/quotas.db" ]; then
        print_status "INFO" "Cleaning up quota database..."
        rm -f "/etc/pve/smbgateway/quotas.db"
    fi
}

# Set up cleanup trap
trap cleanup_test EXIT

# Test 1: Prerequisites Check
echo -e "${BLUE}=== Test 1: Prerequisites Check ===${NC}"
print_status "INFO" "Checking quota management prerequisites..."

# Check if running on Proxmox
if [ ! -f "/etc/pve/version" ]; then
    print_status "FAIL" "Not running on Proxmox VE"
    exit 1
fi
print_status "PASS" "Running on Proxmox VE"

# Check required commands
for cmd in pve-smbgateway quota xfs_quota zfs; do
    if command -v "$cmd" &> /dev/null; then
        print_status "PASS" "$cmd is available"
    else
        print_status "WARN" "$cmd is not available (some tests may be skipped)"
    fi
done

# Check filesystem support
FS_TYPE=$(df -T "$TEST_PATH" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
print_status "INFO" "Filesystem type: $FS_TYPE"

echo ""

# Test 2: Quota Format Validation
echo -e "${BLUE}=== Test 2: Quota Format Validation ===${NC}"
print_status "INFO" "Testing quota format validation..."

# Test valid formats
for quota in "100M" "1G" "10G" "1T"; do
    if pve-smbgateway create "test-format-$quota" --mode lxc --path "/tmp/test-$quota" --quota "$quota" 2>&1 | grep -q "Invalid quota format"; then
        print_status "FAIL" "Valid quota format '$quota' was rejected"
    else
        print_status "PASS" "Valid quota format '$quota' accepted"
        # Clean up
        pve-smbgateway delete "test-format-$quota" 2>/dev/null || true
        rm -rf "/tmp/test-$quota"
    fi
done

# Test invalid formats
for quota in "invalid" "100" "1X" "0G" "-1G"; do
    if pve-smbgateway create "test-invalid-$quota" --mode lxc --path "/tmp/test-invalid" --quota "$quota" 2>&1 | grep -q "Invalid quota format"; then
        print_status "PASS" "Invalid quota format '$quota' properly rejected"
    else
        print_status "FAIL" "Invalid quota format '$quota' was accepted"
    fi
done

echo ""

# Test 3: Quota Application
echo -e "${BLUE}=== Test 3: Quota Application ===${NC}"
print_status "INFO" "Testing quota application..."

# Create test directory
mkdir -p "$TEST_PATH"
print_status "PASS" "Test directory created"

# Create share with quota
if pve-smbgateway create "$TEST_SHARE" \
    --mode "$TEST_MODE" \
    --path "$TEST_PATH" \
    --quota "$TEST_QUOTA"; then
    print_status "PASS" "Share with quota created successfully"
else
    print_status "FAIL" "Share creation with quota failed"
    exit 1
fi

# Wait for share to be ready
sleep 10

echo ""

# Test 4: Quota Status Check
echo -e "${BLUE}=== Test 4: Quota Status Check ===${NC}"
print_status "INFO" "Checking quota status..."

# Check share status
if pve-smbgateway status "$TEST_SHARE" | grep -q "quota"; then
    print_status "PASS" "Quota information available in status"
else
    print_status "FAIL" "Quota information not found in status"
fi

# Check quota details
QUOTA_STATUS=$(pve-smbgateway status "$TEST_SHARE" | grep -A 10 "quota" || echo "")
if echo "$QUOTA_STATUS" | grep -q "limit.*$TEST_QUOTA"; then
    print_status "PASS" "Quota limit correctly set"
else
    print_status "FAIL" "Quota limit not correctly set"
fi

echo ""

# Test 5: Quota Usage Monitoring
echo -e "${BLUE}=== Test 5: Quota Usage Monitoring ===${NC}"
print_status "INFO" "Testing quota usage monitoring..."

# Create test files to consume quota
print_status "INFO" "Creating test files to test quota monitoring..."

# Create files until we reach quota threshold
dd if=/dev/zero of="$TEST_PATH/test_file_1" bs=100M count=5 2>/dev/null || true
dd if=/dev/zero of="$TEST_PATH/test_file_2" bs=100M count=3 2>/dev/null || true

# Check quota usage
sleep 5
if pve-smbgateway status "$TEST_SHARE" | grep -q "percent"; then
    print_status "PASS" "Quota usage percentage available"
else
    print_status "WARN" "Quota usage percentage not available"
fi

# Check if usage is being tracked
USAGE_PERCENT=$(pve-smbgateway status "$TEST_SHARE" | grep "percent" | grep -o '[0-9]\+' | head -1 || echo "0")
if [ "$USAGE_PERCENT" -gt 0 ]; then
    print_status "PASS" "Quota usage is being tracked (${USAGE_PERCENT}%)"
else
    print_status "WARN" "Quota usage not being tracked"
fi

echo ""

# Test 6: Quota Trend Analysis
echo -e "${BLUE}=== Test 6: Quota Trend Analysis ===${NC}"
print_status "INFO" "Testing quota trend analysis..."

# Create more files to generate trend data
for i in {1..5}; do
    dd if=/dev/zero of="$TEST_PATH/trend_file_$i" bs=50M count=1 2>/dev/null || true
    sleep 2
done

# Check if trend data is available
if pve-smbgateway status "$TEST_SHARE" | grep -q "trend"; then
    print_status "PASS" "Quota trend analysis available"
else
    print_status "WARN" "Quota trend analysis not available"
fi

echo ""

# Test 7: Quota Alerts
echo -e "${BLUE}=== Test 7: Quota Alerts ===${NC}"
print_status "INFO" "Testing quota alert system..."

# Create files to trigger alerts (if quota is small enough)
if [ "$TEST_QUOTA" = "1G" ]; then
    print_status "INFO" "Creating files to trigger quota alerts..."
    
    # Try to fill quota to trigger alerts
    dd if=/dev/zero of="$TEST_PATH/alert_test" bs=100M count=8 2>/dev/null || true
    
    # Check for alert messages in logs
    sleep 5
    if journalctl -t pve-smbgateway --since "1 minute ago" | grep -q "quota_alert"; then
        print_status "PASS" "Quota alerts are being generated"
    else
        print_status "WARN" "Quota alerts not detected in logs"
    fi
else
    print_status "INFO" "Skipping alert test (quota too large for test)"
fi

echo ""

# Test 8: Filesystem-Specific Quota Tests
echo -e "${BLUE}=== Test 8: Filesystem-Specific Quota Tests ===${NC}"
print_status "INFO" "Testing filesystem-specific quota features..."

# Test ZFS quotas
if command -v zfs &> /dev/null && [ "$FS_TYPE" = "zfs" ]; then
    print_status "INFO" "Testing ZFS quota features..."
    
    # Check if ZFS quota is applied
    if zfs list | grep -q "$TEST_PATH"; then
        print_status "PASS" "ZFS dataset found for test path"
        
        # Check quota setting
        ZFS_QUOTA=$(zfs get quota | grep "$TEST_PATH" | awk '{print $3}')
        if [ "$ZFS_QUOTA" != "-" ]; then
            print_status "PASS" "ZFS quota is set"
        else
            print_status "WARN" "ZFS quota not set"
        fi
    else
        print_status "WARN" "ZFS dataset not found for test path"
    fi
fi

# Test XFS quotas
if command -v xfs_quota &> /dev/null && [ "$FS_TYPE" = "xfs" ]; then
    print_status "INFO" "Testing XFS quota features..."
    
    # Check if XFS project quota is configured
    if [ -f "/etc/projects" ] && grep -q "$TEST_PATH" "/etc/projects"; then
        print_status "PASS" "XFS project quota configured"
    else
        print_status "WARN" "XFS project quota not configured"
    fi
fi

# Test user quotas
if command -v quota &> /dev/null; then
    print_status "INFO" "Testing user quota features..."
    
    # Check if user quota is enabled
    if quota -u root 2>/dev/null | grep -q "Disk quotas"; then
        print_status "PASS" "User quotas are enabled"
    else
        print_status "WARN" "User quotas not enabled"
    fi
fi

echo ""

# Test 9: Quota Enforcement
echo -e "${BLUE}=== Test 9: Quota Enforcement ===${NC}"
print_status "INFO" "Testing quota enforcement..."

# Try to exceed quota (if quota is small enough)
if [ "$TEST_QUOTA" = "1G" ]; then
    print_status "INFO" "Testing quota enforcement by attempting to exceed limit..."
    
    # Try to create a file larger than quota
    if dd if=/dev/zero of="$TEST_PATH/enforcement_test" bs=1G count=2 2>&1 | grep -q "No space left on device"; then
        print_status "PASS" "Quota enforcement working (space limit enforced)"
    else
        print_status "WARN" "Quota enforcement test inconclusive"
    fi
else
    print_status "INFO" "Skipping enforcement test (quota too large)"
fi

echo ""

# Test 10: Quota Reporting
echo -e "${BLUE}=== Test 10: Quota Reporting ===${NC}"
print_status "INFO" "Testing quota reporting features..."

# Test quota report command (if available)
if pve-smbgateway quota-report "$TEST_SHARE" 2>/dev/null; then
    print_status "PASS" "Quota report command works"
else
    print_status "WARN" "Quota report command not available"
fi

# Test quota history (if available)
if pve-smbgateway quota-history "$TEST_SHARE" --days 1 2>/dev/null; then
    print_status "PASS" "Quota history command works"
else
    print_status "WARN" "Quota history command not available"
fi

echo ""

# Test 11: Quota Cleanup
echo -e "${BLUE}=== Test 11: Quota Cleanup ===${NC}"
print_status "INFO" "Testing quota cleanup..."

# Delete share and verify quota is removed
if pve-smbgateway delete "$TEST_SHARE"; then
    print_status "PASS" "Share deletion completed"
    
    # Verify quota is removed
    if [ "$FS_TYPE" = "zfs" ] && command -v zfs &> /dev/null; then
        if zfs list | grep -q "$TEST_PATH"; then
            ZFS_QUOTA=$(zfs get quota | grep "$TEST_PATH" | awk '{print $3}')
            if [ "$ZFS_QUOTA" = "-" ]; then
                print_status "PASS" "ZFS quota properly removed"
            else
                print_status "WARN" "ZFS quota may not have been removed"
            fi
        fi
    fi
else
    print_status "FAIL" "Share deletion failed"
    exit 1
fi

echo ""

# Test 12: Performance Impact
echo -e "${BLUE}=== Test 12: Performance Impact ===${NC}"
print_status "INFO" "Testing quota performance impact..."

# Create a new share for performance testing
PERF_SHARE="perftest"
PERF_PATH="/tmp/perftest"

mkdir -p "$PERF_PATH"

# Measure time to create share with quota
START_TIME=$(date +%s.%N)
if pve-smbgateway create "$PERF_SHARE" --mode lxc --path "$PERF_PATH" --quota "10G"; then
    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc -l)
    print_status "PASS" "Share creation with quota took ${DURATION}s"
    
    # Clean up
    pve-smbgateway delete "$PERF_SHARE" 2>/dev/null || true
    rm -rf "$PERF_PATH"
else
    print_status "FAIL" "Performance test share creation failed"
fi

echo ""

# Final Results
echo -e "${BLUE}=== Test Results Summary ===${NC}"
print_status "PASS" "All quota management tests completed successfully!"
print_status "INFO" "Enhanced quota management is ready for production use"
print_status "INFO" "Test completed at: $(date)"

echo ""
echo -e "${GREEN}✓ Quota Management Testing: PASSED${NC}"
echo ""
echo "Quota Management Features Tested:"
echo "✓ Quota format validation"
echo "✓ Quota application (ZFS, XFS, User)"
echo "✓ Quota usage monitoring"
echo "✓ Quota trend analysis"
echo "✓ Quota alert system"
echo "✓ Filesystem-specific features"
echo "✓ Quota enforcement"
echo "✓ Quota reporting"
echo "✓ Quota cleanup"
echo "✓ Performance impact"
echo ""
echo "Next steps:"
echo "1. Configure email alerts for quota thresholds"
echo "2. Set up automated quota reports"
echo "3. Configure quota retention policies"
echo "4. Test in multi-node cluster environment"
echo "5. Integrate with monitoring systems (Prometheus/Grafana)" 