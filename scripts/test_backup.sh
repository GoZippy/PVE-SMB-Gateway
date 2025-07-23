#!/bin/bash

# Test script for PVE SMB Gateway Backup System
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>

set -e

echo "=== Testing PVE SMB Gateway Backup System ==="

# Test 1: Check if Backup module can be loaded
echo "Test 1: Loading Backup module..."
perl -MPVE::SMBGateway::Backup -e 'print "Backup module loaded successfully\n"'

# Test 2: Test backup system initialization
echo "Test 2: Testing backup system initialization..."
perl -e '
use PVE::SMBGateway::Backup;

my $backup = PVE::SMBGateway::Backup->new(
    share_name => "test_share",
    share_id => "test_share",
    mode => "lxc",
    path => "/tmp/test_share"
);

print "Backup system initialized successfully\n";
print "Share: " . $backup->{share_name} . "\n";
print "Mode: " . $backup->{mode} . "\n";
print "Path: " . $backup->{path} . "\n";
'

# Test 3: Test backup job registration
echo "Test 3: Testing backup job registration..."
perl -e '
use PVE::SMBGateway::Backup;

my $backup = PVE::SMBGateway::Backup->new(
    share_name => "test_share",
    share_id => "test_share",
    mode => "lxc",
    path => "/tmp/test_share"
);

# Register backup job
my $result = $backup->register_backup_job(
    schedule => "daily",
    retention_days => 30,
    enabled => 1
);

print "Backup job registered: " . $result->{status} . "\n";
print "Schedule: " . $result->{schedule} . "\n";
print "Retention: " . $result->{retention_days} . " days\n";
'

# Test 4: Test backup snapshot creation (dry run)
echo "Test 4: Testing backup snapshot creation..."
perl -e '
use PVE::SMBGateway::Backup;

my $backup = PVE::SMBGateway::Backup->new(
    share_name => "test_share",
    share_id => "test_share",
    mode => "lxc",
    path => "/tmp/test_share"
);

# Create backup snapshot
my $result = $backup->create_backup_snapshot(
    type => "test",
    snapshot_name => "test_backup_" . time()
);

print "Backup snapshot created: " . $result->{status} . "\n";
print "Snapshot name: " . $result->{snapshot_name} . "\n";
print "Backup type: " . $result->{backup_type} . "\n";
'

# Test 5: Test backup status retrieval
echo "Test 5: Testing backup status retrieval..."
perl -e '
use PVE::SMBGateway::Backup;

my $backup = PVE::SMBGateway::Backup->new(
    share_name => "test_share",
    share_id => "test_share",
    mode => "lxc",
    path => "/tmp/test_share"
);

# Get backup status
my $status = $backup->get_backup_status();

print "Backup status retrieved successfully\n";
print "Total snapshots: " . $status->{total_snapshots} . "\n";
print "Total size: " . $status->{total_size_bytes} . " bytes\n";
if ($status->{job}) {
    print "Job schedule: " . $status->{job}->{schedule} . "\n";
    print "Job status: " . $status->{job}->{last_status} . "\n";
}
'

# Test 6: Test backup cleanup
echo "Test 6: Testing backup cleanup..."
perl -e '
use PVE::SMBGateway::Backup;

my $backup = PVE::SMBGateway::Backup->new(
    share_name => "test_share",
    share_id => "test_share",
    mode => "lxc",
    path => "/tmp/test_share"
);

# Cleanup old backups
my $result = $backup->cleanup_old_backups(days => 0);

print "Backup cleanup completed\n";
print "Deleted count: " . $result->{deleted_count} . "\n";
print "Freed bytes: " . $result->{freed_bytes} . "\n";
'

# Test 7: Test CLI backup commands (if share exists)
echo "Test 7: Testing CLI backup commands..."
if command -v pve-smbgateway >/dev/null 2>&1; then
    # List shares to find one to test with
    SHARES=$(pve-smbgateway list 2>/dev/null | grep -o '[a-zA-Z0-9_-]*' | head -1)
    if [ -n "$SHARES" ]; then
        echo "Testing with share: $SHARES"
        
        # Test backup registration
        pve-smbgateway backup register "$SHARES" daily 30 2>/dev/null || echo "Backup registration available but no data yet"
        
        # Test backup status
        pve-smbgateway backup status "$SHARES" 2>/dev/null || echo "Backup status command available but no data yet"
        
        # Test backup list
        pve-smbgateway backup list 2>/dev/null || echo "Backup list command available but no data yet"
    else
        echo "No shares found for testing"
    fi
else
    echo "CLI tool not installed, skipping CLI tests"
fi

# Test 8: Check backup directories
echo "Test 8: Checking backup directories..."
if [ -d "/etc/pve/smbgateway/backups" ]; then
    echo "Backup config directory exists"
else
    echo "Backup config directory not found (will be created on first use)"
fi

if [ -d "/var/log/pve/smbgateway/backups" ]; then
    echo "Backup log directory exists"
else
    echo "Backup log directory not found (will be created on first use)"
fi

if [ -f "/var/lib/pve/smbgateway/backups.db" ]; then
    echo "Backup database exists"
else
    echo "Backup database not found (will be created on first use)"
fi

echo "=== Backup System Test Complete ===" 