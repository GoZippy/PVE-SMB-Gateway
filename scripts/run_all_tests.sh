#!/bin/bash

# PVE SMB Gateway - Master Test Runner
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive test suite runner for all components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="/tmp/pve-smbgateway-test-results"
TEST_LOGS_DIR="$TEST_RESULTS_DIR/logs"
TEST_REPORTS_DIR="$TEST_RESULTS_DIR/reports"

# Test suites
TEST_SUITES=(
    "frontend_unit"
    "backend_unit"
    "cli_unit"
    "integration"
)

# Test counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test timing
START_TIME=$(date +%s)
SUITE_TIMES=()

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}[HEADER]${NC} $1"
}

log_subheader() {
    echo -e "${CYAN}[SUBHEADER]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop any running test processes
    pkill -f "test_.*\.sh" 2>/dev/null || true
    pkill -f "mock_api_server.py" 2>/dev/null || true
    pkill -f "mock_samba_service.py" 2>/dev/null || true
    
    # Clean up temporary test directories
    rm -rf /tmp/pve-smbgateway-*-tests 2>/dev/null || true
    rm -rf /tmp/test-* 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$TEST_LOGS_DIR"
    mkdir -p "$TEST_REPORTS_DIR"
    
    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/README.md" ]; then
        log_error "Not in project root directory"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("bash" "curl" "jq" "sqlite3" "python3" "perl")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check if test scripts exist
    for suite in "${TEST_SUITES[@]}"; do
        local test_script="$SCRIPT_DIR/test_${suite}.sh"
        if [ ! -f "$test_script" ]; then
            log_error "Test script not found: $test_script"
            exit 1
        fi
        chmod +x "$test_script"
    done
    
    log_success "Test environment setup completed"
}

# Run individual test suite
run_test_suite() {
    local suite_name="$1"
    local test_script="$SCRIPT_DIR/test_${suite_name}.sh"
    local log_file="$TEST_LOGS_DIR/${suite_name}.log"
    local report_file="$TEST_REPORTS_DIR/${suite_name}.json"
    
    log_subheader "Running $suite_name test suite..."
    
    local suite_start_time=$(date +%s)
    
    # Run the test suite
    if "$test_script" > "$log_file" 2>&1; then
        local suite_end_time=$(date +%s)
        local suite_duration=$((suite_end_time - suite_start_time))
        SUITE_TIMES+=("$suite_name:$suite_duration")
        
        log_success "$suite_name test suite completed successfully (${suite_duration}s)"
        ((PASSED_SUITES++))
        
        # Extract test results from log
        extract_test_results "$suite_name" "$log_file" "$report_file"
        
        return 0
    else
        local suite_end_time=$(date +%s)
        local suite_duration=$((suite_end_time - suite_start_time))
        SUITE_TIMES+=("$suite_name:$suite_duration")
        
        log_error "$suite_name test suite failed (${suite_duration}s)"
        ((FAILED_SUITES++))
        
        # Show error details
        log_warning "Last 10 lines of $suite_name log:"
        tail -10 "$log_file" | sed 's/^/  /'
        
        return 1
    fi
}

# Extract test results from log files
extract_test_results() {
    local suite_name="$1"
    local log_file="$2"
    local report_file="$3"
    
    # Parse test results from log
    local passed=$(grep -c "\[PASS\]" "$log_file" || echo "0")
    local failed=$(grep -c "\[FAIL\]" "$log_file" || echo "0")
    local total=$((passed + failed))
    
    # Update global counters
    ((PASSED_TESTS += passed))
    ((FAILED_TESTS += failed))
    ((TOTAL_TESTS += total))
    
    # Create JSON report
    cat > "$report_file" << EOF
{
    "suite": "$suite_name",
    "timestamp": "$(date -Iseconds)",
    "results": {
        "total": $total,
        "passed": $passed,
        "failed": $failed,
        "success_rate": $(echo "scale=2; $passed * 100 / $total" | bc -l 2>/dev/null || echo "0")
    },
    "duration": $(echo "${SUITE_TIMES[-1]}" | cut -d: -f2),
    "status": "$([ $failed -eq 0 ] && echo "success" || echo "failed")"
}
EOF
}

# Run all test suites
run_all_tests() {
    log_header "Starting PVE SMB Gateway Test Suite"
    log_info "Project Root: $PROJECT_ROOT"
    log_info "Test Scripts: $SCRIPT_DIR"
    log_info "Results Directory: $TEST_RESULTS_DIR"
    
    local overall_result=0
    
    # Run each test suite
    for suite in "${TEST_SUITES[@]}"; do
        ((TOTAL_SUITES++))
        
        if run_test_suite "$suite"; then
            log_success "✓ $suite test suite passed"
        else
            log_error "✗ $suite test suite failed"
            overall_result=1
        fi
        
        echo ""
    done
    
    return $overall_result
}

# Generate test summary
generate_test_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    log_header "Test Suite Summary"
    echo ""
    
    # Overall statistics
    echo -e "${CYAN}Overall Results:${NC}"
    echo "  Total Test Suites: $TOTAL_SUITES"
    echo "  Passed Suites: $PASSED_SUITES"
    echo "  Failed Suites: $FAILED_SUITES"
    echo "  Success Rate: $(echo "scale=1; $PASSED_SUITES * 100 / $TOTAL_SUITES" | bc -l)%"
    echo ""
    
    echo -e "${CYAN}Test Results:${NC}"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed Tests: $PASSED_TESTS"
    echo "  Failed Tests: $FAILED_TESTS"
    echo "  Skipped Tests: $SKIPPED_TESTS"
    if [ $TOTAL_TESTS -gt 0 ]; then
        echo "  Test Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)%"
    fi
    echo ""
    
    echo -e "${CYAN}Timing:${NC}"
    echo "  Total Duration: ${total_duration}s"
    for timing in "${SUITE_TIMES[@]}"; do
        local suite=$(echo "$timing" | cut -d: -f1)
        local duration=$(echo "$timing" | cut -d: -f2)
        echo "  $suite: ${duration}s"
    done
    echo ""
    
    # Individual suite results
    echo -e "${CYAN}Individual Suite Results:${NC}"
    for suite in "${TEST_SUITES[@]}"; do
        local report_file="$TEST_REPORTS_DIR/${suite}.json"
        if [ -f "$report_file" ]; then
            local status=$(jq -r '.status' "$report_file")
            local passed=$(jq -r '.results.passed' "$report_file")
            local total=$(jq -r '.results.total' "$report_file")
            local duration=$(jq -r '.duration' "$report_file")
            
            if [ "$status" = "success" ]; then
                echo -e "  ✓ $suite: $passed/$total tests passed (${duration}s)"
            else
                echo -e "  ✗ $suite: $passed/$total tests passed (${duration}s)"
            fi
        else
            echo -e "  ? $suite: No report available"
        fi
    done
    echo ""
}

# Generate detailed report
generate_detailed_report() {
    local report_file="$TEST_REPORTS_DIR/detailed_report.json"
    
    # Collect all suite reports
    local suite_reports=()
    for suite in "${TEST_SUITES[@]}"; do
        local suite_report="$TEST_REPORTS_DIR/${suite}.json"
        if [ -f "$suite_report" ]; then
            suite_reports+=("$suite_report")
        fi
    done
    
    # Create detailed report
    cat > "$report_file" << EOF
{
    "test_run": {
        "timestamp": "$(date -Iseconds)",
        "project": "PVE SMB Gateway",
        "version": "$(git describe --tags 2>/dev/null || echo 'unknown')",
        "hostname": "$(hostname)",
        "duration": $(( $(date +%s) - START_TIME ))
    },
    "summary": {
        "total_suites": $TOTAL_SUITES,
        "passed_suites": $PASSED_SUITES,
        "failed_suites": $FAILED_SUITES,
        "total_tests": $TOTAL_TESTS,
        "passed_tests": $PASSED_TESTS,
        "failed_tests": $FAILED_TESTS,
        "skipped_tests": $SKIPPED_TESTS
    },
    "suites": [
EOF
    
    # Add suite reports
    local first=true
    for report in "${suite_reports[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        cat "$report" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    ],
    "environment": {
        "os": "$(uname -s)",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "shell": "$SHELL",
        "python_version": "$(python3 --version 2>&1)",
        "perl_version": "$(perl --version 2>&1 | head -1)"
    }
}
EOF
    
    log_info "Detailed report generated: $report_file"
}

# Generate HTML report
generate_html_report() {
    local html_file="$TEST_REPORTS_DIR/test_report.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PVE SMB Gateway Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; }
        .header h1 { color: #333; margin-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background-color: #f8f9fa; padding: 20px; border-radius: 6px; text-align: center; }
        .summary-card.success { background-color: #d4edda; border: 1px solid #c3e6cb; }
        .summary-card.failure { background-color: #f8d7da; border: 1px solid #f5c6cb; }
        .summary-card h3 { margin: 0 0 10px 0; color: #333; }
        .summary-card .number { font-size: 2em; font-weight: bold; }
        .summary-card.success .number { color: #155724; }
        .summary-card.failure .number { color: #721c24; }
        .suite-results { margin-bottom: 30px; }
        .suite-card { background-color: #f8f9fa; margin-bottom: 15px; border-radius: 6px; overflow: hidden; }
        .suite-header { padding: 15px; background-color: #e9ecef; border-bottom: 1px solid #dee2e6; }
        .suite-header.success { background-color: #d4edda; }
        .suite-header.failure { background-color: #f8d7da; }
        .suite-content { padding: 15px; }
        .suite-stats { display: flex; gap: 20px; margin-bottom: 10px; }
        .suite-stat { flex: 1; text-align: center; }
        .suite-stat .label { font-size: 0.9em; color: #666; }
        .suite-stat .value { font-size: 1.2em; font-weight: bold; }
        .log-preview { background-color: #f8f9fa; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 0.9em; max-height: 200px; overflow-y: auto; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PVE SMB Gateway Test Report</h1>
            <p class="timestamp">Generated on $(date)</p>
        </div>
        
        <div class="summary">
            <div class="summary-card $( [ $FAILED_SUITES -eq 0 ] && echo 'success' || echo 'failure' )">
                <h3>Test Suites</h3>
                <div class="number">$PASSED_SUITES/$TOTAL_SUITES</div>
                <p>Suites Passed</p>
            </div>
            <div class="summary-card $( [ $FAILED_TESTS -eq 0 ] && echo 'success' || echo 'failure' )">
                <h3>Individual Tests</h3>
                <div class="number">$PASSED_TESTS/$TOTAL_TESTS</div>
                <p>Tests Passed</p>
            </div>
            <div class="summary-card">
                <h3>Duration</h3>
                <div class="number">$(( $(date +%s) - START_TIME ))s</div>
                <p>Total Time</p>
            </div>
        </div>
        
        <div class="suite-results">
            <h2>Test Suite Results</h2>
EOF
    
    # Add suite results
    for suite in "${TEST_SUITES[@]}"; do
        local report_file="$TEST_REPORTS_DIR/${suite}.json"
        local log_file="$TEST_LOGS_DIR/${suite}.log"
        
        if [ -f "$report_file" ]; then
            local status=$(jq -r '.status' "$report_file")
            local passed=$(jq -r '.results.passed' "$report_file")
            local total=$(jq -r '.results.total' "$report_file")
            local duration=$(jq -r '.duration' "$report_file")
            local success_rate=$(jq -r '.results.success_rate' "$report_file")
            
            cat >> "$html_file" << EOF
            <div class="suite-card">
                <div class="suite-header $status">
                    <h3>$suite Test Suite</h3>
                </div>
                <div class="suite-content">
                    <div class="suite-stats">
                        <div class="suite-stat">
                            <div class="label">Status</div>
                            <div class="value">$status</div>
                        </div>
                        <div class="suite-stat">
                            <div class="label">Tests Passed</div>
                            <div class="value">$passed/$total</div>
                        </div>
                        <div class="suite-stat">
                            <div class="label">Success Rate</div>
                            <div class="value">${success_rate}%</div>
                        </div>
                        <div class="suite-stat">
                            <div class="label">Duration</div>
                            <div class="value">${duration}s</div>
                        </div>
                    </div>
EOF
            
            # Add log preview if log file exists
            if [ -f "$log_file" ]; then
                local log_preview=$(tail -10 "$log_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                cat >> "$html_file" << EOF
                    <div class="log-preview">
                        <strong>Log Preview (last 10 lines):</strong><br>
                        <pre>$log_preview</pre>
                    </div>
EOF
            fi
            
            cat >> "$html_file" << EOF
                </div>
            </div>
EOF
        fi
    done
    
    cat >> "$html_file" << 'EOF'
        </div>
    </div>
</body>
</html>
EOF
    
    log_info "HTML report generated: $html_file"
}

# Main execution
main() {
    log_header "PVE SMB Gateway - Master Test Runner"
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Setup test environment
    setup_test_environment
    
    # Run all tests
    run_all_tests
    local overall_result=$?
    
    # Generate reports
    generate_test_summary
    generate_detailed_report
    generate_html_report
    
    # Final status
    echo ""
    if [ $overall_result -eq 0 ]; then
        log_success "🎉 All test suites completed successfully!"
        log_info "📊 Test reports available in: $TEST_REPORTS_DIR"
        log_info "📋 HTML report: $TEST_REPORTS_DIR/test_report.html"
        log_info "📄 Detailed report: $TEST_REPORTS_DIR/detailed_report.json"
        exit 0
    else
        log_error "❌ Some test suites failed!"
        log_info "📊 Test reports available in: $TEST_REPORTS_DIR"
        log_info "📋 HTML report: $TEST_REPORTS_DIR/test_report.html"
        log_info "📄 Detailed report: $TEST_REPORTS_DIR/detailed_report.json"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        cat << 'EOF'
PVE SMB Gateway - Master Test Runner

Usage: ./run_all_tests.sh [OPTIONS]

Options:
    --help, -h          Show this help message
    --frontend-only     Run only frontend unit tests
    --backend-only      Run only backend unit tests
    --cli-only          Run only CLI unit tests
    --integration-only  Run only integration tests
    --quick             Run quick tests only (skip integration)
    --verbose           Enable verbose output
    --no-cleanup        Don't cleanup after tests

Examples:
    ./run_all_tests.sh                    # Run all tests
    ./run_all_tests.sh --frontend-only    # Run only frontend tests
    ./run_all_tests.sh --quick            # Run unit tests only
    ./run_all_tests.sh --verbose          # Run with verbose output

Test Suites:
    - frontend_unit: ExtJS component tests
    - backend_unit: Perl module tests
    - cli_unit: Command-line interface tests
    - integration: End-to-end workflow tests

Reports:
    - HTML report: test_reports/test_report.html
    - JSON report: test_reports/detailed_report.json
    - Logs: test_logs/
EOF
        exit 0
        ;;
    --frontend-only)
        TEST_SUITES=("frontend_unit")
        ;;
    --backend-only)
        TEST_SUITES=("backend_unit")
        ;;
    --cli-only)
        TEST_SUITES=("cli_unit")
        ;;
    --integration-only)
        TEST_SUITES=("integration")
        ;;
    --quick)
        TEST_SUITES=("frontend_unit" "backend_unit" "cli_unit")
        ;;
    --verbose)
        set -x
        ;;
    --no-cleanup)
        trap - EXIT
        ;;
    "")
        # Default: run all tests
        ;;
    *)
        log_error "Unknown option: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@" 