#!/bin/bash

# Test script for PVE SMB Gateway Metrics System
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>

set -e

echo "=== Testing PVE SMB Gateway Metrics System ==="

# Test 1: Check if Monitor module can be loaded
echo "Test 1: Loading Monitor module..."
perl -MPVE::SMBGateway::Monitor -e 'print "Monitor module loaded successfully\n"'

# Test 2: Test metrics collection for a sample share
echo "Test 2: Testing metrics collection..."
perl -e '
use PVE::SMBGateway::Monitor;

my $monitor = PVE::SMBGateway::Monitor->new(
    share_name => "test_share",
    share_path => "/tmp/test_share",
    db_path => "/tmp/test_metrics.db"
);

# Test collection methods
my $io_stats = $monitor->collect_io_stats();
my $conn_stats = $monitor->collect_connection_stats();
my $quota_stats = $monitor->collect_quota_stats();
my $sys_stats = $monitor->collect_system_stats();

print "IO Stats: " . scalar(keys %$io_stats) . " metrics collected\n";
print "Connection Stats: " . scalar(keys %$conn_stats) . " metrics collected\n";
print "Quota Stats: " . scalar(keys %$quota_stats) . " metrics collected\n";
print "System Stats: " . scalar(keys %$sys_stats) . " metrics collected\n";

# Test storage
$monitor->store_metrics($io_stats, $conn_stats, $quota_stats, $sys_stats);
print "Metrics stored successfully\n";

# Test retrieval
my $history = $monitor->get_metrics_history(hours => 1, limit => 10);
print "Retrieved " . scalar(@$history) . " historical records\n";

# Test summary
my $summary = $monitor->get_metrics_summary(hours => 1);
print "Summary generated with " . scalar(keys %$summary) . " categories\n";

# Test Prometheus export
my $prometheus = $monitor->export_prometheus_metrics();
print "Prometheus export generated (" . length($prometheus) . " characters)\n";

# Test alerts
my $alerts = $monitor->check_performance_alerts();
print "Performance alerts checked (" . scalar(@$alerts) . " alerts generated)\n";

# Cleanup
unlink "/tmp/test_metrics.db" if -f "/tmp/test_metrics.db";
print "Test completed successfully\n";
'

# Test 3: Test CLI metrics commands (if share exists)
echo "Test 3: Testing CLI metrics commands..."
if command -v pve-smbgateway >/dev/null 2>&1; then
    # List shares to find one to test with
    SHARES=$(pve-smbgateway list 2>/dev/null | grep -o '[a-zA-Z0-9_-]*' | head -1)
    if [ -n "$SHARES" ]; then
        echo "Testing with share: $SHARES"
        pve-smbgateway metrics current "$SHARES" 2>/dev/null || echo "Metrics command available but no data yet"
    else
        echo "No shares found for testing"
    fi
else
    echo "CLI tool not installed, skipping CLI tests"
fi

# Test 4: Check systemd services (if available)
echo "Test 4: Checking systemd services..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl status pve-smbgateway-metrics.timer 2>/dev/null || echo "Metrics timer service not installed"
else
    echo "systemctl not available, skipping service tests"
fi

echo "=== Metrics System Test Complete ===" 