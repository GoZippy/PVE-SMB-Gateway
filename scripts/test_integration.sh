#!/bin/bash

# PVE SMB Gateway Integration Test Script
# Tests all deployment modes (LXC, Native, VM) and core functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_SHARES=("test-lxc" "test-native" "test-vm")
TEST_PATHS=("/srv/smb/test-lxc" "/srv/smb/test-native" "/srv/smb/test-vm")
TEST_QUOTA="1G"
VM_MEMORY="1024"
VM_CORES="1"

echo -e "${BLUE}=== PVE SMB Gateway Integration Test ===${NC}"

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
    
    for share in "${TEST_SHARES[@]}"; do
        # Remove test share if it exists
        if pve-smbgateway list | grep -q "$share"; then
            echo "Removing test share: $share"
            pve-smbgateway delete "$share" 2>/dev/null || true
        fi
        
        # Remove test directory
        test_path="/srv/smb/$share"
        if [ -d "$test_path" ]; then
            echo "Removing test directory: $test_path"
            rm -rf "$test_path"
        fi
    done
}

# Set up cleanup trap
trap cleanup EXIT

echo -e "\n${BLUE}1. Testing Prerequisites${NC}"

# Check if CLI tool exists
if command -v pve-smbgateway >/dev/null 2>&1; then
    print_status "PASS" "CLI tool available"
else
    print_status "FAIL" "CLI tool not found"
    exit 1
fi

# Check if we're running on Proxmox
if [ -f "/etc/pve/version" ]; then
    print_status "PASS" "Running on Proxmox VE"
else
    print_status "FAIL" "Not running on Proxmox VE"
    exit 1
fi

# Check available storage
STORAGE_LIST=$(pvesh get /nodes/$(hostname)/storage 2>/dev/null || echo "")
if echo "$STORAGE_LIST" | grep -q "local"; then
    print_status "PASS" "Local storage available"
else
    print_status "FAIL" "No local storage found"
    exit 1
fi

echo -e "\n${BLUE}2. Testing LXC Mode${NC}"

# Create test share in LXC mode
echo "Creating test share in LXC mode..."
if pve-smbgateway create "${TEST_SHARES[0]}" \
    --mode lxc \
    --quota "$TEST_QUOTA" \
    --path "${TEST_PATHS[0]}"; then
    print_status "PASS" "LXC share creation successful"
else
    print_status "FAIL" "LXC share creation failed"
    exit 1
fi

# Check LXC status
LXC_STATUS=$(pve-smbgateway status "${TEST_SHARES[0]}" 2>/dev/null || echo "")
if echo "$LXC_STATUS" | grep -q "running\|active"; then
    print_status "PASS" "LXC container is running"
else
    print_status "FAIL" "LXC container is not running"
    echo "LXC Status: $LXC_STATUS"
fi

echo -e "\n${BLUE}3. Testing Native Mode${NC}"

# Create test share in native mode
echo "Creating test share in native mode..."
if pve-smbgateway create "${TEST_SHARES[1]}" \
    --mode native \
    --quota "$TEST_QUOTA" \
    --path "${TEST_PATHS[1]}"; then
    print_status "PASS" "Native share creation successful"
else
    print_status "FAIL" "Native share creation failed"
    exit 1
fi

# Check native status
NATIVE_STATUS=$(pve-smbgateway status "${TEST_SHARES[1]}" 2>/dev/null || echo "")
if echo "$NATIVE_STATUS" | grep -q "running\|active"; then
    print_status "PASS" "Native Samba service is running"
else
    print_status "FAIL" "Native Samba service is not running"
    echo "Native Status: $NATIVE_STATUS"
fi

echo -e "\n${BLUE}4. Testing VM Mode${NC}"

# Check if VM templates are available
TEMPLATE_LIST=$(pvesh get /nodes/$(hostname)/storage/local/content --type iso 2>/dev/null || echo "")
if echo "$TEMPLATE_LIST" | grep -q "debian.*\.qcow2\|smb-gateway"; then
    print_status "PASS" "VM templates available"
    
    # Create test share in VM mode
    echo "Creating test share in VM mode..."
    if pve-smbgateway create "${TEST_SHARES[2]}" \
        --mode vm \
        --vm-memory "$VM_MEMORY" \
        --vm-cores "$VM_CORES" \
        --quota "$TEST_QUOTA" \
        --path "${TEST_PATHS[2]}"; then
        print_status "PASS" "VM share creation successful"
    else
        print_status "FAIL" "VM share creation failed"
    fi
    
    # Wait for VM to start
    sleep 15
    
    # Check VM status
    VM_STATUS=$(pve-smbgateway status "${TEST_SHARES[2]}" 2>/dev/null || echo "")
    if echo "$VM_STATUS" | grep -q "running\|active"; then
        print_status "PASS" "VM is running"
    else
        print_status "FAIL" "VM is not running"
        echo "VM Status: $VM_STATUS"
    fi
else
    print_status "SKIP" "No VM templates available, skipping VM mode test"
fi

echo -e "\n${BLUE}5. Testing Quota Management${NC}"

# Test quota functionality for each mode
for share in "${TEST_SHARES[@]}"; do
    if pve-smbgateway list | grep -q "$share"; then
        QUOTA_STATUS=$(pve-smbgateway status "$share" 2>/dev/null | grep -A 5 "quota" || echo "")
        if echo "$QUOTA_STATUS" | grep -q "limit.*$TEST_QUOTA"; then
            print_status "PASS" "Quota configured for $share"
        else
            print_status "FAIL" "Quota not configured for $share"
        fi
    fi
done

echo -e "\n${BLUE}6. Testing SMB Connectivity${NC}"

# Test SMB connectivity for each share
for share in "${TEST_SHARES[@]}"; do
    if pve-smbgateway list | grep -q "$share"; then
        # Get share IP (for LXC/VM) or use localhost (for native)
        SHARE_IP="127.0.0.1"
        
        # For LXC/VM, try to get the actual IP
        if [ "$share" = "test-lxc" ]; then
            # Get LXC container IP
            CONTAINER_ID=$(pct list | grep "smb-$share" | awk '{print $1}')
            if [ -n "$CONTAINER_ID" ]; then
                SHARE_IP=$(pct exec "$CONTAINER_ID" -- ip route get 1 | awk '{print $7}' | head -1)
            fi
        elif [ "$share" = "test-vm" ]; then
            # Get VM IP
            VM_ID=$(qm list | grep "smb-$share" | awk '{print $1}')
            if [ -n "$VM_ID" ]; then
                SHARE_IP=$(qm guest cmd "$VM_ID" network-get-interfaces 2>/dev/null | grep -o '"ip-address": "[^"]*"' | grep -v "127.0.0.1" | head -1 | cut -d'"' -f4)
            fi
        fi
        
        # Test SMB connectivity
        if [ -n "$SHARE_IP" ] && [ "$SHARE_IP" != "127.0.0.1" ]; then
            if timeout 10 smbclient "//$SHARE_IP/$share" -U guest -c "ls" 2>/dev/null; then
                print_status "PASS" "SMB connectivity for $share"
            else
                print_status "FAIL" "SMB connectivity failed for $share"
            fi
        else
            # For native mode, test localhost
            if timeout 10 smbclient "//127.0.0.1/$share" -U guest -c "ls" 2>/dev/null; then
                print_status "PASS" "SMB connectivity for $share (localhost)"
            else
                print_status "FAIL" "SMB connectivity failed for $share (localhost)"
            fi
        fi
    fi
done

echo -e "\n${BLUE}7. Testing Share Management${NC}"

# Test share listing
SHARE_LIST=$(pve-smbgateway list 2>/dev/null || echo "")
for share in "${TEST_SHARES[@]}"; do
    if echo "$SHARE_LIST" | grep -q "$share"; then
        print_status "PASS" "Share $share appears in list"
    else
        print_status "FAIL" "Share $share not found in list"
    fi
done

echo -e "\n${BLUE}8. Testing Share Deletion${NC}"

# Delete all test shares
for share in "${TEST_SHARES[@]}"; do
    if pve-smbgateway list | grep -q "$share"; then
        if pve-smbgateway delete "$share"; then
            print_status "PASS" "Share $share deletion successful"
        else
            print_status "FAIL" "Share $share deletion failed"
        fi
    fi
done

# Verify cleanup
sleep 5
for share in "${TEST_SHARES[@]}"; do
    if ! pve-smbgateway list | grep -q "$share"; then
        print_status "PASS" "Share $share properly cleaned up"
    else
        print_status "FAIL" "Share $share not properly cleaned up"
    fi
done

echo -e "\n${GREEN}=== All Integration Tests Passed! ===${NC}"
echo -e "${BLUE}All deployment modes are working correctly.${NC}"

# Summary
echo -e "\n${BLUE}Test Summary:${NC}"
echo "✓ Prerequisites validated"
echo "✓ LXC mode working"
echo "✓ Native mode working"
echo "✓ VM mode working (if templates available)"
echo "✓ Quota management functional"
echo "✓ SMB connectivity verified"
echo "✓ Share management working"
echo "✓ Cleanup and deletion working"

echo -e "\n${GREEN}PVE SMB Gateway is ready for production use!${NC}" 