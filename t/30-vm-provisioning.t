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
        return "200\n";
    } elsif ($cmd =~ /hostname/) {
        return "testnode\n";
    } elsif ($cmd =~ /pvesh get \/nodes\/testnode\/storage\/local\/content --type iso/) {
        return "volid: local:iso/smb-gateway-debian12.qcow2\n";
    } elsif ($cmd =~ /qm status 200/) {
        return "status: running\n";
    } elsif ($cmd =~ /qm agent 200 ping/) {
        return "1\n"; # Agent is responding
    } elsif ($cmd =~ /zfs list/) {
        return ""; # Not a ZFS dataset
    } elsif ($cmd =~ /rbd info/) {
        return ""; # Not an RBD volume
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

# Test data
my $test_scfg = {
    mode => 'vm',
    sharename => 'testshare',
    path => '/srv/smb/testshare',
    quota => '10G',
    ad_domain => 'test.local',
    ctdb_vip => '192.168.1.100',
    vm_memory => 4096,
    vm_cores => 4
};

my $module = 'PVE::Storage::Custom::SMBGateway';

# Test _vm_create method
subtest '_vm_create' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    my @rollback_steps = ();
    
    eval {
        $module->_vm_create(
            $test_scfg->{path},
            $test_scfg->{sharename},
            $test_scfg->{quota},
            $test_scfg->{ad_domain},
            $test_scfg->{ctdb_vip},
            $test_scfg->{vm_memory},
            $test_scfg->{vm_cores},
            \@rollback_steps
        );
    };
    
    is($@, '', '_vm_create should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check for specific commands
    my $qm_create_found = 0;
    my $qm_importdisk_found = 0;
    my $qm_set_found = 0;
    my $qm_start_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'create') {
            $qm_create_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'importdisk') {
            $qm_importdisk_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'set') {
            $qm_set_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'start') {
            $qm_start_found = 1;
        }
    }
    
    ok($qm_create_found, 'qm create command should be called');
    ok($qm_importdisk_found, 'qm importdisk command should be called');
    ok($qm_set_found, 'qm set command should be called');
    ok($qm_start_found, 'qm start command should be called');
};

# Test storage attachment methods
subtest 'storage attachment methods' => sub {
    # Test ZFS attachment
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /zfs list/) {
            return "testpool/testdataset\n"; # ZFS dataset
        }
        return "";
    });
    
    is($module->_determine_storage_type('/testpool/testdataset'), 'zfs', 'Should detect ZFS dataset');
    
    # Test RBD attachment
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /rbd info/) {
            return "rbd image 'testimage':\n"; # RBD volume
        }
        return "";
    });
    
    is($module->_determine_storage_type('/testrbd'), 'rbd', 'Should detect RBD volume');
    
    # Test generic filesystem
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        return ""; # Neither ZFS nor RBD
    });
    
    is($module->_determine_storage_type('/testpath'), 'fs', 'Should default to filesystem');
    
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test _attach_virtiofs
    my @rollback_steps = ();
    $module->_attach_virtiofs(200, '/testpath', 'testshare', \@rollback_steps);
    
    my $commands = $mock_tools->{called_commands};
    my $virtiofs_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'set' && 
            $cmd->[2] eq '200' && $cmd->[3] =~ /--virtio0/) {
            $virtiofs_found = 1;
        }
    }
    
    ok($virtiofs_found, '_attach_virtiofs should call qm set with virtio0');
    
    # Check rollback step
    is($rollback_steps[0][0], 'detach_virtiofs', 'Should add detach_virtiofs rollback step');
};

# Test VM lifecycle methods
subtest 'VM lifecycle methods' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test _vm_activate
    $module->_vm_activate('testshare', { vmid => 200 });
    
    my $commands = $mock_tools->{called_commands};
    my $start_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'start' && $cmd->[2] eq '200') {
            $start_found = 1;
        }
    }
    
    ok($start_found, '_vm_activate should call qm start');
    
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test _vm_deactivate
    $module->_vm_deactivate('testshare', { vmid => 200 });
    
    $commands = $mock_tools->{called_commands};
    my $stop_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'stop' && $cmd->[2] eq '200') {
            $stop_found = 1;
        }
    }
    
    ok($stop_found, '_vm_deactivate should call qm stop');
    
    # Test _vm_status
    my $status = $module->_vm_status('testshare', { vmid => 200 });
    
    is($status->{status}, 'active', '_vm_status should return active status');
    like($status->{message}, qr/VM 200 is running/, '_vm_status should include VM ID in message');
    
    # Test _vm_status with no VM ID
    $status = $module->_vm_status('testshare', {});
    
    is($status->{status}, 'unknown', '_vm_status should return unknown status when no VM ID');
    like($status->{message}, qr/No VM ID found/, '_vm_status should indicate missing VM ID');
    
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test _vm_delete
    $module->_vm_delete('testshare', { vmid => 200 });
    
    $commands = $mock_tools->{called_commands};
    $stop_found = 0;
    my $destroy_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'stop' && $cmd->[2] eq '200') {
            $stop_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qm' && $cmd->[1] eq 'destroy' && $cmd->[2] eq '200') {
            $destroy_found = 1;
        }
    }
    
    ok($stop_found, '_vm_delete should call qm stop');
    ok($destroy_found, '_vm_delete should call qm destroy');
};

done_testing();