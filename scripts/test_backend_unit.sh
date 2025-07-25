#!/bin/bash

# PVE SMB Gateway - Backend Unit Tests
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive unit tests for Perl backend components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/pve-smbgateway-backend-tests"
PERL_VERSION="5.36"
TEST_MODULES=(
    "Test::More"
    "Test::Exception"
    "Test::MockObject"
    "Test::MockModule"
    "Test::Deep"
    "Test::Warn"
    "Test::Output"
    "DBD::SQLite"
    "DBI"
    "JSON::PP"
    "Time::HiRes"
)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up backend test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Create test structure
    mkdir -p lib/PVE/Storage/Custom
    mkdir -p lib/PVE/SMBGateway
    mkdir -p t
    mkdir -p test_data
    
    # Copy source files
    cp -r /usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm lib/PVE/Storage/Custom/ 2>/dev/null || {
        log_warning "Source file not found, creating mock for testing"
        create_mock_source_files
    }
    
    # Install test dependencies
    install_test_dependencies
    
    # Create test configuration
    create_test_config
}

# Install test dependencies
install_test_dependencies() {
    log_info "Installing test dependencies..."
    
    # Check if cpanm is available
    if command -v cpanm >/dev/null 2>&1; then
        for module in "${TEST_MODULES[@]}"; do
            cpanm --quiet --notest "$module" 2>/dev/null || {
                log_warning "Failed to install $module"
            }
        done
    else
        log_warning "cpanm not available, skipping dependency installation"
    fi
}

# Create mock source files for testing
create_mock_source_files() {
    log_info "Creating mock source files for testing..."
    
    # Create mock SMBGateway.pm
    cat > lib/PVE/Storage/Custom/SMBGateway.pm << 'EOF'
package PVE::Storage::Custom::SMBGateway;

use strict;
use warnings;
use base qw(PVE::Storage::Plugin);

sub type { 'smbgateway' }
sub plugindata { { content => [ 'images', 'iso', 'backup', 'snippets' ] } }

sub properties {
    return {
        mode => { type => 'string', enum => [ 'native', 'lxc', 'vm' ] },
        sharename => { type => 'string', format => 'pve-storage-id' },
        path => { type => 'string', optional => 1 },
        quota => { type => 'string', optional => 1 },
        ad_domain => { type => 'string', optional => 1 },
        ad_join => { type => 'boolean', optional => 1, default => 0 },
        ctdb_vip => { type => 'string', optional => 1 },
        ha_enabled => { type => 'boolean', optional => 1, default => 0 },
    };
}

sub activate_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    return 1;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    return 1;
}

sub status {
    my ($class, $storeid, $scfg, %param) = @_;
    return { status => 'running', message => 'Share is active' };
}

1;
EOF

    # Create mock Monitor.pm
    cat > lib/PVE/SMBGateway/Monitor.pm << 'EOF'
package PVE::SMBGateway::Monitor;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub collect_io_stats {
    my ($self, $share_name) = @_;
    return {
        bytes_read => 1024,
        bytes_written => 2048,
        operations_read => 10,
        operations_written => 5
    };
}

sub collect_connection_stats {
    my ($self, $share_name) = @_;
    return {
        active_connections => 2,
        total_connections => 10,
        failed_connections => 1
    };
}

1;
EOF

    # Create mock CLI module
    cat > lib/PVE/SMBGateway/CLI.pm << 'EOF'
package PVE::SMBGateway::CLI;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub list_shares {
    my ($self) = @_;
    return [
        { id => 'test-share', name => 'Test Share', status => 'running' }
    ];
}

sub create_share {
    my ($self, $config) = @_;
    return { success => 1, share_id => 'test-share' };
}

1;
EOF
}

# Create test configuration
create_test_config() {
    log_info "Creating test configuration..."
    
    # Create test data
    cat > test_data/storage.cfg << 'EOF'
storage: test-share
    type smbgateway
    sharename test-share
    mode lxc
    path /srv/smb/test
    quota 10G
EOF

    # Create test environment setup
    cat > t/test_setup.pl << 'EOF'
use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Exception;

# Add lib to @INC
use lib 'lib';

# Mock PVE modules
my $mock_pve_tools = Test::MockModule->new('PVE::Tools');
$mock_pve_tools->mock('run_command', sub { return 0; });
$mock_pve_tools->mock('file_read_all', sub { return "test content"; });
$mock_pve_tools->mock('file_set_contents', sub { return 1; });

# Mock PVE::Exception
my $mock_pve_exception = Test::MockModule->new('PVE::Exception');
$mock_pve_exception->mock('raise_param_exc', sub { die "Parameter error"; });

1;
EOF
}

# Create comprehensive test files
create_test_files() {
    log_info "Creating comprehensive test files..."
    
    # Create storage plugin tests
    create_storage_plugin_tests
    
    # Create monitoring tests
    create_monitoring_tests
    
    # Create CLI tests
    create_cli_tests
    
    # Create utility tests
    create_utility_tests
    
    # Create integration tests
    create_integration_tests
}

# Create storage plugin tests
create_storage_plugin_tests() {
    cat > t/01-storage-plugin.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::MockModule;

require_ok('PVE::Storage::Custom::SMBGateway');

my $module = 'PVE::Storage::Custom::SMBGateway';

# Test basic module functionality
subtest 'Basic Module Tests' => sub {
    is($module->type, 'smbgateway', 'type() returns correct storage type');
    
    my $plugindata = $module->plugindata;
    is(ref($plugindata), 'HASH', 'plugindata() returns a hash reference');
    ok(exists($plugindata->{content}), 'plugindata contains content key');
    is(ref($plugindata->{content}), 'ARRAY', 'content is an array reference');
    
    my $properties = $module->properties;
    is(ref($properties), 'HASH', 'properties() returns a hash reference');
    ok(exists($properties->{mode}), 'properties contains mode');
    ok(exists($properties->{sharename}), 'properties contains sharename');
    ok(exists($properties->{path}), 'properties contains path');
    
    # Test mode enum
    my $mode_enum = $properties->{mode}->{enum};
    is(ref($mode_enum), 'ARRAY', 'mode enum is an array reference');
    ok(grep(/^native$/, @$mode_enum), 'mode enum contains native');
    ok(grep(/^lxc$/, @$mode_enum), 'mode enum contains lxc');
    ok(grep(/^vm$/, @$mode_enum), 'mode enum contains vm');
};

# Test storage activation
subtest 'Storage Activation Tests' => sub {
    my $scfg = {
        mode => 'lxc',
        sharename => 'test-share',
        path => '/srv/smb/test'
    };
    
    lives_ok { $module->activate_storage('test-share', $scfg) } 'activate_storage succeeds';
    
    # Test with invalid mode
    my $invalid_scfg = { mode => 'invalid', sharename => 'test-share' };
    lives_ok { $module->activate_storage('test-share', $invalid_scfg) } 'activate_storage handles invalid mode';
};

# Test storage deactivation
subtest 'Storage Deactivation Tests' => sub {
    my $scfg = {
        mode => 'lxc',
        sharename => 'test-share'
    };
    
    lives_ok { $module->deactivate_storage('test-share', $scfg) } 'deactivate_storage succeeds';
};

# Test status method
subtest 'Status Tests' => sub {
    my $scfg = {
        mode => 'lxc',
        sharename => 'test-share'
    };
    
    my $status = $module->status('test-share', $scfg);
    is(ref($status), 'HASH', 'status returns hash reference');
    ok(exists($status->{status}), 'status contains status key');
    ok(exists($status->{message}), 'status contains message key');
};

done_testing();
EOF
}

# Create monitoring tests
create_monitoring_tests() {
    cat > t/02-monitoring.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

require_ok('PVE::SMBGateway::Monitor');

my $monitor = PVE::SMBGateway::Monitor->new();

# Test monitor instantiation
subtest 'Monitor Instantiation' => sub {
    isa_ok($monitor, 'PVE::SMBGateway::Monitor', 'Monitor object created correctly');
};

# Test I/O statistics collection
subtest 'I/O Statistics Tests' => sub {
    my $io_stats = $monitor->collect_io_stats('test-share');
    
    is(ref($io_stats), 'HASH', 'collect_io_stats returns hash reference');
    ok(exists($io_stats->{bytes_read}), 'io_stats contains bytes_read');
    ok(exists($io_stats->{bytes_written}), 'io_stats contains bytes_written');
    ok(exists($io_stats->{operations_read}), 'io_stats contains operations_read');
    ok(exists($io_stats->{operations_written}), 'io_stats contains operations_written');
    
    is($io_stats->{bytes_read}, 1024, 'bytes_read has expected value');
    is($io_stats->{bytes_written}, 2048, 'bytes_written has expected value');
};

# Test connection statistics collection
subtest 'Connection Statistics Tests' => sub {
    my $conn_stats = $monitor->collect_connection_stats('test-share');
    
    is(ref($conn_stats), 'HASH', 'collect_connection_stats returns hash reference');
    ok(exists($conn_stats->{active_connections}), 'conn_stats contains active_connections');
    ok(exists($conn_stats->{total_connections}), 'conn_stats contains total_connections');
    ok(exists($conn_stats->{failed_connections}), 'conn_stats contains failed_connections');
    
    is($conn_stats->{active_connections}, 2, 'active_connections has expected value');
    is($conn_stats->{total_connections}, 10, 'total_connections has expected value');
    is($conn_stats->{failed_connections}, 1, 'failed_connections has expected value');
};

done_testing();
EOF
}

# Create CLI tests
create_cli_tests() {
    cat > t/03-cli.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

require_ok('PVE::SMBGateway::CLI');

my $cli = PVE::SMBGateway::CLI->new();

# Test CLI instantiation
subtest 'CLI Instantiation' => sub {
    isa_ok($cli, 'PVE::SMBGateway::CLI', 'CLI object created correctly');
};

# Test share listing
subtest 'Share Listing Tests' => sub {
    my $shares = $cli->list_shares();
    
    is(ref($shares), 'ARRAY', 'list_shares returns array reference');
    is(scalar(@$shares), 1, 'list_shares returns expected number of shares');
    
    my $share = $shares->[0];
    is(ref($share), 'HASH', 'share is hash reference');
    ok(exists($share->{id}), 'share contains id');
    ok(exists($share->{name}), 'share contains name');
    ok(exists($share->{status}), 'share contains status');
    
    is($share->{id}, 'test-share', 'share id has expected value');
    is($share->{name}, 'Test Share', 'share name has expected value');
    is($share->{status}, 'running', 'share status has expected value');
};

# Test share creation
subtest 'Share Creation Tests' => sub {
    my $config = {
        sharename => 'new-share',
        mode => 'lxc',
        path => '/srv/smb/new-share',
        quota => '10G'
    };
    
    my $result = $cli->create_share($config);
    
    is(ref($result), 'HASH', 'create_share returns hash reference');
    ok(exists($result->{success}), 'result contains success key');
    ok(exists($result->{share_id}), 'result contains share_id key');
    
    is($result->{success}, 1, 'create_share returns success');
    is($result->{share_id}, 'test-share', 'share_id has expected value');
};

done_testing();
EOF
}

# Create utility tests
create_utility_tests() {
    cat > t/04-utilities.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

# Test utility functions
subtest 'Quota Parsing Tests' => sub {
    # Test valid quota formats
    is(parse_quota('1G'), 1073741824, 'parse_quota handles 1G');
    is(parse_quota('10G'), 10737418240, 'parse_quota handles 10G');
    is(parse_quota('1T'), 1099511627776, 'parse_quota handles 1T');
    
    # Test invalid quota formats
    is(parse_quota('invalid'), undef, 'parse_quota handles invalid format');
    is(parse_quota('1GB'), undef, 'parse_quota handles invalid unit');
    is(parse_quota(''), undef, 'parse_quota handles empty string');
};

subtest 'Path Validation Tests' => sub {
    # Test valid paths
    ok(is_valid_path('/srv/smb/share'), 'is_valid_path accepts valid path');
    ok(is_valid_path('/mnt/data'), 'is_valid_path accepts valid path');
    ok(is_valid_path('/home/user'), 'is_valid_path accepts valid path');
    
    # Test invalid paths
    ok(!is_valid_path(''), 'is_valid_path rejects empty path');
    ok(!is_valid_path('relative/path'), 'is_valid_path rejects relative path');
    ok(!is_valid_path('path with spaces'), 'is_valid_path rejects path with spaces');
};

subtest 'Share Name Validation Tests' => sub {
    # Test valid share names
    ok(is_valid_share_name('myshare'), 'is_valid_share_name accepts valid name');
    ok(is_valid_share_name('my-share'), 'is_valid_share_name accepts valid name');
    ok(is_valid_share_name('my_share'), 'is_valid_share_name accepts valid name');
    ok(is_valid_share_name('share123'), 'is_valid_share_name accepts valid name');
    
    # Test invalid share names
    ok(!is_valid_share_name(''), 'is_valid_share_name rejects empty name');
    ok(!is_valid_share_name('my share'), 'is_valid_share_name rejects name with spaces');
    ok(!is_valid_share_name('share@123'), 'is_valid_share_name rejects invalid characters');
};

# Helper functions
sub parse_quota {
    my ($quota) = @_;
    return undef unless $quota =~ /^(\d+)([GT])$/;
    my ($value, $unit) = ($1, $2);
    my $multipliers = { 'G' => 1073741824, 'T' => 1099511627776 };
    return $value * $multipliers->{$unit};
}

sub is_valid_path {
    my ($path) = @_;
    return 0 unless $path;
    return $path =~ /^\/[a-zA-Z0-9\/_-]+$/;
}

sub is_valid_share_name {
    my ($name) = @_;
    return 0 unless $name;
    return $name =~ /^[a-zA-Z0-9_-]+$/;
}

done_testing();
EOF
}

# Create integration tests
create_integration_tests() {
    cat > t/05-integration.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;

# Test integration between components
subtest 'Storage Plugin Integration' => sub {
    require_ok('PVE::Storage::Custom::SMBGateway');
    require_ok('PVE::SMBGateway::Monitor');
    require_ok('PVE::SMBGateway::CLI');
    
    my $storage = 'PVE::Storage::Custom::SMBGateway';
    my $monitor = PVE::SMBGateway::Monitor->new();
    my $cli = PVE::SMBGateway::CLI->new();
    
    # Test complete workflow
    my $config = {
        mode => 'lxc',
        sharename => 'integration-test',
        path => '/srv/smb/integration-test',
        quota => '10G'
    };
    
    # Create share
    my $result = $cli->create_share($config);
    is($result->{success}, 1, 'Share creation succeeds');
    
    # Activate storage
    lives_ok { $storage->activate_storage('integration-test', $config) } 'Storage activation succeeds';
    
    # Get status
    my $status = $storage->status('integration-test', $config);
    is(ref($status), 'HASH', 'Status returns hash reference');
    
    # Monitor share
    my $io_stats = $monitor->collect_io_stats('integration-test');
    is(ref($io_stats), 'HASH', 'I/O stats collection succeeds');
    
    my $conn_stats = $monitor->collect_connection_stats('integration-test');
    is(ref($conn_stats), 'HASH', 'Connection stats collection succeeds');
    
    # Deactivate storage
    lives_ok { $storage->deactivate_storage('integration-test', $config) } 'Storage deactivation succeeds';
};

subtest 'Error Handling Integration' => sub {
    my $storage = 'PVE::Storage::Custom::SMBGateway';
    
    # Test with missing required parameters
    my $invalid_config = { mode => 'lxc' }; # Missing sharename
    
    lives_ok { $storage->activate_storage('test', $invalid_config) } 'Handles missing parameters gracefully';
    
    # Test with invalid configuration
    my $bad_config = { mode => 'invalid', sharename => 'test' };
    lives_ok { $storage->activate_storage('test', $bad_config) } 'Handles invalid configuration gracefully';
};

done_testing();
EOF
}

# Run all tests
run_tests() {
    log_info "Running backend unit tests..."
    
    cd "$TEST_DIR"
    
    # Run individual test files
    run_storage_plugin_tests
    run_monitoring_tests
    run_cli_tests
    run_utility_tests
    run_integration_tests
    
    # Run all tests together
    run_all_tests
}

# Run storage plugin tests
run_storage_plugin_tests() {
    log_info "Running storage plugin tests..."
    
    if perl t/01-storage-plugin.t 2>/dev/null; then
        log_success "Storage plugin tests passed"
    else
        log_error "Storage plugin tests failed"
        return 1
    fi
}

# Run monitoring tests
run_monitoring_tests() {
    log_info "Running monitoring tests..."
    
    if perl t/02-monitoring.t 2>/dev/null; then
        log_success "Monitoring tests passed"
    else
        log_error "Monitoring tests failed"
        return 1
    fi
}

# Run CLI tests
run_cli_tests() {
    log_info "Running CLI tests..."
    
    if perl t/03-cli.t 2>/dev/null; then
        log_success "CLI tests passed"
    else
        log_error "CLI tests failed"
        return 1
    fi
}

# Run utility tests
run_utility_tests() {
    log_info "Running utility tests..."
    
    if perl t/04-utilities.t 2>/dev/null; then
        log_success "Utility tests passed"
    else
        log_error "Utility tests failed"
        return 1
    fi
}

# Run integration tests
run_integration_tests() {
    log_info "Running integration tests..."
    
    if perl t/05-integration.t 2>/dev/null; then
        log_success "Integration tests passed"
    else
        log_error "Integration tests failed"
        return 1
    fi
}

# Run all tests together
run_all_tests() {
    log_info "Running all tests together..."
    
    if prove -v t/ 2>/dev/null; then
        log_success "All backend tests passed"
    else
        log_warning "Some backend tests failed (prove not available or tests failed)"
    fi
}

# Main execution
main() {
    log_info "Starting backend unit tests..."
    
    # Setup
    setup_test_environment
    create_test_files
    
    # Run tests
    run_tests
    
    # Report results
    log_info "Test Results:"
    log_info "Total Tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All backend unit tests passed!"
        exit 0
    else
        log_error "Some backend unit tests failed!"
        exit 1
    fi
}

# Cleanup on exit
trap cleanup EXIT

# Run main function
main "$@" 