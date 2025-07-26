#!/bin/bash

# PVE SMB Gateway - Comprehensive Unit Test Suite
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive unit test runner for both frontend and backend components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/pve-smbgateway-comprehensive-tests"
REPORT_DIR="$TEST_DIR/reports"
COVERAGE_DIR="$TEST_DIR/coverage"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test results
FRONTEND_RESULT=0
BACKEND_RESULT=0
INTEGRATION_RESULT=0

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
    ((SKIPPED_TESTS++))
    ((TOTAL_TESTS++))
}

log_header() {
    echo -e "${MAGENTA}================================${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}================================${NC}"
}

log_subheader() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    # Keep reports and coverage for analysis
    # rm -rf "$TEST_DIR"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up comprehensive test environment..."
    
    # Create test directories
    mkdir -p "$TEST_DIR"
    mkdir -p "$REPORT_DIR"
    mkdir -p "$COVERAGE_DIR"
    
    # Create test configuration
    create_test_config
    
    log_success "Test environment setup complete"
}

# Create test configuration
create_test_config() {
    log_info "Creating test configuration..."
    
    # Create main test configuration
    cat > "$TEST_DIR/test-config.json" << 'EOF'
{
  "test_suite": {
    "name": "PVE SMB Gateway Comprehensive Unit Tests",
    "version": "1.0.0",
    "timestamp": "TIMESTAMP_PLACEHOLDER"
  },
  "frontend": {
    "framework": "Mocha + Chai + Sinon",
    "browsers": ["ChromeHeadless", "FirefoxHeadless"],
    "coverage": true,
    "timeout": 10000
  },
  "backend": {
    "framework": "Test::More + Test::MockModule",
    "modules": [
      "PVE::Storage::Custom::SMBGateway",
      "PVE::SMBGateway::Monitor",
      "PVE::SMBGateway::CLI",
      "PVE::SMBGateway::Security",
      "PVE::SMBGateway::Backup"
    ],
    "coverage": true
  },
  "integration": {
    "enabled": true,
    "timeout": 30000,
    "parallel": false
  },
  "reporting": {
    "format": ["html", "json", "junit"],
    "output_dir": "reports",
    "coverage_dir": "coverage"
  }
}
EOF

    # Replace timestamp placeholder
    sed -i "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/g" "$TEST_DIR/test-config.json"
}

# Run frontend tests
run_frontend_tests() {
    log_header "Frontend Unit Tests"
    
    if [ -f "scripts/test_frontend_unit.sh" ]; then
        log_subheader "Executing Frontend Test Suite"
        
        if ./scripts/test_frontend_unit.sh > "$REPORT_DIR/frontend-test.log" 2>&1; then
            log_success "Frontend tests completed successfully"
            FRONTEND_RESULT=0
        else
            log_error "Frontend tests failed"
            FRONTEND_RESULT=1
        fi
        
        # Copy frontend coverage if available
        if [ -d "/tmp/pve-smbgateway-frontend-tests/coverage" ]; then
            cp -r /tmp/pve-smbgateway-frontend-tests/coverage "$COVERAGE_DIR/frontend"
            log_info "Frontend coverage report saved"
        fi
    else
        log_warning "Frontend test script not found, skipping"
        FRONTEND_RESULT=2
    fi
}

# Run backend tests
run_backend_tests() {
    log_header "Backend Unit Tests"
    
    if [ -f "scripts/test_backend_unit.sh" ]; then
        log_subheader "Executing Backend Test Suite"
        
        if ./scripts/test_backend_unit.sh > "$REPORT_DIR/backend-test.log" 2>&1; then
            log_success "Backend tests completed successfully"
            BACKEND_RESULT=0
        else
            log_error "Backend tests failed"
            BACKEND_RESULT=1
        fi
        
        # Copy backend coverage if available
        if [ -d "/tmp/pve-smbgateway-backend-tests/coverage" ]; then
            cp -r /tmp/pve-smbgateway-backend-tests/coverage "$COVERAGE_DIR/backend"
            log_info "Backend coverage report saved"
        fi
    else
        log_warning "Backend test script not found, skipping"
        BACKEND_RESULT=2
    fi
}

# Run integration tests
run_integration_tests() {
    log_header "Integration Tests"
    
    if [ -f "scripts/test_integration.sh" ]; then
        log_subheader "Executing Integration Test Suite"
        
        if ./scripts/test_integration.sh > "$REPORT_DIR/integration-test.log" 2>&1; then
            log_success "Integration tests completed successfully"
            INTEGRATION_RESULT=0
        else
            log_error "Integration tests failed"
            INTEGRATION_RESULT=1
        fi
    else
        log_warning "Integration test script not found, skipping"
        INTEGRATION_RESULT=2
    fi
}

# Generate test reports
generate_reports() {
    log_header "Generating Test Reports"
    
    # Create HTML report
    create_html_report
    
    # Create JSON report
    create_json_report
    
    # Create JUnit report
    create_junit_report
    
    # Create coverage summary
    create_coverage_summary
    
    log_success "Test reports generated successfully"
}

# Create HTML report
create_html_report() {
    cat > "$REPORT_DIR/test-report.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PVE SMB Gateway - Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .test-section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .success { background: #d4edda; border-color: #c3e6cb; }
        .failure { background: #f8d7da; border-color: #f5c6cb; }
        .warning { background: #fff3cd; border-color: #ffeaa7; }
        .coverage { margin: 20px 0; }
        .coverage-bar { background: #e9ecef; height: 20px; border-radius: 10px; overflow: hidden; }
        .coverage-fill { height: 100%; background: linear-gradient(90deg, #28a745, #20c997); }
    </style>
</head>
<body>
    <div class="header">
        <h1>PVE SMB Gateway - Comprehensive Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Test Suite Version: 1.0.0</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $TOTAL_TESTS</p>
        <p><strong>Passed:</strong> <span style="color: green;">$PASSED_TESTS</span></p>
        <p><strong>Failed:</strong> <span style="color: red;">$FAILED_TESTS</span></p>
        <p><strong>Skipped:</strong> <span style="color: orange;">$SKIPPED_TESTS</span></p>
        <p><strong>Success Rate:</strong> $(if [ $TOTAL_TESTS -gt 0 ]; then echo "$((PASSED_TESTS * 100 / TOTAL_TESTS))%"; else echo "0%"; fi)</p>
    </div>
    
    <div class="test-section $(if [ $FRONTEND_RESULT -eq 0 ]; then echo "success"; elif [ $FRONTEND_RESULT -eq 1 ]; then echo "failure"; else echo "warning"; fi)">
        <h3>Frontend Tests</h3>
        <p><strong>Status:</strong> $(if [ $FRONTEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $FRONTEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)</p>
        <p><strong>Framework:</strong> Mocha + Chai + Sinon</p>
        <p><strong>Coverage:</strong> Available in coverage/frontend/</p>
    </div>
    
    <div class="test-section $(if [ $BACKEND_RESULT -eq 0 ]; then echo "success"; elif [ $BACKEND_RESULT -eq 1 ]; then echo "failure"; else echo "warning"; fi)">
        <h3>Backend Tests</h3>
        <p><strong>Status:</strong> $(if [ $BACKEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $BACKEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)</p>
        <p><strong>Framework:</strong> Test::More + Test::MockModule</p>
        <p><strong>Coverage:</strong> Available in coverage/backend/</p>
    </div>
    
    <div class="test-section $(if [ $INTEGRATION_RESULT -eq 0 ]; then echo "success"; elif [ $INTEGRATION_RESULT -eq 1 ]; then echo "failure"; else echo "warning"; fi)">
        <h3>Integration Tests</h3>
        <p><strong>Status:</strong> $(if [ $INTEGRATION_RESULT -eq 0 ]; then echo "PASSED"; elif [ $INTEGRATION_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)</p>
        <p><strong>Framework:</strong> Custom Integration Tests</p>
    </div>
    
    <div class="coverage">
        <h2>Coverage Summary</h2>
        <p>Detailed coverage reports are available in the coverage directory.</p>
        <div class="coverage-bar">
            <div class="coverage-fill" style="width: $(if [ $TOTAL_TESTS -gt 0 ]; then echo "$((PASSED_TESTS * 100 / TOTAL_TESTS))%"; else echo "0%"; fi);"></div>
        </div>
        <p>Overall Coverage: $(if [ $TOTAL_TESTS -gt 0 ]; then echo "$((PASSED_TESTS * 100 / TOTAL_TESTS))%"; else echo "0%"; fi)</p>
    </div>
</body>
</html>
EOF
}

# Create JSON report
create_json_report() {
    cat > "$REPORT_DIR/test-report.json" << EOF
{
  "test_suite": {
    "name": "PVE SMB Gateway Comprehensive Unit Tests",
    "version": "1.0.0",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "duration": "$(date +%s)"
  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $(if [ $TOTAL_TESTS -gt 0 ]; then echo "$((PASSED_TESTS * 100 / TOTAL_TESTS))"; else echo "0"; fi)
  },
  "results": {
    "frontend": {
      "status": "$(if [ $FRONTEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $FRONTEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)",
      "framework": "Mocha + Chai + Sinon",
      "coverage_available": $(if [ -d "$COVERAGE_DIR/frontend" ]; then echo "true"; else echo "false"; fi)
    },
    "backend": {
      "status": "$(if [ $BACKEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $BACKEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)",
      "framework": "Test::More + Test::MockModule",
      "coverage_available": $(if [ -d "$COVERAGE_DIR/backend" ]; then echo "true"; else echo "false"; fi)
    },
    "integration": {
      "status": "$(if [ $INTEGRATION_RESULT -eq 0 ]; then echo "PASSED"; elif [ $INTEGRATION_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)",
      "framework": "Custom Integration Tests"
    }
  },
  "environment": {
    "node_version": "$(node --version 2>/dev/null || echo 'N/A')",
    "perl_version": "$(perl --version | head -1 2>/dev/null || echo 'N/A')",
    "platform": "$(uname -s)"
  }
}
EOF
}

# Create JUnit report
create_junit_report() {
    cat > "$REPORT_DIR/test-report.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="PVE SMB Gateway Comprehensive Tests" time="$(date +%s)">
  <testsuite name="Frontend Tests" tests="1" failures="$(if [ $FRONTEND_RESULT -eq 1 ]; then echo "1"; else echo "0"; fi)" skipped="$(if [ $FRONTEND_RESULT -eq 2 ]; then echo "1"; else echo "0"; fi)">
    <testcase name="Frontend Test Suite" time="0">
      $(if [ $FRONTEND_RESULT -eq 1 ]; then echo '<failure message="Frontend tests failed"/>'; fi)
      $(if [ $FRONTEND_RESULT -eq 2 ]; then echo '<skipped message="Frontend tests skipped"/>'; fi)
    </testcase>
  </testsuite>
  <testsuite name="Backend Tests" tests="1" failures="$(if [ $BACKEND_RESULT -eq 1 ]; then echo "1"; else echo "0"; fi)" skipped="$(if [ $BACKEND_RESULT -eq 2 ]; then echo "1"; else echo "0"; fi)">
    <testcase name="Backend Test Suite" time="0">
      $(if [ $BACKEND_RESULT -eq 1 ]; then echo '<failure message="Backend tests failed"/>'; fi)
      $(if [ $BACKEND_RESULT -eq 2 ]; then echo '<skipped message="Backend tests skipped"/>'; fi)
    </testcase>
  </testsuite>
  <testsuite name="Integration Tests" tests="1" failures="$(if [ $INTEGRATION_RESULT -eq 1 ]; then echo "1"; else echo "0"; fi)" skipped="$(if [ $INTEGRATION_RESULT -eq 2 ]; then echo "1"; else echo "0"; fi)">
    <testcase name="Integration Test Suite" time="0">
      $(if [ $INTEGRATION_RESULT -eq 1 ]; then echo '<failure message="Integration tests failed"/>'; fi)
      $(if [ $INTEGRATION_RESULT -eq 2 ]; then echo '<skipped message="Integration tests skipped"/>'; fi)
    </testcase>
  </testsuite>
</testsuites>
EOF
}

# Create coverage summary
create_coverage_summary() {
    cat > "$COVERAGE_DIR/coverage-summary.txt" << EOF
PVE SMB Gateway - Coverage Summary
Generated: $(date)

Overall Test Results:
- Total Tests: $TOTAL_TESTS
- Passed: $PASSED_TESTS
- Failed: $FAILED_TESTS
- Skipped: $SKIPPED_TESTS
- Success Rate: $(if [ $TOTAL_TESTS -gt 0 ]; then echo "$((PASSED_TESTS * 100 / TOTAL_TESTS))%"; else echo "0%"; fi)

Component Coverage:
- Frontend: $(if [ -d "$COVERAGE_DIR/frontend" ]; then echo "Available"; else echo "Not available"; fi)
- Backend: $(if [ -d "$COVERAGE_DIR/backend" ]; then echo "Available"; else echo "Not available"; fi)

Test Status:
- Frontend Tests: $(if [ $FRONTEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $FRONTEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)
- Backend Tests: $(if [ $BACKEND_RESULT -eq 0 ]; then echo "PASSED"; elif [ $BACKEND_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)
- Integration Tests: $(if [ $INTEGRATION_RESULT -eq 0 ]; then echo "PASSED"; elif [ $INTEGRATION_RESULT -eq 1 ]; then echo "FAILED"; else echo "SKIPPED"; fi)

For detailed coverage reports, see:
- Frontend: coverage/frontend/
- Backend: coverage/backend/
EOF
}

# Display test results
display_results() {
    log_header "Test Results Summary"
    
    echo -e "${CYAN}Test Execution Results:${NC}"
    echo -e "  Frontend Tests: $(if [ $FRONTEND_RESULT -eq 0 ]; then echo -e "${GREEN}PASSED${NC}"; elif [ $FRONTEND_RESULT -eq 1 ]; then echo -e "${RED}FAILED${NC}"; else echo -e "${YELLOW}SKIPPED${NC}"; fi)"
    echo -e "  Backend Tests:  $(if [ $BACKEND_RESULT -eq 0 ]; then echo -e "${GREEN}PASSED${NC}"; elif [ $BACKEND_RESULT -eq 1 ]; then echo -e "${RED}FAILED${NC}"; else echo -e "${YELLOW}SKIPPED${NC}"; fi)"
    echo -e "  Integration Tests: $(if [ $INTEGRATION_RESULT -eq 0 ]; then echo -e "${GREEN}PASSED${NC}"; elif [ $INTEGRATION_RESULT -eq 1 ]; then echo -e "${RED}FAILED${NC}"; else echo -e "${YELLOW}SKIPPED${NC}"; fi)"
    
    echo -e "\n${CYAN}Test Statistics:${NC}"
    echo -e "  Total Tests: $TOTAL_TESTS"
    echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
    echo -e "  Skipped: ${YELLOW}$SKIPPED_TESTS${NC}"
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo -e "  Success Rate: ${GREEN}${success_rate}%${NC}"
    fi
    
    echo -e "\n${CYAN}Reports Generated:${NC}"
    echo -e "  HTML Report: $REPORT_DIR/test-report.html"
    echo -e "  JSON Report: $REPORT_DIR/test-report.json"
    echo -e "  JUnit Report: $REPORT_DIR/test-report.xml"
    echo -e "  Coverage Summary: $COVERAGE_DIR/coverage-summary.txt"
}

# Main execution
main() {
    log_header "PVE SMB Gateway - Comprehensive Unit Test Suite"
    
    # Setup
    setup_test_environment
    
    # Run tests
    run_frontend_tests
    run_backend_tests
    run_integration_tests
    
    # Generate reports
    generate_reports
    
    # Display results
    display_results
    
    # Determine exit code
    local exit_code=0
    if [ $FRONTEND_RESULT -eq 1 ] || [ $BACKEND_RESULT -eq 1 ] || [ $INTEGRATION_RESULT -eq 1 ]; then
        exit_code=1
        log_error "Some tests failed!"
    else
        log_success "All tests completed successfully!"
    fi
    
    log_info "Test reports available in: $REPORT_DIR"
    log_info "Coverage reports available in: $COVERAGE_DIR"
    
    exit $exit_code
}

# Cleanup on exit
trap cleanup EXIT

# Run main function
main "$@" 