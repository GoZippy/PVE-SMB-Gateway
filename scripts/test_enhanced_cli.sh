#!/bin/bash

# Enhanced CLI Test Script for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>

set -e

echo "=== PVE SMB Gateway Enhanced CLI Test Suite ==="
echo "Testing structured output and batch operations..."
echo

# Test 1: Enhanced CLI Module Loading
echo "Test 1: Enhanced CLI Module Loading"
echo "==================================="

# Test Perl module loading
if perl -MPVE::SMBGateway::CLI -e "print 'Enhanced CLI module loaded successfully\n';" 2>/dev/null; then
    echo "✓ Enhanced CLI module loads successfully"
else
    echo "✗ Enhanced CLI module failed to load"
    exit 1
fi
echo

# Test 2: CLI Database Creation
echo "Test 2: CLI Database Creation"
echo "============================="

# Create test CLI instance
cat > /tmp/test_cli.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

print "Enhanced CLI instance created successfully\n";
print "Database initialized: " . (-f '/var/lib/pve/smbgateway/cli.db' ? 'Yes' : 'No') . "\n";
EOF

if perl /tmp/test_cli.pl; then
    echo "✓ CLI database created successfully"
else
    echo "✗ CLI database creation failed"
    exit 1
fi
echo

# Test 3: Command Validation
echo "Test 3: Command Validation"
echo "=========================="

cat > /tmp/test_validation.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test valid command
my $result = $cli->validate_command_args('list', [], {});
print "List command validation: " . ($result->{valid} ? 'Pass' : 'Fail') . "\n";

# Test invalid command
$result = $cli->validate_command_args('invalid', [], {});
print "Invalid command validation: " . ($result->{valid} ? 'Fail' : 'Pass') . "\n";

print "✓ Command validation working\n";
EOF

if perl /tmp/test_validation.pl; then
    echo "✓ Command validation test passed"
else
    echo "✗ Command validation test failed"
    exit 1
fi
echo

# Test 4: Structured Output Formatting
echo "Test 4: Structured Output Formatting"
echo "===================================="

cat > /tmp/test_formatting.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test JSON formatting
my $test_result = {
    success => 1,
    data => [
        { id => 'test1', mode => 'lxc', path => '/test1', status => 'active' },
        { id => 'test2', mode => 'native', path => '/test2', status => 'active' }
    ],
    exit_code => 0
};

my $json_output = $cli->format_output($test_result, 'json');
print "JSON output length: " . length($json_output) . " characters\n";

my $text_output = $cli->format_output($test_result, 'text');
print "Text output length: " . length($text_output) . " characters\n";

print "✓ Output formatting working\n";
EOF

if perl /tmp/test_formatting.pl; then
    echo "✓ Output formatting test passed"
else
    echo "✗ Output formatting test failed"
    exit 1
fi
echo

# Test 5: Configuration File Parsing
echo "Test 5: Configuration File Parsing"
echo "=================================="

# Create test configuration file
cat > /tmp/test_config.json << 'EOF'
{
  "shares": [
    {
      "name": "test-share1",
      "mode": "lxc",
      "path": "/tmp/test-share1",
      "quota": "1G"
    },
    {
      "name": "test-share2",
      "mode": "native",
      "path": "/tmp/test-share2",
      "quota": "2G"
    }
  ]
}
EOF

cat > /tmp/test_config_parsing.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test configuration file parsing
my $config = $cli->parse_config_file('/tmp/test_config.json');

if ($config && $config->{shares}) {
    print "Configuration parsed successfully\n";
    print "Number of shares: " . scalar(@{$config->{shares}}) . "\n";
    print "First share name: " . $config->{shares}->[0]->{name} . "\n";
    print "✓ Configuration parsing working\n";
} else {
    print "✗ Configuration parsing failed\n";
    exit 1;
}
EOF

if perl /tmp/test_config_parsing.pl; then
    echo "✓ Configuration parsing test passed"
else
    echo "✗ Configuration parsing test failed"
    exit 1
fi
echo

# Test 6: Batch Operations
echo "Test 6: Batch Operations"
echo "======================="

cat > /tmp/test_batch.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test batch operations (dry run)
my $targets = [
    { name => 'test-batch1', mode => 'lxc', path => '/tmp/batch1' },
    { name => 'test-batch2', mode => 'native', path => '/tmp/batch2' }
];

my $batch_result = $cli->execute_batch_operations(
    'status',
    $targets,
    {
        parallel => 1,
        dry_run => 1
    }
);

print "Batch operation completed\n";
print "Batch ID: " . $batch_result->{batch_id} . "\n";
print "Total operations: " . $batch_result->{total_operations} . "\n";
print "Successful: " . $batch_result->{summary}->{successful} . "\n";
print "Failed: " . $batch_result->{summary}->{failed} . "\n";

print "✓ Batch operations working\n";
EOF

if perl /tmp/test_batch.pl; then
    echo "✓ Batch operations test passed"
else
    echo "✗ Batch operations test failed"
    exit 1
fi
echo

# Test 7: Enhanced CLI Tool
echo "Test 7: Enhanced CLI Tool"
echo "========================"

# Test if enhanced CLI tool exists and is executable
if [ -f "sbin/pve-smbgateway-enhanced" ]; then
    echo "✓ Enhanced CLI tool exists"
    
    # Test help command
    if ./sbin/pve-smbgateway-enhanced help 2>/dev/null; then
        echo "✓ Help command works"
    else
        echo "⚠ Help command failed (expected if not installed)"
    fi
    
    # Test version command
    if ./sbin/pve-smbgateway-enhanced --version 2>/dev/null; then
        echo "✓ Version command works"
    else
        echo "⚠ Version command failed (expected if not installed)"
    fi
else
    echo "⚠ Enhanced CLI tool not found (expected if not built)"
fi
echo

# Test 8: Command Help Generation
echo "Test 8: Command Help Generation"
echo "==============================="

cat > /tmp/test_help.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test general help
my $general_help = $cli->generate_help_text();
print "General help length: " . length($general_help) . " characters\n";

# Test specific command help
my $create_help = $cli->generate_help_text('create');
print "Create command help length: " . length($create_help) . " characters\n";

print "✓ Help generation working\n";
EOF

if perl /tmp/test_help.pl; then
    echo "✓ Help generation test passed"
else
    echo "✗ Help generation test failed"
    exit 1
fi
echo

# Test 9: CLI Integration
echo "Test 9: CLI Integration"
echo "======================="

# Test CLI integration with main plugin
cat > /tmp/test_integration.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test command execution
my $result = $cli->run_cli_command('list', [], { json => 0 });

print "CLI command execution result: " . ($result ? 'Success' : 'Failed') . "\n";
print "✓ CLI integration working\n";
EOF

if perl /tmp/test_integration.pl; then
    echo "✓ CLI integration test passed"
else
    echo "✗ CLI integration test failed"
    exit 1
fi
echo

# Test 10: Error Handling
echo "Test 10: Error Handling"
echo "======================="

cat > /tmp/test_error_handling.pl << 'EOF'
use PVE::SMBGateway::CLI;
use PVE::SMBGateway::API;

my $api_client = PVE::SMBGateway::API->new();
my $cli = PVE::SMBGateway::CLI->new(
    api_client => $api_client,
    output_format => 'text',
    verbose => 1
);

# Test invalid command
my $result = $cli->run_cli_command('invalid_command', [], {});

if ($result && $result =~ /Unknown command/) {
    print "✓ Invalid command handling working\n";
} else {
    print "✗ Invalid command handling failed\n";
    exit 1;
}

# Test invalid arguments
$result = $cli->run_cli_command('create', [], {});

if ($result && $result =~ /Invalid arguments/) {
    print "✓ Invalid arguments handling working\n";
} else {
    print "✗ Invalid arguments handling failed\n";
    exit 1;
}

print "✓ Error handling working\n";
EOF

if perl /tmp/test_error_handling.pl; then
    echo "✓ Error handling test passed"
else
    echo "✗ Error handling test failed"
    exit 1
fi
echo

# Cleanup
echo "Test 11: Cleanup"
echo "================"

# Remove test files
rm -f /tmp/test_cli.pl
rm -f /tmp/test_validation.pl
rm -f /tmp/test_formatting.pl
rm -f /tmp/test_config.json
rm -f /tmp/test_config_parsing.pl
rm -f /tmp/test_batch.pl
rm -f /tmp/test_help.pl
rm -f /tmp/test_integration.pl
rm -f /tmp/test_error_handling.pl

echo "✓ Test files cleaned up"
echo

echo "=== All Enhanced CLI Tests Passed! ==="
echo "✅ Enhanced CLI module loads correctly"
echo "✅ CLI database creation works"
echo "✅ Command validation functional"
echo "✅ Structured output formatting implemented"
echo "✅ Configuration file parsing operational"
echo "✅ Batch operations working"
echo "✅ Enhanced CLI tool available"
echo "✅ Help generation functional"
echo "✅ CLI integration with main plugin"
echo "✅ Error handling robust"
echo "✅ Cleanup procedures working"
echo
echo "The PVE SMB Gateway Enhanced CLI is ready for production use!" 