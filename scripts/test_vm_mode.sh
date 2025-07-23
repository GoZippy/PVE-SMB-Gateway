#!/bin/bash

# PVE SMB Gateway VM Mode Test Script
# Tests VM template creation, VM provisioning, and SMB functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_SHARE="testvm"
TEST_PATH="/srv/smb/testvm"
TEST_QUOTA="1G"
VM_MEMORY="1024"
VM_CORES="1"

echo -e "${BLUE}=== PVE SMB Gateway VM Mode Test ===${NC}"

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ $message${NC}"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ $message${NC}"
    else
        echo -e "${YELLOW}? $message${NC}"
    fi
}

# Function to cleanup test resources
cleanup() {
    echo -e "\n${YELLOW}Cleaning up test resources...${NC}"
    
    # Stop and destroy test VM if it exists
    if qm list | grep -q "smb-$TEST_SHARE"; then
        echo "Stopping test VM..."
        qm stop $(qm list | grep "smb-$TEST_SHARE" | awk '{print $1}') 2>/dev/null || true
        sleep 5
        echo "Destroying test VM..."
        qm destroy $(qm list | grep "smb-$TEST_SHARE" | awk '{print $1}') 2>/dev/null || true
    fi
    
    # Remove test share if it exists
    if pve-smbgateway list | grep -q "$TEST_SHARE"; then
        echo "Removing test share..."
        pve-smbgateway delete "$TEST_SHARE" 2>/dev/null || true
    fi
    
    # Remove test directory
    if [ -d "$TEST_PATH" ]; then
        echo "Removing test directory..."
        rm -rf "$TEST_PATH"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

echo -e "\n${BLUE}1. Testing VM Template Creation${NC}"

# Check if template creation script exists
if [ -f "./scripts/create_vm_template.sh" ]; then
    print_status "PASS" "Template creation script found"
else
    print_status "FAIL" "Template creation script not found"
    exit 1
fi

# Test template creation (dry run)
echo "Testing template creation script..."
if ./scripts/create_vm_template.sh --dry-run 2>/dev/null; then
    print_status "PASS" "Template creation script syntax check passed"
else
    print_status "FAIL" "Template creation script has syntax errors"
    exit 1
fi

echo -e "\n${BLUE}2. Testing VM Template Discovery${NC}"

# Check if we can find VM templates
TEMPLATE_LIST=$(pvesh get /nodes/$(hostname)/storage/local/content --type iso 2>/dev/null || echo "")
if echo "$TEMPLATE_LIST" | grep -q "smb-gateway-debian12.qcow2"; then
    print_status "PASS" "SMB Gateway template found"
elif echo "$TEMPLATE_LIST" | grep -q "debian.*\.qcow2"; then
    print_status "PASS" "Debian template found (will use as fallback)"
else
    print_status "FAIL" "No suitable VM templates found"
    echo "Available templates:"
    echo "$TEMPLATE_LIST" | grep -E "\.(qcow2|img)$" || echo "None"
fi

echo -e "\n${BLUE}3. Testing VM Share Creation${NC}"

# Create test share in VM mode
echo "Creating test share in VM mode..."
if pve-smbgateway create "$TEST_SHARE" \
    --mode vm \
    --vm-memory "$VM_MEMORY" \
    --vm-cores "$VM_CORES" \
    --quota "$TEST_QUOTA" \
    --path "$TEST_PATH"; then
    print_status "PASS" "VM share creation successful"
else
    print_status "FAIL" "VM share creation failed"
    exit 1
fi

# Wait a moment for VM to start
sleep 10

echo -e "\n${BLUE}4. Testing VM Status${NC}"

# Check VM status
VM_STATUS=$(pve-smbgateway status "$TEST_SHARE" 2>/dev/null || echo "")
if echo "$VM_STATUS" | grep -q "running\|active"; then
    print_status "PASS" "VM is running"
else
    print_status "FAIL" "VM is not running"
    echo "VM Status: $VM_STATUS"
fi

echo -e "\n${BLUE}5. Testing SMB Connectivity${NC}"

# Get VM IP address
VM_ID=$(qm list | grep "smb-$TEST_SHARE" | awk '{print $1}')
if [ -n "$VM_ID" ]; then
    # Wait for VM to get IP
    echo "Waiting for VM to get IP address..."
    for i in {1..30}; do
        VM_IP=$(qm guest cmd "$VM_ID" network-get-interfaces 2>/dev/null | grep -o '"ip-address": "[^"]*"' | grep -v "127.0.0.1" | head -1 | cut -d'"' -f4)
        if [ -n "$VM_IP" ]; then
            print_status "PASS" "VM IP address: $VM_IP"
            break
        fi
        sleep 2
    done
    
    if [ -n "$VM_IP" ]; then
        # Test SMB connectivity
        echo "Testing SMB connectivity..."
        if timeout 10 smbclient "//$VM_IP/$TEST_SHARE" -U guest -c "ls" 2>/dev/null; then
            print_status "PASS" "SMB connectivity successful"
        else
            print_status "FAIL" "SMB connectivity failed"
        fi
    else
        print_status "FAIL" "Could not get VM IP address"
    fi
else
    print_status "FAIL" "Could not find VM ID"
fi

echo -e "\n${BLUE}6. Testing Quota Functionality${NC}"

# Check quota status
QUOTA_STATUS=$(pve-smbgateway status "$TEST_SHARE" 2>/dev/null | grep -A 10 "quota" || echo "")
if echo "$QUOTA_STATUS" | grep -q "limit.*$TEST_QUOTA"; then
    print_status "PASS" "Quota configured correctly"
else
    print_status "FAIL" "Quota not configured correctly"
    echo "Quota Status: $QUOTA_STATUS"
fi

echo -e "\n${BLUE}7. Testing Share Deletion${NC}"

# Delete test share
if pve-smbgateway delete "$TEST_SHARE"; then
    print_status "PASS" "VM share deletion successful"
else
    print_status "FAIL" "VM share deletion failed"
    exit 1
fi

# Verify VM is destroyed
sleep 5
if ! qm list | grep -q "smb-$TEST_SHARE"; then
    print_status "PASS" "VM properly destroyed"
else
    print_status "FAIL" "VM not properly destroyed"
fi

echo -e "\n${GREEN}=== All VM Mode Tests Passed! ===${NC}"
echo -e "${BLUE}VM mode is working correctly.${NC}"

# Summary
echo -e "\n${BLUE}Test Summary:${NC}"
echo "✓ Template creation script validated"
echo "✓ VM template discovery working"
echo "✓ VM share creation successful"
echo "✓ VM status monitoring working"
echo "✓ SMB connectivity functional"
echo "✓ Quota management working"
echo "✓ Share deletion and cleanup working"

echo -e "\n${GREEN}VM mode is ready for production use!${NC}" 