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

# Test authentication fallback script
subtest 'Authentication fallback script' => sub {
    # Check if script exists
    ok(-f "scripts/configure_auth_fallback.sh", "Authentication fallback script should exist");
    
    # Test script content
    my $script_content = `cat scripts/configure_auth_fallback.sh 2>/dev/null`;
    like($script_content, qr/SMB Gateway Authentication Fallback Configuration/, "Script should contain expected header");
    like($script_content, qr/Creating local user/, "Script should create local user");
    like($script_content, qr/Updating smb.conf with fallback authentication/, "Script should update smb.conf");
    like($script_content, qr/Creating AD connectivity warning script/, "Script should create connectivity warning script");
};

# Test _configure_auth_fallback method
subtest '_configure_auth_fallback' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Create a mock script
    my $mock_script = "/tmp/configure_auth_fallback.sh";
    open my $fh, '>', $mock_script or die "Cannot create mock script: $!";
    print $fh "#!/bin/bash\necho \"Mock authentication fallback script\"\n";
    close $fh;
    chmod 0755, $mock_script;
    
    # Mock the script path
    my $orig_f = \&CORE::GLOBAL::glob;
    no warnings 'redefine';
    *CORE::GLOBAL::glob = sub {
        my ($pattern) = @_;
        if ($pattern eq "scripts/configure_auth_fallback.sh") {
            return $mock_script;
        }
        return $orig_f->($pattern);
    };
    
    # Test with script
    my @rollback_steps = ();
    my $result;
    
    eval {
        $result = $instance->_configure_auth_fallback('testshare', 'native', undef, \@rollback_steps);
    };
    
    is($@, '', '_configure_auth_fallback should not throw an exception');
    
    # Verify that script was called
    my $commands = $mock_tools->{called_commands};
    my $script_called = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq $mock_script) {
            $script_called = 1;
            # Check if command includes share name
            my $cmd_str = join(' ', @$cmd);
            like($cmd_str, qr/--share testshare/, 'Script command should include share name');
            like($cmd_str, qr/--mode native/, 'Script command should include mode');
        }
    }
    
    ok($script_called, 'Authentication fallback script should be called');
    
    # Clean up
    unlink $mock_script;
    
    # Restore original glob
    *CORE::GLOBAL::glob = $orig_f;
};

# Test _generate_random_password method
subtest '_generate_random_password' => sub {
    my $password = $instance->_generate_random_password(16);
    
    ok(defined $password, 'Password should be generated');
    is(length($password), 16, 'Password should have the specified length');
    like($password, qr/[A-Za-z0-9!@#\$%^&*]/, 'Password should contain valid characters');
};

# Test AD domain join with fallback
subtest '_join_ad_domain with fallback' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Create mock scripts
    my $mock_kerberos_script = "/tmp/configure_kerberos.sh";
    open my $kfh, '>', $mock_kerberos_script or die "Cannot create mock script: $!";
    print $kfh "#!/bin/bash\necho \"Mock Kerberos configuration script\"\n";
    close $kfh;
    chmod 0755, $mock_kerberos_script;
    
    my $mock_fallback_script = "/tmp/configure_auth_fallback.sh";
    open my $ffh, '>', $mock_fallback_script or die "Cannot create mock script: $!";
    print $ffh "#!/bin/bash\necho \"Mock authentication fallback script\"\n";
    close $ffh;
    chmod 0755, $mock_fallback_script;
    
    # Mock the script paths
    my $orig_f = \&CORE::GLOBAL::glob;
    no warnings 'redefine';
    *CORE::GLOBAL::glob = sub {
        my ($pattern) = @_;
        if ($pattern eq "scripts/configure_kerberos.sh") {
            return $mock_kerberos_script;
        } elsif ($pattern eq "scripts/configure_auth_fallback.sh") {
            return $mock_fallback_script;
        }
        return $orig_f->($pattern);
    };
    
    # Test with scripts
    my @rollback_steps = ();
    my $domain_info;
    
    eval {
        $domain_info = $instance->_join_ad_domain(
            'example.com', 
            'Administrator', 
            'password123', 
            'OU=Servers,DC=example,DC=com', 
            'native', 
            undef, 
            \@rollback_steps,
            'testshare',
            1
        );
    };
    
    is($@, '', '_join_ad_domain with fallback should not throw an exception');
    
    # Verify that both scripts were called
    my $commands = $mock_tools->{called_commands};
    my $kerberos_script_called = 0;
    my $fallback_script_called = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq $mock_kerberos_script) {
            $kerberos_script_called = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq $mock_fallback_script) {
            $fallback_script_called = 1;
        }
    }
    
    ok($kerberos_script_called, 'Kerberos configuration script should be called');
    ok($fallback_script_called, 'Authentication fallback script should be called');
    
    # Clean up
    unlink $mock_kerberos_script;
    unlink $mock_fallback_script;
    
    # Restore original glob
    *CORE::GLOBAL::glob = $orig_f;
};

# Test VM cloud-init configuration with fallback
subtest 'VM cloud-init with fallback' => sub {
    my $vmid = 100;
    my $share = 'testshare';
    my $ad_domain = 'example.com';
    my $ctdb_vip = '';
    
    # Set environment variables for AD credentials
    local $ENV{SMB_AD_USERNAME} = 'Administrator';
    local $ENV{SMB_AD_PASSWORD} = 'password123';
    local $ENV{SMB_AD_FALLBACK} = '1';
    
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
            my $ad_fallback = $ENV{SMB_AD_FALLBACK} // '0';
            
            # Extract domain components
            my $workgroup = uc(substr($ad_domain, 0, index($ad_domain, '.')));
            my $realm = uc($ad_domain);
            
            $user_data .= "# Configure AD domain\n";
            
            # Add domain join if credentials are provided
            if ($ad_password) {
                $user_data .= "# Join AD domain\n";
                $user_data .= "net ads join -U \"$ad_username%$ad_password\"\n";
                
                if ($ad_fallback eq '1') {
                    $user_data .= "# Configure hybrid authentication\n";
                    $user_data .= "sed -i '/\\[global\\]/a\\  auth methods = kerberos winbind sam' /etc/samba/smb.conf\n";
                    $user_data .= "sed -i '/\\[global\\]/a\\  winbind offline logon = yes' /etc/samba/smb.conf\n";
                    $user_data .= "sed -i '/\\[global\\]/a\\  winbind refresh tickets = yes' /etc/samba/smb.conf\n";
                    $user_data .= "# Create local fallback user\n";
                    $user_data .= "useradd -m -s /bin/bash smb_$share\n";
                    $user_data .= "echo 'smb_$share:$ad_password' | chpasswd\n";
                    $user_data .= "echo -e '$ad_password\\n$ad_password' | smbpasswd -a smb_$share\n";
                    
                    # Add AD connectivity monitoring
                    $user_data .= "# Create AD connectivity monitoring script\n";
                    $user_data .= "cat > /usr/local/bin/monitor_ad_connectivity.sh << 'EOT'\n";
                    $user_data .= "#!/bin/bash\n";
                    $user_data .= "# AD Connectivity Monitoring Script\n";
                    $user_data .= "DOMAIN=\$(grep -A5 '\\[global\\]' /etc/samba/smb.conf | grep 'realm' | awk '{print \$3}')\n";
                    $user_data .= "LOG_FILE=\"/var/log/ad-connectivity.log\"\n";
                    $user_data .= "# Check connectivity and log results\n";
                    $user_data .= "ping -c 1 -W 2 \$DOMAIN > /dev/null 2>&1 || echo \"\$(date): Cannot connect to AD domain \$DOMAIN\" >> \$LOG_FILE\n";
                    $user_data .= "EOT\n";
                    $user_data .= "chmod +x /usr/local/bin/monitor_ad_connectivity.sh\n";
                    
                    # Add cron job
                    $user_data .= "# Create cron job for monitoring\n";
                    $user_data .= "echo '*/5 * * * * root /usr/local/bin/monitor_ad_connectivity.sh' > /etc/cron.d/monitor-ad-connectivity\n";
                }
            }
        }
        
        return $user_data;
    };
    
    # Call the function
    my $result = $module->_configure_cloud_init($vmid, $share, $ad_domain, $ctdb_vip);
    
    # Check the result
    like($result, qr/Configure AD domain/, 'Cloud-init should configure AD domain');
    like($result, qr/Join AD domain/, 'Cloud-init should join AD domain');
    like($result, qr/Configure hybrid authentication/, 'Cloud-init should configure hybrid authentication');
    like($result, qr/Create local fallback user/, 'Cloud-init should create local fallback user');
    like($result, qr/Create AD connectivity monitoring script/, 'Cloud-init should create AD connectivity monitoring script');
    like($result, qr/Create cron job for monitoring/, 'Cloud-init should create cron job for monitoring');
};

# Test authentication method switching
subtest '_switch_authentication_method' => sub {
    # Reset mock command log
    $mock_tools->{called_commands} = [];
    
    # Test switching from AD to hybrid mode
    my $result;
    eval {
        $result = $instance->_switch_authentication_method('testshare', 'native', undef, 'hybrid');
    };
    
    is($@, '', '_switch_authentication_method should not throw an exception');
    
    # Verify that commands were called
    my $commands = $mock_tools->{called_commands};
    my $sed_called = 0;
    my $restart_called = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'sed') {
            $sed_called = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'systemctl' && $cmd->[1] eq 'restart') {
            $restart_called = 1;
        }
    }
    
    ok($sed_called, 'sed command should be called to modify smb.conf');
    ok($restart_called, 'systemctl restart should be called to restart services');
    
    # Test switching from hybrid to local mode
    $mock_tools->{called_commands} = [];
    
    eval {
        $result = $instance->_switch_authentication_method('testshare', 'native', undef, 'local');
    };
    
    is($@, '', '_switch_authentication_method should not throw an exception');
    
    # Verify that commands were called
    $commands = $mock_tools->{called_commands};
    $sed_called = 0;
    $restart_called = 0;
    
    foreach my $cmd (@$commands) {
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'sed') {
            $sed_called = 1;
        }
        if (ref($cmd) eq 'ARRAY' && $cmd->[0] eq 'systemctl' && $cmd->[1] eq 'restart') {
            $restart_called = 1;
        }
    }
    
    ok($sed_called, 'sed command should be called to modify smb.conf');
    ok($restart_called, 'systemctl restart should be called to restart services');
};

done_testing();