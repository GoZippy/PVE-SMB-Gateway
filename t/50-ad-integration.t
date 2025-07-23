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
    } elsif ($cmd =~ /host -t SRV/) {
        return "has SRV record 0 0 389 dc.example.com.\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test _join_ad_domain method
subtest '_join_ad_domain' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my @rollback_steps = ();
    my $domain_info;
    
    # Test native mode
    eval {
        $domain_info = $instance->_join_ad_domain('example.com', 'Administrator', 'password123', 'OU=Servers,DC=example,DC=com', 'native', undef, \@rollback_steps);
    };
    
    is($@, '', '_join_ad_domain should not throw an exception');
    ok(ref($domain_info) eq 'HASH', 'Domain info should be a hash reference');
    is($domain_info->{domain}, 'example.com', 'Domain should be example.com');
    is($domain_info->{realm}, 'EXAMPLE.COM', 'Realm should be EXAMPLE.COM');
    is($domain_info->{workgroup}, 'EXAMPLE', 'Workgroup should be EXAMPLE');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $apt_install_found = 0;
    my $net_ads_join_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'apt-get' && $cmd->[1] eq 'install') {
            $apt_install_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'net' && $cmd->[1] eq 'ads' && $cmd->[2] eq 'join') {
            $net_ads_join_found = 1;
            # Check if command includes username and password
            my $cmd_str = join(' ', @$cmd);
            like($cmd_str, qr/Administrator%password123/, 'Join command should include credentials');
            # Check if command includes OU
            like($cmd_str, qr/createcomputer OU=Servers,DC=example,DC=com/, 'Join command should include OU');
        }
    }
    
    ok($apt_install_found, 'apt-get install command should be called');
    ok($net_ads_join_found, 'net ads join command should be called');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
    my $leave_domain_step_found = 0;
    
    foreach my $step (@rollback_steps) {
        if ($step->[0] eq 'leave_domain') {
            $leave_domain_step_found = 1;
        }
    }
    
    ok($leave_domain_step_found, 'leave_domain rollback step should be added');
    
    # Test LXC mode
    $mock_tools->{called_commands} = [];
    @rollback_steps = ();
    
    eval {
        $domain_info = $instance->_join_ad_domain('example.com', 'Administrator', 'password123', undef, 'lxc', 100, \@rollback_steps);
    };
    
    is($@, '', '_join_ad_domain with LXC mode should not throw an exception');
    
    # Verify that expected commands were called
    $commands = $mock_tools->{called_commands};
    my $pct_exec_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[1] eq 'exec') {
            $pct_exec_found = 1;
        }
    }
    
    ok($pct_exec_found, 'pct exec command should be called for LXC mode');
    
    # Test VM mode
    eval {
        $domain_info = $instance->_join_ad_domain('example.com', 'Administrator', 'password123', undef, 'vm', undef, \@rollback_steps);
    };
    
    is($@, '', '_join_ad_domain with VM mode should not throw an exception');
    is($domain_info->{domain}, 'example.com', 'Domain should be example.com');
    is($domain_info->{username}, 'Administrator', 'Username should be Administrator');
    is($domain_info->{password}, 'password123', 'Password should be password123');
};

# Test _generate_krb5_conf method
subtest '_generate_krb5_conf' => sub {
    my $krb5_conf = $instance->_generate_krb5_conf('example.com');
    
    like($krb5_conf, qr/default_realm = EXAMPLE.COM/, 'Kerberos config should include realm');
    like($krb5_conf, qr/\[realms\]/, 'Kerberos config should include realms section');
    like($krb5_conf, qr/\[domain_realm\]/, 'Kerberos config should include domain_realm section');
};

# Test _test_domain_connection method
subtest '_test_domain_connection' => sub {
    # Mock system to simulate successful ping
    $mock_system->mock('system', sub { return 0; });
    
    my $result = $instance->_test_domain_connection('example.com', 'native');
    ok($result, 'Domain connection test should succeed');
    
    # Mock system to simulate failed ping
    $mock_system->mock('system', sub { return 1; });
    
    $result = $instance->_test_domain_connection('example.com', 'native');
    ok(!$result, 'Domain connection test should fail');
};

# Test _discover_domain_controllers method
subtest '_discover_domain_controllers' => sub {
    my $result = $instance->_discover_domain_controllers('example.com', 'native');
    ok($result, 'Domain controller discovery should succeed');
};

# Test native mode with AD domain
subtest 'native_create with AD domain' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Set environment variables for AD credentials
    local $ENV{SMB_AD_USERNAME} = 'Administrator';
    local $ENV{SMB_AD_PASSWORD} = 'password123';
    
    my $path = '/srv/smb/testshare';
    my $share = 'testshare';
    my $quota = '10G';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '';
    my @rollback_steps = ();
    
    eval {
        $module->_native_create($path, $share, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
    };
    
    is($@, '', '_native_create with AD domain should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $net_ads_join_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'net' && $cmd->[1] eq 'ads' && $cmd->[2] eq 'join') {
            $net_ads_join_found = 1;
        }
    }
    
    ok($net_ads_join_found, 'net ads join command should be called for native mode with AD domain');
};

# Test LXC mode with AD domain
subtest 'lxc_create with AD domain' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock pct exec to simulate container IP
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /pct exec \d+ -- ip -4 addr show eth0/) {
            return "inet 192.168.1.10/24 scope global eth0\n";
        } elsif ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /pvesh get \/cluster\/nextid/) {
            return "100\n";
        }
        return "";
    });
    
    # Set environment variables for AD credentials
    local $ENV{SMB_AD_USERNAME} = 'Administrator';
    local $ENV{SMB_AD_PASSWORD} = 'password123';
    
    my $path = '/srv/smb/testshare';
    my $share = 'testshare';
    my $quota = '10G';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '';
    my @rollback_steps = ();
    
    eval {
        $module->_lxc_create($path, $share, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
    };
    
    is($@, '', '_lxc_create with AD domain should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $pct_exec_ads_join_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[1] eq 'exec' && 
            grep(/net ads join/, @$cmd)) {
            $pct_exec_ads_join_found = 1;
        }
    }
    
    ok($pct_exec_ads_join_found, 'pct exec net ads join command should be called for LXC mode with AD domain');
};

done_testing();