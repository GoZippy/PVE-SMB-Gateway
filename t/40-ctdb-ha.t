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
    } elsif ($cmd =~ /ctdb status/) {
        return "OK: ctdb is healthy\n";
    } elsif ($cmd =~ /ctdb nodestatus/) {
        return "0 testnode OK\n1 testnode2 OK\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test _generate_ctdb_config method
subtest '_generate_ctdb_config' => sub {
    my $nodes = ['testnode', 'testnode2'];
    my $vip = '192.168.1.100';
    
    my $config = $instance->_generate_ctdb_config($nodes, $vip);
    
    ok(ref($config) eq 'HASH', 'Config should be a hash reference');
    ok(exists($config->{nodes_file}), 'Config should contain nodes_file');
    ok(exists($config->{public_addresses}), 'Config should contain public_addresses');
    ok(exists($config->{service_script}), 'Config should contain service_script');
    ok(exists($config->{smb_conf_additions}), 'Config should contain smb_conf_additions');
    
    like($config->{nodes_file}, qr/testnode/, 'Nodes file should contain node names');
    like($config->{public_addresses}, qr/192\.168\.1\.100/, 'Public addresses should contain VIP');
    like($config->{service_script}, qr/service smbd start/, 'Service script should manage Samba services');
    like($config->{smb_conf_additions}, qr/clustering = yes/, 'SMB config should enable clustering');
};

# Test _deploy_ctdb_config method
subtest '_deploy_ctdb_config' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my $nodes = ['testnode'];
    my $vip = '192.168.1.100';
    my @rollback_steps = ();
    
    my $config = $instance->_generate_ctdb_config($nodes, $vip);
    
    eval {
        $instance->_deploy_ctdb_config('testnode', $config, \@rollback_steps);
    };
    
    is($@, '', '_deploy_ctdb_config should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check for specific commands
    my $mkdir_found = 0;
    my $cp_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'mkdir') {
            $mkdir_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'cp') {
            $cp_found = 1;
        }
    }
    
    ok($mkdir_found, 'mkdir command should be called');
    ok($cp_found, 'cp command should be called');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
};

# Test _start_ctdb_service method
subtest '_start_ctdb_service' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my @rollback_steps = ();
    
    eval {
        $instance->_start_ctdb_service('testnode', \@rollback_steps);
    };
    
    is($@, '', '_start_ctdb_service should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check for specific commands
    my $apt_found = 0;
    my $systemctl_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'apt-get') {
            $apt_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'systemctl') {
            $systemctl_found = 1;
        }
    }
    
    ok($apt_found, 'apt-get command should be called');
    ok($systemctl_found, 'systemctl command should be called');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
};

# Test _validate_ctdb_cluster method
subtest '_validate_ctdb_cluster' => sub {
    my $nodes = ['testnode', 'testnode2'];
    
    my $status = $instance->_validate_ctdb_cluster($nodes);
    
    ok(ref($status) eq 'HASH', 'Status should be a hash reference');
    is($status->{status}, 'active', 'Status should be active');
    is($status->{total_nodes}, 2, 'Should report 2 total nodes');
    is($status->{healthy_nodes}, 2, 'Should report 2 healthy nodes');
};

# Test _setup_ctdb_cluster method
subtest '_setup_ctdb_cluster' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my $nodes = ['testnode', 'testnode2'];
    my $vip = '192.168.1.100';
    my @rollback_steps = ();
    
    my $status;
    eval {
        $status = $instance->_setup_ctdb_cluster($nodes, $vip, \@rollback_steps);
    };
    
    is($@, '', '_setup_ctdb_cluster should not throw an exception');
    ok(ref($status) eq 'HASH', 'Status should be a hash reference');
    is($status->{status}, 'active', 'Status should be active');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
};

# Test LXC mode with CTDB
subtest 'lxc_create with CTDB' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock pct exec to simulate container IP
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /pct exec \d+ -- ip -4 addr show eth0/) {
            return "inet 192.168.1.10/24 scope global eth0\n";
        }
        return "";
    });
    
    my $path = '/srv/smb/testshare';
    my $share = 'testshare';
    my $quota = '10G';
    my $ad_domain = 'test.local';
    my $ctdb_vip = '192.168.1.100';
    my @rollback_steps = ();
    
    eval {
        $module->_lxc_create($path, $share, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
    };
    
    is($@, '', '_lxc_create with CTDB should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    
    # Check for CTDB-specific commands
    my $ctdb_install_found = 0;
    my $ctdb_enable_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[2] eq '--' && 
            $cmd->[3] eq 'apt-get' && $cmd->[4] eq 'install' && grep(/ctdb/, @$cmd)) {
            $ctdb_install_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[2] eq '--' && 
            $cmd->[3] eq 'systemctl' && $cmd->[4] eq 'enable' && $cmd->[5] eq 'ctdb') {
            $ctdb_enable_found = 1;
        }
    }
    
    ok($ctdb_install_found, 'CTDB should be installed in LXC container');
    ok($ctdb_enable_found, 'CTDB service should be enabled in LXC container');
};

# Test VIP management methods
subtest '_allocate_vip' => sub {
    # Mock system commands for VIP allocation
    $mock_system->mock('system', sub { 
        my ($cmd) = @_;
        # Simulate ping responses (all IPs are unused)
        return 1; # Non-zero exit code means ping failed (IP is free)
    });
    
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            return "inet 192.168.1.5/24 scope global eth0\n";
        }
        return "";
    });
    
    my $vip = $instance->_allocate_vip('192.168.1');
    
    ok($vip, 'Should allocate a VIP');
    like($vip, qr/^192\.168\.1\.\d+$/, 'VIP should be in the correct network');
    
    # Test with existing VIPs
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            return "inet 192.168.1.5/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
        }
        return "";
    });
    
    $vip = $instance->_allocate_vip('192.168.1');
    
    ok($vip, 'Should allocate a VIP even with existing VIPs');
    like($vip, qr/^192\.168\.1\.\d+$/, 'VIP should be in the correct network');
    isnt($vip, '192.168.1.100', 'Should not allocate an already used VIP');
};

subtest '_assign_vip and _unassign_vip' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock system commands
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            return "inet 192.168.1.5/24 scope global eth0\n";
        } elsif ($cmd =~ /ssh.*echo success/) {
            return "success\n";
        }
        return "";
    });
    
    # Test local VIP assignment
    eval {
        $instance->_assign_vip('192.168.1.100', 'eth0');
    };
    
    is($@, '', '_assign_vip should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $ip_add_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ip' && $cmd->[1] eq 'addr' && $cmd->[2] eq 'add') {
            $ip_add_found = 1;
        }
    }
    
    ok($ip_add_found, 'ip addr add command should be called');
    
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test local VIP unassignment
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            return "inet 192.168.1.5/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
        }
        return "";
    });
    
    eval {
        $instance->_unassign_vip('192.168.1.100', 'eth0');
    };
    
    is($@, '', '_unassign_vip should not throw an exception');
    
    # Verify that expected commands were called
    $commands = $mock_tools->{called_commands};
    my $ip_del_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ip' && $cmd->[1] eq 'addr' && $cmd->[2] eq 'del') {
            $ip_del_found = 1;
        }
    }
    
    ok($ip_del_found, 'ip addr del command should be called');
    
    # Test remote VIP assignment
    $mock_tools->{called_commands} = [];
    
    eval {
        $instance->_assign_vip('192.168.1.100', 'eth0', 'remotenode');
    };
    
    is($@, '', '_assign_vip with remote node should not throw an exception');
    
    # Verify that expected commands were called
    $commands = $mock_tools->{called_commands};
    my $ssh_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ssh') {
            $ssh_found = 1;
        }
    }
    
    ok($ssh_found, 'ssh command should be called for remote node');
};

subtest '_monitor_vip_health' => sub {
    # Mock system commands
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            return "inet 192.168.1.5/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
        } elsif ($cmd =~ /ctdb status/) {
            return "OK: ctdb is healthy\n";
        } elsif ($cmd =~ /systemctl is-active smbd/) {
            return "active\n";
        } elsif ($cmd =~ /ssh.*echo success/) {
            return "success\n";
        }
        return "";
    });
    
    my $nodes = ['testnode', 'testnode2'];
    my $vip = '192.168.1.100';
    
    my $status = $instance->_monitor_vip_health($vip, $nodes);
    
    ok(ref($status) eq 'HASH', 'Status should be a hash reference');
    is($status->{status}, 'active', 'VIP status should be active');
    is($status->{active_node}, 'testnode', 'Active node should be testnode');
    ok(exists($status->{nodes}->{testnode}), 'Status should include testnode');
    ok(exists($status->{nodes}->{testnode2}), 'Status should include testnode2');
    is($status->{nodes}->{testnode}->{has_vip}, 1, 'testnode should have VIP');
    is($status->{nodes}->{testnode}->{ctdb_status}, 'active', 'testnode CTDB status should be active');
    is($status->{nodes}->{testnode}->{smb_status}, 'active', 'testnode SMB status should be active');
};

subtest '_trigger_failover' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock system commands
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /ip addr/) {
            # First call shows VIP on testnode, second call (after failover) shows VIP on testnode2
            state $call_count = 0;
            $call_count++;
            
            if ($call_count <= 2) {
                return "inet 192.168.1.5/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
            } else {
                return "inet 192.168.1.6/24 scope global eth0\n";
            }
        } elsif ($cmd =~ /ssh.*ip addr/) {
            # First call shows no VIP on testnode2, second call shows VIP on testnode2
            state $ssh_call_count = 0;
            $ssh_call_count++;
            
            if ($ssh_call_count <= 2) {
                return "inet 192.168.1.6/24 scope global eth0\n";
            } else {
                return "inet 192.168.1.6/24 scope global eth0\ninet 192.168.1.100/24 scope global eth0\n";
            }
        } elsif ($cmd =~ /ctdb status/) {
            return "OK: ctdb is healthy\n";
        } elsif ($cmd =~ /systemctl is-active smbd/) {
            return "active\n";
        } elsif ($cmd =~ /ssh.*echo success/) {
            return "success\n";
        }
        return "";
    });
    
    my $result = $instance->_trigger_failover('192.168.1.100', 'testnode', 'testnode2');
    
    ok(ref($result) eq 'HASH', 'Result should be a hash reference');
    is($result->{success}, 1, 'Failover should be successful');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $ip_del_found = 0;
    my $ssh_add_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ip' && $cmd->[1] eq 'addr' && $cmd->[2] eq 'del') {
            $ip_del_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'ssh' && grep(/ip addr add/, @$cmd)) {
            $ssh_add_found = 1;
        }
    }
    
    ok($ip_del_found, 'ip addr del command should be called to remove VIP from source node');
    ok($ssh_add_found, 'ssh command should be called to add VIP to target node');
};

done_testing();