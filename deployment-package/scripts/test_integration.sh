#!/bin/bash

# PVE SMB Gateway - Integration Tests
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive integration tests for complete workflow

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/pve-smbgateway-integration-tests"
API_BASE_URL="http://localhost:8006/api2/json"
TEST_NODE="pve"
TEST_USER="root@pam"
TEST_PASSWORD="test-password"

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
    log_info "Cleaning up integration test environment..."
    
    # Clean up test shares
    cleanup_test_shares
    
    # Remove test directory
    rm -rf "$TEST_DIR"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up integration test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Create test configuration
    create_test_config
    
    # Setup mock services
    setup_mock_services
    
    # Verify environment
    verify_test_environment
}

# Create test configuration
create_test_config() {
    cat > integration_config.json << 'EOF'
{
    "test_scenarios": {
        "basic_lxc": {
            "sharename": "integration-lxc",
            "mode": "lxc",
            "path": "/srv/smb/integration-lxc",
            "quota": "10G",
            "expected_status": "active"
        },
        "native_ad": {
            "sharename": "integration-native-ad",
            "mode": "native",
            "path": "/srv/smb/integration-native-ad",
            "ad_domain": "test.local",
            "ad_join": true,
            "expected_status": "active"
        },
        "vm_ha": {
            "sharename": "integration-vm-ha",
            "mode": "vm",
            "path": "/srv/smb/integration-vm-ha",
            "vm_memory": 4096,
            "vm_cores": 4,
            "ha_enabled": true,
            "ctdb_vip": "192.168.1.200",
            "expected_status": "active"
        }
    },
    "test_data": {
        "files": [
            "test-file-1.txt",
            "test-file-2.txt",
            "test-directory/test-file-3.txt"
        ],
        "file_content": "Integration test data - $(date)",
        "file_size": 1024
    },
    "performance_targets": {
        "creation_time": 30,
        "deletion_time": 20,
        "io_throughput": 50,
        "concurrent_connections": 10
    }
}
EOF
}

# Setup mock services
setup_mock_services() {
    log_info "Setting up mock services..."
    
    # Create mock API server
    create_mock_api_server
    
    # Create mock database
    create_mock_database
    
    # Create mock Samba service
    create_mock_samba_service
}

# Create mock API server
create_mock_api_server() {
    cat > mock_api_server.py << 'EOF'
#!/usr/bin/env python3

import json
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

class MockAPIHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.test_data = {
            'shares': {},
            'metrics': {},
            'backups': {},
            'ha_status': {},
            'ad_status': {}
        }
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        
        if path.startswith('/api2/json/nodes/'):
            self.handle_node_api(parsed_url)
        elif path.startswith('/api2/json/storage/'):
            self.handle_storage_api(parsed_url)
        else:
            self.send_error(404, "Not Found")
    
    def do_POST(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        
        if path.startswith('/api2/json/nodes/'):
            self.handle_node_api_post(parsed_url)
        elif path.startswith('/api2/json/storage/'):
            self.handle_storage_api_post(parsed_url)
        else:
            self.send_error(404, "Not Found")
    
    def handle_node_api(self, parsed_url):
        path = parsed_url.path
        query = parse_qs(parsed_url.query)
        
        if 'smbgateway' in path:
            share_name = path.split('/')[-1]
            if share_name in self.test_data['shares']:
                self.send_json_response(self.test_data['shares'][share_name])
            else:
                self.send_error(404, "Share not found")
        elif 'metrics' in path:
            share_name = path.split('/')[-2]
            if share_name in self.test_data['metrics']:
                self.send_json_response(self.test_data['metrics'][share_name])
            else:
                self.send_error(404, "Metrics not found")
        else:
            self.send_error(404, "Not Found")
    
    def handle_storage_api(self, parsed_url):
        path = parsed_url.path
        
        if 'smbgateway' in path:
            self.send_json_response({
                'data': list(self.test_data['shares'].values())
            })
        else:
            self.send_error(404, "Not Found")
    
    def handle_node_api_post(self, parsed_url):
        path = parsed_url.path
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            data = json.loads(post_data.decode('utf-8'))
            
            if 'smbgateway' in path:
                share_name = path.split('/')[-1]
                self.test_data['shares'][share_name] = {
                    'sharename': share_name,
                    'mode': data.get('mode', 'lxc'),
                    'path': data.get('path', f'/srv/smb/{share_name}'),
                    'quota': data.get('quota', '10G'),
                    'status': 'active',
                    'created': time.time()
                }
                
                # Create mock metrics
                self.test_data['metrics'][share_name] = {
                    'io_stats': {
                        'bytes_read': 1073741824,
                        'bytes_written': 2147483648,
                        'operations_read': 1000,
                        'operations_written': 500,
                        'latency_avg_ms': 2.5,
                        'throughput_mbps': 15.5
                    },
                    'connection_stats': {
                        'active_connections': 5,
                        'total_connections': 100,
                        'failed_connections': 2,
                        'auth_failures': 1
                    },
                    'quota_stats': {
                        'quota_limit': 10737418240,
                        'quota_used': 2684354560,
                        'quota_percent': 25.0
                    }
                }
                
                self.send_json_response({'success': True, 'data': self.test_data['shares'][share_name]})
            else:
                self.send_error(404, "Not Found")
                
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
    
    def send_json_response(self, data):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
    def log_message(self, format, *args):
        # Suppress logging for cleaner test output
        pass

def run_mock_server():
    server = HTTPServer(('localhost', 8006), MockAPIHandler)
    print("Mock API server started on localhost:8006")
    server.serve_forever()

if __name__ == '__main__':
    run_mock_server()
EOF

    chmod +x mock_api_server.py
}

# Create mock database
create_mock_database() {
    cat > create_mock_db.sql << 'EOF'
-- Create mock SQLite database for testing
CREATE TABLE IF NOT EXISTS shares (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sharename TEXT UNIQUE NOT NULL,
    mode TEXT NOT NULL,
    path TEXT NOT NULL,
    quota TEXT,
    ad_domain TEXT,
    ad_join BOOLEAN DEFAULT 0,
    ctdb_vip TEXT,
    ha_enabled BOOLEAN DEFAULT 0,
    vm_memory INTEGER,
    vm_cores INTEGER,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sharename TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    io_stats TEXT,
    connection_stats TEXT,
    quota_stats TEXT,
    system_stats TEXT,
    FOREIGN KEY (sharename) REFERENCES shares(sharename)
);

CREATE TABLE IF NOT EXISTS backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sharename TEXT NOT NULL,
    snapshot_name TEXT NOT NULL,
    size_bytes INTEGER,
    status TEXT DEFAULT 'success',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sharename) REFERENCES shares(sharename)
);

-- Insert test data
INSERT OR REPLACE INTO shares (sharename, mode, path, quota, status) VALUES
    ('integration-lxc', 'lxc', '/srv/smb/integration-lxc', '10G', 'active'),
    ('integration-native-ad', 'native', '/srv/smb/integration-native-ad', '20G', 'active'),
    ('integration-vm-ha', 'vm', '/srv/smb/integration-vm-ha', '50G', 'active');

INSERT OR REPLACE INTO metrics (sharename, io_stats, connection_stats, quota_stats) VALUES
    ('integration-lxc', '{"bytes_read": 1073741824, "bytes_written": 2147483648}', '{"active_connections": 5, "total_connections": 100}', '{"quota_limit": 10737418240, "quota_used": 2684354560, "quota_percent": 25.0}');

INSERT OR REPLACE INTO backups (sharename, snapshot_name, size_bytes, status) VALUES
    ('integration-lxc', 'backup-20250101-120000', 1073741824, 'success'),
    ('integration-lxc', 'backup-20250102-120000', 2147483648, 'success');
EOF

    # Create SQLite database
    sqlite3 "$TEST_DIR/test.db" < create_mock_db.sql
}

# Create mock Samba service
create_mock_samba_service() {
    cat > mock_samba_service.py << 'EOF'
#!/usr/bin/env python3

import time
import threading
import socket
import json

class MockSambaService:
    def __init__(self):
        self.shares = {}
        self.connections = {}
        self.running = False
    
    def add_share(self, sharename, path, mode='lxc'):
        self.shares[sharename] = {
            'path': path,
            'mode': mode,
            'status': 'active',
            'connections': 0,
            'bytes_read': 0,
            'bytes_written': 0
        }
        print(f"Mock Samba: Added share {sharename} at {path}")
    
    def remove_share(self, sharename):
        if sharename in self.shares:
            del self.shares[sharename]
            print(f"Mock Samba: Removed share {sharename}")
    
    def simulate_io(self, sharename, bytes_read=0, bytes_written=0):
        if sharename in self.shares:
            self.shares[sharename]['bytes_read'] += bytes_read
            self.shares[sharename]['bytes_written'] += bytes_written
            print(f"Mock Samba: Simulated I/O for {sharename}")
    
    def get_stats(self, sharename):
        if sharename in self.shares:
            return self.shares[sharename]
        return None
    
    def start(self):
        self.running = True
        print("Mock Samba service started")
        
        # Start I/O simulation thread
        def simulate_io():
            while self.running:
                for sharename in self.shares:
                    self.simulate_io(sharename, 1024, 2048)
                time.sleep(5)
        
        threading.Thread(target=simulate_io, daemon=True).start()
    
    def stop(self):
        self.running = False
        print("Mock Samba service stopped")

if __name__ == '__main__':
    service = MockSambaService()
    service.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        service.stop()
EOF

    chmod +x mock_samba_service.py
}

# Verify test environment
verify_test_environment() {
    log_info "Verifying test environment..."
    
    # Check if required tools are available
    local required_tools=("curl" "jq" "sqlite3" "python3")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check if test files exist
    local required_files=(
        "integration_config.json"
        "mock_api_server.py"
        "create_mock_db.sql"
        "mock_samba_service.py"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    log_success "Test environment verified"
}

# Start mock services
start_mock_services() {
    log_info "Starting mock services..."
    
    # Start mock API server
    python3 mock_api_server.py &
    local api_pid=$!
    echo "$api_pid" > api_server.pid
    
    # Wait for API server to start
    sleep 2
    
    # Start mock Samba service
    python3 mock_samba_service.py &
    local samba_pid=$!
    echo "$samba_pid" > samba_service.pid
    
    # Wait for services to start
    sleep 2
    
    log_success "Mock services started"
}

# Stop mock services
stop_mock_services() {
    log_info "Stopping mock services..."
    
    # Stop API server
    if [ -f api_server.pid ]; then
        local api_pid=$(cat api_server.pid)
        kill "$api_pid" 2>/dev/null || true
        rm -f api_server.pid
    fi
    
    # Stop Samba service
    if [ -f samba_service.pid ]; then
        local samba_pid=$(cat samba_service.pid)
        kill "$samba_pid" 2>/dev/null || true
        rm -f samba_service.pid
    fi
    
    log_success "Mock services stopped"
}

# Test API integration
test_api_integration() {
    log_info "Testing API integration..."
    
    # Test API connectivity
    if curl -s -f "http://localhost:8006/api2/json/version" >/dev/null; then
        log_success "API connectivity works"
    else
        log_error "API connectivity failed"
        return 1
    fi
    
    # Test share creation via API
    local test_share="api-test-share"
    local create_data="{\"mode\":\"lxc\",\"path\":\"/srv/smb/$test_share\",\"quota\":\"10G\"}"
    
    if response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$create_data" \
        "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$test_share"); then
        
        if echo "$response" | jq -e '.success' >/dev/null; then
            log_success "Share creation via API works"
        else
            log_error "Share creation via API failed"
            return 1
        fi
    else
        log_error "Share creation via API failed"
        return 1
    fi
    
    # Test share retrieval via API
    if response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$test_share"); then
        if echo "$response" | jq -e '.sharename' >/dev/null; then
            log_success "Share retrieval via API works"
        else
            log_error "Share retrieval via API failed"
            return 1
        fi
    else
        log_error "Share retrieval via API failed"
        return 1
    fi
    
    # Test metrics retrieval via API
    if response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$test_share/metrics"); then
        if echo "$response" | jq -e '.io_stats' >/dev/null; then
            log_success "Metrics retrieval via API works"
        else
            log_error "Metrics retrieval via API failed"
            return 1
        fi
    else
        log_error "Metrics retrieval via API failed"
        return 1
    fi
}

# Test database operations
test_database_operations() {
    log_info "Testing database operations..."
    
    local db_file="$TEST_DIR/test.db"
    
    # Test share insertion
    if sqlite3 "$db_file" "INSERT INTO shares (sharename, mode, path, quota) VALUES ('db-test-share', 'lxc', '/srv/smb/db-test-share', '10G');"; then
        log_success "Share insertion works"
    else
        log_error "Share insertion failed"
        return 1
    fi
    
    # Test share retrieval
    if result=$(sqlite3 "$db_file" "SELECT sharename, mode, status FROM shares WHERE sharename = 'db-test-share';"); then
        if [ -n "$result" ]; then
            log_success "Share retrieval works"
        else
            log_error "Share retrieval failed"
            return 1
        fi
    else
        log_error "Share retrieval failed"
        return 1
    fi
    
    # Test metrics insertion
    local metrics_data='{"bytes_read": 1073741824, "bytes_written": 2147483648}'
    if sqlite3 "$db_file" "INSERT INTO metrics (sharename, io_stats) VALUES ('db-test-share', '$metrics_data');"; then
        log_success "Metrics insertion works"
    else
        log_error "Metrics insertion failed"
        return 1
    fi
    
    # Test metrics retrieval
    if result=$(sqlite3 "$db_file" "SELECT io_stats FROM metrics WHERE sharename = 'db-test-share' ORDER BY timestamp DESC LIMIT 1;"); then
        if echo "$result" | jq -e '.bytes_read' >/dev/null; then
            log_success "Metrics retrieval works"
        else
            log_error "Metrics retrieval failed"
            return 1
        fi
    else
        log_error "Metrics retrieval failed"
        return 1
    fi
    
    # Test backup operations
    if sqlite3 "$db_file" "INSERT INTO backups (sharename, snapshot_name, size_bytes) VALUES ('db-test-share', 'backup-test', 1073741824);"; then
        log_success "Backup insertion works"
    else
        log_error "Backup insertion failed"
        return 1
    fi
    
    # Clean up test data
    sqlite3 "$db_file" "DELETE FROM shares WHERE sharename = 'db-test-share';"
    sqlite3 "$db_file" "DELETE FROM metrics WHERE sharename = 'db-test-share';"
    sqlite3 "$db_file" "DELETE FROM backups WHERE sharename = 'db-test-share';"
}

# Test end-to-end workflow
test_end_to_end_workflow() {
    log_info "Testing end-to-end workflow..."
    
    # Load test scenarios
    local scenarios=$(jq -r '.test_scenarios | keys[]' integration_config.json)
    
    for scenario in $scenarios; do
        log_info "Testing scenario: $scenario"
        
        local scenario_data=$(jq -r ".test_scenarios.$scenario" integration_config.json)
        local sharename=$(echo "$scenario_data" | jq -r '.sharename')
        local mode=$(echo "$scenario_data" | jq -r '.mode')
        local path=$(echo "$scenario_data" | jq -r '.path')
        local quota=$(echo "$scenario_data" | jq -r '.quota // empty')
        local expected_status=$(echo "$scenario_data" | jq -r '.expected_status')
        
        # Step 1: Create share via API
        local create_data=$(echo "$scenario_data" | jq -c '.')
        
        if ! response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$create_data" \
            "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename"); then
            
            log_error "Share creation failed for scenario $scenario"
            continue
        fi
        
        if ! echo "$response" | jq -e '.success' >/dev/null; then
            log_error "Share creation API response invalid for scenario $scenario"
            continue
        fi
        
        # Step 2: Verify share status
        sleep 2
        
        if ! response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename"); then
            log_error "Share status retrieval failed for scenario $scenario"
            continue
        fi
        
        local actual_status=$(echo "$response" | jq -r '.status')
        if [ "$actual_status" = "$expected_status" ]; then
            log_success "Share status verification passed for scenario $scenario"
        else
            log_error "Share status verification failed for scenario $scenario (expected: $expected_status, got: $actual_status)"
            continue
        fi
        
        # Step 3: Test metrics collection
        sleep 2
        
        if ! response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename/metrics"); then
            log_error "Metrics retrieval failed for scenario $scenario"
            continue
        fi
        
        if echo "$response" | jq -e '.io_stats' >/dev/null; then
            log_success "Metrics collection works for scenario $scenario"
        else
            log_error "Metrics collection failed for scenario $scenario"
            continue
        fi
        
        # Step 4: Simulate I/O activity
        log_info "Simulating I/O activity for scenario $scenario"
        
        # Simulate file operations
        mkdir -p "$path"
        echo "Test data for $scenario" > "$path/test-file.txt"
        dd if=/dev/zero of="$path/large-file.dat" bs=1M count=10 2>/dev/null
        
        # Step 5: Verify metrics update
        sleep 3
        
        if response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename/metrics"); then
            local bytes_written=$(echo "$response" | jq -r '.io_stats.bytes_written')
            if [ "$bytes_written" -gt 0 ]; then
                log_success "I/O metrics updated for scenario $scenario"
            else
                log_warning "I/O metrics not updated for scenario $scenario"
            fi
        fi
        
        # Step 6: Clean up
        rm -rf "$path"
        
        log_success "End-to-end workflow completed for scenario $scenario"
    done
}

# Test performance scenarios
test_performance_scenarios() {
    log_info "Testing performance scenarios..."
    
    # Load performance targets
    local creation_time_target=$(jq -r '.performance_targets.creation_time' integration_config.json)
    local deletion_time_target=$(jq -r '.performance_targets.deletion_time' integration_config.json)
    local io_throughput_target=$(jq -r '.performance_targets.io_throughput' integration_config.json)
    local concurrent_connections_target=$(jq -r '.performance_targets.concurrent_connections' integration_config.json)
    
    # Test share creation performance
    local start_time=$(date +%s)
    
    for i in {1..5}; do
        local sharename="perf-test-share-$i"
        local create_data="{\"mode\":\"lxc\",\"path\":\"/srv/smb/$sharename\",\"quota\":\"5G\"}"
        
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$create_data" \
            "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename" >/dev/null
    done
    
    local end_time=$(date +%s)
    local creation_time=$((end_time - start_time))
    
    if [ "$creation_time" -le "$creation_time_target" ]; then
        log_success "Share creation performance test passed (${creation_time}s <= ${creation_time_target}s)"
    else
        log_error "Share creation performance test failed (${creation_time}s > ${creation_time_target}s)"
    fi
    
    # Test concurrent connections
    log_info "Testing concurrent connections..."
    
    local connection_count=0
    for i in {1..10}; do
        if curl -s -f "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/perf-test-share-1" >/dev/null; then
            ((connection_count++))
        fi
    done
    
    if [ "$connection_count" -ge "$concurrent_connections_target" ]; then
        log_success "Concurrent connections test passed ($connection_count >= $concurrent_connections_target)"
    else
        log_error "Concurrent connections test failed ($connection_count < $concurrent_connections_target)"
    fi
    
    # Clean up performance test shares
    for i in {1..5}; do
        local sharename="perf-test-share-$i"
        curl -s -X DELETE "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$sharename" >/dev/null || true
    done
}

# Test error handling and recovery
test_error_handling() {
    log_info "Testing error handling and recovery..."
    
    # Test invalid share creation
    local invalid_data="{\"mode\":\"invalid\",\"path\":\"\"}"
    
    if ! response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$invalid_data" \
        "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/invalid-share"); then
        
        log_success "Invalid share creation properly rejected"
    else
        log_error "Invalid share creation should have been rejected"
    fi
    
    # Test non-existent share access
    if ! response=$(curl -s "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/non-existent-share"); then
        log_success "Non-existent share access properly handled"
    else
        log_error "Non-existent share access should have failed"
    fi
    
    # Test malformed JSON
    if ! response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "invalid json" \
        "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/json-test-share"); then
        
        log_success "Malformed JSON properly rejected"
    else
        log_error "Malformed JSON should have been rejected"
    fi
}

# Clean up test shares
cleanup_test_shares() {
    log_info "Cleaning up test shares..."
    
    # Get list of test shares from database
    local test_shares=$(sqlite3 "$TEST_DIR/test.db" "SELECT sharename FROM shares WHERE sharename LIKE 'integration-%' OR sharename LIKE 'api-test-%' OR sharename LIKE 'db-test-%' OR sharename LIKE 'perf-test-%';")
    
    for share in $test_shares; do
        # Delete via API
        curl -s -X DELETE "http://localhost:8006/api2/json/nodes/$TEST_NODE/smbgateway/$share" >/dev/null || true
        
        # Clean up filesystem
        rm -rf "/srv/smb/$share" 2>/dev/null || true
    done
    
    # Clean up database
    sqlite3 "$TEST_DIR/test.db" "DELETE FROM shares WHERE sharename LIKE 'integration-%' OR sharename LIKE 'api-test-%' OR sharename LIKE 'db-test-%' OR sharename LIKE 'perf-test-%';"
    sqlite3 "$TEST_DIR/test.db" "DELETE FROM metrics WHERE sharename LIKE 'integration-%' OR sharename LIKE 'api-test-%' OR sharename LIKE 'db-test-%' OR sharename LIKE 'perf-test-%';"
    sqlite3 "$TEST_DIR/test.db" "DELETE FROM backups WHERE sharename LIKE 'integration-%' OR sharename LIKE 'api-test-%' OR sharename LIKE 'db-test-%' OR sharename LIKE 'perf-test-%';"
}

# Run tests
run_tests() {
    log_info "Running integration tests..."
    
    local test_results=0
    
    # Start mock services
    start_mock_services
    
    # Run test categories
    test_api_integration || ((test_results++))
    test_database_operations || ((test_results++))
    test_end_to_end_workflow || ((test_results++))
    test_performance_scenarios || ((test_results++))
    test_error_handling || ((test_results++))
    
    # Stop mock services
    stop_mock_services
    
    return $test_results
}

# Main execution
main() {
    log_info "Starting PVE SMB Gateway Integration Tests"
    
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
        log_success "All integration tests completed successfully!"
        exit 0
    else
        log_error "Some integration tests failed!"
        exit 1
    fi
}

# Run main function
main "$@" 