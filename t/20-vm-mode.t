#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Exception;

# Mock PVE::Tools for testing
my $mock_tools = Test::MockModule->new('PVE::Tools');
$mock_tools->mock('run_command', sub {
    my ($cmd, %opts) = @_;
    
    # Mock responses for different commands
    if ($cmd->[0] eq 'pvesh' && $cmd->[1] eq 'get' && $cmd->[2] eq '/cluster/nextid') {
        return "100\n";
    }
    
    if ($cmd->[0] eq 'qm' && $cmd->[1] eq 'clone') {
        return 1; # Success
    }
    
    if ($cmd->[0] eq 'qm' && $cmd->[1] eq 'set') {
        return 1; # Success
    }
    
    if ($cmd->[0] eq 'qm' && $cmd->[1] eq 'start') {
        return 1; # Success
    }
    
    if ($cmd->[0] eq 'qm' && $cmd->[1] eq 'status') {
        return "status: running\n";
    }
    
    # Default success
    return 1;
});

# Mock file operations
my $mock_file = Test::MockModule->new('File::Path');
$mock_file->mock('mkpath', sub { return 1; });

# Load the module
use_ok('PVE::Storage::Custom::SMBGateway');

# Test VM template discovery
subtest 'VM template discovery' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    # Mock template discovery
    my $template = $plugin->_find_vm_template();
    ok(defined $template, 'Template discovery returns a value');
    like($template, qr/\.qcow2$/, 'Template has correct extension');
};

# Test VM creation workflow
subtest 'VM creation workflow' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my @rollback_steps;
    my $path = '/srv/smb/testvm';
    my $share = 'testvm';
    my $quota = '10G';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '192.168.1.100';
    my $vm_memory = 2048;
    my $vm_cores = 2;
    
    # Test VM creation
    lives_ok {
        $plugin->_vm_create($path, $share, $quota, $ad_domain, $ctdb_vip, $vm_memory, $vm_cores, \@rollback_steps);
    } 'VM creation completes without errors';
    
    # Check rollback steps were added
    ok(@rollback_steps > 0, 'Rollback steps were added');
    like($rollback_steps[0]->[0], qr/destroy_vm|rmdir/, 'Rollback steps contain expected actions');
};

# Test VM activation
subtest 'VM activation' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my $scfg = { vmid => 100 };
    
    lives_ok {
        $plugin->_vm_activate('testvm', $scfg);
    } 'VM activation completes without errors';
};

# Test VM deactivation
subtest 'VM deactivation' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my $scfg = { vmid => 100 };
    
    lives_ok {
        $plugin->_vm_deactivate('testvm', $scfg);
    } 'VM deactivation completes without errors';
};

# Test VM status
subtest 'VM status' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my $scfg = { vmid => 100 };
    
    my $status = $plugin->_vm_status('testvm', $scfg);
    ok(defined $status, 'VM status returns a value');
    ok(defined $status->{status}, 'Status contains status field');
    ok(defined $status->{message}, 'Status contains message field');
};

# Test VM template validation
subtest 'VM template validation' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    # Test with valid template
    my $valid_template = '/var/lib/vz/template/iso/smb-gateway-debian12.qcow2';
    ok($plugin->_validate_vm_template($valid_template), 'Valid template passes validation');
    
    # Test with invalid template
    my $invalid_template = '/nonexistent/template.qcow2';
    ok(!$plugin->_validate_vm_template($invalid_template), 'Invalid template fails validation');
};

# Test VM IP waiting
subtest 'VM IP waiting' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    # Mock IP detection
    my $mock_net = Test::MockModule->new('Net::Ping');
    $mock_net->mock('new', sub { return bless {}, 'Net::Ping'; });
    $mock_net->mock('ping', sub { return 1; });
    
    my $ip = $plugin->_wait_for_vm_ip(100);
    ok(defined $ip, 'IP detection returns a value');
    like($ip, qr/^\d+\.\d+\.\d+\.\d+$/, 'IP has correct format');
};

# Test Samba configuration in VM
subtest 'Samba configuration in VM' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my $vmid = 100;
    my $vm_ip = '192.168.1.100';
    my $share = 'testvm';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '192.168.1.200';
    
    lives_ok {
        $plugin->_configure_samba_in_vm($vmid, $vm_ip, $share, $ad_domain, $ctdb_vip);
    } 'Samba configuration completes without errors';
};

# Test CTDB setup in VM
subtest 'CTDB setup in VM' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    my $vmid = 100;
    my $vm_ip = '192.168.1.100';
    my $ctdb_vip = '192.168.1.200';
    my @rollback_steps;
    
    lives_ok {
        $plugin->_setup_ctdb_in_vm($vmid, $vm_ip, $ctdb_vip, \@rollback_steps);
    } 'CTDB setup completes without errors';
};

done_testing(); 