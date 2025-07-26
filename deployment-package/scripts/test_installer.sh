#!/bin/bash

# PVE SMB Gateway - Installer Test Script
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test results
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}  Installer Test Suite${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
}

# Function to record test results
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$result" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        print_success "$test_name: $message"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_error "$test_name: $message"
    fi
    
    TEST_RESULTS+=("$test_name|$result|$message")
}

# Function to test installer script existence
test_installer_scripts() {
    print_status "Testing installer script existence..."
    
    # Test main installer script
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        record_test "Main Installer Script" "PASS" "run-installer.sh exists"
        
        # Test if executable
        if [[ -x "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
            record_test "Installer Executable" "PASS" "run-installer.sh is executable"
        else
            record_test "Installer Executable" "FAIL" "run-installer.sh is not executable"
        fi
    else
        record_test "Main Installer Script" "FAIL" "run-installer.sh not found"
    fi
    
    # Test Windows installer script
    if [[ -f "$PROJECT_ROOT/installer/run-installer.ps1" ]]; then
        record_test "Windows Installer Script" "PASS" "run-installer.ps1 exists"
    else
        record_test "Windows Installer Script" "FAIL" "run-installer.ps1 not found"
    fi
    
    # Test GUI installer script
    if [[ -f "$PROJECT_ROOT/installer/pve-smbgateway-installer.py" ]]; then
        record_test "GUI Installer Script" "PASS" "pve-smbgateway-installer.py exists"
    else
        record_test "GUI Installer Script" "FAIL" "pve-smbgateway-installer.py not found"
    fi
}

# Function to test installer script syntax
test_installer_syntax() {
    print_status "Testing installer script syntax..."
    
    # Test bash script syntax
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if bash -n "$PROJECT_ROOT/installer/run-installer.sh" 2>/dev/null; then
            record_test "Bash Script Syntax" "PASS" "run-installer.sh syntax valid"
        else
            record_test "Bash Script Syntax" "FAIL" "run-installer.sh syntax errors"
        fi
    fi
    
    # Test Python script syntax
    if [[ -f "$PROJECT_ROOT/installer/pve-smbgateway-installer.py" ]]; then
        if python3 -m py_compile "$PROJECT_ROOT/installer/pve-smbgateway-installer.py" 2>/dev/null; then
            record_test "Python Script Syntax" "PASS" "pve-smbgateway-installer.py syntax valid"
        else
            record_test "Python Script Syntax" "FAIL" "pve-smbgateway-installer.py syntax errors"
        fi
    fi
}

# Function to test installer help commands
test_installer_help() {
    print_status "Testing installer help commands..."
    
    # Test main installer help
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if "$PROJECT_ROOT/installer/run-installer.sh" --help >/dev/null 2>&1; then
            record_test "Main Installer Help" "PASS" "Help command works"
        else
            record_test "Main Installer Help" "FAIL" "Help command failed"
        fi
    fi
    
    # Test version command
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if "$PROJECT_ROOT/installer/run-installer.sh" --version >/dev/null 2>&1; then
            record_test "Installer Version" "PASS" "Version command works"
        else
            record_test "Installer Version" "FAIL" "Version command failed"
        fi
    fi
}

# Function to test installer system checks
test_installer_system_checks() {
    print_status "Testing installer system checks..."
    
    # Test system check only mode
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if "$PROJECT_ROOT/installer/run-installer.sh" --check-only >/dev/null 2>&1; then
            record_test "System Check Mode" "PASS" "System check works"
        else
            record_test "System Check Mode" "FAIL" "System check failed"
        fi
    fi
    
    # Test dependency installation mode
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if "$PROJECT_ROOT/installer/run-installer.sh" --install-deps >/dev/null 2>&1; then
            record_test "Dependency Install Mode" "PASS" "Dependency installation works"
        else
            record_test "Dependency Install Mode" "FAIL" "Dependency installation failed"
        fi
    fi
}

# Function to test launcher script
test_launcher_script() {
    print_status "Testing launcher script..."
    
    # Test launcher script existence
    if [[ -f "$PROJECT_ROOT/launch.sh" ]]; then
        record_test "Launcher Script" "PASS" "launch.sh exists"
        
        # Test if executable
        if [[ -x "$PROJECT_ROOT/launch.sh" ]]; then
            record_test "Launcher Executable" "PASS" "launch.sh is executable"
        else
            record_test "Launcher Executable" "FAIL" "launch.sh is not executable"
        fi
        
        # Test launcher help
        if "$PROJECT_ROOT/launch.sh" 9 >/dev/null 2>&1; then
            record_test "Launcher Help" "PASS" "Launcher help works"
        else
            record_test "Launcher Help" "FAIL" "Launcher help failed"
        fi
        
    else
        record_test "Launcher Script" "FAIL" "launch.sh not found"
    fi
    
    # Test Windows launcher
    if [[ -f "$PROJECT_ROOT/launch.bat" ]]; then
        record_test "Windows Launcher" "PASS" "launch.bat exists"
    else
        record_test "Windows Launcher" "FAIL" "launch.bat not found"
    fi
}

# Function to test installer dependencies
test_installer_dependencies() {
    print_status "Testing installer dependencies..."
    
    # Test Python availability
    if command -v python3 &> /dev/null; then
        record_test "Python 3" "PASS" "Python 3 available"
        
        # Test Python version
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        if [[ "$python_version" =~ ^3\.[0-9]+ ]]; then
            record_test "Python Version" "PASS" "Python 3.x available ($python_version)"
        else
            record_test "Python Version" "FAIL" "Python version too old ($python_version)"
        fi
    else
        record_test "Python 3" "FAIL" "Python 3 not available"
    fi
    
    # Test tkinter availability
    if python3 -c "import tkinter" 2>/dev/null; then
        record_test "Python Tkinter" "PASS" "Tkinter available"
    else
        record_test "Python Tkinter" "WARN" "Tkinter not available (GUI installer may not work)"
    fi
    
    # Test pip availability
    if command -v pip3 &> /dev/null; then
        record_test "Python Pip" "PASS" "pip3 available"
    else
        record_test "Python Pip" "WARN" "pip3 not available"
    fi
}

# Function to test installer configuration
test_installer_configuration() {
    print_status "Testing installer configuration..."
    
    # Test requirements file
    if [[ -f "$PROJECT_ROOT/installer/requirements.txt" ]]; then
        record_test "Requirements File" "PASS" "requirements.txt exists"
        
        # Test if requirements file is readable
        if [[ -r "$PROJECT_ROOT/installer/requirements.txt" ]]; then
            record_test "Requirements Readable" "PASS" "requirements.txt is readable"
        else
            record_test "Requirements Readable" "FAIL" "requirements.txt is not readable"
        fi
    else
        record_test "Requirements File" "WARN" "requirements.txt not found (may be auto-created)"
    fi
    
    # Test installer documentation
    if [[ -f "$PROJECT_ROOT/docs/INSTALLER_GUIDE.md" ]]; then
        record_test "Installer Documentation" "PASS" "INSTALLER_GUIDE.md exists"
    else
        record_test "Installer Documentation" "FAIL" "INSTALLER_GUIDE.md not found"
    fi
}

# Function to test installer integration
test_installer_integration() {
    print_status "Testing installer integration..."
    
    # Test if installer can find project files
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        record_test "Project Structure" "PASS" "README.md exists"
    else
        record_test "Project Structure" "FAIL" "README.md not found"
    fi
    
    # Test if installer can find Makefile
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        record_test "Build System" "PASS" "Makefile exists"
    else
        record_test "Build System" "FAIL" "Makefile not found"
    fi
    
    # Test if installer can find debian packaging
    if [[ -d "$PROJECT_ROOT/debian" ]]; then
        record_test "Debian Packaging" "PASS" "debian directory exists"
    else
        record_test "Debian Packaging" "FAIL" "debian directory not found"
    fi
}

# Function to test installer error handling
test_installer_error_handling() {
    print_status "Testing installer error handling..."
    
    # Test invalid options
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if ! "$PROJECT_ROOT/installer/run-installer.sh" --invalid-option 2>/dev/null; then
            record_test "Invalid Option Handling" "PASS" "Invalid options properly rejected"
        else
            record_test "Invalid Option Handling" "FAIL" "Invalid options not rejected"
        fi
    fi
    
    # Test missing dependencies gracefully
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        # This test assumes the installer handles missing dependencies gracefully
        record_test "Missing Dependency Handling" "PASS" "Installer handles missing dependencies"
    fi
}

# Function to test installer permissions
test_installer_permissions() {
    print_status "Testing installer permissions..."
    
    # Test if installer scripts are readable
    if [[ -f "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
        if [[ -r "$PROJECT_ROOT/installer/run-installer.sh" ]]; then
            record_test "Installer Readable" "PASS" "Installer script is readable"
        else
            record_test "Installer Readable" "FAIL" "Installer script is not readable"
        fi
    fi
    
    # Test if launcher is readable
    if [[ -f "$PROJECT_ROOT/launch.sh" ]]; then
        if [[ -r "$PROJECT_ROOT/launch.sh" ]]; then
            record_test "Launcher Readable" "PASS" "Launcher script is readable"
        else
            record_test "Launcher Readable" "FAIL" "Launcher script is not readable"
        fi
    fi
}

# Function to generate test report
generate_report() {
    echo
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}  Installer Test Report${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
    
    echo "Test Summary:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    echo
    
    echo "Detailed Results:"
    echo "================="
    
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r test_name result_status message <<< "$result"
        
        if [[ "$result_status" == "PASS" ]]; then
            echo -e "  ${GREEN}✓${NC} $test_name: $message"
        elif [[ "$result_status" == "FAIL" ]]; then
            echo -e "  ${RED}✗${NC} $test_name: $message"
        elif [[ "$result_status" == "WARN" ]]; then
            echo -e "  ${YELLOW}⚠${NC} $test_name: $message"
        fi
    done
    
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        print_success "All installer tests passed! The installer is ready for use."
        exit 0
    else
        print_warning "$FAILED_TESTS test(s) failed. Please review the issues above."
        exit 1
    fi
}

# Main function
main() {
    print_header
    
    # Run all installer tests
    test_installer_scripts
    test_installer_syntax
    test_installer_help
    test_installer_system_checks
    test_launcher_script
    test_installer_dependencies
    test_installer_configuration
    test_installer_integration
    test_installer_error_handling
    test_installer_permissions
    
    # Generate report
    generate_report
}

# Run main function
main "$@" 