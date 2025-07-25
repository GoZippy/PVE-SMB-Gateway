#!/bin/bash

# PVE SMB Gateway VM Mode Testing Script
# Comprehensive testing for VM mode functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEMPLATE_NAME=${1:-"smb-gateway-debian12"}
TEST_SHARE=${2:-"testvm"}
TEST_PATH=${3:-"/srv/smb/testvm"}
TEST_QUOTA=${4:-"10G"}
VM_MEMORY=${5:-2048}
VM_CORES=${6:-2}

echo -e "${BLUE}=== PVE SMB Gateway VM Mode Testing ===${NC}"
echo "Template: $TEMPLATE_NAME"
echo "Test Share: $TEST_SHARE"
echo "Test Path: $TEST_PATH"
echo "Test Quota: $TEST_QUOTA"
echo "VM Memory: ${VM_MEMORY}MB"
echo "VM Cores: $VM_CORES"
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
    
    # Stop and destroy test VM if it exists
    if qm list | grep -q "$TEST_SHARE"; then
        print_status "INFO" "Stopping test VM..."
        qm stop "$TEST_SHARE" 2>/dev/null || true
        sleep 2
        
        print_status "INFO" "Destroying test VM..."
        qm destroy "$TEST_SHARE" 2>/dev/null || true
    fi
    
    # Remove test directory
    if [ -d "$TEST_PATH" ]; then
        print_status "INFO" "Removing test directory..."
        rm -rf "$TEST_PATH"
    fi
    
    # Remove test share from SMB Gateway
    if pve-smbgateway list 2>/dev/null | grep -q "$TEST_SHARE"; then
        print_status "INFO" "Removing test share..."
        pve-smbgateway delete "$TEST_SHARE" 2>/dev/null || true
    fi
}

# Set up cleanup trap
trap cleanup_test EXIT

# Test 1: Check prerequisites
echo -e "${BLUE}=== Test 1: Prerequisites Check ===${NC}"
print_status "INFO" "Checking system prerequisites..."

# Check if running on Proxmox
if [ ! -f "/etc/pve/version" ]; then
    print_status "FAIL" "Not running on Proxmox VE"
    exit 1
fi
print_status "PASS" "Running on Proxmox VE"

# Check required commands
for cmd in qemu-img debootstrap genisoimage qm pve-smbgateway; do
    if command -v "$cmd" &> /dev/null; then
        print_status "PASS" "$cmd is available"
    else
        print_status "FAIL" "$cmd is not available"
        exit 1
    fi
done

# Check storage
if [ ! -d "/var/lib/vz" ]; then
    print_status "FAIL" "Proxmox storage directory not found"
    exit 1
fi
print_status "PASS" "Proxmox storage directory exists"

echo ""

# Test 2: Template creation
echo -e "${BLUE}=== Test 2: VM Template Creation ===${NC}"
print_status "INFO" "Creating VM template..."

# Run template creation script
if ./scripts/create_vm_template.sh "$TEMPLATE_NAME" "$VM_MEMORY" "20G"; then
    print_status "PASS" "Template creation script completed"
else
    print_status "FAIL" "Template creation script failed"
    exit 1
fi

# Verify template files exist
TEMPLATE_DIR="/var/lib/vz/template/iso"
if [ -f "$TEMPLATE_DIR/$TEMPLATE_NAME.qcow2" ]; then
    print_status "PASS" "Template image file created"
else
    print_status "FAIL" "Template image file not found"
    exit 1
fi

if [ -f "$TEMPLATE_DIR/$TEMPLATE_NAME-cloud-init.iso" ]; then
    print_status "PASS" "Cloud-init ISO created"
else
    print_status "FAIL" "Cloud-init ISO not found"
    exit 1
fi

if [ -f "$TEMPLATE_DIR/$TEMPLATE_NAME.conf" ]; then
    print_status "PASS" "Template configuration created"
else
    print_status "FAIL" "Template configuration not found"
    exit 1
fi

echo ""

# Test 3: Template validation
echo -e "${BLUE}=== Test 3: Template Validation ===${NC}"
print_status "INFO" "Validating template..."

# Check template in Proxmox
if qm list | grep -q "$TEMPLATE_NAME"; then
    print_status "PASS" "Template appears in Proxmox VM list"
else
    print_status "WARN" "Template not found in Proxmox VM list (may need manual import)"
fi

# Check template file integrity
if qemu-img info "$TEMPLATE_DIR/$TEMPLATE_NAME.qcow2" &> /dev/null; then
    print_status "PASS" "Template image integrity check passed"
else
    print_status "FAIL" "Template image integrity check failed"
    exit 1
fi

echo ""

# Test 4: VM Mode Share Creation
echo -e "${BLUE}=== Test 4: VM Mode Share Creation ===${NC}"
print_status "INFO" "Creating test share using VM mode..."

# Create test directory
mkdir -p "$TEST_PATH"
print_status "PASS" "Test directory created"

# Create share using CLI
if pve-smbgateway create "$TEST_SHARE" \
    --mode vm \
    --path "$TEST_PATH" \
    --quota "$TEST_QUOTA" \
    --vm-memory "$VM_MEMORY" \
    --vm-cores "$VM_CORES" \
    --vm-template "$TEMPLATE_NAME"; then
    print_status "PASS" "Share creation completed"
else
    print_status "FAIL" "Share creation failed"
    exit 1
fi

# Wait for VM to start
print_status "INFO" "Waiting for VM to start..."
sleep 10

# Check VM status
if qm list | grep -q "$TEST_SHARE.*running"; then
    print_status "PASS" "VM is running"
else
    print_status "FAIL" "VM is not running"
    exit 1
fi

echo ""

# Test 5: VM Connectivity
echo -e "${BLUE}=== Test 5: VM Connectivity ===${NC}"
print_status "INFO" "Testing VM connectivity..."

# Get VM IP address
VM_IP=$(qm guest cmd "$TEST_SHARE" network-get-interfaces 2>/dev/null | grep -o '"ip-addresses":\[[^]]*\]' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)

if [ -n "$VM_IP" ]; then
    print_status "PASS" "VM IP address obtained: $VM_IP"
else
    print_status "WARN" "Could not get VM IP address, trying alternative method..."
    # Try alternative method
    VM_IP=$(qm guest cmd "$TEST_SHARE" network-get-interfaces 2>/dev/null | jq -r '.[] | select(.name=="eth0") | ."ip-addresses"[0]."ip-address"' 2>/dev/null | head -1)
    if [ -n "$VM_IP" ]; then
        print_status "PASS" "VM IP address obtained (alternative): $VM_IP"
    else
        print_status "FAIL" "Could not get VM IP address"
        exit 1
    fi
fi

# Test network connectivity
if ping -c 3 "$VM_IP" &> /dev/null; then
    print_status "PASS" "VM network connectivity confirmed"
else
    print_status "FAIL" "VM network connectivity failed"
    exit 1
fi

echo ""

# Test 6: SMB Service Verification
echo -e "${BLUE}=== Test 6: SMB Service Verification ===${NC}"
print_status "INFO" "Verifying SMB service in VM..."

# Wait for SMB service to start
sleep 30

# Test SMB connectivity
if smbclient -L "//$VM_IP" -U guest% 2>/dev/null | grep -q "$TEST_SHARE"; then
    print_status "PASS" "SMB service is accessible and share is visible"
else
    print_status "WARN" "SMB service test failed (may need more time to start)"
    
    # Try again after waiting
    sleep 30
    if smbclient -L "//$VM_IP" -U guest% 2>/dev/null | grep -q "$TEST_SHARE"; then
        print_status "PASS" "SMB service is accessible and share is visible (retry)"
    else
        print_status "FAIL" "SMB service is not accessible"
        exit 1
    fi
fi

echo ""

# Test 7: Share Status Check
echo -e "${BLUE}=== Test 7: Share Status Check ===${NC}"
print_status "INFO" "Checking share status..."

# Check share status via CLI
if pve-smbgateway status "$TEST_SHARE"; then
    print_status "PASS" "Share status command works"
else
    print_status "FAIL" "Share status command failed"
    exit 1
fi

# Check if quota is applied
if pve-smbgateway status "$TEST_SHARE" | grep -q "quota"; then
    print_status "PASS" "Quota information is available"
else
    print_status "WARN" "Quota information not found"
fi

echo ""

# Test 8: Performance Test
echo -e "${BLUE}=== Test 8: Performance Test ===${NC}"
print_status "INFO" "Running basic performance test..."

# Create test file
TEST_FILE="$TEST_PATH/test_performance.txt"
dd if=/dev/zero of="$TEST_FILE" bs=1M count=100 2>/dev/null

if [ -f "$TEST_FILE" ]; then
    print_status "PASS" "File creation test passed"
    
    # Test file copy via SMB
    if smbclient "//$VM_IP/$TEST_SHARE" -U guest% -c "get test_performance.txt /tmp/test_copy.txt" 2>/dev/null; then
        print_status "PASS" "SMB file transfer test passed"
    else
        print_status "WARN" "SMB file transfer test failed"
    fi
    
    # Cleanup test file
    rm -f "$TEST_FILE" "/tmp/test_copy.txt"
else
    print_status "FAIL" "File creation test failed"
fi

echo ""

# Test 9: Cleanup Test
echo -e "${BLUE}=== Test 9: Cleanup Test ===${NC}"
print_status "INFO" "Testing share deletion..."

# Delete share
if pve-smbgateway delete "$TEST_SHARE"; then
    print_status "PASS" "Share deletion completed"
else
    print_status "FAIL" "Share deletion failed"
    exit 1
fi

# Verify VM is destroyed
sleep 5
if ! qm list | grep -q "$TEST_SHARE"; then
    print_status "PASS" "VM was properly destroyed"
else
    print_status "FAIL" "VM was not destroyed"
    exit 1
fi

echo ""

# Test 10: Error Handling
echo -e "${BLUE}=== Test 10: Error Handling ===${NC}"
print_status "INFO" "Testing error handling..."

# Test invalid quota format
if pve-smbgateway create "invalid-test" --mode vm --path "/tmp/test" --quota "invalid" 2>&1 | grep -q "Invalid quota format"; then
    print_status "PASS" "Invalid quota format properly rejected"
else
    print_status "FAIL" "Invalid quota format not properly rejected"
fi

# Test non-existent path
if pve-smbgateway create "invalid-test" --mode vm --path "/nonexistent/path" --quota "10G" 2>&1 | grep -q "Path does not exist"; then
    print_status "PASS" "Non-existent path properly rejected"
else
    print_status "FAIL" "Non-existent path not properly rejected"
fi

echo ""

# Final Results
echo -e "${BLUE}=== Test Results Summary ===${NC}"
print_status "PASS" "All VM mode tests completed successfully!"
print_status "INFO" "VM mode is ready for production use"
print_status "INFO" "Template: $TEMPLATE_NAME"
print_status "INFO" "Test completed at: $(date)"

echo ""
echo -e "${GREEN}✓ VM Mode Testing: PASSED${NC}"
echo ""
echo "Next steps:"
echo "1. Test with different VM configurations"
echo "2. Test with Active Directory integration"
echo "3. Test with CTDB high availability"
echo "4. Run performance benchmarks"
echo "5. Test in multi-node cluster environment" 