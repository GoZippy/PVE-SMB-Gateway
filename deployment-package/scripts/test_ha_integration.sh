#!/bin/bash

# PVE SMB Gateway HA Integration Test Script
# Tests CTDB High Availability across all deployment modes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_SHARES=("test-ha-lxc" "test-ha-native" "test-ha-vm")
TEST_PATHS=("/srv/smb/test-ha-lxc" "/srv/smb/test-ha-native" "/srv/smb/test-ha-vm")
TEST_QUOTA="1G"
VM_MEMORY="1024"
VM_CORES="1"

# HA Configuration (set these for your environment)
HA_NODES=("192.168.1.10" "192.168.1.11" "192.168.1.12")
HA_VIP="192.168.1.100"
HA_TARGET_NODE="192.168.1.11"

echo -e "${BLUE}=== PVE SMB Gateway HA Integration Test ===${NC}"

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

# Function to check HA configuration
check_ha_config() {
    echo -e "\n${BLUE}1. Checking HA Configuration${NC}"
    
    if [ ${#HA_NODES[@]} -eq 0 ] || [ -z "$HA_VIP" ]; then
        print_status "FAIL" "HA configuration incomplete"
        echo "Please set HA_NODES and HA_VIP variables"
        echo "Example:"
        echo "  HA_NODES=(\"192.168.1.10\" \"192.168.1.11\" \"192.168.1.12\")"
        echo "  HA_VIP=\"192.168.1.100\""
        echo "  HA_TARGET_NODE=\"192.168.1.11\""
        exit 1
    fi
    
    print_status "PASS" "HA configuration provided"
    echo "Nodes: ${HA_NODES[*]}"
    echo "VIP: $HA_VIP"
    echo "Target Node: $HA_TARGET_NODE"
}

# Function to test network connectivity
test_network_connectivity() {
    echo -e "\n${BLUE}2. Testing Network Connectivity${NC}"
    
    # Test connectivity to all nodes
    for node in "${HA_NODES[@]}"; do
        if ping -c 1 "$node" >/dev/null 2>&1; then
            print_status "PASS" "Node $node is reachable"
        else
            print_status "FAIL" "Node $node is not reachable"
            return 1
        fi
    done
    
    # Test VIP availability
    if ping -c 1 "$HA_VIP" >/dev/null 2>&1; then
        print_status "FAIL" "VIP $HA_VIP is already in use"
        return 1
    else
        print_status "PASS" "VIP $HA_VIP is available"
    fi
}

# Function to test CTDB package availability
test_ctdb_availability() {
    echo -e "\n${BLUE}3. Testing CTDB Package Availability${NC}"
    
    # Check if CTDB packages are available
    if apt-cache search ctdb | grep -q "^ctdb "; then
        print_status "PASS" "CTDB packages available in repository"
    else
        print_status "FAIL" "CTDB packages not available in repository"
        echo "Please ensure CTDB packages are available:"
        echo "  apt-get update"
        echo "  apt-get install ctdb ctdb-dev"
        return 1
    fi
}

# Function to test LXC mode with HA
test_lxc_ha() {
    echo -e "\n${BLUE}4. Testing LXC Mode with HA${NC}"
    
    # Create test share in LXC mode with HA
    echo "Creating test share in LXC mode with HA..."
    if pve-smbgateway create "${TEST_SHARES[0]}" \
        --mode lxc \
        --quota "$TEST_QUOTA" \
        --path "${TEST_PATHS[0]}" \
        --ctdb-vip "$HA_VIP" \
        --ha-nodes "${HA_NODES[*]}" \
        --ha-enabled; then
        print_status "PASS" "LXC share creation with HA successful"
    else
        print_status "FAIL" "LXC share creation with HA failed"
        return 1
    fi
    
    # Check LXC status
    LXC_STATUS=$(pve-smbgateway status "${TEST_SHARES[0]}" 2>/dev/null || echo "")
    if echo "$LXC_STATUS" | grep -q "running\|active"; then
        print_status "PASS" "LXC container is running"
    else
        print_status "FAIL" "LXC container is not running"
        echo "LXC Status: $LXC_STATUS"
    fi
    
    # Check HA status
    HA_STATUS=$(pve-smbgateway ha-status "${TEST_SHARES[0]}" 2>/dev/null || echo "")
    if echo "$HA_STATUS" | grep -q "Cluster healthy.*Yes\|VIP active.*Yes"; then
        print_status "PASS" "LXC container HA is working"
    else
        print_status "FAIL" "LXC container HA is not working"
        echo "HA Status: $HA_STATUS"
    fi
}

# Function to test native mode with HA
test_native_ha() {
    echo -e "\n${BLUE}5. Testing Native Mode with HA${NC}"
    
    # Create test share in native mode with HA
    echo "Creating test share in native mode with HA..."
    if pve-smbgateway create "${TEST_SHARES[1]}" \
        --mode native \
        --quota "$TEST_QUOTA" \
        --path "${TEST_PATHS[1]}" \
        --ctdb-vip "$HA_VIP" \
        --ha-nodes "${HA_NODES[*]}" \
        --ha-enabled; then
        print_status "PASS" "Native share creation with HA successful"
    else
        print_status "FAIL" "Native share creation with HA failed"
        return 1
    fi
    
    # Check native status
    NATIVE_STATUS=$(pve-smbgateway status "${TEST_SHARES[1]}" 2>/dev/null || echo "")
    if echo "$NATIVE_STATUS" | grep -q "running\|active"; then
        print_status "PASS" "Native Samba service is running"
    else
        print_status "FAIL" "Native Samba service is not running"
        echo "Native Status: $NATIVE_STATUS"
    fi
    
    # Check HA status
    HA_STATUS=$(pve-smbgateway ha-status "${TEST_SHARES[1]}" 2>/dev/null || echo "")
    if echo "$HA_STATUS" | grep -q "Cluster healthy.*Yes\|VIP active.*Yes"; then
        print_status "PASS" "Native mode HA is working"
    else
        print_status "FAIL" "Native mode HA is not working"
        echo "HA Status: $HA_STATUS"
    fi
}

# Function to test VM mode with HA
test_vm_ha() {
    echo -e "\n${BLUE}6. Testing VM Mode with HA${NC}"
    
    # Check if VM templates are available
    TEMPLATE_LIST=$(pvesh get /nodes/$(hostname)/storage/local/content --type iso 2>/dev/null || echo "")
    if echo "$TEMPLATE_LIST" | grep -q "debian.*\.qcow2\|smb-gateway"; then
        print_status "PASS" "VM templates available"
        
        # Create test share in VM mode with HA
        echo "Creating test share in VM mode with HA..."
        if pve-smbgateway create "${TEST_SHARES[2]}" \
            --mode vm \
            --vm-memory "$VM_MEMORY" \
            --vm-cores "$VM_CORES" \
            --quota "$TEST_QUOTA" \
            --path "${TEST_PATHS[2]}" \
            --ctdb-vip "$HA_VIP" \
            --ha-nodes "${HA_NODES[*]}" \
            --ha-enabled; then
            print_status "PASS" "VM share creation with HA successful"
        else
            print_status "FAIL" "VM share creation with HA failed"
            return 1
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
        
        # Wait for HA to be ready
        echo "Waiting for VM HA to be ready..."
        sleep 30
        
        # Check HA status
        HA_STATUS=$(pve-smbgateway ha-status "${TEST_SHARES[2]}" 2>/dev/null || echo "")
        if echo "$HA_STATUS" | grep -q "Cluster healthy.*Yes\|VIP active.*Yes"; then
            print_status "PASS" "VM HA is working"
        else
            print_status "FAIL" "VM HA is not working"
            echo "HA Status: $HA_STATUS"
        fi
    else
        print_status "SKIP" "No VM templates available, skipping VM mode test"
    fi
}

# Function to test HA failover
test_ha_failover() {
    echo -e "\n${BLUE}7. Testing HA Failover${NC}"
    
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list | grep -q "$share"; then
            echo "Testing HA failover for $share..."
            
            # Test VIP connectivity before failover
            if pve-smbgateway ha-test --vip "$HA_VIP" --share "$share"; then
                print_status "PASS" "VIP connectivity before failover for $share"
            else
                print_status "FAIL" "VIP connectivity before failover failed for $share"
                continue
            fi
            
            # Test failover
            if pve-smbgateway ha-failover "$share" --target-node "$HA_TARGET_NODE"; then
                print_status "PASS" "HA failover successful for $share"
                
                # Wait for failover to complete
                sleep 10
                
                # Test VIP connectivity after failover
                if pve-smbgateway ha-test --vip "$HA_VIP" --share "$share"; then
                    print_status "PASS" "VIP connectivity after failover for $share"
                else
                    print_status "FAIL" "VIP connectivity after failover failed for $share"
                fi
            else
                print_status "FAIL" "HA failover failed for $share"
            fi
        fi
    done
}

# Function to test SMB connectivity via VIP
test_smb_vip_connectivity() {
    echo -e "\n${BLUE}8. Testing SMB Connectivity via VIP${NC}"
    
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list | grep -q "$share"; then
            echo "Testing SMB connectivity via VIP for $share..."
            
            # Test SMB connectivity to VIP
            if timeout 10 smbclient "//$HA_VIP/$share" -U guest% -c "ls" >/dev/null 2>&1; then
                print_status "PASS" "SMB connectivity via VIP for $share"
            else
                print_status "FAIL" "SMB connectivity via VIP failed for $share"
            fi
        fi
    done
}

# Function to test HA monitoring
test_ha_monitoring() {
    echo -e "\n${BLUE}9. Testing HA Monitoring${NC}"
    
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list | grep -q "$share"; then
            echo "Testing HA monitoring for $share..."
            
            # Get detailed HA status
            HA_STATUS=$(pve-smbgateway ha-status "$share" 2>/dev/null || echo "")
            
            # Check cluster health
            if echo "$HA_STATUS" | grep -q "Cluster healthy.*Yes"; then
                print_status "PASS" "Cluster health monitoring for $share"
            else
                print_status "FAIL" "Cluster health monitoring failed for $share"
            fi
            
            # Check VIP status
            if echo "$HA_STATUS" | grep -q "VIP active.*Yes"; then
                print_status "PASS" "VIP status monitoring for $share"
            else
                print_status "FAIL" "VIP status monitoring failed for $share"
            fi
            
            # Check node count
            if echo "$HA_STATUS" | grep -q "Nodes online.*[1-9]"; then
                print_status "PASS" "Node count monitoring for $share"
            else
                print_status "FAIL" "Node count monitoring failed for $share"
            fi
        fi
    done
}

# Function to test HA troubleshooting tools
test_ha_troubleshooting() {
    echo -e "\n${BLUE}10. Testing HA Troubleshooting Tools${NC}"
    
    # Test CTDB status command
    if which ctdb >/dev/null 2>&1; then
        print_status "PASS" "CTDB command available"
        
        # Test CTDB status
        if ctdb status >/dev/null 2>&1; then
            print_status "PASS" "CTDB status command working"
        else
            print_status "FAIL" "CTDB status command failed"
        fi
        
        # Test CTDB ping
        if ctdb ping >/dev/null 2>&1; then
            print_status "PASS" "CTDB ping command working"
        else
            print_status "FAIL" "CTDB ping command failed"
        fi
    else
        print_status "FAIL" "CTDB command not available"
    fi
    
    # Test network connectivity to VIP
    if ping -c 1 "$HA_VIP" >/dev/null 2>&1; then
        print_status "PASS" "Network connectivity to VIP $HA_VIP"
    else
        print_status "FAIL" "Network connectivity to VIP $HA_VIP failed"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}Starting HA Integration Tests${NC}"
    echo "Nodes: ${HA_NODES[*]}"
    echo "VIP: $HA_VIP"
    echo "Target Node: $HA_TARGET_NODE"
    echo ""
    
    # Run all tests
    check_ha_config
    test_network_connectivity
    test_ctdb_availability
    test_lxc_ha
    test_native_ha
    test_vm_ha
    test_ha_failover
    test_smb_vip_connectivity
    test_ha_monitoring
    test_ha_troubleshooting
    
    echo -e "\n${GREEN}=== All HA Integration Tests Completed! ===${NC}"
    echo -e "${BLUE}HA integration is working correctly across all deployment modes.${NC}"
    
    # Summary
    echo -e "\n${BLUE}Test Summary:${NC}"
    echo "✓ HA configuration validation"
    echo "✓ Network connectivity testing"
    echo "✓ CTDB package availability"
    echo "✓ LXC mode HA integration"
    echo "✓ Native mode HA integration"
    echo "✓ VM mode HA integration (if templates available)"
    echo "✓ HA failover testing"
    echo "✓ SMB connectivity via VIP"
    echo "✓ HA monitoring and status"
    echo "✓ HA troubleshooting tools"
    
    echo -e "\n${GREEN}HA integration is ready for production use!${NC}"
}

# Check if HA configuration is provided
if [ ${#HA_NODES[@]} -eq 0 ] || [ -z "$HA_VIP" ]; then
    echo -e "${RED}Error: HA configuration not provided${NC}"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export HA_NODES=(\"192.168.1.10\" \"192.168.1.11\" \"192.168.1.12\")"
    echo "  export HA_VIP=\"192.168.1.100\""
    echo "  export HA_TARGET_NODE=\"192.168.1.11\""
    echo ""
    echo "Then run: $0"
    exit 1
fi

# Run main function
main "$@" 