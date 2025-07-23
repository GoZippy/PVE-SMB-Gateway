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
    } elsif ($cmd =~ /df -T/) {
        return "Filesystem     Type  1K-blocks    Used Available Use% Mounted on\n/dev/sda1      ext4   10485760 1048576   9437184  10% /\n";
    } elsif ($cmd =~ /zfs list/) {
        return "tank/dataset  10G  1G  9G  -  /tank/dataset\n";
    } elsif ($cmd =~ /zfs get -H -o value quota/) {
        return "10G\n";
    } elsif ($cmd =~ /zfs get -H -o value used/) {
        return "1G\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test quota monitoring script
subtest 'Quota monitoring script' => sub {
    # Check if script exists
    ok(-f "scripts/monitor_quotas.sh", "Quota monitoring script should exist");
    
    # Test script content
    my $script_content = `cat scripts/monitor_quotas.sh 2>/dev/null`;
    like($script_content, qr/SMB Gateway Quota Monitoring/, "Script should contain expected header");
    like($script_content, qr/get_quota_usage/, "Script should check quota usage");
    like($script_content, qr/send_notification/, "Script should send notifications");
};

# Test _get_fs_type method
subtest '_get_fs_type' => sub {
    # Test with ext4 filesystem
    my $fs_type = $module->_get_fs_type('/test/path');
    is($fs_type, 'ext4', 'Should detect ext4 filesystem');
    
    # Test with ZFS dataset
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /zfs list/) {
            return "tank/dataset  10G  1G  9G  -  /tank/dataset\n";
        }
        return "";
    });
    
    $fs_type = $module->_get_fs_type('/tank/dataset');
    is($fs_type, 'zfs', 'Should detect ZFS dataset');
};

# Test _apply_quota method
subtest '_apply_quota' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock filesystem type detection
    no warnings 'redefine';
    local *PVE::Storage::Custom::SMBGateway::_get_fs_type = sub {
        return 'ext4';
    };
    
    my @rollback_steps = ();
    
    # Test with valid quota
    $module->_apply_quota('/test/path', '10G', \@rollback_steps);
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $setquota_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'setquota') {
            $setquota_found = 1;
        }
    }
    
    ok($setquota_found, 'setquota command should be called');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
    my $remove_quota_step_found = 0;
    
    foreach my $step (@rollback_steps) {
        if ($step->[0] eq 'remove_quota') {
            $remove_quota_step_found = 1;
        }
    }
    
    ok($remove_quota_step_found, 'remove_quota rollback step should be added');
};

# Test _apply_zfs_quota method
subtest '_apply_zfs_quota' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my @rollback_steps = ();
    
    # Mock dataset detection
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /zfs list/) {
            return "tank/dataset\n";
        }
        return "";
    });
    
    # Test with valid quota
    $module->_apply_zfs_quota('/tank/dataset', '10G', \@rollback_steps);
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    my $zfs_set_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'zfs' && $cmd->[1] eq 'set') {
            $zfs_set_found = 1;
        }
    }
    
    ok($zfs_set_found, 'zfs set command should be called');
    
    # Check rollback steps
    ok(@rollback_steps > 0, 'Rollback steps should be added');
    my $zfs_remove_quota_step_found = 0;
    
    foreach my $step (@rollback_steps) {
        if ($step->[0] eq 'zfs_remove_quota') {
            $zfs_remove_quota_step_found = 1;
        }
    }
    
    ok($zfs_remove_quota_step_found, 'zfs_remove_quota rollback step should be added');
};

# Test _get_quota_usage method
subtest '_get_quota_usage' => sub {
    # Mock ZFS quota usage
    no warnings 'redefine';
    local *PVE::Storage::Custom::SMBGateway::_get_fs_type = sub {
        return 'zfs';
    };
    
    local *PVE::Storage::Custom::SMBGateway::_get_zfs_quota_usage = sub {
        return {
            quota => '10G',
            used => '1G',
            quota_bytes => 10 * 1024**3,
            used_bytes => 1 * 1024**3,
            percent => 10
        };
    };
    
    my $usage = $instance->_get_quota_usage('/tank/dataset');
    
    ok(ref($usage) eq 'HASH', 'Usage should be a hash reference');
    is($usage->{quota}, '10G', 'Quota should be 10G');
    is($usage->{used}, '1G', 'Used should be 1G');
    is($usage->{percent}, 10, 'Percent should be 10');
};

# Test _human_to_bytes and _bytes_to_human methods
subtest 'Size conversion' => sub {
    # Test _human_to_bytes
    is($module->_human_to_bytes('10K'), 10 * 1024, 'Should convert 10K to bytes');
    is($module->_human_to_bytes('10M'), 10 * 1024**2, 'Should convert 10M to bytes');
    is($module->_human_to_bytes('10G'), 10 * 1024**3, 'Should convert 10G to bytes');
    is($module->_human_to_bytes('10T'), 10 * 1024**4, 'Should convert 10T to bytes');
    is($module->_human_to_bytes('10'), 10, 'Should convert 10 to bytes');
    
    # Test _bytes_to_human
    is($module->_bytes_to_human(10 * 1024), '10.0K', 'Should convert bytes to 10.0K');
    is($module->_bytes_to_human(10 * 1024**2), '10.0M', 'Should convert bytes to 10.0M');
    is($module->_bytes_to_human(10 * 1024**3), '10.0G', 'Should convert bytes to 10.0G');
    is($module->_bytes_to_human(10 * 1024**4), '10.0T', 'Should convert bytes to 10.0T');
    is($module->_bytes_to_human(10), '10B', 'Should convert bytes to 10B');
};

# Test status method with quota information
subtest 'Status with quota information' => sub {
    # Mock quota usage
    no warnings 'redefine';
    local *PVE::Storage::Custom::SMBGateway::_get_quota_usage = sub {
        return {
            quota => '10G',
            used => '9G',
            quota_bytes => 10 * 1024**3,
            used_bytes => 9 * 1024**3,
            percent => 90
        };
    };
    
    # Test status method
    my $status = $module->status('teststorage', {
        mode => 'native',
        sharename => 'testshare',
        path => '/test/path',
        quota => '10G'
    });
    
    ok(ref($status) eq 'HASH', 'Status should be a hash reference');
    ok(exists($status->{quota}), 'Status should include quota information');
    is($status->{quota}->{limit}, '10G', 'Quota limit should be 10G');
    is($status->{quota}->{used}, '9G', 'Quota used should be 9G');
    is($status->{quota}->{percent}, 90, 'Quota percent should be 90');
    ok(exists($status->{quota}->{warning}), 'Status should include quota warning');
};

done_testing();