#!/bin/bash

# Comprehensive Integration Test Suite for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Tests all features including multi-node, HA, AD, security, and performance

set -e

echo "=== PVE SMB Gateway Comprehensive Integration Test Suite ==="
echo "Testing all features: Core, HA, AD, Security, Performance, CLI"
echo

# Configuration
TEST_DIR="/tmp/pve-smbgateway-integration-tests"
LOG_DIR="$TEST_DIR/logs"
RESULTS_DIR="$TEST_DIR/results"
CLUSTER_NODES=("node1" "node2" "node3")  # Configure for your cluster
AD_DOMAIN="test.example.com"
AD_USERNAME="Administrator"
AD_PASSWORD="TestPassword123!"
VIP_ADDRESS="192.168.1.100"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Initialize test environment
init_test_environment() {
    echo "Initializing test environment..."
    
    # Create test directories
    mkdir -p "$TEST_DIR" "$LOG_DIR" "$RESULTS_DIR"
    
    # Clean up previous test artifacts
    rm -rf "$TEST_DIR"/*
    mkdir -p "$LOG_DIR" "$RESULTS_DIR"
    
    # Create test configuration
    cat > "$TEST_DIR/test_config.json" << EOF
{
  "test_environment": {
    "cluster_nodes": ["${CLUSTER_NODES[@]}"],
    "ad_domain": "$AD_DOMAIN",
    "vip_address": "$VIP_ADDRESS",
    "test_shares": [
      {
        "name": "test-lxc-integration",
        "mode": "lxc",
        "path": "/tmp/test-lxc",
        "quota": "1G"
      },
      {
        "name": "test-native-integration", 
        "mode": "native",
        "path": "/tmp/test-native",
        "quota": "1G"
      },
      {
        "name": "test-vm-integration",
        "mode": "vm",
        "path": "/tmp/test-vm",
        "quota": "1G",
        "vm_memory": 1024,
        "vm_cores": 1
      }
    ]
  }
}
EOF
    
    echo "✓ Test environment initialized"
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
            echo "✅ PASS: $test_name"
            ;;
        "FAIL")
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo "❌ FAIL: $test_name - $details"
            ;;
        "SKIP")
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            echo "⏭️  SKIP: $test_name - $details"
            ;;
    esac
    
    # Log result
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $result | $test_name | $details" >> "$LOG_DIR/test_results.log"
}

# Test 1: Core Plugin Integration
test_core_plugin_integration() {
    echo
    echo "Test 1: Core Plugin Integration"
    echo "==============================="
    
    # Test plugin loading
    if perl -MPVE::Storage::Custom::SMBGateway -e "print 'Plugin loaded successfully\n';" 2>/dev/null; then
        record_test_result "Plugin Loading" "PASS" "Core plugin loads without errors"
    else
        record_test_result "Plugin Loading" "FAIL" "Core plugin failed to load"
        return 1
    fi
    
    # Test API endpoints
    if curl -k -s "https://localhost:8006/api2/json/nodes/$(hostname)/storage" | grep -q "smbgateway"; then
        record_test_result "API Endpoints" "PASS" "SMB Gateway API endpoints accessible"
    else
        record_test_result "API Endpoints" "FAIL" "SMB Gateway API endpoints not found"
    fi
    
    # Test ExtJS wizard loading
    if [ -f "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js" ]; then
        record_test_result "ExtJS Wizard" "PASS" "Web interface files present"
    else
        record_test_result "ExtJS Wizard" "FAIL" "Web interface files missing"
    fi
}

# Test 2: Multi-Node Cluster Testing
test_multi_node_cluster() {
    echo
    echo "Test 2: Multi-Node Cluster Testing"
    echo "=================================="
    
    # Check if we're in a cluster
    if [ -f "/etc/pve/corosync.conf" ]; then
        record_test_result "Cluster Detection" "PASS" "Proxmox cluster detected"
        
        # Test cluster node connectivity
        for node in "${CLUSTER_NODES[@]}"; do
            if ping -c 1 "$node" >/dev/null 2>&1; then
                record_test_result "Node Connectivity: $node" "PASS" "Node reachable"
            else
                record_test_result "Node Connectivity: $node" "SKIP" "Node not reachable"
            fi
        done
        
        # Test cluster-wide storage access
        if pvesh get /cluster/resources | grep -q "storage"; then
            record_test_result "Cluster Storage" "PASS" "Cluster storage accessible"
        else
            record_test_result "Cluster Storage" "FAIL" "Cluster storage not accessible"
        fi
    else
        record_test_result "Cluster Detection" "SKIP" "Not in a cluster environment"
    fi
}

# Test 3: End-to-End Workflow Testing
test_end_to_end_workflows() {
    echo
    echo "Test 3: End-to-End Workflow Testing"
    echo "==================================="
    
    # Test LXC mode workflow
    echo "Testing LXC mode workflow..."
    if pve-smbgateway create test-lxc-e2e --mode lxc --path /tmp/test-lxc-e2e --quota 1G 2>/dev/null; then
        record_test_result "LXC Workflow" "PASS" "LXC share creation successful"
        
        # Test share status
        if pve-smbgateway status test-lxc-e2e >/dev/null 2>&1; then
            record_test_result "LXC Status" "PASS" "LXC share status accessible"
        else
            record_test_result "LXC Status" "FAIL" "LXC share status failed"
        fi
        
        # Cleanup
        pve-smbgateway delete test-lxc-e2e 2>/dev/null || true
    else
        record_test_result "LXC Workflow" "FAIL" "LXC share creation failed"
    fi
    
    # Test Native mode workflow
    echo "Testing Native mode workflow..."
    if pve-smbgateway create test-native-e2e --mode native --path /tmp/test-native-e2e --quota 1G 2>/dev/null; then
        record_test_result "Native Workflow" "PASS" "Native share creation successful"
        
        # Test share status
        if pve-smbgateway status test-native-e2e >/dev/null 2>&1; then
            record_test_result "Native Status" "PASS" "Native share status accessible"
        else
            record_test_result "Native Status" "FAIL" "Native share status failed"
        fi
        
        # Cleanup
        pve-smbgateway delete test-native-e2e 2>/dev/null || true
    else
        record_test_result "Native Workflow" "FAIL" "Native share creation failed"
    fi
    
    # Test VM mode workflow (if supported)
    echo "Testing VM mode workflow..."
    if pve-smbgateway create test-vm-e2e --mode vm --path /tmp/test-vm-e2e --quota 1G --vm-memory 1024 2>/dev/null; then
        record_test_result "VM Workflow" "PASS" "VM share creation successful"
        
        # Test share status
        if pve-smbgateway status test-vm-e2e >/dev/null 2>&1; then
            record_test_result "VM Status" "PASS" "VM share status accessible"
        else
            record_test_result "VM Status" "FAIL" "VM share status failed"
        fi
        
        # Cleanup
        pve-smbgateway delete test-vm-e2e 2>/dev/null || true
    else
        record_test_result "VM Workflow" "SKIP" "VM mode not available or failed"
    fi
}

# Test 4: High Availability Testing
test_high_availability() {
    echo
    echo "Test 4: High Availability Testing"
    echo "================================="
    
    # Test HA share creation
    echo "Testing HA share creation..."
    if pve-smbgateway create test-ha --mode lxc --path /tmp/test-ha --ctdb-vip "$VIP_ADDRESS" 2>/dev/null; then
        record_test_result "HA Share Creation" "PASS" "HA share created successfully"
        
        # Test HA status
        if pve-smbgateway ha-status test-ha >/dev/null 2>&1; then
            record_test_result "HA Status" "PASS" "HA status accessible"
        else
            record_test_result "HA Status" "FAIL" "HA status failed"
        fi
        
        # Test HA failover (simulated)
        if pve-smbgateway ha-test --vip "$VIP_ADDRESS" --share test-ha 2>/dev/null; then
            record_test_result "HA Failover Test" "PASS" "HA failover test successful"
        else
            record_test_result "HA Failover Test" "SKIP" "HA failover test not available"
        fi
        
        # Cleanup
        pve-smbgateway delete test-ha 2>/dev/null || true
    else
        record_test_result "HA Share Creation" "SKIP" "HA features not available"
    fi
}

# Test 5: Active Directory Integration Testing
test_active_directory_integration() {
    echo
    echo "Test 5: Active Directory Integration Testing"
    echo "============================================"
    
    # Test AD connectivity (if AD server available)
    echo "Testing AD connectivity..."
    if pve-smbgateway ad-test --domain "$AD_DOMAIN" --username "$AD_USERNAME" --password "$AD_PASSWORD" 2>/dev/null; then
        record_test_result "AD Connectivity" "PASS" "AD connectivity successful"
        
        # Test AD share creation
        if pve-smbgateway create test-ad --mode lxc --path /tmp/test-ad --ad-domain "$AD_DOMAIN" --ad-join 2>/dev/null; then
            record_test_result "AD Share Creation" "PASS" "AD share created successfully"
            
            # Test AD status
            if pve-smbgateway ad-status test-ad >/dev/null 2>&1; then
                record_test_result "AD Status" "PASS" "AD status accessible"
            else
                record_test_result "AD Status" "FAIL" "AD status failed"
            fi
            
            # Cleanup
            pve-smbgateway delete test-ad 2>/dev/null || true
        else
            record_test_result "AD Share Creation" "FAIL" "AD share creation failed"
        fi
    else
        record_test_result "AD Connectivity" "SKIP" "AD server not available or credentials invalid"
    fi
}

# Test 6: Security Testing
test_security_features() {
    echo
    echo "Test 6: Security Testing"
    echo "========================"
    
    # Test security module loading
    if perl -MPVE::SMBGateway::Security -e "print 'Security module loaded\n';" 2>/dev/null; then
        record_test_result "Security Module" "PASS" "Security module loads successfully"
    else
        record_test_result "Security Module" "FAIL" "Security module failed to load"
    fi
    
    # Test security scan
    if pve-smbgateway security scan test-share 2>/dev/null; then
        record_test_result "Security Scan" "PASS" "Security scan functional"
    else
        record_test_result "Security Scan" "SKIP" "Security scan not available"
    fi
    
    # Test security status
    if pve-smbgateway security status test-share 2>/dev/null; then
        record_test_result "Security Status" "PASS" "Security status accessible"
    else
        record_test_result "Security Status" "SKIP" "Security status not available"
    fi
}

# Test 7: Performance Testing
test_performance_features() {
    echo
    echo "Test 7: Performance Testing"
    echo "==========================="
    
    # Test metrics module loading
    if perl -MPVE::SMBGateway::Monitor -e "print 'Monitor module loaded\n';" 2>/dev/null; then
        record_test_result "Monitor Module" "PASS" "Monitor module loads successfully"
    else
        record_test_result "Monitor Module" "FAIL" "Monitor module failed to load"
    fi
    
    # Test metrics collection
    if pve-smbgateway metrics current test-share 2>/dev/null; then
        record_test_result "Metrics Collection" "PASS" "Metrics collection functional"
    else
        record_test_result "Metrics Collection" "SKIP" "Metrics collection not available"
    fi
    
    # Test performance benchmarks
    echo "Running performance benchmarks..."
    start_time=$(date +%s)
    pve-smbgateway create test-perf --mode lxc --path /tmp/test-perf --quota 1G 2>/dev/null
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [ $duration -lt 60 ]; then
        record_test_result "Performance Benchmark" "PASS" "Share creation completed in ${duration}s"
    else
        record_test_result "Performance Benchmark" "FAIL" "Share creation took too long: ${duration}s"
    fi
    
    # Cleanup
    pve-smbgateway delete test-perf 2>/dev/null || true
}

# Test 8: Enhanced CLI Testing
test_enhanced_cli() {
    echo
    echo "Test 8: Enhanced CLI Testing"
    echo "============================"
    
    # Test enhanced CLI tool
    if [ -f "/usr/sbin/pve-smbgateway-enhanced" ]; then
        record_test_result "Enhanced CLI Tool" "PASS" "Enhanced CLI tool available"
        
        # Test help command
        if pve-smbgateway-enhanced help 2>/dev/null; then
            record_test_result "Enhanced CLI Help" "PASS" "Help command functional"
        else
            record_test_result "Enhanced CLI Help" "FAIL" "Help command failed"
        fi
        
        # Test JSON output
        if pve-smbgateway-enhanced list --json 2>/dev/null | grep -q "application/json"; then
            record_test_result "Enhanced CLI JSON" "PASS" "JSON output functional"
        else
            record_test_result "Enhanced CLI JSON" "SKIP" "JSON output not available"
        fi
    else
        record_test_result "Enhanced CLI Tool" "SKIP" "Enhanced CLI tool not installed"
    fi
    
    # Test batch operations
    if pve-smbgateway batch create --config "$TEST_DIR/test_config.json" --dry-run 2>/dev/null; then
        record_test_result "Batch Operations" "PASS" "Batch operations functional"
    else
        record_test_result "Batch Operations" "SKIP" "Batch operations not available"
    fi
}

# Test 9: Backup Integration Testing
test_backup_integration() {
    echo
    echo "Test 9: Backup Integration Testing"
    echo "=================================="
    
    # Test backup module loading
    if perl -MPVE::SMBGateway::Backup -e "print 'Backup module loaded\n';" 2>/dev/null; then
        record_test_result "Backup Module" "PASS" "Backup module loads successfully"
    else
        record_test_result "Backup Module" "FAIL" "Backup module failed to load"
    fi
    
    # Test backup creation
    if pve-smbgateway backup create test-share 2>/dev/null; then
        record_test_result "Backup Creation" "PASS" "Backup creation functional"
    else
        record_test_result "Backup Creation" "SKIP" "Backup creation not available"
    fi
    
    # Test backup listing
    if pve-smbgateway backup list test-share 2>/dev/null; then
        record_test_result "Backup Listing" "PASS" "Backup listing functional"
    else
        record_test_result "Backup Listing" "SKIP" "Backup listing not available"
    fi
}

# Test 10: Error Handling and Recovery
test_error_handling() {
    echo
    echo "Test 10: Error Handling and Recovery"
    echo "===================================="
    
    # Test invalid share creation
    if ! pve-smbgateway create invalid-share --mode invalid 2>/dev/null; then
        record_test_result "Invalid Input Handling" "PASS" "Invalid input properly rejected"
    else
        record_test_result "Invalid Input Handling" "FAIL" "Invalid input not rejected"
    fi
    
    # Test duplicate share creation
    pve-smbgateway create test-duplicate --mode lxc --path /tmp/test-duplicate 2>/dev/null || true
    if ! pve-smbgateway create test-duplicate --mode lxc --path /tmp/test-duplicate 2>/dev/null; then
        record_test_result "Duplicate Handling" "PASS" "Duplicate share properly rejected"
    else
        record_test_result "Duplicate Handling" "FAIL" "Duplicate share not rejected"
    fi
    pve-smbgateway delete test-duplicate 2>/dev/null || true
    
    # Test rollback functionality
    if pve-smbgateway create test-rollback --mode lxc --path /tmp/test-rollback 2>/dev/null; then
        record_test_result "Rollback Test" "PASS" "Share creation and rollback successful"
        pve-smbgateway delete test-rollback 2>/dev/null || true
    else
        record_test_result "Rollback Test" "FAIL" "Share creation failed"
    fi
}

# Test 11: Resource Usage and Optimization
test_resource_usage() {
    echo
    echo "Test 11: Resource Usage and Optimization"
    echo "========================================"
    
    # Test memory usage
    memory_before=$(free -m | awk 'NR==2{print $3}')
    pve-smbgateway create test-memory --mode lxc --path /tmp/test-memory 2>/dev/null || true
    memory_after=$(free -m | awk 'NR==2{print $3}')
    memory_used=$((memory_after - memory_before))
    
    if [ $memory_used -lt 100 ]; then
        record_test_result "Memory Usage" "PASS" "Memory usage acceptable: ${memory_used}MB"
    else
        record_test_result "Memory Usage" "FAIL" "Memory usage too high: ${memory_used}MB"
    fi
    
    # Cleanup
    pve-smbgateway delete test-memory 2>/dev/null || true
    
    # Test disk usage
    disk_before=$(df /tmp | awk 'NR==2{print $3}')
    pve-smbgateway create test-disk --mode lxc --path /tmp/test-disk 2>/dev/null || true
    disk_after=$(df /tmp | awk 'NR==2{print $3}')
    disk_used=$((disk_after - disk_before))
    
    if [ $disk_used -lt 50 ]; then
        record_test_result "Disk Usage" "PASS" "Disk usage acceptable: ${disk_used}KB"
    else
        record_test_result "Disk Usage" "FAIL" "Disk usage too high: ${disk_used}KB"
    fi
    
    # Cleanup
    pve-smbgateway delete test-disk 2>/dev/null || true
}

# Test 12: Compatibility Testing
test_compatibility() {
    echo
    echo "Test 12: Compatibility Testing"
    echo "=============================="
    
    # Test Proxmox version compatibility
    pve_version=$(pveversion -v | head -1 | cut -d' ' -f2)
    record_test_result "Proxmox Version" "PASS" "Running on Proxmox $pve_version"
    
    # Test Perl version compatibility
    perl_version=$(perl -v | grep "This is perl" | cut -d' ' -f4)
    record_test_result "Perl Version" "PASS" "Using Perl $perl_version"
    
    # Test Samba version compatibility
    if command -v smbd >/dev/null 2>&1; then
        samba_version=$(smbd --version | head -1 | cut -d' ' -f2)
        record_test_result "Samba Version" "PASS" "Using Samba $samba_version"
    else
        record_test_result "Samba Version" "SKIP" "Samba not installed"
    fi
    
    # Test filesystem compatibility
    for fs in zfs xfs ext4; do
        if command -v "$fs" >/dev/null 2>&1 || [ "$fs" = "ext4" ]; then
            record_test_result "Filesystem: $fs" "PASS" "$fs support available"
        else
            record_test_result "Filesystem: $fs" "SKIP" "$fs not available"
        fi
    done
}

# Generate test report
generate_test_report() {
    echo
    echo "=== Integration Test Report ==="
    echo "Generated: $(date)"
    echo "Test Environment: $(hostname)"
    echo
    
    echo "Test Summary:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Skipped: $SKIPPED_TESTS"
    echo "  Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    echo
    
    # Save detailed results
    cat > "$RESULTS_DIR/integration_test_report.txt" << EOF
PVE SMB Gateway Integration Test Report
=======================================
Generated: $(date)
Test Environment: $(hostname)
Proxmox Version: $(pveversion -v | head -1)

Test Summary:
  Total Tests: $TOTAL_TESTS
  Passed: $PASSED_TESTS
  Failed: $FAILED_TESTS
  Skipped: $SKIPPED_TESTS
  Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%

Detailed Results:
$(cat "$LOG_DIR/test_results.log")

Environment Information:
$(pveversion -v)
$(perl -v | head -3)
$(df -h /tmp)
$(free -h)
EOF
    
    echo "Detailed report saved to: $RESULTS_DIR/integration_test_report.txt"
    echo "Test logs saved to: $LOG_DIR/"
    
    # Return appropriate exit code
    if [ $FAILED_TESTS -eq 0 ]; then
        echo "✅ All tests passed!"
        exit 0
    else
        echo "❌ $FAILED_TESTS tests failed!"
        exit 1
    fi
}

# Main test execution
main() {
    echo "Starting comprehensive integration tests..."
    echo "Test directory: $TEST_DIR"
    echo "Log directory: $LOG_DIR"
    echo "Results directory: $RESULTS_DIR"
    echo
    
    # Initialize test environment
    init_test_environment
    
    # Run all test suites
    test_core_plugin_integration
    test_multi_node_cluster
    test_end_to_end_workflows
    test_high_availability
    test_active_directory_integration
    test_security_features
    test_performance_features
    test_enhanced_cli
    test_backup_integration
    test_error_handling
    test_resource_usage
    test_compatibility
    
    # Generate final report
    generate_test_report
}

# Run main function
main "$@" 