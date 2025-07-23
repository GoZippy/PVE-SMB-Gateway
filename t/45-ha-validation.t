#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;

# Mock PVE::Tools to avoid actual command execution
my $mock_tools = Test::MockModule->new('PVE::Tools');
$mock_tools->mock('run_command', sub {
    my ($cmd, %opts) = @_;
    # Log the command for verification
    push @{$mock_tools->{called_commands}}, $cmd;
    return 1;
});

# Mock system commands
my $mock_system = Test::MockModule->new('CORE::GLOBAL');
$mock_system->mock('system', sub { return 0; });
$mock_system->mock('backtick', sub { 
    my ($cmd) = @_;
    if ($cmd =~ /hostname/) {
        return "testnode\n";
    } elsif ($cmd =~ /pvesh get \/cluster\/status/) {
        return "{\n  \"name\": \"testnode\",\n  \"status\": \"online\"\n},\n{\n  \"name\": \"testnode2\",\n  \"status\": \"online\"\n}\n";
    } elsif ($cmd =~ /ctdb status/) {
        return "OK: ctdb is healthy\n";
    } elsif ($cmd =~ /ctdb nodestatus/) {
        return "0 testnode OK\n1 testnode2 OK\n";
    } elsif ($cmd =~ /ip addr/) {
        return "inet 192.168.1.5/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
    } elsif ($cmd =~ /systemctl is-active smbd/) {
        return "active\n";
    } elsif ($cmd =~ /ping -c 1/) {
        return "64 bytes from 192.168.1.100: icmp_seq=1 ttl=64 time=0.123 ms\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test HA validation framework
subtest 'HA validation framework' => sub {
    # Test script existence
    ok(-f "scripts/test_ha_failover.sh", "HA failover test script should exist");
    ok(-f "scripts/check_ha_health.sh", "HA health check script should exist");
    ok(-f "scripts/benchmark_ha.sh", "HA benchmark script should exist");
    
    # Test script permissions
    # Note: On Windows, we can't test file permissions directly
    # so we'll skip this part of the test
    
    # Test script content
    my $failover_script = `cat scripts/test_ha_failover.sh 2>/dev/null`;
    like($failover_script, qr/SMB Gateway HA Failover Test/, "Failover script should contain expected content");
    
    my $health_script = `cat scripts/check_ha_health.sh 2>/dev/null`;
    like($health_script, qr/SMB Gateway HA Health Check/, "Health check script should contain expected content");
    
    my $benchmark_script = `cat scripts/benchmark_ha.sh 2>/dev/null`;
    like($benchmark_script, qr/SMB Gateway HA Performance Benchmark/, "Benchmark script should contain expected content");
};

# Test HA status monitoring
subtest 'HA status monitoring' => sub {
    # Create a test configuration with HA enabled
    my $test_scfg = {
        mode => 'lxc',
        sharename => 'testshare',
        path => '/srv/smb/testshare',
        ha_enabled => 1,
        ctdb_vip => '192.168.1.100',
        ha_nodes => 'testnode,testnode2'
    };
    
    # Test status method with HA information
    my $status = $module->status('teststorage', $test_scfg);
    
    ok(ref($status) eq 'HASH', 'Status should be a hash reference');
    is($status->{ha_enabled}, 1, 'Status should indicate HA is enabled');
    ok(exists($status->{ctdb_status}), 'Status should include CTDB status');
    
    # Test VIP monitoring
    my $vip_status = $instance->_monitor_vip_health('192.168.1.100', ['testnode', 'testnode2']);
    
    ok(ref($vip_status) eq 'HASH', 'VIP status should be a hash reference');
    is($vip_status->{status}, 'active', 'VIP status should be active');
    is($vip_status->{active_node}, 'testnode', 'Active node should be testnode');
    ok(exists($vip_status->{nodes}->{testnode}), 'VIP status should include testnode');
    ok(exists($vip_status->{nodes}->{testnode2}), 'VIP status should include testnode2');
};

# Test failover functionality
subtest 'HA failover functionality' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test failover trigger
    my $result = $instance->_trigger_failover('192.168.1.100', 'testnode', 'testnode2');
    
    ok(ref($result) eq 'HASH', 'Failover result should be a hash reference');
    is($result->{success}, 1, 'Failover should be successful');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $ip_del_found = 0;
    my $ip_add_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ip' && $cmd->[1] eq 'addr' && $cmd->[2] eq 'del') {
            $ip_del_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ssh' && grep(/ip addr add/, @$cmd)) {
            $ip_add_found = 1;
        }
    }
    
    ok($ip_del_found, 'ip addr del command should be called to remove VIP from source node');
    ok($ip_add_found, 'ssh command should be called to add VIP to target node');
};

done_testing();