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
    } elsif ($cmd =~ /pvesh get \/nodes\/testnode\/storage\/local\/content --type iso/) {
        return "volid: local:iso/smb-gateway-debian12.qcow2\nvolid: local:iso/debian-12-generic-amd64.qcow2\n";
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test _find_vm_template method
subtest '_find_vm_template' => sub {
    my $template;
    
    eval {
        $template = $instance->_find_vm_template();
    };
    
    is($@, '', '_find_vm_template should not throw an exception');
    is($template, 'local:iso/smb-gateway-debian12.qcow2', 'Should find the preferred template');
};

# Test _validate_vm_template method
subtest '_validate_vm_template' => sub {
    # Test with SMB gateway template
    my $smb_template = 'local:iso/smb-gateway-debian12.qcow2';
    my $result;
    
    eval {
        $result = $instance->_validate_vm_template($smb_template);
    };
    
    is($@, '', '_validate_vm_template should not throw an exception for SMB gateway template');
    is($result, $smb_template, 'Should return the same template for SMB gateway template');
    
    # Test with generic Debian template
    my $debian_template = 'local:iso/debian-12-generic-amd64.qcow2';
    
    eval {
        $result = $instance->_validate_vm_template($debian_template);
    };
    
    is($@, '', '_validate_vm_template should not throw an exception for Debian template');
    is($result, $debian_template, 'Should return the same template for Debian template');
    
    # Test with invalid template
    my $invalid_template = 'local:iso/windows-server.qcow2';
    
    eval {
        $result = $instance->_validate_vm_template($invalid_template);
    };
    
    like($@, qr/does not appear to be a valid/, 'Should throw an exception for invalid template');
};

# Test template not found scenario
subtest 'template not found' => sub {
    # Mock backtick to return empty list
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /pvesh get/) {
            return ""; # No templates available
        }
        return "";
    });
    
    eval {
        $instance->_find_vm_template();
    };
    
    like($@, qr/No suitable VM template found/, 'Should throw an exception when no templates are found');
    
    # Restore original mock
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /hostname/) {
            return "testnode\n";
        } elsif ($cmd =~ /pvesh get \/nodes\/testnode\/storage\/local\/content --type iso/) {
            return "volid: local:iso/smb-gateway-debian12.qcow2\nvolid: local:iso/debian-12-generic-amd64.qcow2\n";
        }
        return "";
    });
};

# Test _create_vm_template method
subtest '_create_vm_template' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Mock system to indicate required tools are available
    $mock_system->mock('system', sub { return 0; }); # All commands succeed
    
    my $template;
    
    eval {
        $template = $instance->_create_vm_template(1); # Force creation
    };
    
    is($@, '', '_create_vm_template should not throw an exception');
    
    # Verify that expected commands were called
    my $commands = $mock_tools->{called_commands};
    ok(@$commands > 0, 'Commands should have been executed');
    
    # Check for specific commands
    my $qemu_img_found = 0;
    my $debootstrap_found = 0;
    my $apt_install_found = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'qemu-img') {
            $qemu_img_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'debootstrap') {
            $debootstrap_found = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'chroot' && $cmd->[2] eq 'apt-get' && $cmd->[3] eq 'install') {
            $apt_install_found = 1;
        }
    }
    
    ok($qemu_img_found, 'qemu-img command should be called');
    ok($debootstrap_found, 'debootstrap command should be called');
    ok($apt_install_found, 'apt-get install command should be called');
    
    # Test when tools are missing
    $mock_system->mock('system', sub { return 1; }); # All commands fail
    
    eval {
        $instance->_create_vm_template(1);
    };
    
    like($@, qr/Missing required tools/, 'Should throw an exception when required tools are missing');
    
    # Restore original mock
    $mock_system->mock('system', sub { return 0; });
};

done_testing();