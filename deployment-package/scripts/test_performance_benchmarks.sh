#!/bin/bash

# Performance Benchmarking Suite for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Comprehensive performance testing and optimization

set -e

echo "=== PVE SMB Gateway Performance Benchmarking Suite ==="
echo "Testing performance across all deployment modes and scenarios"
echo

# Configuration
BENCHMARK_DIR="/tmp/pve-smbgateway-benchmarks"
RESULTS_DIR="$BENCHMARK_DIR/results"
LOG_DIR="$BENCHMARK_DIR/logs"
TEST_DATA_SIZE="100M"
CONCURRENT_CLIENTS=5
TEST_DURATION=60

# Performance targets
TARGET_CREATION_TIME=30      # seconds
TARGET_IO_THROUGHPUT=50      # MB/s
TARGET_MEMORY_USAGE=100      # MB
TARGET_CPU_USAGE=10          # percent

# Initialize benchmark environment
init_benchmark_environment() {
    echo "Initializing benchmark environment..."
    
    # Create benchmark directories
    mkdir -p "$BENCHMARK_DIR" "$RESULTS_DIR" "$LOG_DIR"
    
    # Clean up previous benchmarks
    rm -rf "$BENCHMARK_DIR"/*
    mkdir -p "$RESULTS_DIR" "$LOG_DIR"
    
    # Install benchmark tools
    sudo apt-get update
    sudo apt-get install -y iozone3 fio sysbench stress-ng
    
    echo "✓ Benchmark environment initialized"
}

# Record benchmark result
record_benchmark_result() {
    local test_name="$1"
    local metric="$2"
    local value="$3"
    local unit="$4"
    local target="$5"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $test_name | $metric | $value $unit | Target: $target $unit" >> "$LOG_DIR/benchmark_results.log"
    
    # Check if target is met
    if [ -n "$target" ]; then
        if (( $(echo "$value <= $target" | bc -l) )); then
            echo "✅ $test_name: $metric = $value $unit (Target: $target $unit)"
        else
            echo "❌ $test_name: $metric = $value $unit (Target: $target $unit)"
        fi
    else
        echo "📊 $test_name: $metric = $value $unit"
    fi
}

# Benchmark 1: Share Creation Performance
benchmark_share_creation() {
    echo
    echo "Benchmark 1: Share Creation Performance"
    echo "======================================="
    
    # Test LXC mode creation time
    echo "Testing LXC mode share creation..."
    start_time=$(date +%s.%N)
    pve-smbgateway create benchmark-lxc --mode lxc --path /tmp/benchmark-lxc --quota 1G 2>/dev/null
    end_time=$(date +%s.%N)
    creation_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "LXC Creation" "Time" "$creation_time" "seconds" "$TARGET_CREATION_TIME"
    
    # Test Native mode creation time
    echo "Testing Native mode share creation..."
    start_time=$(date +%s.%N)
    pve-smbgateway create benchmark-native --mode native --path /tmp/benchmark-native --quota 1G 2>/dev/null
    end_time=$(date +%s.%N)
    creation_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Native Creation" "Time" "$creation_time" "seconds" "$TARGET_CREATION_TIME"
    
    # Test VM mode creation time (if available)
    echo "Testing VM mode share creation..."
    start_time=$(date +%s.%N)
    if pve-smbgateway create benchmark-vm --mode vm --path /tmp/benchmark-vm --quota 1G --vm-memory 1024 2>/dev/null; then
        end_time=$(date +%s.%N)
        creation_time=$(echo "$end_time - $start_time" | bc -l)
        record_benchmark_result "VM Creation" "Time" "$creation_time" "seconds" "120"
    else
        record_benchmark_result "VM Creation" "Time" "N/A" "seconds" "N/A"
    fi
}

# Benchmark 2: I/O Performance Testing
benchmark_io_performance() {
    echo
    echo "Benchmark 2: I/O Performance Testing"
    echo "===================================="
    
    # Test LXC mode I/O performance
    echo "Testing LXC mode I/O performance..."
    if pve-smbgateway status benchmark-lxc >/dev/null 2>&1; then
        # Get share path
        share_path=$(pve-smbgateway status benchmark-lxc --json 2>/dev/null | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$share_path" ]; then
            # Run fio benchmark
            fio --name=benchmark-lxc --directory="$share_path" --size="$TEST_DATA_SIZE" \
                --numjobs=4 --time_based --runtime="$TEST_DURATION" --ramp_time=2 \
                --ioengine=libaio --direct=1 --verify=0 --bs=1M --iodepth=64 \
                --rw=write --group_reporting > "$RESULTS_DIR/lxc_io_results.txt"
            
            # Extract throughput
            throughput=$(grep "WRITE:" "$RESULTS_DIR/lxc_io_results.txt" | awk '{print $2}' | sed 's/MB\/s//')
            record_benchmark_result "LXC I/O" "Throughput" "$throughput" "MB/s" "$TARGET_IO_THROUGHPUT"
        fi
    fi
    
    # Test Native mode I/O performance
    echo "Testing Native mode I/O performance..."
    if pve-smbgateway status benchmark-native >/dev/null 2>&1; then
        # Get share path
        share_path=$(pve-smbgateway status benchmark-native --json 2>/dev/null | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$share_path" ]; then
            # Run fio benchmark
            fio --name=benchmark-native --directory="$share_path" --size="$TEST_DATA_SIZE" \
                --numjobs=4 --time_based --runtime="$TEST_DURATION" --ramp_time=2 \
                --ioengine=libaio --direct=1 --verify=0 --bs=1M --iodepth=64 \
                --rw=write --group_reporting > "$RESULTS_DIR/native_io_results.txt"
            
            # Extract throughput
            throughput=$(grep "WRITE:" "$RESULTS_DIR/native_io_results.txt" | awk '{print $2}' | sed 's/MB\/s//')
            record_benchmark_result "Native I/O" "Throughput" "$throughput" "MB/s" "$TARGET_IO_THROUGHPUT"
        fi
    fi
}

# Benchmark 3: Resource Usage Testing
benchmark_resource_usage() {
    echo
    echo "Benchmark 3: Resource Usage Testing"
    echo "==================================="
    
    # Test memory usage
    echo "Testing memory usage..."
    
    # LXC mode memory usage
    if pve-smbgateway status benchmark-lxc >/dev/null 2>&1; then
        # Get container ID
        container_id=$(pve-smbgateway status benchmark-lxc --json 2>/dev/null | grep -o '"container_id":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$container_id" ]; then
            memory_usage=$(pct status "$container_id" 2>/dev/null | grep "memory" | awk '{print $2}' | sed 's/M//')
            record_benchmark_result "LXC Memory" "Usage" "$memory_usage" "MB" "$TARGET_MEMORY_USAGE"
        fi
    fi
    
    # Native mode memory usage
    memory_usage=$(ps aux | grep smbd | grep -v grep | awk '{sum+=$6} END {print sum/1024}')
    record_benchmark_result "Native Memory" "Usage" "$memory_usage" "MB" "$TARGET_MEMORY_USAGE"
    
    # Test CPU usage
    echo "Testing CPU usage..."
    
    # Monitor CPU usage for 30 seconds
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    record_benchmark_result "System CPU" "Usage" "$cpu_usage" "%" "$TARGET_CPU_USAGE"
}

# Benchmark 4: Concurrent Access Testing
benchmark_concurrent_access() {
    echo
    echo "Benchmark 4: Concurrent Access Testing"
    echo "======================================"
    
    # Test concurrent SMB connections
    echo "Testing concurrent SMB connections..."
    
    # Create test data
    dd if=/dev/zero of=/tmp/test_data bs=1M count=100 2>/dev/null
    
    # Test concurrent read operations
    start_time=$(date +%s)
    for i in $(seq 1 $CONCURRENT_CLIENTS); do
        (cp /tmp/test_data "/tmp/benchmark-lxc/concurrent_test_$i" 2>/dev/null) &
    done
    wait
    end_time=$(date +%s)
    concurrent_time=$((end_time - start_time))
    
    record_benchmark_result "Concurrent Access" "Time" "$concurrent_time" "seconds" "30"
    
    # Clean up test data
    rm -f /tmp/test_data
    rm -f /tmp/benchmark-lxc/concurrent_test_*
}

# Benchmark 5: Network Performance Testing
benchmark_network_performance() {
    echo
    echo "Benchmark 5: Network Performance Testing"
    echo "========================================"
    
    # Test SMB network performance
    echo "Testing SMB network performance..."
    
    # Get local IP address
    local_ip=$(hostname -I | awk '{print $1}')
    
    # Test SMB transfer performance
    start_time=$(date +%s.%N)
    dd if=/dev/zero bs=1M count=100 2>/dev/null | smbclient //localhost/benchmark-lxc -U guest% -c "put - /network_test" 2>/dev/null
    end_time=$(date +%s.%N)
    transfer_time=$(echo "$end_time - $start_time" | bc -l)
    
    # Calculate throughput (100MB / time)
    throughput=$(echo "100 / $transfer_time" | bc -l)
    record_benchmark_result "Network Transfer" "Throughput" "$throughput" "MB/s" "$TARGET_IO_THROUGHPUT"
    
    # Clean up
    smbclient //localhost/benchmark-lxc -U guest% -c "del network_test" 2>/dev/null || true
}

# Benchmark 6: Quota Performance Testing
benchmark_quota_performance() {
    echo
    echo "Benchmark 6: Quota Performance Testing"
    echo "======================================"
    
    # Test quota enforcement performance
    echo "Testing quota enforcement performance..."
    
    # Test quota status check performance
    start_time=$(date +%s.%N)
    for i in $(seq 1 100); do
        pve-smbgateway status benchmark-lxc >/dev/null 2>&1
    done
    end_time=$(date +%s.%N)
    quota_check_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Quota Check" "Time" "$quota_check_time" "seconds" "5"
    
    # Test quota enforcement
    start_time=$(date +%s.%N)
    dd if=/dev/zero of="/tmp/benchmark-lxc/quota_test" bs=1M count=2000 2>/dev/null || true
    end_time=$(date +%s.%N)
    quota_enforcement_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Quota Enforcement" "Time" "$quota_enforcement_time" "seconds" "10"
    
    # Clean up
    rm -f /tmp/benchmark-lxc/quota_test
}

# Benchmark 7: Monitoring Performance Testing
benchmark_monitoring_performance() {
    echo
    echo "Benchmark 7: Monitoring Performance Testing"
    echo "==========================================="
    
    # Test metrics collection performance
    echo "Testing metrics collection performance..."
    
    # Test metrics collection time
    start_time=$(date +%s.%N)
    pve-smbgateway metrics current benchmark-lxc >/dev/null 2>&1
    end_time=$(date +%s.%N)
    metrics_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Metrics Collection" "Time" "$metrics_time" "seconds" "1"
    
    # Test historical metrics query
    start_time=$(date +%s.%N)
    pve-smbgateway metrics history benchmark-lxc --hours 24 >/dev/null 2>&1
    end_time=$(date +%s.%N)
    history_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Historical Metrics" "Time" "$history_time" "seconds" "5"
}

# Benchmark 8: CLI Performance Testing
benchmark_cli_performance() {
    echo
    echo "Benchmark 8: CLI Performance Testing"
    echo "===================================="
    
    # Test CLI command performance
    echo "Testing CLI command performance..."
    
    # Test list command performance
    start_time=$(date +%s.%N)
    pve-smbgateway list >/dev/null 2>&1
    end_time=$(date +%s.%N)
    list_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "CLI List" "Time" "$list_time" "seconds" "1"
    
    # Test enhanced CLI performance
    if [ -f "/usr/sbin/pve-smbgateway-enhanced" ]; then
        start_time=$(date +%s.%N)
        pve-smbgateway-enhanced list --json >/dev/null 2>&1
        end_time=$(date +%s.%N)
        enhanced_time=$(echo "$end_time - $start_time" | bc -l)
        
        record_benchmark_result "Enhanced CLI" "Time" "$enhanced_time" "seconds" "1"
    fi
}

# Benchmark 9: Stress Testing
benchmark_stress_testing() {
    echo
    echo "Benchmark 9: Stress Testing"
    echo "==========================="
    
    # Test system under stress
    echo "Testing system under stress..."
    
    # Run stress test for 30 seconds
    start_time=$(date +%s)
    stress-ng --cpu 2 --io 2 --vm 1 --vm-bytes 256M --timeout 30s >/dev/null 2>&1 &
    stress_pid=$!
    
    # During stress, test share operations
    for i in $(seq 1 10); do
        pve-smbgateway status benchmark-lxc >/dev/null 2>&1
        sleep 1
    done
    
    wait $stress_pid
    end_time=$(date +%s)
    stress_time=$((end_time - start_time))
    
    record_benchmark_result "Stress Test" "Duration" "$stress_time" "seconds" "30"
}

# Benchmark 10: Scalability Testing
benchmark_scalability() {
    echo
    echo "Benchmark 10: Scalability Testing"
    echo "================================="
    
    # Test with multiple shares
    echo "Testing scalability with multiple shares..."
    
    # Create multiple shares
    start_time=$(date +%s.%N)
    for i in $(seq 1 5); do
        pve-smbgateway create "benchmark-scale-$i" --mode lxc --path "/tmp/benchmark-scale-$i" --quota 1G 2>/dev/null &
    done
    wait
    end_time=$(date +%s.%N)
    scale_creation_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Scalability Creation" "Time" "$scale_creation_time" "seconds" "60"
    
    # Test listing multiple shares
    start_time=$(date +%s.%N)
    pve-smbgateway list >/dev/null 2>&1
    end_time=$(date +%s.%N)
    scale_list_time=$(echo "$end_time - $start_time" | bc -l)
    
    record_benchmark_result "Scalability List" "Time" "$scale_list_time" "seconds" "5"
    
    # Clean up scalability test shares
    for i in $(seq 1 5); do
        pve-smbgateway delete "benchmark-scale-$i" 2>/dev/null || true
    done
}

# Generate performance report
generate_performance_report() {
    echo
    echo "=== Performance Benchmark Report ==="
    echo "Generated: $(date)"
    echo "Test Environment: $(hostname)"
    echo "Proxmox Version: $(pveversion -v | head -1)"
    echo
    
    # Calculate summary statistics
    total_tests=$(wc -l < "$LOG_DIR/benchmark_results.log")
    passed_tests=$(grep -c "✅" "$LOG_DIR/benchmark_results.log" || echo "0")
    failed_tests=$(grep -c "❌" "$LOG_DIR/benchmark_results.log" || echo "0")
    
    echo "Performance Summary:"
    echo "  Total Benchmarks: $total_tests"
    echo "  Targets Met: $passed_tests"
    echo "  Targets Missed: $failed_tests"
    echo "  Success Rate: $((passed_tests * 100 / total_tests))%"
    echo
    
    # Save detailed report
    cat > "$RESULTS_DIR/performance_report.txt" << EOF
PVE SMB Gateway Performance Benchmark Report
============================================
Generated: $(date)
Test Environment: $(hostname)
Proxmox Version: $(pveversion -v | head -1)

Performance Summary:
  Total Benchmarks: $total_tests
  Targets Met: $passed_tests
  Targets Missed: $failed_tests
  Success Rate: $((passed_tests * 100 / total_tests))%

Detailed Results:
$(cat "$LOG_DIR/benchmark_results.log")

System Information:
$(pveversion -v)
$(free -h)
$(df -h /tmp)
$(lscpu | head -10)

Performance Recommendations:
$(generate_performance_recommendations)
EOF
    
    echo "Detailed report saved to: $RESULTS_DIR/performance_report.txt"
    echo "Benchmark logs saved to: $LOG_DIR/"
    
    # Return appropriate exit code
    if [ $failed_tests -eq 0 ]; then
        echo "✅ All performance targets met!"
        exit 0
    else
        echo "❌ $failed_tests performance targets not met!"
        exit 1
    fi
}

# Generate performance recommendations
generate_performance_recommendations() {
    cat << EOF
1. **Share Creation Performance**
   - LXC mode: Fastest creation time, recommended for most use cases
   - Native mode: Good for high-performance requirements
   - VM mode: Highest isolation but slower creation

2. **I/O Performance Optimization**
   - Use ZFS for best performance
   - Enable compression for better throughput
   - Consider SSD storage for high I/O workloads

3. **Resource Usage Optimization**
   - Monitor memory usage during peak loads
   - Adjust container memory limits as needed
   - Use resource quotas for better control

4. **Network Performance**
   - Use 10GbE networking for high-throughput scenarios
   - Optimize SMB protocol settings
   - Consider jumbo frames for large transfers

5. **Monitoring Performance**
   - Metrics collection has minimal overhead
   - Historical queries scale well
   - Consider external monitoring for large deployments

6. **Scalability Considerations**
   - Multiple shares scale linearly
   - Resource usage increases proportionally
   - Consider load balancing for high-availability scenarios
EOF
}

# Cleanup function
cleanup_benchmarks() {
    echo "Cleaning up benchmark environment..."
    
    # Delete test shares
    pve-smbgateway delete benchmark-lxc 2>/dev/null || true
    pve-smbgateway delete benchmark-native 2>/dev/null || true
    pve-smbgateway delete benchmark-vm 2>/dev/null || true
    
    # Clean up test directories
    rm -rf /tmp/benchmark-*
    
    echo "✓ Cleanup completed"
}

# Main benchmark execution
main() {
    echo "Starting comprehensive performance benchmarks..."
    echo "Benchmark directory: $BENCHMARK_DIR"
    echo "Results directory: $RESULTS_DIR"
    echo "Log directory: $LOG_DIR"
    echo
    
    # Initialize benchmark environment
    init_benchmark_environment
    
    # Run all benchmarks
    benchmark_share_creation
    benchmark_io_performance
    benchmark_resource_usage
    benchmark_concurrent_access
    benchmark_network_performance
    benchmark_quota_performance
    benchmark_monitoring_performance
    benchmark_cli_performance
    benchmark_stress_testing
    benchmark_scalability
    
    # Generate final report
    generate_performance_report
    
    # Cleanup
    cleanup_benchmarks
}

# Handle script interruption
trap cleanup_benchmarks EXIT

# Run main function
main "$@" 