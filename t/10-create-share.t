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
    if ($cmd =~ /pvesh get \/cluster\/nextid/) {
        return "100\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

# Test data
my $test_scfg = {
    mode => 'lxc',
    sharename => 'testshare',
    path => '/srv/smb/testshare',
    quota => '10G',
    ad_domain => 'test.local',
    ctdb_vip => '192.168.1.100'
};

my $module = 'PVE::Storage::Custom::SMBGateway';

# Test create_share with LXC mode
subtest 'create_share LXC mode' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    eval {
        $module->create_share('teststorage', $test_scfg);
    };
    
    is($@, '', 'create_share should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check for specific commands
    my $pct_create_found = 0;
    my $pct_start_found = 0;
    my $pct_set_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[1] eq 'create') {
            $pct_create_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[1] eq 'start') {
            $pct_start_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'pct' && $cmd->[1] eq 'set') {
            $pct_set_found = 1;
        }
    }
    
    ok($pct_create_found, 'pct create command should be called');
    ok($pct_start_found, 'pct start command should be called');
    ok($pct_set_found, 'pct set command should be called');
};

# Test create_share with native mode
subtest 'create_share native mode' => sub {
    my $native_scfg = { %$test_scfg, mode => 'native' };
    
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    eval {
        $module->create_share('teststorage', $native_scfg);
    };
    
    is($@, '', 'create_share native mode should not throw an exception');
    
    # Verify that systemctl reload was called
    my $commands = $mock_tools->{called_commands};
    my $systemctl_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'systemctl' && $cmd->[1] eq 'reload') {
            $systemctl_found = 1;
        }
    }
    
    ok($systemctl_found, 'systemctl reload should be called for native mode');
};

# Test error handling
subtest 'create_share error handling' => sub {
    # Mock run_command to fail
    $mock_tools->mock('run_command', sub {
        die "Simulated command failure";
    });
    
    eval {
        $module->create_share('teststorage', $test_scfg);
    };
    
    like($@, qr/Failed to create share/, 'Should handle command failures gracefully');
    
    # Restore original mock
    $mock_tools->mock('run_command', sub {
        my ($cmd, %opts) = @_;
        push @{$mock_tools->{called_commands}}, $cmd;
        return 1;
    });
};

# Test missing sharename
subtest 'create_share missing sharename' => sub {
    my $invalid_scfg = { mode => 'lxc' }; # Missing sharename
    
    eval {
        $module->create_share('teststorage', $invalid_scfg);
    };
    
    like($@, qr/missing sharename/, 'Should fail when sharename is missing');
};

done_testing(); 