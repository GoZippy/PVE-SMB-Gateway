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

# Test AD troubleshooting scripts
subtest 'AD troubleshooting scripts' => sub {
    # Check if scripts exist
    ok(-f "scripts/ad_troubleshoot.sh", "AD troubleshooting script should exist");
    ok(-f "scripts/test_ad_connectivity.sh", "AD connectivity test script should exist");
    ok(-f "scripts/validate_kerberos.sh", "Kerberos validation script should exist");
    
    # Test script content
    my $troubleshoot_script = `cat scripts/ad_troubleshoot.sh 2>/dev/null`;
    like($troubleshoot_script, qr/SMB Gateway AD Troubleshooting/, "Troubleshooting script should contain expected header");
    like($troubleshoot_script, qr/check_dns/, "Troubleshooting script should check DNS");
    like($troubleshoot_script, qr/check_kerberos/, "Troubleshooting script should check Kerberos");
    like($troubleshoot_script, qr/check_samba/, "Troubleshooting script should check Samba");
    like($troubleshoot_script, qr/check_domain_membership/, "Troubleshooting script should check domain membership");
    
    my $connectivity_script = `cat scripts/test_ad_connectivity.sh 2>/dev/null`;
    like($connectivity_script, qr/Testing DNS resolution/, "Connectivity script should test DNS resolution");
    like($connectivity_script, qr/Testing LDAP connectivity/, "Connectivity script should test LDAP connectivity");
    like($connectivity_script, qr/Testing Kerberos connectivity/, "Connectivity script should test Kerberos connectivity");
    
    my $kerberos_script = `cat scripts/validate_kerberos.sh 2>/dev/null`;
    like($kerberos_script, qr/Checking Kerberos configuration/, "Kerberos script should check configuration");
    like($kerberos_script, qr/Getting new Kerberos ticket/, "Kerberos script should get tickets");
    like($kerberos_script, qr/Testing service ticket acquisition/, "Kerberos script should test service tickets");
};

# Test domain controller discovery
subtest '_discover_domain_controllers' => sub {
    # Mock backtick to simulate SRV record lookup
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /host -t SRV/) {
            return "has SRV record 0 0 389 dc.example.com.\n";
        }
        return "";
    });
    
    my $result = $instance->_discover_domain_controllers('example.com', 'native');
    ok($result, 'Domain controller discovery should succeed');
    
    # Mock backtick to simulate failed SRV record lookup
    $mock_system->mock('backtick', sub { 
        my ($cmd) = @_;
        if ($cmd =~ /host -t SRV/) {
            return "not found\n";
        }
        return "";
    });
    
    $result = $instance->_discover_domain_controllers('example.com', 'native');
    ok(!$result, 'Domain controller discovery should fail when SRV records are not found');
};

# Test domain connection testing
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

done_testing();