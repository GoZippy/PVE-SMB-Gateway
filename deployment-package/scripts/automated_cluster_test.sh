#!/bin/bash

# Automated Cluster Test Suite for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Tests all features in a real Proxmox cluster environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="/tmp/pve-smbgateway-cluster-test-results"
TEST_LOGS_DIR="$TEST_RESULTS_DIR/logs"
TEST_REPORTS_DIR="$TEST_RESULTS_DIR/reports"

# Cluster configuration (can be overridden by environment variables)
CLUSTER_NODES=(${CLUSTER_NODES:-"192.168.1.10 192.168.1.11 192.168.1.12"})
CLUSTER_VIP=${CLUSTER_VIP:-"192.168.1.100"}
AD_DOMAIN=${AD_DOMAIN:-"test.example.com"}
AD_USERNAME=${AD_USERNAME:-"Administrator"}
AD_PASSWORD=${AD_PASSWORD:-"TestPassword123!"}

# Test configuration
TEST_SHARES=(
    "test-cluster-lxc"
    "test-cluster-native" 
    "test-cluster-vm"
)
TEST_PATHS=(
    "/srv/smb/test-cluster-lxc"
    "/srv/smb/test-cluster-native"
    "/srv/smb/test-cluster-vm"
)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | INFO | $1" >> "$TEST_LOGS_DIR/test.log"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | PASS | $1" >> "$TEST_LOGS_DIR/test.log"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | FAIL | $1" >> "$TEST_LOGS_DIR/test.log"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | WARN | $1" >> "$TEST_LOGS_DIR/test.log"
}

log_header() {
    echo -e "${PURPLE}[HEADER]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | HEADER | $1" >> "$TEST_LOGS_DIR/test.log"
}

# Test result tracking
record_test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    case "$result" in
        "PASS")
            PASSED_TESTS=$((PASSED_TESTS + 1))
            log_success "$test_name"
            ;;
        "FAIL")
            FAILED_TESTS=$((FAILED_TESTS + 1))
            log_error "$test_name - $details"
            ;;
        "SKIP")
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            log_warning "$test_name - $details"
            ;;
    esac
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop any running test processes
    pkill -f "test_.*\.sh" 2>/dev/null || true
    pkill -f "fio" 2>/dev/null || true
    pkill -f "smbclient" 2>/dev/null || true
    
    # Clean up test shares
    for share in "${TEST_SHARES[@]}"; do
        if pve-smbgateway list 2>/dev/null | grep -q "$share"; then
            log_info "Removing test share: $share"
            pve-smbgateway delete "$share" 2>/dev/null || true
        fi
    done
    
    # Clean up test directories
    for path in "${TEST_PATHS[@]}"; do
        if [ -d "$path" ]; then
            log_info "Removing test directory: $path"
            rm -rf "$path" 2>/dev/null || true
        fi
    done
    
    log_info "Cleanup completed"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$TEST_LOGS_DIR"
    mkdir -p "$TEST_REPORTS_DIR"
    
    # Check if we're in a Proxmox environment
    if [ ! -f "/etc/pve/version" ]; then
        log_error "Not running in a Proxmox environment"
        exit 1
    fi
    
    # Check cluster status
    if ! pvecm status >/dev/null 2>&1; then
        log_warning "Not in a cluster environment, some tests will be skipped"
    fi
    
    # Check if SMB Gateway is installed
    if ! command -v pve-smbgateway >/dev/null 2>&1; then
        log_error "PVE SMB Gateway not installed"
        exit 1
    fi
    
    log_success "Test environment setup completed"
}

# Test cluster connectivity
test_cluster_connectivity() {
    log_header "Testing Cluster Connectivity"
    
    local test_name="Cluster Node Connectivity"
    
    for node in "${CLUSTER_NODES[@]}"; do
        if ping -c 1 "$node" >/dev/null 2>&1; then
            log_info "Node $node is reachable"
        else
            record_test_result "$test_name" "FAIL" "Node $node is not reachable"
            return 1
        fi
    done
    
    record_test_result "$test_name" "PASS" "All cluster nodes are reachable"
}

# Test SMB Gateway installation
test_smb_gateway_installation() {
    log_header "Testing SMB Gateway Installation"
    
    local test_name="SMB Gateway Installation"
    
    # Check if the plugin is loaded
    if pvesh get /nodes/$(hostname)/storage | grep -q "smbgateway"; then
        record_test_result "$test_name" "PASS" "SMB Gateway plugin is installed and loaded"
    else
        record_test_result "$test_name" "FAIL" "SMB Gateway plugin is not loaded"
        return 1
    fi
}

# Test share creation in different modes
test_share_creation() {
    log_header "Testing Share Creation"
    
    local modes=("lxc" "native" "vm")
    local i=0
    
    for mode in "${modes[@]}"; do
        local share_name="${TEST_SHARES[$i]}"
        local test_path="${TEST_PATHS[$i]}"
        
        log_info "Testing share creation in $mode mode: $share_name"
        
        # Create test directory
        mkdir -p "$test_path"
        
        # Create share
        if pve-smbgateway create "$share_name" --path "$test_path" --mode "$mode" --quota "1G"; then
            record_test_result "Share Creation ($mode)" "PASS" "Successfully created $share_name in $mode mode"
            
            # Verify share exists
            if pve-smbgateway list | grep -q "$share_name"; then
                record_test_result "Share Verification ($mode)" "PASS" "Share $share_name is listed"
            else
                record_test_result "Share Verification ($mode)" "FAIL" "Share $share_name not found in list"
            fi
        else
            record_test_result "Share Creation ($mode)" "FAIL" "Failed to create $share_name in $mode mode"
        fi
        
        i=$((i + 1))
    done
}

# Test SMB connectivity
test_smb_connectivity() {
    log_header "Testing SMB Connectivity"
    
    for share in "${TEST_SHARES[@]}"; do
        log_info "Testing SMB connectivity to share: $share"
        
        # Test SMB connection
        if smbclient -L "//localhost/$share" -U guest% 2>/dev/null | grep -q "$share"; then
            record_test_result "SMB Connectivity ($share)" "PASS" "Successfully connected to $share"
        else
            record_test_result "SMB Connectivity ($share)" "FAIL" "Failed to connect to $share"
        fi
    done
}

# Test HA failover (if in cluster)
test_ha_failover() {
    log_header "Testing HA Failover"
    
    # Check if we're in a cluster
    if ! pvecm status >/dev/null 2>&1; then
        record_test_result "HA Failover" "SKIP" "Not in a cluster environment"
        return 0
    fi
    
    # Get current node
    local current_node=$(hostname)
    local other_nodes=()
    
    # Find other nodes in cluster
    for node in "${CLUSTER_NODES[@]}"; do
        if [ "$node" != "$current_node" ]; then
            other_nodes+=("$node")
        fi
    done
    
    if [ ${#other_nodes[@]} -eq 0 ]; then
        record_test_result "HA Failover" "SKIP" "No other nodes available for failover test"
        return 0
    fi
    
    # Test failover by stopping services on current node
    log_info "Testing failover by stopping services on current node"
    
    # Stop SMB services
    systemctl stop smbd nmbd 2>/dev/null || true
    
    # Wait for failover
    sleep 10
    
    # Check if services are running on other nodes
    local failover_success=false
    for node in "${other_nodes[@]}"; do
        if ssh root@$node "systemctl is-active smbd" 2>/dev/null | grep -q "active"; then
            failover_success=true
            break
        fi
    done
    
    # Restart services on current node
    systemctl start smbd nmbd 2>/dev/null || true
    
    if [ "$failover_success" = true ]; then
        record_test_result "HA Failover" "PASS" "Services failed over successfully"
    else
        record_test_result "HA Failover" "FAIL" "Services did not fail over properly"
    fi
}

# Test performance
test_performance() {
    log_header "Testing Performance"
    
    # Install fio if not available
    if ! command -v fio >/dev/null 2>&1; then
        apt-get update && apt-get install -y fio
    fi
    
    for share in "${TEST_SHARES[@]}"; do
        log_info "Testing performance for share: $share"
        
        local mount_point="/tmp/test-$share"
        mkdir -p "$mount_point"
        
        # Mount share
        if mount -t cifs "//localhost/$share" "$mount_point" -o guest; then
            # Run fio test
            local fio_output=$(fio --name=test --directory="$mount_point" --size=100M --numjobs=4 --time_based --runtime=30 --ramp_time=2 --ioengine=libaio --direct=1 --verify=0 --bs=1M --iodepth=64 --rw=randread --group_reporting 2>/dev/null)
            
            # Extract IOPS
            local iops=$(echo "$fio_output" | grep "IOPS" | awk '{print $3}' | sed 's/,//')
            
            if [ -n "$iops" ] && [ "$iops" -gt 0 ]; then
                record_test_result "Performance ($share)" "PASS" "IOPS: $iops"
            else
                record_test_result "Performance ($share)" "FAIL" "No IOPS recorded"
            fi
            
            # Unmount
            umount "$mount_point" 2>/dev/null || true
        else
            record_test_result "Performance ($share)" "FAIL" "Failed to mount share for testing"
        fi
        
        rmdir "$mount_point" 2>/dev/null || true
    done
}

# Test security
test_security() {
    log_header "Testing Security"
    
    # Test SMB protocol version enforcement
    for share in "${TEST_SHARES[@]}"; do
        log_info "Testing SMB protocol security for share: $share"
        
        # Test with old SMB1 protocol (should fail)
        if smbclient "//localhost/$share" -U guest% --option='client min protocol=NT1' 2>&1 | grep -q "protocol negotiation failed"; then
            record_test_result "Security - SMB1 Blocked ($share)" "PASS" "SMB1 protocol correctly blocked"
        else
            record_test_result "Security - SMB1 Blocked ($share)" "FAIL" "SMB1 protocol not blocked"
        fi
    done
}

# Generate test report
generate_test_report() {
    log_header "Generating Test Report"
    
    local report_file="$TEST_REPORTS_DIR/cluster_test_report_$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PVE SMB Gateway Cluster Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .test-result { margin: 10px 0; padding: 10px; border-radius: 5px; }
        .pass { background-color: #d4edda; border: 1px solid #c3e6cb; }
        .fail { background-color: #f8d7da; border: 1px solid #f5c6cb; }
        .skip { background-color: #fff3cd; border: 1px solid #ffeaa7; }
        .log { background-color: #f8f9fa; padding: 10px; border-radius: 5px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="header">
        <h1>PVE SMB Gateway Cluster Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Cluster Nodes: ${CLUSTER_NODES[*]}</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: $TOTAL_TESTS</p>
        <p>Passed: $PASSED_TESTS</p>
        <p>Failed: $FAILED_TESTS</p>
        <p>Skipped: $SKIPPED_TESTS</p>
    </div>
    
    <div class="log">
        <h2>Test Log</h2>
        <pre>$(cat "$TEST_LOGS_DIR/test.log" 2>/dev/null || echo "No log available")</pre>
    </div>
</body>
</html>
EOF
    
    log_info "Test report generated: $report_file"
    
    # Also generate JSON report
    local json_report="$TEST_REPORTS_DIR/cluster_test_report_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$json_report" << EOF
{
    "test_run": {
        "timestamp": "$(date -Iseconds)",
        "cluster_nodes": ${CLUSTER_NODES[@]@Q},
        "summary": {
            "total_tests": $TOTAL_TESTS,
            "passed": $PASSED_TESTS,
            "failed": $FAILED_TESTS,
            "skipped": $SKIPPED_TESTS
        }
    }
}
EOF
    
    log_info "JSON report generated: $json_report"
}

# Main test execution
main() {
    log_header "Starting PVE SMB Gateway Cluster Test Suite"
    
    # Setup cleanup trap
    trap cleanup EXIT
    
    # Setup test environment
    setup_test_environment
    
    # Run tests
    test_cluster_connectivity
    test_smb_gateway_installation
    test_share_creation
    test_smb_connectivity
    test_ha_failover
    test_performance
    test_security
    
    # Generate report
    generate_test_report
    
    # Print summary
    log_header "Test Suite Summary"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Skipped: $SKIPPED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "$FAILED_TESTS tests failed"
        exit 1
    fi
}

# Run main function
main "$@" 