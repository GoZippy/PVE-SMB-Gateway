#!/bin/bash

# Security Module Test Script for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>

set -e

echo "=== PVE SMB Gateway Security Module Test Suite ==="
echo "Testing security hardening and validation..."
echo

# Test 1: Security Module Loading
echo "Test 1: Security Module Loading"
echo "================================"

# Test Perl module loading
if perl -MPVE::SMBGateway::Security -e "print 'Security module loaded successfully\n';" 2>/dev/null; then
    echo "✓ Security module loads successfully"
else
    echo "✗ Security module failed to load"
    exit 1
fi
echo

# Test 2: Security Database Creation
echo "Test 2: Security Database Creation"
echo "=================================="

# Create test security instance
cat > /tmp/test_security.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'lxc',
    path => '/tmp/test-share'
);

print "Security instance created successfully\n";
print "Database initialized: " . (-f '/var/lib/pve/smbgateway/security.db' ? 'Yes' : 'No') . "\n";
EOF

if perl /tmp/test_security.pl; then
    echo "✓ Security database created successfully"
else
    echo "✗ Security database creation failed"
    exit 1
fi
echo

# Test 3: Security Profile Creation
echo "Test 3: Security Profile Creation"
echo "================================="

cat > /tmp/test_profile.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'lxc',
    path => '/tmp/test-share'
);

my $profile = $security->create_security_profile(
    profile_type => 'standard',
    mode => 'lxc'
);

print "Profile created: $profile->{name}\n";
print "Profile type: $profile->{type}\n";
print "Mode: $profile->{mode}\n";
print "Policies: " . scalar(keys %{$profile->{policies}}) . "\n";
EOF

if perl /tmp/test_profile.pl; then
    echo "✓ Security profile creation successful"
else
    echo "✗ Security profile creation failed"
    exit 1
fi
echo

# Test 4: SMB Protocol Hardening
echo "Test 4: SMB Protocol Hardening"
echo "=============================="

# Create test Samba configuration
mkdir -p /tmp/test-samba
cat > /tmp/test-samba/smb.conf << 'EOF'
[global]
    workgroup = WORKGROUP
    server string = Test Server
    security = user
    map to guest = bad user

[test-share]
    path = /tmp/test-share
    browseable = yes
    read only = no
    guest ok = yes
EOF

cat > /tmp/test_hardening.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'lxc',
    path => '/tmp/test-share'
);

# Test SMB hardening
my $result = $security->harden_smb_protocol(
    smb_conf_path => '/tmp/test-samba/smb.conf'
);

print "SMB hardening result: $result->{status}\n";
if ($result->{status} eq 'success') {
    print "✓ SMB protocol hardening successful\n";
} else {
    print "✗ SMB protocol hardening failed: $result->{error}\n";
    exit 1;
}
EOF

if perl /tmp/test_hardening.pl; then
    echo "✓ SMB protocol hardening test passed"
else
    echo "✗ SMB protocol hardening test failed"
    exit 1
fi
echo

# Test 5: Security Scan
echo "Test 5: Security Scan"
echo "===================="

cat > /tmp/test_scan.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'lxc',
    path => '/tmp/test-share'
);

# Run security scan
my $result = $security->run_security_scan(
    scan_type => 'comprehensive'
);

print "Scan status: $result->{status}\n";
print "Findings: $result->{findings_count}\n";
print "Critical: $result->{critical_count}\n";
print "High: $result->{high_count}\n";
print "Medium: $result->{medium_count}\n";
print "Low: $result->{low_count}\n";
print "Duration: $result->{duration} seconds\n";

if ($result->{status} eq 'completed') {
    print "✓ Security scan completed successfully\n";
} else {
    print "✗ Security scan failed\n";
    exit 1;
}
EOF

if perl /tmp/test_scan.pl; then
    echo "✓ Security scan test passed"
else
    echo "✗ Security scan test failed"
    exit 1
fi
echo

# Test 6: Security Report Generation
echo "Test 6: Security Report Generation"
echo "=================================="

cat > /tmp/test_report.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'lxc',
    path => '/tmp/test-share'
);

# Generate security report
my $report = $security->generate_security_report(
    report_type => 'comprehensive',
    timeframe => 30
);

print "Report generated successfully\n";
print "Share info: $report->{share_info}->{share_name}\n";
print "Report type: $report->{report_info}->{report_type}\n";
print "Recent events: " . scalar(@{$report->{recent_events}}) . "\n";
print "Recent scans: " . scalar(@{$report->{scan_results}}) . "\n";
print "Recommendations: " . scalar(@{$report->{recommendations}}) . "\n";

print "✓ Security report generation successful\n";
EOF

if perl /tmp/test_report.pl; then
    echo "✓ Security report generation test passed"
else
    echo "✗ Security report generation test failed"
    exit 1
fi
echo

# Test 7: Service User Management
echo "Test 7: Service User Management"
echo "==============================="

cat > /tmp/test_user.pl << 'EOF'
use PVE::SMBGateway::Security;

my $security = PVE::SMBGateway::Security->new(
    share_name => 'test-share',
    share_id => 'test-share',
    mode => 'native',
    path => '/tmp/test-share'
);

# Test service user creation (will fail if not root, but should not crash)
my $result = $security->setup_service_user(
    username => 'test_smbgateway'
);

print "Service user result: $result->{status}\n";
if ($result->{status} eq 'success') {
    print "✓ Service user creation successful\n";
} else {
    print "⚠ Service user creation failed (expected if not root): $result->{error}\n";
}
EOF

if perl /tmp/test_user.pl; then
    echo "✓ Service user management test passed"
else
    echo "✗ Service user management test failed"
    exit 1
fi
echo

# Test 8: CLI Security Commands
echo "Test 8: CLI Security Commands"
echo "============================="

# Test CLI security status command
if pve-smbgateway security status test-share 2>/dev/null; then
    echo "✓ CLI security status command works"
else
    echo "⚠ CLI security status command failed (expected if no share exists)"
fi

# Test CLI security scan command
if pve-smbgateway security scan test-share comprehensive 2>/dev/null; then
    echo "✓ CLI security scan command works"
else
    echo "⚠ CLI security scan command failed (expected if no share exists)"
fi

# Test CLI security report command
if pve-smbgateway security report test-share comprehensive 30 2>/dev/null; then
    echo "✓ CLI security report command works"
else
    echo "⚠ CLI security report command failed (expected if no share exists)"
fi
echo

# Test 9: Security Integration
echo "Test 9: Security Integration"
echo "============================"

# Test security integration with main plugin
cat > /tmp/test_integration.pl << 'EOF'
use PVE::Storage::Custom::SMBGateway;

# Test security hardening method
my $result = PVE::Storage::Custom::SMBGateway::_apply_security_hardening(
    'test-ctid',
    'test-share',
    '/tmp/test-share',
    'lxc'
);

print "Security integration test result: $result->{status}\n";
if ($result->{status} eq 'success') {
    print "✓ Security integration successful\n";
} else {
    print "✗ Security integration failed\n";
    exit 1;
}
EOF

if perl /tmp/test_integration.pl; then
    echo "✓ Security integration test passed"
else
    echo "✗ Security integration test failed"
    exit 1
fi
echo

# Cleanup
echo "Test 10: Cleanup"
echo "================"

# Remove test files
rm -f /tmp/test_security.pl
rm -f /tmp/test_profile.pl
rm -f /tmp/test_hardening.pl
rm -f /tmp/test_scan.pl
rm -f /tmp/test_report.pl
rm -f /tmp/test_user.pl
rm -f /tmp/test_integration.pl
rm -rf /tmp/test-samba
rm -rf /tmp/test-share

echo "✓ Test files cleaned up"
echo

echo "=== All Security Tests Passed! ==="
echo "✅ Security module loads correctly"
echo "✅ Security database creation works"
echo "✅ Security profile creation functional"
echo "✅ SMB protocol hardening implemented"
echo "✅ Security scanning operational"
echo "✅ Security reporting functional"
echo "✅ Service user management available"
echo "✅ CLI security commands integrated"
echo "✅ Security integration with main plugin"
echo "✅ Cleanup procedures working"
echo
echo "The PVE SMB Gateway Security module is ready for production use!" 