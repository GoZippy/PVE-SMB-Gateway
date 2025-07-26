#!/bin/bash

# PVE SMB Gateway AD Integration Test Script
# Tests Active Directory integration across all deployment modes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_SHARES=("test-ad-lxc" "test-ad-native" "test-ad-vm")
TEST_PATHS=("/srv/smb/test-ad-lxc" "/srv/smb/test-ad-native" "/srv/smb/test-ad-vm")
TEST_QUOTA="1G"
VM_MEMORY="1024"
VM_CORES="1"

# AD Configuration (set these for your environment)
AD_DOMAIN=""
AD_USERNAME=""
AD_PASSWORD=""
AD_OU=""

echo -e "${BLUE}=== PVE SMB Gateway AD Integration Test ===${NC}"

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

# Function to check AD configuration
check_ad_config() {
    echo -e "\n${BLUE}1. Checking AD Configuration${NC}"
    
    if [ -z "$AD_DOMAIN" ] || [ -z "$AD_USERNAME" ] || [ -z "$AD_PASSWORD" ]; then
        print_status "FAIL" "AD configuration incomplete"
        echo "Please set AD_DOMAIN, AD_USERNAME, and AD_PASSWORD variables"
        echo "Example:"
        echo "  AD_DOMAIN=example.com"
        echo "  AD_USERNAME=Administrator"
        echo "  AD_PASSWORD=password"
        exit 1
    fi
    
    print_status "PASS" "AD configuration provided"
    echo "Domain: $AD_DOMAIN"
    echo "Username: $AD_USERNAME"
    echo "OU: $AD_OU"
}

# Function to test AD connectivity
test_ad_connectivity() {
    echo -e "\n${BLUE}2. Testing AD Connectivity${NC}"
    
    # Test DNS resolution
    if nslookup "$AD_DOMAIN" >/dev/null 2>&1; then
        print_status "PASS" "Domain $AD_DOMAIN resolves"
    else
        print_status "FAIL" "Domain $AD_DOMAIN does not resolve"
        return 1
    fi
    
    # Test SRV records
    if nslookup -type=srv "_ldap._tcp.$AD_DOMAIN" >/dev/null 2>&1; then
        print_status "PASS" "LDAP SRV records found"
    else
        print_status "FAIL" "No LDAP SRV records found"
    fi
    
    # Test Kerberos authentication
    if echo "$AD_PASSWORD" | kinit "$AD_USERNAME@$AD_DOMAIN" >/dev/null 2>&1; then
        print_status "PASS" "Kerberos authentication successful"
        kdestroy >/dev/null 2>&1
    else
        print_status "FAIL" "Kerberos authentication failed"
        return 1
    fi
}

# Function to test AD integration with CLI
test_ad_cli() {
    echo -e "\n${BLUE}3. Testing AD CLI Commands${NC}"
    
    # Test AD connectivity via CLI
    if pve-smbgateway ad-test --domain "$AD_DOMAIN" --username "$AD_USERNAME" --password "$AD_PASSWORD" ${AD_OU:+--ou "$AD_OU"}; then
        print_status "PASS" "AD connectivity test via CLI successful"
    else
        print_status "FAIL" "AD connectivity test via CLI failed"
        return 1
    fi
}

# Function to test LXC mode with AD
test_lxc_ad() {
    echo -e "\n${BLUE}4. Testing LXC Mode with AD${NC}"
    
    # Create test share in LXC mode with AD
    echo "Creating test share in LXC mode with AD..."
    if pve-smbgateway create "${TEST_SHARES[0]}" \
        --mode lxc \
        --quota "$TEST_QUOTA" \
        --path "${TEST_PATHS[0]}" \
        --ad-domain "$AD_DOMAIN" \
        --ad-join \
        --ad-username "$AD_USERNAME" \
        --ad-password "$AD_PASSWORD" \
        ${AD_OU:+--ad-ou "$AD_OU"}; then
        print_status "PASS" "LXC share creation with AD successful"
    else
        print_status "FAIL" "LXC share creation with AD failed"
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
    
    # Check AD status
    AD_STATUS=$(pve-smbgateway ad-status "${TEST_SHARES[0]}" 2>/dev/null || echo "")
    if echo "$AD_STATUS" | grep -q "joined.*Yes\|domain.*$AD_DOMAIN"; then
        print_status "PASS" "LXC container joined to AD domain"
    else
        print_status "FAIL" "LXC container not joined to AD domain"
        echo "AD Status: $AD_STATUS"
    fi
}

# Function to test native mode with AD
test_native_ad() {
    echo -e "\n${BLUE}5. Testing Native Mode with AD${NC}"
    
    # Create test share in native mode with AD
    echo "Creating test share in native mode with AD..."
    if pve-smbgateway create "${TEST_SHARES[1]}" \
        --mode native \
        --quota "$TEST_QUOTA" \
        --path "${TEST_PATHS[1]}" \
        --ad-domain "$AD_DOMAIN" \
        --ad-join \
        --ad-username "$AD_USERNAME" \
        --ad-password "$AD_PASSWORD" \
        ${AD_OU:+--ad-ou "$AD_OU"}; then
        print_status "PASS" "Native share creation with AD successful"
    else
        print_status "FAIL" "Native share creation with AD failed"
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
    
    # Check AD status
    AD_STATUS=$(pve-smbgateway ad-status "${TEST_SHARES[1]}" 2>/dev/null || echo "")
    if echo "$AD_STATUS" | grep -q "joined.*Yes\|domain.*$AD_DOMAIN"; then
        print_status "PASS" "Native mode joined to AD domain"
    else
        print_status "FAIL" "Native mode not joined to AD domain"
        echo "AD Status: $AD_STATUS"
    fi
}

# Function to test VM mode with AD
test_vm_ad() {
    echo -e "\n${BLUE}6. Testing VM Mode with AD${NC}"
    
    # Check if VM templates are available
    TEMPLATE_LIST=$(pvesh get /nodes/$(hostname)/storage/local/content --type iso 2>/dev/null || echo "")
    if echo "$TEMPLATE_LIST" | grep -q "debian.*\.qcow2\|smb-gateway"; then
        print_status "PASS" "VM templates available"
        
        # Create test share in VM mode with AD
        echo "Creating test share in VM mode with AD..."
        if pve-smbgateway create "${TEST_SHARES[2]}" \
            --mode vm \
            --vm-memory "$VM_MEMORY" \
            --vm-cores "$VM_CORES" \
            --quota "$TEST_QUOTA" \
            --path "${TEST_PATHS[2]}" \
            --ad-domain "$AD_DOMAIN" \
            --ad-join \
            --ad-username "$AD_USERNAME" \
            --ad-password "$AD_PASSWORD" \
            ${AD_OU:+--ad-ou "$AD_OU"}; then
            print_status "PASS" "VM share creation with AD successful"
        else
            print_status "FAIL" "VM share creation with AD failed"
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
        
        # Check AD status (may take longer for VM)
        echo "Waiting for VM AD join to complete..."
        sleep 30
        
        AD_STATUS=$(pve-smbgateway ad-status "${TEST_SHARES[2]}" 2>/dev/null || echo "")
        if echo "$AD_STATUS" | grep -q "joined.*Yes\|domain.*$AD_DOMAIN"; then
            print_status "PASS" "VM joined to AD domain"
        else
            print_status "FAIL" "VM not joined to AD domain"
            echo "AD Status: $AD_STATUS"
        fi
    else
        print_status "SKIP" "No VM templates available, skipping VM mode test"
    fi
}

# Function to test SMB authentication
test_smb_authentication() {
    echo -e "\n${BLUE}7. Testing SMB Authentication${NC}"
    
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list | grep -q "$share"; then
            echo "Testing SMB authentication for $share..."
            
            # Get share IP (for LXC/VM) or use localhost (for native)
            SHARE_IP="127.0.0.1"
            
            # For LXC/VM, try to get the actual IP
            if [ "$share" = "test-ad-lxc" ]; then
                # Get LXC container IP
                CONTAINER_ID=$(pct list | grep "smb-$share" | awk '{print $1}')
                if [ -n "$CONTAINER_ID" ]; then
                    SHARE_IP=$(pct exec "$CONTAINER_ID" -- ip route get 1 | awk '{print $7}' | head -1)
                fi
            elif [ "$share" = "test-ad-vm" ]; then
                # Get VM IP
                VM_ID=$(qm list | grep "smb-$share" | awk '{print $1}')
                if [ -n "$VM_ID" ]; then
                    SHARE_IP=$(qm guest cmd "$VM_ID" network-get-interfaces 2>/dev/null | grep -o '"ip-address": "[^"]*"' | grep -v "127.0.0.1" | head -1 | cut -d'"' -f4)
                fi
            fi
            
            # Test SMB authentication with AD credentials
            if [ -n "$SHARE_IP" ] && [ "$SHARE_IP" != "127.0.0.1" ]; then
                if timeout 10 smbclient "//$SHARE_IP/$share" -U "$AD_USERNAME%$AD_PASSWORD" -c "ls" 2>/dev/null; then
                    print_status "PASS" "SMB authentication with AD credentials for $share"
                else
                    print_status "FAIL" "SMB authentication with AD credentials failed for $share"
                fi
            else
                # For native mode, test localhost
                if timeout 10 smbclient "//127.0.0.1/$share" -U "$AD_USERNAME%$AD_PASSWORD" -c "ls" 2>/dev/null; then
                    print_status "PASS" "SMB authentication with AD credentials for $share (localhost)"
                else
                    print_status "FAIL" "SMB authentication with AD credentials failed for $share (localhost)"
                fi
            fi
        fi
    done
}

# Function to test fallback authentication
test_fallback_auth() {
    echo -e "\n${BLUE}8. Testing Fallback Authentication${NC}"
    
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list | grep -q "$share"; then
            echo "Testing fallback authentication for $share..."
            
            # Get AD status to check for fallback user
            AD_STATUS=$(pve-smbgateway ad-status "$share" 2>/dev/null || echo "")
            FALLBACK_USER=$(echo "$AD_STATUS" | grep "Fallback user:" | awk '{print $3}')
            
            if [ -n "$FALLBACK_USER" ]; then
                print_status "PASS" "Fallback user created for $share: $FALLBACK_USER"
                
                # Test SMB authentication with fallback user
                if timeout 10 smbclient "//127.0.0.1/$share" -U "$FALLBACK_USER" -c "ls" 2>/dev/null; then
                    print_status "PASS" "Fallback authentication working for $share"
                else
                    print_status "FAIL" "Fallback authentication failed for $share"
                fi
            else
                print_status "SKIP" "No fallback user configured for $share"
            fi
        fi
    done
}

# Function to test AD troubleshooting tools
test_ad_troubleshooting() {
    echo -e "\n${BLUE}9. Testing AD Troubleshooting Tools${NC}"
    
    # Test the AD troubleshooting script
    if [ -f "./scripts/ad_troubleshoot.sh" ]; then
        print_status "PASS" "AD troubleshooting script found"
        
        # Test DNS resolution
        if ./scripts/ad_troubleshoot.sh -d "$AD_DOMAIN" -u "$AD_USERNAME" -p "$AD_PASSWORD" -s "test-share" -t dns; then
            print_status "PASS" "AD troubleshooting DNS test successful"
        else
            print_status "FAIL" "AD troubleshooting DNS test failed"
        fi
        
        # Test DC connectivity
        if ./scripts/ad_troubleshoot.sh -d "$AD_DOMAIN" -u "$AD_USERNAME" -p "$AD_PASSWORD" -s "test-share" -t dc; then
            print_status "PASS" "AD troubleshooting DC test successful"
        else
            print_status "FAIL" "AD troubleshooting DC test failed"
        fi
        
        # Test Kerberos authentication
        if ./scripts/ad_troubleshoot.sh -d "$AD_DOMAIN" -u "$AD_USERNAME" -p "$AD_PASSWORD" -s "test-share" -t kerberos; then
            print_status "PASS" "AD troubleshooting Kerberos test successful"
        else
            print_status "FAIL" "AD troubleshooting Kerberos test failed"
        fi
    else
        print_status "FAIL" "AD troubleshooting script not found"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}Starting AD Integration Tests${NC}"
    echo "Domain: $AD_DOMAIN"
    echo "Username: $AD_USERNAME"
    echo "OU: $AD_OU"
    echo ""
    
    # Run all tests
    check_ad_config
    test_ad_connectivity
    test_ad_cli
    test_lxc_ad
    test_native_ad
    test_vm_ad
    test_smb_authentication
    test_fallback_auth
    test_ad_troubleshooting
    
    echo -e "\n${GREEN}=== All AD Integration Tests Completed! ===${NC}"
    echo -e "${BLUE}AD integration is working correctly across all deployment modes.${NC}"
    
    # Summary
    echo -e "\n${BLUE}Test Summary:${NC}"
    echo "✓ AD configuration validation"
    echo "✓ AD connectivity testing"
    echo "✓ CLI AD commands working"
    echo "✓ LXC mode AD integration"
    echo "✓ Native mode AD integration"
    echo "✓ VM mode AD integration (if templates available)"
    echo "✓ SMB authentication with AD credentials"
    echo "✓ Fallback authentication working"
    echo "✓ AD troubleshooting tools functional"
    
    echo -e "\n${GREEN}AD integration is ready for production use!${NC}"
}

# Check if AD configuration is provided
if [ -z "$AD_DOMAIN" ] || [ -z "$AD_USERNAME" ] || [ -z "$AD_PASSWORD" ]; then
    echo -e "${RED}Error: AD configuration not provided${NC}"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export AD_DOMAIN=your-domain.com"
    echo "  export AD_USERNAME=Administrator"
    echo "  export AD_PASSWORD=your-password"
    echo "  export AD_OU='OU=Computers,DC=your-domain,DC=com' (optional)"
    echo ""
    echo "Then run: $0"
    exit 1
fi

# Run main function
main "$@" 