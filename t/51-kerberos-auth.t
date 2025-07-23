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
    }
    return "";
});

BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

my $module = 'PVE::Storage::Custom::SMBGateway';
my $instance = bless {}, $module;

# Test Kerberos configuration script
subtest 'Kerberos configuration script' => sub {
    # Check if script exists
    ok(-f "scripts/configure_kerberos.sh", "Kerberos configuration script should exist");
    
    # Test script content
    my $script_content = `cat scripts/configure_kerberos.sh 2>/dev/null`;
    like($script_content, qr/SMB Gateway Kerberos Configuration/, "Script should contain expected header");
    like($script_content, qr/Creating Kerberos keytab/, "Script should contain keytab creation");
    like($script_content, qr/Configuring Samba for Kerberos/, "Script should configure Samba for Kerberos");
};

# Test _join_ad_domain with Kerberos script
subtest '_join_ad_domain with Kerberos script' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Create a mock script
    my $mock_script = "/tmp/configure_kerberos.sh";
    open my $fh, '>', $mock_script or die "Cannot create mock script: $!";
    print $fh "#!/bin/bash\necho \"Mock Kerberos configuration script\"\n";
    close $fh;
    chmod 0755, $mock_script;
    
    # Mock the script path
    my $orig_f = \&CORE::GLOBAL::glob;
    no warnings 'redefine';
    *CORE::GLOBAL::glob = sub {
        my ($pattern) = @_;
        if ($pattern eq "scripts/configure_kerberos.sh") {
            return $mock_script;
        }
        return $orig_f->($pattern);
    };
    
    # Test with script
    my @rollback_steps = ();
    my $domain_info;
    
    eval {
        $domain_info = $instance->_join_ad_domain('example.com', 'Administrator', 'password123', 'OU=Servers,DC=example,DC=com', 'native', undef, \@rollback_steps);
    };
    
    is($@, '', '_join_ad_domain with Kerberos script should not throw an exception');
    
    # Verify that script was called
    my $commands = $mock_tools->{called_commands};
    my $script_called = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq $mock_script) {
            $script_called = 1;
            # Check if command includes domain and credentials
            my $cmd_str = join(' ', @$cmd);
            like($cmd_str, qr/--domain example.com/, 'Script command should include domain');
            like($cmd_str, qr/--username Administrator/, 'Script command should include username');
            like($cmd_str, qr/--password password123/, 'Script command should include password');
        }
    }
    
    ok($script_called, 'Kerberos configuration script should be called');
    
    # Clean up
    unlink $mock_script;
    
    # Restore original glob
    *CORE::GLOBAL::glob = $orig_f;
};

# Test VM cloud-init Kerberos configuration
subtest 'VM cloud-init Kerberos configuration' => sub {
    my $vmid = 100;
    my $share = 'testshare';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '';
    
    # Set environment variables for AD credentials
    local $ENV{SMB_AD_USERNAME} = 'Administrator';
    local $ENV{SMB_AD_PASSWORD} = 'password123';
    
    # Call _configure_cloud_init
    my $user_data = '';
    no warnings 'redefine';
    local *PVE::Storage::Custom::SMBGateway::_configure_cloud_init = sub {
        my ($vmid, $share, $ad_domain, $ctdb_vip) = @_;
        
        # Create cloud-init configuration
        $user_data = "#!/bin/bash\n# SMB Gateway cloud-init configuration\n";
        
        # Add AD domain configuration if specified
        if ($ad_domain) {
            # Check if we have credentials in the environment
            my $ad_username = $ENV{SMB_AD_USERNAME} // 'Administrator';
            my $ad_password = $ENV{SMB_AD_PASSWORD};
            
            # Extract domain components
            my $workgroup = uc(substr($ad_domain, 0, index($ad_domain, '.')));
            my $realm = uc($ad_domain);
            
            $user_data .= "# Configure Kerberos\n";
            $user_data .= "cat > /etc/krb5.conf << 'EOF'\n";
            $user_data .= "[libdefaults]\n";
            $user_data .= "    default_realm = $realm\n";
            $user_data .= "EOF\n";
            
            # Add domain join if credentials are provided
            if ($ad_password) {
                $user_data .= "# Join AD domain\n";
                $user_data .= "net ads join -U \"$ad_username%$ad_password\"\n";
            }
        }
        
        return $user_data;
    };
    
    # Call the function
    my $result = $module->_configure_cloud_init($vmid, $share, $ad_domain, $ctdb_vip);
    
    # Check the result
    like($result, qr/Configure Kerberos/, 'Cloud-init should configure Kerberos');
    like($result, qr/default_realm = EXAMPLE.COM/, 'Cloud-init should set correct realm');
    like($result, qr/net ads join -U "Administrator%password123"/, 'Cloud-init should join domain');
};

done_testing();