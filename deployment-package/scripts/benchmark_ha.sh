#!/bin/bash
# SMB Gateway HA Performance Benchmark Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-ha-benchmark.log"
SHARE_NAME=""
TEST_CLIENT=""
TEST_MOUNT_POINT="/mnt/smb-test"
TEST_DURATION=60
TEST_FILE_SIZE="1G"
FAILOVER_COUNT=3
VERBOSE=0
JSON_OUTPUT=0

# Function to log messages
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ $VERBOSE -eq 1 ]; then
        echo "[$timestamp] $1"
    fi
    echo "[$timestamp] $1" >> $LOG_FILE
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --share <name>       Share name to benchmark (required)"
    echo "  -c, --client <ip>        Test client IP address (required)"
    echo "  -m, --mount <path>       Test mount point (default: /mnt/smb-test)"
    echo "  -d, --duration <seconds> Test duration in seconds (default: 60)"
    echo "  -z, --size <size>        Size of test file (default: 1G)"
    echo "  -f, --failovers <count>  Number of failovers to test (default: 3)"
    echo "  -j, --json               Output results in JSON format"
    echo "  -v, --verbose            Enable verbose output"
    echo "  -h, --help               Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--share)
            SHARE_NAME="$2"
            shift
            shift
            ;;
        -c|--client)
            TEST_CLIENT="$2"
            shift
            shift
            ;;
        -m|--mount)
            TEST_MOUNT_POINT="$2"
            shift
            shift
            ;;
        -d|--duration)
            TEST_DURATION="$2"
            shift
            shift
            ;;
        -z|--size)
            TEST_FILE_SIZE="$2"
            shift
            shift
            ;;
        -f|--failovers)
            FAILOVER_COUNT="$2"
            shift
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check required parameters
if [ -z "$SHARE_NAME" ]; then
    echo "Error: Share name is required"
    usage
fi

if [ -z "$TEST_CLIENT" ]; then
    echo "Error: Test client IP address is required"
    usage
fi

# Initialize log file
echo "SMB Gateway HA Performance Benchmark" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Share: $SHARE_NAME" >> $LOG_FILE
echo "Client: $TEST_CLIENT" >> $LOG_FILE
echo "Duration: $TEST_DURATION seconds" >> $LOG_FILE
echo "File Size: $TEST_FILE_SIZE" >> $LOG_FILE
echo "Failover Count: $FAILOVER_COUNT" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

# Initialize results
declare -A results
results["baseline_read_mbps"]=0
results["baseline_write_mbps"]=0
results["failover_count"]=0
results["successful_failovers"]=0
results["average_failover_time"]=0
results["failover_read_mbps"]=0
results["failover_write_mbps"]=0
results["reconnect_time"]=0

# Get share status and VIP
log "Checking share status..."
SHARE_STATUS=$(pve-smbgateway status $SHARE_NAME 2>/dev/null || echo "error")
if [[ "$SHARE_STATUS" != *"active"* ]]; then
    log "Error: Share '$SHARE_NAME' is not active"
    exit 1
fi

# Get VIP status
log "Checking VIP status..."
VIP_STATUS=$(pve-smbgateway vip-status $SHARE_NAME 2>/dev/null || echo "error")
if [[ "$VIP_STATUS" != *"active"* ]]; then
    log "Error: VIP for share '$SHARE_NAME' is not active"
    exit 1
fi

# Extract VIP and active node
VIP=$(echo "$VIP_STATUS" | grep -oP '(?<=VIP )[0-9.]+' || echo "")
ACTIVE_NODE=$(echo "$VIP_STATUS" | grep -oP '(?<=Active node: )[^\n]*' || echo "")

if [ -z "$VIP" ] || [ -z "$ACTIVE_NODE" ]; then
    log "Error: Could not determine VIP or active node for share '$SHARE_NAME'"
    exit 1
fi

log "VIP: $VIP"
log "Active Node: $ACTIVE_NODE"

# Get list of cluster nodes
NODES=()
CLUSTER_STATUS=$(pvesh get /cluster/status -output-format=json 2>/dev/null || echo "")
if [ -n "$CLUSTER_STATUS" ]; then
    # Parse JSON output
    while read -r line; do
        if [[ "$line" =~ \"name\":\"([^\"]+)\" ]]; then
            NODE="${BASH_REMATCH[1]}"
            if [ "$NODE" != "$ACTIVE_NODE" ]; then
                NODES+=("$NODE")
            fi
        fi
    done <<< "$CLUSTER_STATUS"
fi

if [ ${#NODES[@]} -eq 0 ]; then
    log "Warning: No additional cluster nodes found for failover testing"
    exit 1
fi

log "Available failover nodes: ${NODES[*]}"

# Check if we can SSH to the client
log "Checking connection to test client..."
ssh -o BatchMode=yes -o ConnectTimeout=5 root@$TEST_CLIENT echo "Connected to test client" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log "Error: Cannot connect to test client at $TEST_CLIENT"
    exit 1
fi

# Install required packages on client
log "Installing required packages on test client..."
ssh root@$TEST_CLIENT "apt-get update && apt-get install -y cifs-utils fio" >> $LOG_FILE 2>&1

# Create mount point
ssh root@$TEST_CLIENT "mkdir -p $TEST_MOUNT_POINT" >> $LOG_FILE 2>&1

# Mount share
log "Mounting share on test client..."
ssh root@$TEST_CLIENT "umount $TEST_MOUNT_POINT 2>/dev/null || true" >> $LOG_FILE 2>&1
ssh root@$TEST_CLIENT "mount -t cifs //$VIP/$SHARE_NAME $TEST_MOUNT_POINT -o guest" >> $LOG_FILE 2>&1

# Run baseline performance test
log "Running baseline performance test..."
BASELINE_RESULTS=$(ssh root@$TEST_CLIENT "cd $TEST_MOUNT_POINT && fio --name=test --rw=readwrite --rwmixread=50 --size=$TEST_FILE_SIZE --time_based --runtime=$TEST_DURATION --ioengine=sync --direct=0 --bs=4k --numjobs=4 --group_reporting --output-format=json" 2>/dev/null)

# Extract baseline metrics
BASELINE_READ_BW=$(echo "$BASELINE_RESULTS" | grep -oP '"read":\s*{.*?"bw":\s*(\d+)' | grep -oP '\d+$')
BASELINE_WRITE_BW=$(echo "$BASELINE_RESULTS" | grep -oP '"write":\s*{.*?"bw":\s*(\d+)' | grep -oP '\d+$')

# Convert to MB/s
BASELINE_READ_MBPS=$(echo "scale=2; $BASELINE_READ_BW / 1024" | bc)
BASELINE_WRITE_MBPS=$(echo "scale=2; $BASELINE_WRITE_BW / 1024" | bc)

results["baseline_read_mbps"]=$BASELINE_READ_MBPS
results["baseline_write_mbps"]=$BASELINE_WRITE_MBPS

log "Baseline Read: $BASELINE_READ_MBPS MB/s"
log "Baseline Write: $BASELINE_WRITE_MBPS MB/s"

# Run failover tests
log "Running $FAILOVER_COUNT failover tests..."

TOTAL_FAILOVER_TIME=0
TOTAL_RECONNECT_TIME=0
SUCCESSFUL_FAILOVERS=0

for ((i=1; i<=$FAILOVER_COUNT; i++)); do
    log "Failover test $i of $FAILOVER_COUNT"
    
    # Select target node
    TARGET_NODE=${NODES[$(($i % ${#NODES[@]}))]}
    log "Failing over to $TARGET_NODE..."
    
    # Start continuous read/write in background
    ssh root@$TEST_CLIENT "cd $TEST_MOUNT_POINT && fio --name=test --rw=readwrite --rwmixread=50 --size=100M --time_based --runtime=300 --ioengine=sync --direct=0 --bs=4k --numjobs=2 --group_reporting --output-format=json > /tmp/fio_output.json &" >> $LOG_FILE 2>&1
    
    # Give it a moment to start
    sleep 2
    
    # Trigger failover and measure time
    FAILOVER_START=$(date +%s.%N)
    pve-smbgateway failover $SHARE_NAME $TARGET_NODE >> $LOG_FILE 2>&1
    
    # Wait for VIP to appear on target node
    FAILOVER_COMPLETE=0
    TIMEOUT=60
    ELAPSED=0
    
    while [ $FAILOVER_COMPLETE -eq 0 ] && [ $ELAPSED -lt $TIMEOUT ]; do
        VIP_STATUS=$(pve-smbgateway vip-status $SHARE_NAME 2>/dev/null || echo "")
        if [[ "$VIP_STATUS" == *"$TARGET_NODE"* ]]; then
            FAILOVER_COMPLETE=1
        else
            sleep 1
            ELAPSED=$((ELAPSED + 1))
        fi
    done
    
    FAILOVER_END=$(date +%s.%N)
    FAILOVER_TIME=$(echo "$FAILOVER_END - $FAILOVER_START" | bc)
    
    if [ $FAILOVER_COMPLETE -eq 1 ]; then
        log "Failover completed in $FAILOVER_TIME seconds"
        TOTAL_FAILOVER_TIME=$(echo "$TOTAL_FAILOVER_TIME + $FAILOVER_TIME" | bc)
        
        # Measure client reconnect time
        RECONNECT_START=$(date +%s.%N)
        RECONNECT_COMPLETE=0
        TIMEOUT=60
        ELAPSED=0
        
        while [ $RECONNECT_COMPLETE -eq 0 ] && [ $ELAPSED -lt $TIMEOUT ]; do
            CLIENT_ACCESS=$(ssh root@$TEST_CLIENT "ls -la $TEST_MOUNT_POINT 2>/dev/null | wc -l" 2>/dev/null || echo "0")
            if [ "$CLIENT_ACCESS" -gt "0" ]; then
                RECONNECT_COMPLETE=1
            else
                sleep 1
                ELAPSED=$((ELAPSED + 1))
            fi
        done
        
        RECONNECT_END=$(date +%s.%N)
        RECONNECT_TIME=$(echo "$RECONNECT_END - $RECONNECT_START" | bc)
        
        if [ $RECONNECT_COMPLETE -eq 1 ]; then
            log "Client reconnected in $RECONNECT_TIME seconds"
            TOTAL_RECONNECT_TIME=$(echo "$TOTAL_RECONNECT_TIME + $RECONNECT_TIME" | bc)
            SUCCESSFUL_FAILOVERS=$((SUCCESSFUL_FAILOVERS + 1))
        else
            log "Client failed to reconnect within timeout"
        fi
    else
        log "Failover did not complete within timeout"
    fi
    
    # Stop the background fio job
    ssh root@$TEST_CLIENT "pkill -f fio" >> $LOG_FILE 2>&1
    
    # Wait a moment before next test
    sleep 5
    
    # Update active node for next iteration
    ACTIVE_NODE=$TARGET_NODE
done

# Calculate averages
if [ $SUCCESSFUL_FAILOVERS -gt 0 ]; then
    AVG_FAILOVER_TIME=$(echo "scale=2; $TOTAL_FAILOVER_TIME / $SUCCESSFUL_FAILOVERS" | bc)
    AVG_RECONNECT_TIME=$(echo "scale=2; $TOTAL_RECONNECT_TIME / $SUCCESSFUL_FAILOVERS" | bc)
    
    results["failover_count"]=$FAILOVER_COUNT
    results["successful_failovers"]=$SUCCESSFUL_FAILOVERS
    results["average_failover_time"]=$AVG_FAILOVER_TIME
    results["reconnect_time"]=$AVG_RECONNECT_TIME
    
    log "Average failover time: $AVG_FAILOVER_TIME seconds"
    log "Average client reconnect time: $AVG_RECONNECT_TIME seconds"
else
    log "No successful failovers to calculate averages"
fi

# Run post-failover performance test
log "Running post-failover performance test..."
POST_RESULTS=$(ssh root@$TEST_CLIENT "cd $TEST_MOUNT_POINT && fio --name=test --rw=readwrite --rwmixread=50 --size=$TEST_FILE_SIZE --time_based --runtime=$TEST_DURATION --ioengine=sync --direct=0 --bs=4k --numjobs=4 --group_reporting --output-format=json" 2>/dev/null)

# Extract post-failover metrics
POST_READ_BW=$(echo "$POST_RESULTS" | grep -oP '"read":\s*{.*?"bw":\s*(\d+)' | grep -oP '\d+$')
POST_WRITE_BW=$(echo "$POST_RESULTS" | grep -oP '"write":\s*{.*?"bw":\s*(\d+)' | grep -oP '\d+$')

# Convert to MB/s
POST_READ_MBPS=$(echo "scale=2; $POST_READ_BW / 1024" | bc)
POST_WRITE_MBPS=$(echo "scale=2; $POST_WRITE_BW / 1024" | bc)

results["failover_read_mbps"]=$POST_READ_MBPS
results["failover_write_mbps"]=$POST_WRITE_MBPS

log "Post-failover Read: $POST_READ_MBPS MB/s"
log "Post-failover Write: $POST_WRITE_MBPS MB/s"

# Calculate performance impact
READ_IMPACT=$(echo "scale=2; 100 - ($POST_READ_MBPS * 100 / $BASELINE_READ_MBPS)" | bc)
WRITE_IMPACT=$(echo "scale=2; 100 - ($POST_WRITE_MBPS * 100 / $BASELINE_WRITE_MBPS)" | bc)

results["read_impact_percent"]=$READ_IMPACT
results["write_impact_percent"]=$WRITE_IMPACT

log "Read performance impact: $READ_IMPACT%"
log "Write performance impact: $WRITE_IMPACT%"

# Clean up
log "Cleaning up..."
ssh root@$TEST_CLIENT "umount $TEST_MOUNT_POINT" >> $LOG_FILE 2>&1 || true

# Output results
if [ $JSON_OUTPUT -eq 1 ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"share\": \"$SHARE_NAME\","
    echo "  \"vip\": \"$VIP\","
    echo "  \"baseline_performance\": {"
    echo "    \"read_mbps\": ${results["baseline_read_mbps"]},"
    echo "    \"write_mbps\": ${results["baseline_write_mbps"]}"
    echo "  },"
    echo "  \"failover_tests\": {"
    echo "    \"count\": ${results["failover_count"]},"
    echo "    \"successful\": ${results["successful_failovers"]},"
    echo "    \"average_time_seconds\": ${results["average_failover_time"]},"
    echo "    \"client_reconnect_seconds\": ${results["reconnect_time"]}"
    echo "  },"
    echo "  \"post_failover_performance\": {"
    echo "    \"read_mbps\": ${results["failover_read_mbps"]},"
    echo "    \"write_mbps\": ${results["failover_write_mbps"]},"
    echo "    \"read_impact_percent\": ${results["read_impact_percent"]},"
    echo "    \"write_impact_percent\": ${results["write_impact_percent"]}"
    echo "  }"
    echo "}"
else
    echo "HA Performance Benchmark Results for $SHARE_NAME"
    echo "------------------------------------------------"
    echo "Baseline Performance:"
    echo "  Read: ${results["baseline_read_mbps"]} MB/s"
    echo "  Write: ${results["baseline_write_mbps"]} MB/s"
    echo ""
    echo "Failover Tests:"
    echo "  Total: ${results["failover_count"]}"
    echo "  Successful: ${results["successful_failovers"]}"
    echo "  Average Time: ${results["average_failover_time"]} seconds"
    echo "  Client Reconnect Time: ${results["reconnect_time"]} seconds"
    echo ""
    echo "Post-Failover Performance:"
    echo "  Read: ${results["failover_read_mbps"]} MB/s (${results["read_impact_percent"]}% impact)"
    echo "  Write: ${results["failover_write_mbps"]} MB/s (${results["write_impact_percent"]}% impact)"
    echo ""
    echo "Detailed log available at: $LOG_FILE"
fi

exit 0