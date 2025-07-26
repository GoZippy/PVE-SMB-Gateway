#!/bin/bash
# SMB Gateway HA Failover Testing Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
LOG_FILE="/var/log/smb-gateway-ha-test.log"
SHARE_NAME=""
TARGET_NODE=""
SOURCE_NODE=$(hostname)
TEST_CLIENT=""
TEST_MOUNT_POINT="/mnt/smb-test"
TEST_FILE_COUNT=100
TEST_FILE_SIZE="1M"
FAILOVER_DELAY=5
VERBOSE=0

# Function to log messages
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a $LOG_FILE
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --share <name>       Share name to test (required)"
    echo "  -t, --target <node>      Target node for failover (required)"
    echo "  -c, --client <ip>        Test client IP address (optional)"
    echo "  -m, --mount <path>       Test mount point (default: /mnt/smb-test)"
    echo "  -f, --files <count>      Number of test files (default: 100)"
    echo "  -z, --size <size>        Size of test files (default: 1M)"
    echo "  -d, --delay <seconds>    Delay between failover steps (default: 5)"
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
        -t|--target)
            TARGET_NODE="$2"
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
        -f|--files)
            TEST_FILE_COUNT="$2"
            shift
            shift
            ;;
        -z|--size)
            TEST_FILE_SIZE="$2"
            shift
            shift
            ;;
        -d|--delay)
            FAILOVER_DELAY="$2"
            shift
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

if [ -z "$TARGET_NODE" ]; then
    echo "Error: Target node is required"
    usage
fi

# Initialize log file
echo "SMB Gateway HA Failover Test" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Share: $SHARE_NAME" >> $LOG_FILE
echo "Source Node: $SOURCE_NODE" >> $LOG_FILE
echo "Target Node: $TARGET_NODE" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

log "Starting HA failover test for share '$SHARE_NAME'"

# Get share status
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

# Extract VIP from status
VIP=$(echo "$VIP_STATUS" | grep -oP '(?<=VIP status for share)[^:]*' | tr -d ' ')
if [ -z "$VIP" ]; then
    log "Error: Could not determine VIP for share '$SHARE_NAME'"
    exit 1
fi

log "VIP: $VIP"

# If test client is provided, run client-side tests
if [ -n "$TEST_CLIENT" ]; then
    log "Setting up test client at $TEST_CLIENT..."
    
    # Check if we can SSH to the client
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@$TEST_CLIENT echo "Connected to test client" >> $LOG_FILE 2>&1
    if [ $? -ne 0 ]; then
        log "Error: Cannot connect to test client at $TEST_CLIENT"
        exit 1
    }
    
    # Install required packages on client
    log "Installing required packages on test client..."
    ssh root@$TEST_CLIENT "apt-get update && apt-get install -y cifs-utils fio" >> $LOG_FILE 2>&1
    
    # Create mount point
    ssh root@$TEST_CLIENT "mkdir -p $TEST_MOUNT_POINT" >> $LOG_FILE 2>&1
    
    # Mount share
    log "Mounting share on test client..."
    ssh root@$TEST_CLIENT "mount -t cifs //$VIP/$SHARE_NAME $TEST_MOUNT_POINT -o guest" >> $LOG_FILE 2>&1
    
    # Create test files
    log "Creating $TEST_FILE_COUNT test files of size $TEST_FILE_SIZE..."
    ssh root@$TEST_CLIENT "cd $TEST_MOUNT_POINT && fio --name=test --rw=write --size=$TEST_FILE_SIZE --numjobs=$TEST_FILE_COUNT --end_fsync=1" >> $LOG_FILE 2>&1
    
    # Start continuous read test in background
    log "Starting continuous read test..."
    ssh root@$TEST_CLIENT "cd $TEST_MOUNT_POINT && while true; do find . -type f -exec cat {} > /dev/null \; ; sleep 1; done" >> $LOG_FILE 2>&1 &
    CLIENT_PID=$!
    
    # Give the client time to start reading
    sleep 2
fi

# Trigger failover
log "Triggering failover to $TARGET_NODE..."
FAILOVER_START=$(date +%s)
pve-smbgateway failover $SHARE_NAME $TARGET_NODE >> $LOG_FILE 2>&1

# Wait for failover to complete
log "Waiting $FAILOVER_DELAY seconds for failover to complete..."
sleep $FAILOVER_DELAY

# Check VIP status after failover
log "Checking VIP status after failover..."
VIP_STATUS_AFTER=$(pve-smbgateway vip-status $SHARE_NAME 2>/dev/null || echo "error")
if [[ "$VIP_STATUS_AFTER" != *"$TARGET_NODE"* ]]; then
    log "Error: Failover to $TARGET_NODE failed"
    exit 1
fi

FAILOVER_END=$(date +%s)
FAILOVER_TIME=$((FAILOVER_END - FAILOVER_START))
log "Failover completed in $FAILOVER_TIME seconds"

# If test client is provided, verify client access after failover
if [ -n "$TEST_CLIENT" ]; then
    log "Verifying client access after failover..."
    
    # Check if client can still access the share
    CLIENT_ACCESS=$(ssh root@$TEST_CLIENT "ls -la $TEST_MOUNT_POINT 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    if [ "$CLIENT_ACCESS" -eq "0" ]; then
        log "Error: Client lost access to share after failover"
    else
        log "Client maintained access to share after failover"
    }
    
    # Stop continuous read test
    if [ -n "$CLIENT_PID" ]; then
        kill $CLIENT_PID 2>/dev/null || true
    }
    
    # Unmount share
    log "Unmounting share from test client..."
    ssh root@$TEST_CLIENT "umount $TEST_MOUNT_POINT" >> $LOG_FILE 2>&1 || true
fi

# Trigger failover back to source node
log "Triggering failover back to $SOURCE_NODE..."
pve-smbgateway failover $SHARE_NAME $SOURCE_NODE >> $LOG_FILE 2>&1

# Wait for failover to complete
log "Waiting $FAILOVER_DELAY seconds for failover to complete..."
sleep $FAILOVER_DELAY

# Check VIP status after failover back
log "Checking VIP status after failover back..."
VIP_STATUS_FINAL=$(pve-smbgateway vip-status $SHARE_NAME 2>/dev/null || echo "error")
if [[ "$VIP_STATUS_FINAL" != *"$SOURCE_NODE"* ]]; then
    log "Error: Failover back to $SOURCE_NODE failed"
    exit 1
fi

log "HA failover test completed successfully"
log "See $LOG_FILE for detailed log"

exit 0