#!/bin/bash

# PVE SMB Gateway AD Troubleshooting Tools
# Comprehensive Active Directory connectivity and authentication testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to test DNS resolution
test_dns_resolution() {
    local domain=$1
    echo -e "\n${BLUE}Testing DNS Resolution for $domain${NC}"
    
    # Test basic domain resolution
    if nslookup "$domain" >/dev/null 2>&1; then
        print_status "PASS" "Domain $domain resolves"
    else
        print_status "FAIL" "Domain $domain does not resolve"
        return 1
    fi
    
    # Test SRV records
    if nslookup -type=srv "_ldap._tcp.$domain" >/dev/null 2>&1; then
        print_status "PASS" "LDAP SRV records found"
    else
        print_status "FAIL" "No LDAP SRV records found"
    fi
    
    # Test Kerberos SRV records
    if nslookup -type=srv "_kerberos._tcp.$domain" >/dev/null 2>&1; then
        print_status "PASS" "Kerberos SRV records found"
    else
        print_status "FAIL" "No Kerberos SRV records found"
    fi
}

# Function to discover domain controllers
discover_domain_controllers() {
    local domain=$1
    echo -e "\n${BLUE}Discovering Domain Controllers for $domain${NC}"
    
    local controllers=()
    
    # Try DNS SRV records
    local srv_records=$(nslookup -type=srv "_ldap._tcp.$domain" 2>/dev/null | grep -E "svr hostname" | awk '{print $NF}')
    if [ -n "$srv_records" ]; then
        echo "Found DCs via SRV records:"
        echo "$srv_records" | while read -r dc; do
            print_status "PASS" "DC: $dc"
            controllers+=("$dc")
        done
    fi
    
    # Try common DC names
    local common_names=("dc1" "dc" "ad" "ldap" "dc01" "dc02")
    for name in "${common_names[@]}"; do
        if nslookup "$name.$domain" >/dev/null 2>&1; then
            print_status "PASS" "DC: $name.$domain"
            controllers+=("$name.$domain")
        fi
    done
    
    # Return first controller found
    if [ ${#controllers[@]} -gt 0 ]; then
        echo "${controllers[0]}"
    else
        echo ""
    fi
}

# Function to test DC connectivity
test_dc_connectivity() {
    local dc=$1
    local domain=$2
    echo -e "\n${BLUE}Testing Connectivity to $dc${NC}"
    
    # Test ping
    if ping -c 1 "$dc" >/dev/null 2>&1; then
        print_status "PASS" "Ping to $dc successful"
    else
        print_status "FAIL" "Cannot ping $dc"
        return 1
    fi
    
    # Test LDAP connectivity
    if timeout 5 ldapsearch -H "ldap://$dc" -x -b "" -s base >/dev/null 2>&1; then
        print_status "PASS" "LDAP connectivity to $dc successful"
    else
        print_status "FAIL" "LDAP connectivity to $dc failed"
    fi
    
    # Test SMB connectivity
    if timeout 5 smbclient -L "$dc" -U guest% >/dev/null 2>&1; then
        print_status "PASS" "SMB connectivity to $dc successful"
    else
        print_status "FAIL" "SMB connectivity to $dc failed"
    fi
    
    # Test Kerberos connectivity
    if timeout 5 kinit -k -t /etc/krb5.keytab "host/$dc@$domain" >/dev/null 2>&1; then
        print_status "PASS" "Kerberos connectivity to $dc successful"
    else
        print_status "FAIL" "Kerberos connectivity to $dc failed"
    fi
}

# Function to test domain join
test_domain_join() {
    local domain=$1
    local username=$2
    local password=$3
    local ou=$4
    echo -e "\n${BLUE}Testing Domain Join for $domain${NC}"
    
    # Check if already joined
    if net ads testjoin >/dev/null 2>&1; then
        print_status "PASS" "Already joined to domain"
        return 0
    fi
    
    # Test join without actually joining
    local join_cmd="net ads join -U $username%$password"
    if [ -n "$ou" ]; then
        join_cmd="$join_cmd -s $ou"
    fi
    
    if $join_cmd --dry-run >/dev/null 2>&1; then
        print_status "PASS" "Domain join test successful"
    else
        print_status "FAIL" "Domain join test failed"
        return 1
    fi
}

# Function to test Kerberos authentication
test_kerberos_auth() {
    local domain=$1
    local username=$2
    local password=$3
    echo -e "\n${BLUE}Testing Kerberos Authentication${NC}"
    
    # Test kinit
    if echo "$password" | kinit "$username@$domain" >/dev/null 2>&1; then
        print_status "PASS" "Kerberos authentication successful"
        
        # Test ticket
        if klist >/dev/null 2>&1; then
            print_status "PASS" "Kerberos ticket valid"
        else
            print_status "FAIL" "Kerberos ticket invalid"
        fi
        
        # Clean up
        kdestroy >/dev/null 2>&1
    else
        print_status "FAIL" "Kerberos authentication failed"
        return 1
    fi
}

# Function to test Samba AD integration
test_samba_ad() {
    local share=$1
    local domain=$2
    echo -e "\n${BLUE}Testing Samba AD Integration for $share${NC}"
    
    # Check Samba configuration
    if testparm -s >/dev/null 2>&1; then
        print_status "PASS" "Samba configuration valid"
    else
        print_status "FAIL" "Samba configuration invalid"
        return 1
    fi
    
    # Check winbind service
    if systemctl is-active winbind >/dev/null 2>&1; then
        print_status "PASS" "Winbind service running"
    else
        print_status "FAIL" "Winbind service not running"
    fi
    
    # Test winbind user enumeration
    if wbinfo -u >/dev/null 2>&1; then
        print_status "PASS" "Winbind user enumeration working"
    else
        print_status "FAIL" "Winbind user enumeration failed"
    fi
    
    # Test winbind group enumeration
    if wbinfo -g >/dev/null 2>&1; then
        print_status "PASS" "Winbind group enumeration working"
    else
        print_status "FAIL" "Winbind group enumeration failed"
    fi
    
    # Test SMB share access
    if smbclient "//localhost/$share" -U guest% -c "ls" >/dev/null 2>&1; then
        print_status "PASS" "SMB share access working"
    else
        print_status "FAIL" "SMB share access failed"
    fi
}

# Function to check system requirements
check_system_requirements() {
    echo -e "\n${BLUE}Checking System Requirements${NC}"
    
    # Check required packages
    local required_packages=("samba" "winbind" "krb5-user" "libpam-krb5")
    for package in "${required_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package"; then
            print_status "PASS" "Package $package installed"
        else
            print_status "FAIL" "Package $package not installed"
        fi
    done
    
    # Check Samba services
    local samba_services=("smbd" "nmbd" "winbind")
    for service in "${samba_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            print_status "PASS" "Service $service enabled"
        else
            print_status "FAIL" "Service $service not enabled"
        fi
    done
    
    # Check configuration files
    local config_files=("/etc/samba/smb.conf" "/etc/krb5.conf")
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            print_status "PASS" "Config file $file exists"
        else
            print_status "FAIL" "Config file $file missing"
        fi
    done
}

# Function to generate diagnostic report
generate_diagnostic_report() {
    local domain=$1
    local username=$2
    local password=$3
    local share=$4
    local ou=$5
    
    echo -e "${BLUE}=== AD Diagnostic Report ===${NC}"
    echo "Domain: $domain"
    echo "Username: $username"
    echo "Share: $share"
    echo "OU: $ou"
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d | cut -f2)"
    
    # System requirements
    check_system_requirements
    
    # DNS resolution
    test_dns_resolution "$domain"
    
    # Discover DCs
    local dc=$(discover_domain_controllers "$domain")
    if [ -n "$dc" ]; then
        # Test DC connectivity
        test_dc_connectivity "$dc" "$domain"
        
        # Test Kerberos authentication
        test_kerberos_auth "$domain" "$username" "$password"
        
        # Test domain join
        test_domain_join "$domain" "$username" "$password" "$ou"
        
        # Test Samba AD integration
        test_samba_ad "$share" "$domain"
    else
        print_status "FAIL" "No domain controllers found"
    fi
    
    echo -e "\n${BLUE}=== Diagnostic Report Complete ===${NC}"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN     Domain to test (e.g., example.com)"
    echo "  -u, --username USER     Username for authentication"
    echo "  -p, --password PASS     Password for authentication"
    echo "  -s, --share SHARE       SMB share name to test"
    echo "  -o, --ou OU             Organizational Unit (optional)"
    echo "  -t, --test TYPE         Specific test to run:"
    echo "                          dns, dc, kerberos, join, samba, all"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -d example.com -u administrator -p password -s myshare"
    echo "  $0 -d example.com -u administrator -p password -s myshare -t dns"
    echo "  $0 -d example.com -u administrator -p password -s myshare -o 'OU=Computers,DC=example,DC=com'"
}

# Main script
main() {
    local domain=""
    local username=""
    local password=""
    local share=""
    local ou=""
    local test_type="all"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -u|--username)
                username="$2"
                shift 2
                ;;
            -p|--password)
                password="$2"
                shift 2
                ;;
            -s|--share)
                share="$2"
                shift 2
                ;;
            -o|--ou)
                ou="$2"
                shift 2
                ;;
            -t|--test)
                test_type="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        echo "Error: Domain, username, and password are required"
        show_usage
        exit 1
    fi
    
    # Run specific test or full diagnostic
    case $test_type in
        dns)
            test_dns_resolution "$domain"
            ;;
        dc)
            local dc=$(discover_domain_controllers "$domain")
            if [ -n "$dc" ]; then
                test_dc_connectivity "$dc" "$domain"
            fi
            ;;
        kerberos)
            test_kerberos_auth "$domain" "$username" "$password"
            ;;
        join)
            test_domain_join "$domain" "$username" "$password" "$ou"
            ;;
        samba)
            if [ -n "$share" ]; then
                test_samba_ad "$share" "$domain"
            else
                echo "Error: Share name required for Samba test"
                exit 1
            fi
            ;;
        all)
            generate_diagnostic_report "$domain" "$username" "$password" "$share" "$ou"
            ;;
        *)
            echo "Error: Unknown test type: $test_type"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"