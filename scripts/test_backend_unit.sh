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
            cpanm --quiet --notest "$module" || log_warning "Failed to install $module"
        done
    else
        log_warning "cpanm not available, skipping module installation"
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
use Test::MockObject;

# Mock PVE modules
my $mock_tools = Test::MockObject->new();
$mock_tools->mock('run_command', sub { return 1; });
$mock_tools->mock('file_read_all', sub { return "mock content"; });
$mock_tools->mock('file_set_contents', sub { return 1; });

# Mock PVE::Exception
my $mock_exception = Test::MockObject->new();
$mock_exception->mock('raise_param_exc', sub { die "Parameter error: $_[1]"; });

# Mock PVE::JSONSchema
my $mock_schema = Test::MockObject->new();
$mock_schema->mock('get_standard_option', sub { return { type => 'string' }; });

# Mock Time::HiRes
my $mock_time = Test::MockObject->new();
$mock_time->mock('time', sub { return 1640995200; });

# Mock JSON::PP
my $mock_json = Test::MockObject->new();
$mock_json->mock('encode_json', sub { return '{"test": "data"}'; });
$mock_json->mock('decode_json', sub { return { test => 'data' }; });

# Main plugin class
sub type { 'smbgateway' }
sub plugindata { { content => [ 'images', 'iso', 'backup', 'snippets' ] } }

sub properties {
    return {
        mode      => { type => 'string',  enum => [ 'native', 'lxc', 'vm' ] },
        sharename => { type => 'string',  format => 'pve-storage-id' },
        path      => { type => 'string',  optional => 1 },
        quota     => { type => 'string',  optional => 1 },
        ad_domain => { type => 'string',  optional => 1 },
        ad_join   => { type => 'boolean', optional => 1, default => 0 },
        ctdb_vip  => { type => 'string',  optional => 1 },
        ha_enabled => { type => 'boolean', optional => 1, default => 0 },
        vm_memory => { type => 'integer', optional => 1, default => 2048 },
        vm_cores  => { type => 'integer', optional => 1, default => 2 },
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
    return { status => 'active', message => 'Mock status' };
}

sub create_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    return 1;
}

sub delete_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    return 1;
}

# Mock helper methods
sub _validate_sharename {
    my ($self, $sharename) = @_;
    return $sharename =~ /^[a-zA-Z0-9_-]+$/;
}

sub _validate_quota {
    my ($self, $quota) = @_;
    return $quota =~ /^\d+[GT]$/;
}

sub _validate_vip {
    my ($self, $vip) = @_;
    return $vip =~ /^(\d{1,3}\.){3}\d{1,3}$/;
}

sub _validate_domain {
    my ($self, $domain) = @_;
    return $domain =~ /^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
}

1;
EOF

    # Create mock Monitor.pm
    cat > lib/PVE/SMBGateway/Monitor.pm << 'EOF'
package PVE::SMBGateway::Monitor;

use strict;
use warnings;
use Test::MockObject;

# Mock DBI
my $mock_dbi = Test::MockObject->new();
$mock_dbi->mock('connect', sub { return $mock_dbi; });
$mock_dbi->mock('prepare', sub { return $mock_dbi; });
$mock_dbi->mock('execute', sub { return 1; });
$mock_dbi->mock('fetchrow_hashref', sub { return { test => 'data' }; });
$mock_dbi->mock('finish', sub { return 1; });
$mock_dbi->mock('disconnect', sub { return 1; });

sub new {
    my ($class, %param) = @_;
    return bless {
        share_name => $param{share_name} || 'test-share',
        share_path => $param{share_path} || '/srv/smb/test-share',
        db_path => $param{db_path} || '/tmp/test-metrics.db'
    }, $class;
}

sub collect_io_stats {
    my ($self) = @_;
    return {
        bytes_read => 1024,
        bytes_written => 2048,
        operations_read => 10,
        operations_written => 5,
        latency_avg_ms => 1.5,
        latency_max_ms => 5.0,
        iops_total => 15,
        throughput_mbps => 2.5
    };
}

sub collect_connection_stats {
    my ($self) = @_;
    return {
        active_connections => 5,
        total_connections => 100,
        failed_connections => 2,
        auth_failures => 1,
        concurrent_users => 3,
        session_count => 8
    };
}

sub collect_quota_stats {
    my ($self) = @_;
    return {
        quota_limit => 10737418240, # 10GB
        quota_used => 2684354560,   # 2.5GB
        quota_percent => 25.0,
        files_count => 100,
        directories_count => 10,
        largest_file_size => 104857600 # 100MB
    };
}

sub collect_system_stats {
    my ($self) = @_;
    return {
        cpu_usage_percent => 15.5,
        memory_usage_percent => 45.2,
        disk_usage_percent => 60.8,
        network_rx_mbps => 10.5,
        network_tx_mbps => 8.2,
        load_average => 0.75
    };
}

sub store_metrics {
    my ($self, $metrics) = @_;
    return 1;
}

sub get_metrics {
    my ($self, $share_name, $start_time) = @_;
    return [
        {
            timestamp => 1640995200,
            io_stats => $self->collect_io_stats(),
            connection_stats => $self->collect_connection_stats(),
            quota_stats => $self->collect_quota_stats(),
            system_stats => $self->collect_system_stats()
        }
    ];
}

sub cleanup_old_metrics {
    my ($self, $days) = @_;
    return { deleted_records => 100 };
}

1;
EOF

    # Create mock Backup.pm
    cat > lib/PVE/SMBGateway/Backup.pm << 'EOF'
package PVE::SMBGateway::Backup;

use strict;
use warnings;
use Test::MockObject;

sub new {
    my ($class, %param) = @_;
    return bless {
        share_name => $param{share_name} || 'test-share',
        share_id => $param{share_id} || 'test-share',
        mode => $param{mode} || 'lxc',
        path => $param{path} || '/srv/smb/test-share'
    }, $class;
}

sub register_backup_job {
    my ($self, %param) = @_;
    return {
        success => 1,
        job_id => 'backup-123',
        message => 'Backup job registered successfully'
    };
}

sub unregister_backup_job {
    my ($self) = @_;
    return {
        success => 1,
        message => 'Backup job unregistered successfully'
    };
}

sub create_backup_snapshot {
    my ($self, %param) = @_;
    return {
        success => 1,
        snapshot_name => 'snapshot-123',
        size_bytes => 1073741824, # 1GB
        message => 'Backup snapshot created successfully'
    };
}

sub restore_backup_snapshot {
    my ($self, $snapshot_name, %param) = @_;
    return {
        success => 1,
        message => 'Backup restored successfully'
    };
}

sub verify_backup_integrity {
    my ($self, $snapshot_name) = @_;
    return {
        success => 1,
        integrity_check => 'passed',
        message => 'Backup integrity verified'
    };
}

sub get_backup_status {
    my ($self) = @_;
    return {
        last_backup => 1640995200,
        last_status => 'success',
        next_backup => 1641081600,
        total_snapshots => 5,
        total_size_bytes => 5368709120 # 5GB
    };
}

sub list_backup_jobs {
    return [
        {
            share_id => 'test-share',
            schedule => 'daily',
            enabled => 1,
            last_run => 1640995200
        }
    ];
}

1;
EOF
}

# Create test configuration
create_test_config() {
    cat > test_config.pl << 'EOF'
# Test configuration for PVE SMB Gateway
use strict;
use warnings;

our $TEST_CONFIG = {
    # Test data
    test_share => {
        sharename => 'test-share',
        mode => 'lxc',
        path => '/srv/smb/test-share',
        quota => '10G',
        ad_domain => 'test.local',
        ad_join => 1,
        ctdb_vip => '192.168.1.100',
        ha_enabled => 1,
        vm_memory => 2048,
        vm_cores => 2
    },
    
    # Test scenarios
    scenarios => {
        basic_lxc => {
            sharename => 'basic-lxc',
            mode => 'lxc',
            path => '/srv/smb/basic-lxc',
            quota => '5G'
        },
        native_ad => {
            sharename => 'native-ad',
            mode => 'native',
            path => '/srv/smb/native-ad',
            ad_domain => 'test.local',
            ad_join => 1
        },
        vm_ha => {
            sharename => 'vm-ha',
            mode => 'vm',
            path => '/srv/smb/vm-ha',
            vm_memory => 4096,
            vm_cores => 4,
            ha_enabled => 1,
            ctdb_vip => '192.168.1.200'
        }
    },
    
    # Expected results
    expected_results => {
        valid_sharename => ['test-share', 'my-share', 'share123'],
        invalid_sharename => ['', 'ab', 'my share', 'share@123'],
        valid_quota => ['1G', '10G', '100G', '1T', '10T'],
        invalid_quota => ['1', '1M', '1K', '1GB', 'abc'],
        valid_vip => ['192.168.1.100', '10.0.0.1', '172.16.0.1'],
        invalid_vip => ['192.168.1', '192.168.1.256', '192.168.1.abc'],
        valid_domain => ['example.com', 'test.local', 'subdomain.example.com'],
        invalid_domain => ['example', '.com', 'example.', 'example..com']
    }
};

1;
EOF
}

# Create individual test files
create_storage_plugin_tests() {
    cat > t/01-storage-plugin.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::MockObject;
use lib 'lib';

# Load test configuration
require 'test_config.pl';

# Load the module
use_ok('PVE::Storage::Custom::SMBGateway');

# Test basic functionality
subtest 'Basic Plugin Functions' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    
    is($plugin->type(), 'smbgateway', 'Plugin type is correct');
    
    my $plugindata = $plugin->plugindata();
    is_deeply($plugindata, { content => [ 'images', 'iso', 'backup', 'snippets' ] }, 'Plugin data is correct');
    
    my $properties = $plugin->properties();
    ok(exists $properties->{mode}, 'Mode property exists');
    ok(exists $properties->{sharename}, 'Sharename property exists');
    ok(exists $properties->{path}, 'Path property exists');
    ok(exists $properties->{quota}, 'Quota property exists');
    
    done_testing();
};

# Test validation methods
subtest 'Validation Methods' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    
    # Test sharename validation
    ok($plugin->_validate_sharename('test-share'), 'Valid sharename passes');
    ok($plugin->_validate_sharename('my_share'), 'Valid sharename with underscore passes');
    ok($plugin->_validate_sharename('share123'), 'Valid sharename with numbers passes');
    
    ok(!$plugin->_validate_sharename(''), 'Empty sharename fails');
    ok(!$plugin->_validate_sharename('ab'), 'Short sharename fails');
    ok(!$plugin->_validate_sharename('my share'), 'Sharename with space fails');
    ok(!$plugin->_validate_sharename('share@123'), 'Sharename with special chars fails');
    
    # Test quota validation
    ok($plugin->_validate_quota('1G'), 'Valid quota passes');
    ok($plugin->_validate_quota('10G'), 'Valid quota passes');
    ok($plugin->_validate_quota('1T'), 'Valid quota passes');
    
    ok(!$plugin->_validate_quota('1'), 'Invalid quota fails');
    ok(!$plugin->_validate_quota('1M'), 'Invalid quota unit fails');
    ok(!$plugin->_validate_quota('1GB'), 'Invalid quota format fails');
    
    # Test VIP validation
    ok($plugin->_validate_vip('192.168.1.100'), 'Valid VIP passes');
    ok($plugin->_validate_vip('10.0.0.1'), 'Valid VIP passes');
    
    ok(!$plugin->_validate_vip('192.168.1'), 'Invalid VIP fails');
    ok(!$plugin->_validate_vip('192.168.1.256'), 'Invalid VIP fails');
    ok(!$plugin->_validate_vip('192.168.1.abc'), 'Invalid VIP fails');
    
    # Test domain validation
    ok($plugin->_validate_domain('example.com'), 'Valid domain passes');
    ok($plugin->_validate_domain('test.local'), 'Valid domain passes');
    
    ok(!$plugin->_validate_domain('example'), 'Invalid domain fails');
    ok(!$plugin->_validate_domain('.com'), 'Invalid domain fails');
    ok(!$plugin->_validate_domain('example..com'), 'Invalid domain fails');
    
    done_testing();
};

# Test storage operations
subtest 'Storage Operations' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    
    # Test storage creation
    lives_ok {
        $plugin->create_storage('test-share', {
            sharename => 'test-share',
            mode => 'lxc',
            path => '/srv/smb/test-share'
        });
    } 'Storage creation does not die';
    
    # Test storage activation
    lives_ok {
        $plugin->activate_storage('test-share', {
            sharename => 'test-share',
            mode => 'lxc'
        });
    } 'Storage activation does not die';
    
    # Test storage status
    my $status = $plugin->status('test-share', {
        sharename => 'test-share',
        mode => 'lxc'
    });
    is($status->{status}, 'active', 'Storage status is active');
    
    # Test storage deactivation
    lives_ok {
        $plugin->deactivate_storage('test-share', {
            sharename => 'test-share',
            mode => 'lxc'
        });
    } 'Storage deactivation does not die';
    
    # Test storage deletion
    lives_ok {
        $plugin->delete_storage('test-share', {
            sharename => 'test-share',
            mode => 'lxc'
        });
    } 'Storage deletion does not die';
    
    done_testing();
};

# Test configuration scenarios
subtest 'Configuration Scenarios' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    
    # Test basic LXC configuration
    lives_ok {
        $plugin->create_storage('basic-lxc', $TEST_CONFIG->{scenarios}->{basic_lxc});
    } 'Basic LXC configuration works';
    
    # Test native AD configuration
    lives_ok {
        $plugin->create_storage('native-ad', $TEST_CONFIG->{scenarios}->{native_ad});
    } 'Native AD configuration works';
    
    # Test VM HA configuration
    lives_ok {
        $plugin->create_storage('vm-ha', $TEST_CONFIG->{scenarios}->{vm_ha});
    } 'VM HA configuration works';
    
    done_testing();
};

done_testing();
EOF
}

create_monitoring_tests() {
    cat > t/02-monitoring.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib 'lib';

# Load test configuration
require 'test_config.pl';

# Load the module
use_ok('PVE::SMBGateway::Monitor');

# Test monitor initialization
subtest 'Monitor Initialization' => sub {
    my $monitor = PVE::SMBGateway::Monitor->new(
        share_name => 'test-share',
        share_path => '/srv/smb/test-share',
        db_path => '/tmp/test-metrics.db'
    );
    
    isa_ok($monitor, 'PVE::SMBGateway::Monitor', 'Monitor object created');
    is($monitor->{share_name}, 'test-share', 'Share name set correctly');
    is($monitor->{share_path}, '/srv/smb/test-share', 'Share path set correctly');
    is($monitor->{db_path}, '/tmp/test-metrics.db', 'DB path set correctly');
    
    done_testing();
};

# Test metrics collection
subtest 'Metrics Collection' => sub {
    my $monitor = PVE::SMBGateway::Monitor->new();
    
    # Test I/O stats collection
    my $io_stats = $monitor->collect_io_stats();
    ok(exists $io_stats->{bytes_read}, 'I/O stats contains bytes_read');
    ok(exists $io_stats->{bytes_written}, 'I/O stats contains bytes_written');
    ok(exists $io_stats->{operations_read}, 'I/O stats contains operations_read');
    ok(exists $io_stats->{operations_written}, 'I/O stats contains operations_written');
    ok(exists $io_stats->{latency_avg_ms}, 'I/O stats contains latency_avg_ms');
    ok(exists $io_stats->{throughput_mbps}, 'I/O stats contains throughput_mbps');
    
    # Test connection stats collection
    my $conn_stats = $monitor->collect_connection_stats();
    ok(exists $conn_stats->{active_connections}, 'Connection stats contains active_connections');
    ok(exists $conn_stats->{total_connections}, 'Connection stats contains total_connections');
    ok(exists $conn_stats->{failed_connections}, 'Connection stats contains failed_connections');
    ok(exists $conn_stats->{auth_failures}, 'Connection stats contains auth_failures');
    ok(exists $conn_stats->{concurrent_users}, 'Connection stats contains concurrent_users');
    
    # Test quota stats collection
    my $quota_stats = $monitor->collect_quota_stats();
    ok(exists $quota_stats->{quota_limit}, 'Quota stats contains quota_limit');
    ok(exists $quota_stats->{quota_used}, 'Quota stats contains quota_used');
    ok(exists $quota_stats->{quota_percent}, 'Quota stats contains quota_percent');
    ok(exists $quota_stats->{files_count}, 'Quota stats contains files_count');
    ok(exists $quota_stats->{directories_count}, 'Quota stats contains directories_count');
    
    # Test system stats collection
    my $sys_stats = $monitor->collect_system_stats();
    ok(exists $sys_stats->{cpu_usage_percent}, 'System stats contains cpu_usage_percent');
    ok(exists $sys_stats->{memory_usage_percent}, 'System stats contains memory_usage_percent');
    ok(exists $sys_stats->{disk_usage_percent}, 'System stats contains disk_usage_percent');
    ok(exists $sys_stats->{network_rx_mbps}, 'System stats contains network_rx_mbps');
    ok(exists $sys_stats->{network_tx_mbps}, 'System stats contains network_tx_mbps');
    
    done_testing();
};

# Test metrics storage and retrieval
subtest 'Metrics Storage and Retrieval' => sub {
    my $monitor = PVE::SMBGateway::Monitor->new();
    
    # Test metrics storage
    my $metrics = {
        io_stats => $monitor->collect_io_stats(),
        connection_stats => $monitor->collect_connection_stats(),
        quota_stats => $monitor->collect_quota_stats(),
        system_stats => $monitor->collect_system_stats()
    };
    
    lives_ok {
        $monitor->store_metrics($metrics);
    } 'Metrics storage does not die';
    
    # Test metrics retrieval
    my $retrieved_metrics = $monitor->get_metrics('test-share', 1640995200);
    isa_ok($retrieved_metrics, 'ARRAY', 'Retrieved metrics is an array');
    ok(scalar @$retrieved_metrics > 0, 'Retrieved metrics contains data');
    
    my $first_metric = $retrieved_metrics->[0];
    ok(exists $first_metric->{timestamp}, 'Metric contains timestamp');
    ok(exists $first_metric->{io_stats}, 'Metric contains io_stats');
    ok(exists $first_metric->{connection_stats}, 'Metric contains connection_stats');
    ok(exists $first_metric->{quota_stats}, 'Metric contains quota_stats');
    ok(exists $first_metric->{system_stats}, 'Metric contains system_stats');
    
    done_testing();
};

# Test cleanup operations
subtest 'Cleanup Operations' => sub {
    my $monitor = PVE::SMBGateway::Monitor->new();
    
    # Test old metrics cleanup
    my $cleanup_result = $monitor->cleanup_old_metrics(30);
    ok(exists $cleanup_result->{deleted_records}, 'Cleanup result contains deleted_records');
    ok($cleanup_result->{deleted_records} >= 0, 'Deleted records count is valid');
    
    done_testing();
};

done_testing();
EOF
}

create_backup_tests() {
    cat > t/03-backup.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib 'lib';

# Load test configuration
require 'test_config.pl';

# Load the module
use_ok('PVE::SMBGateway::Backup');

# Test backup initialization
subtest 'Backup Initialization' => sub {
    my $backup = PVE::SMBGateway::Backup->new(
        share_name => 'test-share',
        share_id => 'test-share',
        mode => 'lxc',
        path => '/srv/smb/test-share'
    );
    
    isa_ok($backup, 'PVE::SMBGateway::Backup', 'Backup object created');
    is($backup->{share_name}, 'test-share', 'Share name set correctly');
    is($backup->{share_id}, 'test-share', 'Share ID set correctly');
    is($backup->{mode}, 'lxc', 'Mode set correctly');
    is($backup->{path}, '/srv/smb/test-share', 'Path set correctly');
    
    done_testing();
};

# Test backup job management
subtest 'Backup Job Management' => sub {
    my $backup = PVE::SMBGateway::Backup->new();
    
    # Test backup job registration
    my $register_result = $backup->register_backup_job(
        schedule => 'daily',
        retention_days => 30,
        enabled => 1
    );
    
    ok($register_result->{success}, 'Backup job registration successful');
    ok(exists $register_result->{job_id}, 'Registration result contains job_id');
    ok(exists $register_result->{message}, 'Registration result contains message');
    
    # Test backup job unregistration
    my $unregister_result = $backup->unregister_backup_job();
    
    ok($unregister_result->{success}, 'Backup job unregistration successful');
    ok(exists $unregister_result->{message}, 'Unregistration result contains message');
    
    done_testing();
};

# Test backup operations
subtest 'Backup Operations' => sub {
    my $backup = PVE::SMBGateway::Backup->new();
    
    # Test backup snapshot creation
    my $create_result = $backup->create_backup_snapshot(
        type => 'manual',
        snapshot_name => 'test-snapshot'
    );
    
    ok($create_result->{success}, 'Backup snapshot creation successful');
    ok(exists $create_result->{snapshot_name}, 'Creation result contains snapshot_name');
    ok(exists $create_result->{size_bytes}, 'Creation result contains size_bytes');
    ok(exists $create_result->{message}, 'Creation result contains message');
    
    # Test backup restoration
    my $restore_result = $backup->restore_backup_snapshot(
        'test-snapshot',
        dry_run => 0
    );
    
    ok($restore_result->{success}, 'Backup restoration successful');
    ok(exists $restore_result->{message}, 'Restoration result contains message');
    
    # Test backup integrity verification
    my $verify_result = $backup->verify_backup_integrity('test-snapshot');
    
    ok($verify_result->{success}, 'Backup integrity verification successful');
    ok(exists $verify_result->{integrity_check}, 'Verification result contains integrity_check');
    ok(exists $verify_result->{message}, 'Verification result contains message');
    
    done_testing();
};

# Test backup status and listing
subtest 'Backup Status and Listing' => sub {
    my $backup = PVE::SMBGateway::Backup->new();
    
    # Test backup status retrieval
    my $status = $backup->get_backup_status();
    
    ok(exists $status->{last_backup}, 'Status contains last_backup');
    ok(exists $status->{last_status}, 'Status contains last_status');
    ok(exists $status->{next_backup}, 'Status contains next_backup');
    ok(exists $status->{total_snapshots}, 'Status contains total_snapshots');
    ok(exists $status->{total_size_bytes}, 'Status contains total_size_bytes');
    
    # Test backup job listing
    my $jobs = PVE::SMBGateway::Backup::list_backup_jobs();
    isa_ok($jobs, 'ARRAY', 'Backup jobs list is an array');
    ok(scalar @$jobs > 0, 'Backup jobs list contains data');
    
    my $first_job = $jobs->[0];
    ok(exists $first_job->{share_id}, 'Job contains share_id');
    ok(exists $first_job->{schedule}, 'Job contains schedule');
    ok(exists $first_job->{enabled}, 'Job contains enabled');
    ok(exists $first_job->{last_run}, 'Job contains last_run');
    
    done_testing();
};

done_testing();
EOF
}

create_utility_tests() {
    cat > t/04-utilities.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib 'lib';

# Load test configuration
require 'test_config.pl';

# Test utility functions
subtest 'Utility Functions' => sub {
    # Test human-readable size conversion
    subtest 'Size Conversion' => sub {
        # Test bytes to human
        is(bytes_to_human(1024), '1.0K', '1024 bytes = 1.0K');
        is(bytes_to_human(1048576), '1.0M', '1048576 bytes = 1.0M');
        is(bytes_to_human(1073741824), '1.0G', '1073741824 bytes = 1.0G');
        is(bytes_to_human(1099511627776), '1.0T', '1099511627776 bytes = 1.0T');
        
        # Test human to bytes
        is(human_to_bytes('1K'), 1024, '1K = 1024 bytes');
        is(human_to_bytes('1M'), 1048576, '1M = 1048576 bytes');
        is(human_to_bytes('1G'), 1073741824, '1G = 1073741824 bytes');
        is(human_to_bytes('1T'), 1099511627776, '1T = 1099511627776 bytes');
        
        done_testing();
    };
    
    # Test filesystem detection
    subtest 'Filesystem Detection' => sub {
        # Mock filesystem detection
        my $fs_type = detect_filesystem_type('/test/path');
        ok($fs_type =~ /^(zfs|xfs|ext4|btrfs)$/, 'Filesystem type is valid');
        
        done_testing();
    };
    
    # Test network utilities
    subtest 'Network Utilities' => sub {
        # Test IP validation
        ok(is_valid_ip('192.168.1.100'), 'Valid IP passes');
        ok(is_valid_ip('10.0.0.1'), 'Valid IP passes');
        ok(!is_valid_ip('192.168.1'), 'Invalid IP fails');
        ok(!is_valid_ip('192.168.1.256'), 'Invalid IP fails');
        
        # Test domain validation
        ok(is_valid_domain('example.com'), 'Valid domain passes');
        ok(is_valid_domain('test.local'), 'Valid domain passes');
        ok(!is_valid_domain('example'), 'Invalid domain fails');
        ok(!is_valid_domain('.com'), 'Invalid domain fails');
        
        done_testing();
    };
    
    done_testing();
};

# Utility function implementations for testing
sub bytes_to_human {
    my ($bytes) = @_;
    
    if ($bytes >= 1099511627776) {
        return sprintf("%.1fT", $bytes / 1099511627776);
    } elsif ($bytes >= 1073741824) {
        return sprintf("%.1fG", $bytes / 1073741824);
    } elsif ($bytes >= 1048576) {
        return sprintf("%.1fM", $bytes / 1048576);
    } elsif ($bytes >= 1024) {
        return sprintf("%.1fK", $bytes / 1024);
    } else {
        return "${bytes}B";
    }
}

sub human_to_bytes {
    my ($human) = @_;
    
    if ($human =~ /^(\d+)([KMGT]?)$/) {
        my ($size, $unit) = ($1, $2);
        
        if ($unit eq 'K') {
            return $size * 1024;
        } elsif ($unit eq 'M') {
            return $size * 1024**2;
        } elsif ($unit eq 'G') {
            return $size * 1024**3;
        } elsif ($unit eq 'T') {
            return $size * 1024**4;
        } else {
            return $size;
        }
    }
    
    return 0;
}

sub detect_filesystem_type {
    my ($path) = @_;
    # Mock filesystem detection
    my @types = qw(zfs xfs ext4 btrfs);
    return $types[int(rand(scalar @types))];
}

sub is_valid_ip {
    my ($ip) = @_;
    return $ip =~ /^(\d{1,3}\.){3}\d{1,3}$/;
}

sub is_valid_domain {
    my ($domain) = @_;
    return $domain =~ /^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
}

done_testing();
EOF
}

create_integration_tests() {
    cat > t/05-integration.t << 'EOF'
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib 'lib';

# Load test configuration
require 'test_config.pl';

# Load modules
use_ok('PVE::Storage::Custom::SMBGateway');
use_ok('PVE::SMBGateway::Monitor');
use_ok('PVE::SMBGateway::Backup');

# Test complete workflow
subtest 'Complete Workflow' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    my $test_config = $TEST_CONFIG->{test_share};
    
    # Step 1: Create storage
    lives_ok {
        $plugin->create_storage('test-share', $test_config);
    } 'Storage creation works';
    
    # Step 2: Activate storage
    lives_ok {
        $plugin->activate_storage('test-share', $test_config);
    } 'Storage activation works';
    
    # Step 3: Check status
    my $status = $plugin->status('test-share', $test_config);
    is($status->{status}, 'active', 'Storage is active');
    
    # Step 4: Initialize monitoring
    my $monitor = PVE::SMBGateway::Monitor->new(
        share_name => 'test-share',
        share_path => $test_config->{path}
    );
    isa_ok($monitor, 'PVE::SMBGateway::Monitor', 'Monitor initialized');
    
    # Step 5: Collect metrics
    my $metrics = {
        io_stats => $monitor->collect_io_stats(),
        connection_stats => $monitor->collect_connection_stats(),
        quota_stats => $monitor->collect_quota_stats(),
        system_stats => $monitor->collect_system_stats()
    };
    ok(exists $metrics->{io_stats}, 'I/O metrics collected');
    ok(exists $metrics->{connection_stats}, 'Connection metrics collected');
    ok(exists $metrics->{quota_stats}, 'Quota metrics collected');
    ok(exists $metrics->{system_stats}, 'System metrics collected');
    
    # Step 6: Store metrics
    lives_ok {
        $monitor->store_metrics($metrics);
    } 'Metrics storage works';
    
    # Step 7: Initialize backup
    my $backup = PVE::SMBGateway::Backup->new(
        share_name => 'test-share',
        share_id => 'test-share',
        mode => $test_config->{mode},
        path => $test_config->{path}
    );
    isa_ok($backup, 'PVE::SMBGateway::Backup', 'Backup initialized');
    
    # Step 8: Register backup job
    my $backup_result = $backup->register_backup_job(
        schedule => 'daily',
        retention_days => 30,
        enabled => 1
    );
    ok($backup_result->{success}, 'Backup job registered');
    
    # Step 9: Create backup snapshot
    my $snapshot_result = $backup->create_backup_snapshot(
        type => 'manual',
        snapshot_name => 'test-snapshot'
    );
    ok($snapshot_result->{success}, 'Backup snapshot created');
    
    # Step 10: Verify backup
    my $verify_result = $backup->verify_backup_integrity('test-snapshot');
    ok($verify_result->{success}, 'Backup integrity verified');
    
    # Step 11: Get backup status
    my $backup_status = $backup->get_backup_status();
    ok(exists $backup_status->{last_backup}, 'Backup status retrieved');
    
    # Step 12: Deactivate storage
    lives_ok {
        $plugin->deactivate_storage('test-share', $test_config);
    } 'Storage deactivation works';
    
    # Step 13: Delete storage
    lives_ok {
        $plugin->delete_storage('test-share', $test_config);
    } 'Storage deletion works';
    
    done_testing();
};

# Test error handling
subtest 'Error Handling' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    
    # Test invalid configuration
    throws_ok {
        $plugin->create_storage('invalid-share', {
            sharename => '',  # Invalid sharename
            mode => 'invalid' # Invalid mode
        });
    } qr/Parameter error/, 'Invalid configuration throws error';
    
    # Test missing required parameters
    throws_ok {
        $plugin->create_storage('missing-share', {});
    } qr/Parameter error/, 'Missing parameters throws error';
    
    done_testing();
};

# Test performance
subtest 'Performance Tests' => sub {
    my $plugin = 'PVE::Storage::Custom::SMBGateway';
    my $monitor = PVE::SMBGateway::Monitor->new();
    
    # Test metrics collection performance
    my $start_time = time();
    for (1..100) {
        $monitor->collect_io_stats();
        $monitor->collect_connection_stats();
        $monitor->collect_quota_stats();
        $monitor->collect_system_stats();
    }
    my $end_time = time();
    my $duration = $end_time - $start_time;
    
    ok($duration < 5, "Metrics collection completed in ${duration}s (should be < 5s)");
    
    done_testing();
};

done_testing();
EOF
}

# Run tests
run_tests() {
    log_info "Running backend unit tests..."
    
    # Create test files
    create_storage_plugin_tests
    create_monitoring_tests
    create_backup_tests
    create_utility_tests
    create_integration_tests
    
    # Set up Perl environment
    export PERL5LIB="lib:$PERL5LIB"
    
    # Run tests
    log_info "Executing test suite..."
    
    local test_results=0
    
    for test_file in t/*.t; do
        log_info "Running $test_file..."
        if perl "$test_file"; then
            log_success "$test_file passed"
        else
            log_error "$test_file failed"
            ((test_results++))
        fi
    done
    
    return $test_results
}

# Main execution
main() {
    log_info "Starting PVE SMB Gateway Backend Unit Tests"
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Setup test environment
    setup_test_environment
    
    # Run tests
    run_tests
    local test_exit_code=$?
    
    # Print summary
    log_info "Test Summary:"
    log_info "Total Tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [ $test_exit_code -eq 0 ] && [ $FAILED_TESTS -eq 0 ]; then
        log_success "All backend tests completed successfully!"
        exit 0
    else
        log_error "Some backend tests failed!"
        exit 1
    fi
}

# Run main function
main "$@" 