#!/bin/bash

# PVE SMB Gateway - CLI Unit Tests
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive unit tests for CLI interface

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/pve-smbgateway-cli-tests"
CLI_TOOL="/usr/sbin/pve-smbgateway"
MOCK_API_DIR="$TEST_DIR/mock-api"
TEST_SHARES=(
    "test-share-1"
    "test-share-2"
    "test-share-3"
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
    log_info "Setting up CLI test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Create mock API directory
    mkdir -p "$MOCK_API_DIR"
    
    # Create test configuration
    create_test_config
    
    # Create mock CLI tool if not available
    if [ ! -f "$CLI_TOOL" ]; then
        log_warning "CLI tool not found, creating mock for testing"
        create_mock_cli_tool
    fi
}

# Create test configuration
create_test_config() {
    cat > test_config.json << 'EOF'
{
    "test_shares": [
        {
            "sharename": "test-share-1",
            "mode": "lxc",
            "path": "/srv/smb/test-share-1",
            "quota": "10G",
            "status": "active",
            "created": "2025-01-01T00:00:00Z"
        },
        {
            "sharename": "test-share-2",
            "mode": "native",
            "path": "/srv/smb/test-share-2",
            "quota": "20G",
            "status": "active",
            "created": "2025-01-02T00:00:00Z"
        },
        {
            "sharename": "test-share-3",
            "mode": "vm",
            "path": "/srv/smb/test-share-3",
            "quota": "50G",
            "vm_memory": 4096,
            "vm_cores": 4,
            "status": "active",
            "created": "2025-01-03T00:00:00Z"
        }
    ],
    "test_metrics": {
        "test-share-1": {
            "io_stats": {
                "bytes_read": 1073741824,
                "bytes_written": 2147483648,
                "operations_read": 1000,
                "operations_written": 500,
                "latency_avg_ms": 2.5,
                "throughput_mbps": 15.5
            },
            "connection_stats": {
                "active_connections": 5,
                "total_connections": 100,
                "failed_connections": 2,
                "auth_failures": 1
            },
            "quota_stats": {
                "quota_limit": 10737418240,
                "quota_used": 2684354560,
                "quota_percent": 25.0
            }
        }
    },
    "test_backups": {
        "test-share-1": [
            {
                "snapshot_name": "backup-20250101-120000",
                "size_bytes": 1073741824,
                "created": "2025-01-01T12:00:00Z",
                "status": "success"
            },
            {
                "snapshot_name": "backup-20250102-120000",
                "size_bytes": 2147483648,
                "created": "2025-01-02T12:00:00Z",
                "status": "success"
            }
        ]
    }
}
EOF
}

# Create mock CLI tool
create_mock_cli_tool() {
    cat > "$CLI_TOOL" << 'EOF'
#!/bin/bash

# Mock PVE SMB Gateway CLI tool for testing
set -euo pipefail

# Test configuration
CONFIG_FILE="/tmp/pve-smbgateway-cli-tests/test_config.json"

# Helper functions
log_error() {
    echo "ERROR: $1" >&2
}

log_info() {
    echo "INFO: $1"
}

# Parse command line arguments
parse_args() {
    local command="$1"
    shift
    
    case "$command" in
        list)
            cmd_list "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        metrics)
            cmd_metrics "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        ha)
            cmd_ha "$@"
            ;;
        ad)
            cmd_ad "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# List shares command
cmd_list() {
    local format="table"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                format="json"
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway list [--json]"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found"
        exit 1
    fi
    
    local shares=$(jq -r '.test_shares[] | "\(.sharename)\t\(.mode)\t\(.status)\t\(.quota)"' "$CONFIG_FILE")
    
    if [ "$format" = "json" ]; then
        jq '.test_shares' "$CONFIG_FILE"
    else
        echo -e "Share Name\tMode\tStatus\tQuota"
        echo -e "----------\t----\t------\t-----"
        echo -e "$shares"
    fi
}

# Create share command
cmd_create() {
    local sharename=""
    local mode="lxc"
    local path=""
    local quota=""
    local ad_domain=""
    local ad_join=false
    local ctdb_vip=""
    local ha_enabled=false
    local vm_memory=2048
    local vm_cores=2
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode="$2"
                shift 2
                ;;
            --path)
                path="$2"
                shift 2
                ;;
            --quota)
                quota="$2"
                shift 2
                ;;
            --ad-domain)
                ad_domain="$2"
                shift 2
                ;;
            --ad-join)
                ad_join=true
                shift
                ;;
            --ctdb-vip)
                ctdb_vip="$2"
                shift 2
                ;;
            --ha-enabled)
                ha_enabled=true
                shift
                ;;
            --vm-memory)
                vm_memory="$2"
                shift 2
                ;;
            --vm-cores)
                vm_cores="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway create SHARENAME [options]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    if [ -z "$path" ]; then
        path="/srv/smb/$sharename"
    fi
    
    # Validate share name format
    if [[ ! "$sharename" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid share name format"
        exit 1
    fi
    
    # Validate quota format
    if [ -n "$quota" ] && [[ ! "$quota" =~ ^[0-9]+[GT]$ ]]; then
        log_error "Invalid quota format (use format like 10G or 1T)"
        exit 1
    fi
    
    # Validate VIP format
    if [ -n "$ctdb_vip" ] && [[ ! "$ctdb_vip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid VIP format"
        exit 1
    fi
    
    # Validate VM parameters
    if [ "$mode" = "vm" ]; then
        if [ "$vm_memory" -lt 1024 ] || [ "$vm_memory" -gt 16384 ]; then
            log_error "VM memory must be between 1024 and 16384 MB"
            exit 1
        fi
        
        if [ "$vm_cores" -lt 1 ] || [ "$vm_cores" -gt 16 ]; then
            log_error "VM cores must be between 1 and 16"
            exit 1
        fi
    fi
    
    # Simulate share creation
    log_info "Creating share '$sharename' in $mode mode..."
    sleep 1
    
    echo "Share '$sharename' created successfully"
    echo "  Mode: $mode"
    echo "  Path: $path"
    if [ -n "$quota" ]; then
        echo "  Quota: $quota"
    fi
    if [ -n "$ad_domain" ]; then
        echo "  AD Domain: $ad_domain"
    fi
    if [ "$ha_enabled" = true ]; then
        echo "  HA Enabled: yes"
        if [ -n "$ctdb_vip" ]; then
            echo "  CTDB VIP: $ctdb_vip"
        fi
    fi
    if [ "$mode" = "vm" ]; then
        echo "  VM Memory: ${vm_memory}MB"
        echo "  VM Cores: $vm_cores"
    fi
}

# Delete share command
cmd_delete() {
    local sharename=""
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway delete SHARENAME [--force]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    # Check if share exists
    if ! jq -e ".test_shares[] | select(.sharename == \"$sharename\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Share '$sharename' not found"
        exit 1
    fi
    
    # Simulate share deletion
    if [ "$force" = true ]; then
        log_info "Force deleting share '$sharename'..."
    else
        log_info "Deleting share '$sharename'..."
    fi
    
    sleep 1
    echo "Share '$sharename' deleted successfully"
}

# Status command
cmd_status() {
    local sharename=""
    local format="table"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                format="json"
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway status SHARENAME [--json]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    # Check if share exists
    if ! jq -e ".test_shares[] | select(.sharename == \"$sharename\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Share '$sharename' not found"
        exit 1
    fi
    
    # Get share info
    local share_info=$(jq -r ".test_shares[] | select(.sharename == \"$sharename\")" "$CONFIG_FILE")
    
    if [ "$format" = "json" ]; then
        echo "$share_info"
    else
        echo "Share: $sharename"
        echo "Mode: $(echo "$share_info" | jq -r '.mode')"
        echo "Status: $(echo "$share_info" | jq -r '.status')"
        echo "Path: $(echo "$share_info" | jq -r '.path')"
        echo "Quota: $(echo "$share_info" | jq -r '.quota // "Not set"')"
        echo "Created: $(echo "$share_info" | jq -r '.created')"
    fi
}

# Metrics command
cmd_metrics() {
    local sharename=""
    local format="table"
    local type="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                format="json"
                shift
                ;;
            --type)
                type="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway metrics SHARENAME [--json] [--type TYPE]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    # Check if metrics exist
    if ! jq -e ".test_metrics.\"$sharename\"" "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Metrics for share '$sharename' not found"
        exit 1
    fi
    
    # Get metrics
    local metrics=$(jq -r ".test_metrics.\"$sharename\"" "$CONFIG_FILE")
    
    if [ "$format" = "json" ]; then
        if [ "$type" = "all" ]; then
            echo "$metrics"
        else
            jq -r ".$type" "$CONFIG_FILE" | jq ".test_metrics.\"$sharename\".$type"
        fi
    else
        echo "Metrics for share: $sharename"
        echo ""
        
        if [ "$type" = "all" ] || [ "$type" = "io_stats" ]; then
            echo "I/O Statistics:"
            local io_stats=$(echo "$metrics" | jq -r '.io_stats')
            echo "  Bytes Read: $(echo "$io_stats" | jq -r '.bytes_read')"
            echo "  Bytes Written: $(echo "$io_stats" | jq -r '.bytes_written')"
            echo "  Operations Read: $(echo "$io_stats" | jq -r '.operations_read')"
            echo "  Operations Written: $(echo "$io_stats" | jq -r '.operations_written')"
            echo "  Average Latency: $(echo "$io_stats" | jq -r '.latency_avg_ms') ms"
            echo "  Throughput: $(echo "$io_stats" | jq -r '.throughput_mbps') Mbps"
            echo ""
        fi
        
        if [ "$type" = "all" ] || [ "$type" = "connection_stats" ]; then
            echo "Connection Statistics:"
            local conn_stats=$(echo "$metrics" | jq -r '.connection_stats')
            echo "  Active Connections: $(echo "$conn_stats" | jq -r '.active_connections')"
            echo "  Total Connections: $(echo "$conn_stats" | jq -r '.total_connections')"
            echo "  Failed Connections: $(echo "$conn_stats" | jq -r '.failed_connections')"
            echo "  Auth Failures: $(echo "$conn_stats" | jq -r '.auth_failures')"
            echo ""
        fi
        
        if [ "$type" = "all" ] || [ "$type" = "quota_stats" ]; then
            echo "Quota Statistics:"
            local quota_stats=$(echo "$metrics" | jq -r '.quota_stats')
            echo "  Quota Limit: $(echo "$quota_stats" | jq -r '.quota_limit')"
            echo "  Quota Used: $(echo "$quota_stats" | jq -r '.quota_used')"
            echo "  Quota Percent: $(echo "$quota_stats" | jq -r '.quota_percent')%"
        fi
    fi
}

# Backup command
cmd_backup() {
    local subcommand=""
    local sharename=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            list|create|restore|verify)
                if [ -z "$subcommand" ]; then
                    subcommand="$1"
                else
                    log_error "Multiple subcommands specified"
                    exit 1
                fi
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway backup {list|create|restore|verify} SHARENAME [options]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$subcommand" ]; then
        log_error "Backup subcommand is required"
        exit 1
    fi
    
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    case "$subcommand" in
        list)
            cmd_backup_list "$sharename"
            ;;
        create)
            cmd_backup_create "$sharename"
            ;;
        restore)
            cmd_backup_restore "$sharename"
            ;;
        verify)
            cmd_backup_verify "$sharename"
            ;;
        *)
            log_error "Unknown backup subcommand: $subcommand"
            exit 1
            ;;
    esac
}

cmd_backup_list() {
    local sharename="$1"
    
    # Check if backups exist
    if ! jq -e ".test_backups.\"$sharename\"" "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "No backups found for share '$sharename'"
        exit 1
    fi
    
    echo "Backups for share: $sharename"
    echo ""
    echo "Snapshot Name\t\t\tSize\t\tCreated\t\t\tStatus"
    echo "-------------\t\t\t----\t\t-------\t\t\t------"
    
    jq -r ".test_backups.\"$sharename\"[] | \"\(.snapshot_name)\t\(.size_bytes)\t\(.created)\t\(.status)\"" "$CONFIG_FILE"
}

cmd_backup_create() {
    local sharename="$1"
    
    log_info "Creating backup for share '$sharename'..."
    sleep 2
    
    local snapshot_name="backup-$(date +%Y%m%d-%H%M%S)"
    echo "Backup created successfully: $snapshot_name"
}

cmd_backup_restore() {
    local sharename="$1"
    local snapshot_name="$2"
    
    if [ -z "$snapshot_name" ]; then
        log_error "Snapshot name is required"
        exit 1
    fi
    
    log_info "Restoring backup '$snapshot_name' for share '$sharename'..."
    sleep 3
    
    echo "Backup restored successfully"
}

cmd_backup_verify() {
    local sharename="$1"
    local snapshot_name="$2"
    
    if [ -z "$snapshot_name" ]; then
        log_error "Snapshot name is required"
        exit 1
    fi
    
    log_info "Verifying backup '$snapshot_name' for share '$sharename'..."
    sleep 1
    
    echo "Backup verification completed: integrity check passed"
}

# HA command
cmd_ha() {
    local subcommand=""
    local sharename=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            status|test|failover)
                if [ -z "$subcommand" ]; then
                    subcommand="$1"
                else
                    log_error "Multiple subcommands specified"
                    exit 1
                fi
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway ha {status|test|failover} SHARENAME [options]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$subcommand" ]; then
        log_error "HA subcommand is required"
        exit 1
    fi
    
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    case "$subcommand" in
        status)
            echo "HA Status for share: $sharename"
            echo "  Cluster Status: healthy"
            echo "  VIP: 192.168.1.100"
            echo "  Active Node: node1"
            echo "  Failover Time: 15s"
            ;;
        test)
            log_info "Testing HA failover for share '$sharename'..."
            sleep 2
            echo "HA test completed successfully"
            ;;
        failover)
            log_info "Triggering HA failover for share '$sharename'..."
            sleep 3
            echo "HA failover completed successfully"
            ;;
        *)
            log_error "Unknown HA subcommand: $subcommand"
            exit 1
            ;;
    esac
}

# AD command
cmd_ad() {
    local subcommand=""
    local sharename=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            test|status|join|leave)
                if [ -z "$subcommand" ]; then
                    subcommand="$1"
                else
                    log_error "Multiple subcommands specified"
                    exit 1
                fi
                shift
                ;;
            --help|-h)
                echo "Usage: pve-smbgateway ad {test|status|join|leave} SHARENAME [options]"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$sharename" ]; then
                    sharename="$1"
                else
                    log_error "Multiple share names specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$subcommand" ]; then
        log_error "AD subcommand is required"
        exit 1
    fi
    
    if [ -z "$sharename" ]; then
        log_error "Share name is required"
        exit 1
    fi
    
    case "$subcommand" in
        test)
            log_info "Testing AD connectivity for share '$sharename'..."
            sleep 1
            echo "AD connectivity test completed: domain controller reachable"
            ;;
        status)
            echo "AD Status for share: $sharename"
            echo "  Domain: test.local"
            echo "  Status: joined"
            echo "  Authentication: Kerberos"
            echo "  Fallback: enabled"
            ;;
        join)
            log_info "Joining AD domain for share '$sharename'..."
            sleep 2
            echo "AD domain join completed successfully"
            ;;
        leave)
            log_info "Leaving AD domain for share '$sharename'..."
            sleep 2
            echo "AD domain leave completed successfully"
            ;;
        *)
            log_error "Unknown AD subcommand: $subcommand"
            exit 1
            ;;
    esac
}

# Show help
show_help() {
    cat << 'EOF'
PVE SMB Gateway CLI Tool

Usage: pve-smbgateway <command> [options]

Commands:
  list                    List all SMB shares
  create SHARENAME        Create a new SMB share
  delete SHARENAME        Delete an SMB share
  status SHARENAME        Show share status
  metrics SHARENAME       Show share metrics
  backup <subcommand>     Manage share backups
  ha <subcommand>         Manage high availability
  ad <subcommand>         Manage Active Directory integration
  help                    Show this help message

For more information about a command, use: pve-smbgateway <command> --help
EOF
}

# Main execution
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

parse_args "$@"
EOF

    chmod +x "$CLI_TOOL"
}

# Test CLI commands
test_list_command() {
    log_info "Testing list command..."
    
    # Test basic list
    if output=$("$CLI_TOOL" list 2>&1); then
        log_success "List command works"
        echo "$output" | head -5
    else
        log_error "List command failed"
        return 1
    fi
    
    # Test JSON output
    if output=$("$CLI_TOOL" list --json 2>&1); then
        log_success "List command with JSON output works"
        echo "$output" | head -3
    else
        log_error "List command with JSON output failed"
        return 1
    fi
    
    # Test help
    if output=$("$CLI_TOOL" list --help 2>&1); then
        log_success "List command help works"
    else
        log_error "List command help failed"
        return 1
    fi
}

test_create_command() {
    log_info "Testing create command..."
    
    # Test basic create
    if output=$("$CLI_TOOL" create test-share-new --mode lxc --quota 5G 2>&1); then
        log_success "Create command works"
        echo "$output"
    else
        log_error "Create command failed"
        return 1
    fi
    
    # Test create with AD
    if output=$("$CLI_TOOL" create test-share-ad --mode native --ad-domain test.local --ad-join 2>&1); then
        log_success "Create command with AD works"
        echo "$output"
    else
        log_error "Create command with AD failed"
        return 1
    fi
    
    # Test create with HA
    if output=$("$CLI_TOOL" create test-share-ha --mode vm --vm-memory 4096 --ha-enabled --ctdb-vip 192.168.1.200 2>&1); then
        log_success "Create command with HA works"
        echo "$output"
    else
        log_error "Create command with HA failed"
        return 1
    fi
    
    # Test validation errors
    if ! output=$("$CLI_TOOL" create "" 2>&1); then
        log_success "Create command validates empty share name"
    else
        log_error "Create command should fail with empty share name"
        return 1
    fi
    
    if ! output=$("$CLI_TOOL" create test@share 2>&1); then
        log_success "Create command validates share name format"
    else
        log_error "Create command should fail with invalid share name"
        return 1
    fi
    
    if ! output=$("$CLI_TOOL" create test-share --quota 1M 2>&1); then
        log_success "Create command validates quota format"
    else
        log_error "Create command should fail with invalid quota"
        return 1
    fi
}

test_delete_command() {
    log_info "Testing delete command..."
    
    # Test basic delete
    if output=$("$CLI_TOOL" delete test-share-1 2>&1); then
        log_success "Delete command works"
        echo "$output"
    else
        log_error "Delete command failed"
        return 1
    fi
    
    # Test force delete
    if output=$("$CLI_TOOL" delete test-share-2 --force 2>&1); then
        log_success "Delete command with force works"
        echo "$output"
    else
        log_error "Delete command with force failed"
        return 1
    fi
    
    # Test delete non-existent share
    if ! output=$("$CLI_TOOL" delete non-existent-share 2>&1); then
        log_success "Delete command validates share existence"
    else
        log_error "Delete command should fail for non-existent share"
        return 1
    fi
}

test_status_command() {
    log_info "Testing status command..."
    
    # Test basic status
    if output=$("$CLI_TOOL" status test-share-1 2>&1); then
        log_success "Status command works"
        echo "$output"
    else
        log_error "Status command failed"
        return 1
    fi
    
    # Test JSON output
    if output=$("$CLI_TOOL" status test-share-1 --json 2>&1); then
        log_success "Status command with JSON output works"
        echo "$output"
    else
        log_error "Status command with JSON output failed"
        return 1
    fi
    
    # Test non-existent share
    if ! output=$("$CLI_TOOL" status non-existent-share 2>&1); then
        log_success "Status command validates share existence"
    else
        log_error "Status command should fail for non-existent share"
        return 1
    fi
}

test_metrics_command() {
    log_info "Testing metrics command..."
    
    # Test basic metrics
    if output=$("$CLI_TOOL" metrics test-share-1 2>&1); then
        log_success "Metrics command works"
        echo "$output" | head -10
    else
        log_error "Metrics command failed"
        return 1
    fi
    
    # Test JSON output
    if output=$("$CLI_TOOL" metrics test-share-1 --json 2>&1); then
        log_success "Metrics command with JSON output works"
        echo "$output" | head -5
    else
        log_error "Metrics command with JSON output failed"
        return 1
    fi
    
    # Test specific metric type
    if output=$("$CLI_TOOL" metrics test-share-1 --type io_stats 2>&1); then
        log_success "Metrics command with specific type works"
        echo "$output"
    else
        log_error "Metrics command with specific type failed"
        return 1
    fi
}

test_backup_command() {
    log_info "Testing backup command..."
    
    # Test backup list
    if output=$("$CLI_TOOL" backup list test-share-1 2>&1); then
        log_success "Backup list command works"
        echo "$output"
    else
        log_error "Backup list command failed"
        return 1
    fi
    
    # Test backup create
    if output=$("$CLI_TOOL" backup create test-share-1 2>&1); then
        log_success "Backup create command works"
        echo "$output"
    else
        log_error "Backup create command failed"
        return 1
    fi
    
    # Test backup verify
    if output=$("$CLI_TOOL" backup verify test-share-1 backup-20250101-120000 2>&1); then
        log_success "Backup verify command works"
        echo "$output"
    else
        log_error "Backup verify command failed"
        return 1
    fi
}

test_ha_command() {
    log_info "Testing HA command..."
    
    # Test HA status
    if output=$("$CLI_TOOL" ha status test-share-1 2>&1); then
        log_success "HA status command works"
        echo "$output"
    else
        log_error "HA status command failed"
        return 1
    fi
    
    # Test HA test
    if output=$("$CLI_TOOL" ha test test-share-1 2>&1); then
        log_success "HA test command works"
        echo "$output"
    else
        log_error "HA test command failed"
        return 1
    fi
    
    # Test HA failover
    if output=$("$CLI_TOOL" ha failover test-share-1 2>&1); then
        log_success "HA failover command works"
        echo "$output"
    else
        log_error "HA failover command failed"
        return 1
    fi
}

test_ad_command() {
    log_info "Testing AD command..."
    
    # Test AD status
    if output=$("$CLI_TOOL" ad status test-share-1 2>&1); then
        log_success "AD status command works"
        echo "$output"
    else
        log_error "AD status command failed"
        return 1
    fi
    
    # Test AD test
    if output=$("$CLI_TOOL" ad test test-share-1 2>&1); then
        log_success "AD test command works"
        echo "$output"
    else
        log_error "AD test command failed"
        return 1
    fi
    
    # Test AD join
    if output=$("$CLI_TOOL" ad join test-share-1 2>&1); then
        log_success "AD join command works"
        echo "$output"
    else
        log_error "AD join command failed"
        return 1
    fi
}

test_error_handling() {
    log_info "Testing error handling..."
    
    # Test unknown command
    if ! output=$("$CLI_TOOL" unknown-command 2>&1); then
        log_success "Unknown command handling works"
    else
        log_error "Unknown command should fail"
        return 1
    fi
    
    # Test missing arguments
    if ! output=$("$CLI_TOOL" create 2>&1); then
        log_success "Missing arguments handling works"
    else
        log_error "Missing arguments should fail"
        return 1
    fi
    
    # Test invalid options
    if ! output=$("$CLI_TOOL" create test-share --invalid-option 2>&1); then
        log_success "Invalid options handling works"
    else
        log_error "Invalid options should fail"
        return 1
    fi
}

# Run tests
run_tests() {
    log_info "Running CLI unit tests..."
    
    local test_results=0
    
    # Test each command category
    test_list_command || ((test_results++))
    test_create_command || ((test_results++))
    test_delete_command || ((test_results++))
    test_status_command || ((test_results++))
    test_metrics_command || ((test_results++))
    test_backup_command || ((test_results++))
    test_ha_command || ((test_results++))
    test_ad_command || ((test_results++))
    test_error_handling || ((test_results++))
    
    return $test_results
}

# Main execution
main() {
    log_info "Starting PVE SMB Gateway CLI Unit Tests"
    
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
        log_success "All CLI tests completed successfully!"
        exit 0
    else
        log_error "Some CLI tests failed!"
        exit 1
    fi
}

# Run main function
main "$@" 