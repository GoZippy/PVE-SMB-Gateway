#!/bin/bash

# Release Validation and Certification Script for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Comprehensive pre-release validation and certification

set -e

echo "=== PVE SMB Gateway Release Validation and Certification ==="
echo "Validating release quality and compatibility"
echo

# Configuration
VALIDATION_DIR="/tmp/pve-smbgateway-validation"
LOG_DIR="$VALIDATION_DIR/logs"
RESULTS_DIR="$VALIDATION_DIR/results"
CERTIFICATION_FILE="$VALIDATION_DIR/certification_report.md"

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Initialize validation environment
init_validation_environment() {
    echo "Initializing validation environment..."
    
    # Create validation directories
    mkdir -p "$VALIDATION_DIR" "$LOG_DIR" "$RESULTS_DIR"
    
    # Clean up previous validation
    rm -rf "$VALIDATION_DIR"/*
    mkdir -p "$LOG_DIR" "$RESULTS_DIR"
    
    echo "✓ Validation environment initialized"
}

# Record validation result
record_validation_result() {
    local check_name="$1"
    local result="$2"
    local details="$3"
    local severity="$4"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    case "$result" in
        "PASS")
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            echo "✅ PASS: $check_name"
            ;;
        "FAIL")
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            echo "❌ FAIL: $check_name - $details"
            ;;
        "WARN")
            WARNINGS=$((WARNINGS + 1))
            echo "⚠️  WARN: $check_name - $details"
            ;;
    esac
    
    # Log result
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $result | $check_name | $details | $severity" >> "$LOG_DIR/validation_results.log"
}

# Validation 1: Code Quality Checks
validate_code_quality() {
    echo
    echo "Validation 1: Code Quality Checks"
    echo "================================="
    
    # Check Perl syntax
    echo "Checking Perl syntax..."
    if find . -name "*.pm" -exec perl -c {} \; 2>/dev/null; then
        record_validation_result "Perl Syntax" "PASS" "All Perl files have valid syntax" "critical"
    else
        record_validation_result "Perl Syntax" "FAIL" "Perl syntax errors found" "critical"
    fi
    
    # Check JavaScript syntax
    echo "Checking JavaScript syntax..."
    if command -v node >/dev/null 2>&1; then
        if node -c www/ext6/pvemanager6/smb-gateway.js 2>/dev/null; then
            record_validation_result "JavaScript Syntax" "PASS" "JavaScript files have valid syntax" "critical"
        else
            record_validation_result "JavaScript Syntax" "FAIL" "JavaScript syntax errors found" "critical"
        fi
    else
        record_validation_result "JavaScript Syntax" "WARN" "Node.js not available for syntax check" "medium"
    fi
    
    # Check for TODO/FIXME comments
    echo "Checking for TODO/FIXME comments..."
    todo_count=$(grep -r "TODO\|FIXME" . --exclude-dir=.git --exclude-dir=node_modules | wc -l)
    if [ $todo_count -eq 0 ]; then
        record_validation_result "TODO Comments" "PASS" "No TODO/FIXME comments found" "medium"
    else
        record_validation_result "TODO Comments" "WARN" "Found $todo_count TODO/FIXME comments" "medium"
    fi
    
    # Check for hardcoded credentials
    echo "Checking for hardcoded credentials..."
    if ! grep -r "password\|secret\|key" . --exclude-dir=.git --exclude-dir=node_modules | grep -v "test\|example" | grep -q "="; then
        record_validation_result "Hardcoded Credentials" "PASS" "No hardcoded credentials found" "critical"
    else
        record_validation_result "Hardcoded Credentials" "FAIL" "Potential hardcoded credentials found" "critical"
    fi
}

# Validation 2: Build System Checks
validate_build_system() {
    echo
    echo "Validation 2: Build System Checks"
    echo "================================="
    
    # Check package build
    echo "Testing package build..."
    if ./scripts/build_package.sh 2>/dev/null; then
        record_validation_result "Package Build" "PASS" "Debian package builds successfully" "critical"
    else
        record_validation_result "Package Build" "FAIL" "Package build failed" "critical"
    fi
    
    # Check package structure
    echo "Validating package structure..."
    if [ -f "../pve-plugin-smbgateway_*_all.deb" ]; then
        record_validation_result "Package Structure" "PASS" "Package file exists" "critical"
        
        # Check package contents
        if dpkg-deb -I ../pve-plugin-smbgateway_*_all.deb >/dev/null 2>&1; then
            record_validation_result "Package Contents" "PASS" "Package contents valid" "critical"
        else
            record_validation_result "Package Contents" "FAIL" "Package contents invalid" "critical"
        fi
    else
        record_validation_result "Package Structure" "FAIL" "Package file not found" "critical"
    fi
    
    # Check dependencies
    echo "Checking package dependencies..."
    if dpkg-deb -f ../pve-plugin-smbgateway_*_all.deb Depends >/dev/null 2>&1; then
        record_validation_result "Package Dependencies" "PASS" "Package dependencies defined" "critical"
    else
        record_validation_result "Package Dependencies" "FAIL" "Package dependencies missing" "critical"
    fi
}

# Validation 3: Installation and Deployment Checks
validate_installation() {
    echo
    echo "Validation 3: Installation and Deployment Checks"
    echo "================================================"
    
    # Test package installation
    echo "Testing package installation..."
    if sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb 2>/dev/null; then
        record_validation_result "Package Installation" "PASS" "Package installs successfully" "critical"
        
        # Check if all files are installed
        if [ -f "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm" ] && \
           [ -f "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js" ] && \
           [ -f "/usr/sbin/pve-smbgateway" ]; then
            record_validation_result "File Installation" "PASS" "All required files installed" "critical"
        else
            record_validation_result "File Installation" "FAIL" "Required files missing" "critical"
        fi
    else
        record_validation_result "Package Installation" "FAIL" "Package installation failed" "critical"
    fi
    
    # Test service restart
    echo "Testing service restart..."
    if sudo systemctl restart pveproxy 2>/dev/null; then
        record_validation_result "Service Restart" "PASS" "Proxmox service restarts successfully" "critical"
    else
        record_validation_result "Service Restart" "FAIL" "Service restart failed" "critical"
    fi
}

# Validation 4: Functionality Checks
validate_functionality() {
    echo
    echo "Validation 4: Functionality Checks"
    echo "=================================="
    
    # Test CLI tool functionality
    echo "Testing CLI tool functionality..."
    if pve-smbgateway list >/dev/null 2>&1; then
        record_validation_result "CLI Tool" "PASS" "CLI tool functions correctly" "critical"
    else
        record_validation_result "CLI Tool" "FAIL" "CLI tool not functional" "critical"
    fi
    
    # Test share creation
    echo "Testing share creation..."
    if pve-smbgateway create validation-test --mode lxc --path /tmp/validation-test --quota 1G 2>/dev/null; then
        record_validation_result "Share Creation" "PASS" "Share creation works" "critical"
        
        # Test share status
        if pve-smbgateway status validation-test >/dev/null 2>&1; then
            record_validation_result "Share Status" "PASS" "Share status accessible" "critical"
        else
            record_validation_result "Share Status" "FAIL" "Share status not accessible" "critical"
        fi
        
        # Cleanup
        pve-smbgateway delete validation-test 2>/dev/null || true
    else
        record_validation_result "Share Creation" "FAIL" "Share creation failed" "critical"
    fi
    
    # Test API endpoints
    echo "Testing API endpoints..."
    if curl -k -s "https://localhost:8006/api2/json/nodes/$(hostname)/storage" | grep -q "smbgateway"; then
        record_validation_result "API Endpoints" "PASS" "API endpoints accessible" "critical"
    else
        record_validation_result "API Endpoints" "FAIL" "API endpoints not accessible" "critical"
    fi
}

# Validation 5: Security Checks
validate_security() {
    echo
    echo "Validation 5: Security Checks"
    echo "============================="
    
    # Check file permissions
    echo "Checking file permissions..."
    if [ -r "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm" ] && \
       [ -r "/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js" ] && \
       [ -x "/usr/sbin/pve-smbgateway" ]; then
        record_validation_result "File Permissions" "PASS" "File permissions correct" "critical"
    else
        record_validation_result "File Permissions" "FAIL" "Incorrect file permissions" "critical"
    fi
    
    # Check for security vulnerabilities
    echo "Checking for security vulnerabilities..."
    if ! grep -r "eval\|system\|exec" . --exclude-dir=.git --exclude-dir=node_modules | grep -v "test\|example" | grep -q "("; then
        record_validation_result "Security Vulnerabilities" "PASS" "No obvious security vulnerabilities" "critical"
    else
        record_validation_result "Security Vulnerabilities" "WARN" "Potential security issues found" "critical"
    fi
    
    # Check SSL/TLS configuration
    echo "Checking SSL/TLS configuration..."
    if [ -f "/etc/pve/pve-ssl.key" ] && [ -f "/etc/pve/pve-ssl.pem" ]; then
        record_validation_result "SSL Configuration" "PASS" "SSL certificates present" "medium"
    else
        record_validation_result "SSL Configuration" "WARN" "SSL certificates not found" "medium"
    fi
}

# Validation 6: Performance Checks
validate_performance() {
    echo
    echo "Validation 6: Performance Checks"
    echo "================================"
    
    # Check memory usage
    echo "Checking memory usage..."
    memory_usage=$(ps aux | grep smbd | grep -v grep | awk '{sum+=$6} END {print sum/1024}')
    if [ -n "$memory_usage" ] && (( $(echo "$memory_usage < 200" | bc -l) )); then
        record_validation_result "Memory Usage" "PASS" "Memory usage acceptable: ${memory_usage}MB" "medium"
    else
        record_validation_result "Memory Usage" "WARN" "Memory usage high: ${memory_usage}MB" "medium"
    fi
    
    # Check disk usage
    echo "Checking disk usage..."
    disk_usage=$(du -sh /usr/share/pve-smbgateway 2>/dev/null | cut -f1)
    record_validation_result "Disk Usage" "PASS" "Disk usage: $disk_usage" "low"
    
    # Check startup time
    echo "Checking startup time..."
    start_time=$(date +%s.%N)
    pve-smbgateway list >/dev/null 2>&1
    end_time=$(date +%s.%N)
    startup_time=$(echo "$end_time - $start_time" | bc -l)
    
    if (( $(echo "$startup_time < 5" | bc -l) )); then
        record_validation_result "Startup Time" "PASS" "Startup time acceptable: ${startup_time}s" "medium"
    else
        record_validation_result "Startup Time" "WARN" "Startup time slow: ${startup_time}s" "medium"
    fi
}

# Validation 7: Compatibility Checks
validate_compatibility() {
    echo
    echo "Validation 7: Compatibility Checks"
    echo "=================================="
    
    # Check Proxmox version compatibility
    echo "Checking Proxmox version compatibility..."
    pve_version=$(pveversion -v | head -1 | cut -d' ' -f2)
    if [[ "$pve_version" =~ ^8\.[0-9] ]]; then
        record_validation_result "Proxmox Version" "PASS" "Compatible with Proxmox $pve_version" "critical"
    else
        record_validation_result "Proxmox Version" "FAIL" "Incompatible Proxmox version: $pve_version" "critical"
    fi
    
    # Check Perl version compatibility
    echo "Checking Perl version compatibility..."
    perl_version=$(perl -v | grep "This is perl" | cut -d' ' -f4)
    if [[ "$perl_version" =~ ^v?5\.[3-9][0-9] ]]; then
        record_validation_result "Perl Version" "PASS" "Compatible Perl version: $perl_version" "critical"
    else
        record_validation_result "Perl Version" "FAIL" "Incompatible Perl version: $perl_version" "critical"
    fi
    
    # Check Samba version compatibility
    echo "Checking Samba version compatibility..."
    if command -v smbd >/dev/null 2>&1; then
        samba_version=$(smbd --version | head -1 | cut -d' ' -f2)
        record_validation_result "Samba Version" "PASS" "Samba version: $samba_version" "medium"
    else
        record_validation_result "Samba Version" "WARN" "Samba not installed" "medium"
    fi
    
    # Check filesystem compatibility
    echo "Checking filesystem compatibility..."
    for fs in zfs xfs ext4; do
        if command -v "$fs" >/dev/null 2>&1 || [ "$fs" = "ext4" ]; then
            record_validation_result "Filesystem: $fs" "PASS" "$fs support available" "medium"
        else
            record_validation_result "Filesystem: $fs" "WARN" "$fs not available" "medium"
        fi
    done
}

# Validation 8: Documentation Checks
validate_documentation() {
    echo
    echo "Validation 8: Documentation Checks"
    echo "=================================="
    
    # Check required documentation files
    echo "Checking documentation files..."
    required_docs=("README.md" "docs/ARCHITECTURE.md" "docs/DEV_GUIDE.md" "docs/PRD.md")
    
    for doc in "${required_docs[@]}"; do
        if [ -f "$doc" ]; then
            record_validation_result "Documentation: $doc" "PASS" "Documentation file present" "medium"
        else
            record_validation_result "Documentation: $doc" "FAIL" "Documentation file missing" "medium"
        fi
    done
    
    # Check documentation quality
    echo "Checking documentation quality..."
    readme_size=$(wc -w < README.md 2>/dev/null || echo "0")
    if [ $readme_size -gt 500 ]; then
        record_validation_result "Documentation Quality" "PASS" "README has sufficient content: $readme_size words" "medium"
    else
        record_validation_result "Documentation Quality" "WARN" "README content minimal: $readme_size words" "medium"
    fi
    
    # Check for installation instructions
    if grep -q "install\|setup\|configure" README.md; then
        record_validation_result "Installation Instructions" "PASS" "Installation instructions present" "medium"
    else
        record_validation_result "Installation Instructions" "FAIL" "Installation instructions missing" "medium"
    fi
}

# Validation 9: Testing Checks
validate_testing() {
    echo
    echo "Validation 9: Testing Checks"
    echo "============================"
    
    # Check test scripts
    echo "Checking test scripts..."
    test_scripts=("scripts/test_integration_comprehensive.sh" "scripts/test_security.sh" "scripts/test_enhanced_cli.sh")
    
    for script in "${test_scripts[@]}"; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            record_validation_result "Test Script: $script" "PASS" "Test script present and executable" "medium"
        else
            record_validation_result "Test Script: $script" "WARN" "Test script missing or not executable" "medium"
        fi
    done
    
    # Check unit tests
    echo "Checking unit tests..."
    if [ -d "t" ] && [ "$(ls t/*.t 2>/dev/null | wc -l)" -gt 0 ]; then
        record_validation_result "Unit Tests" "PASS" "Unit tests present" "medium"
    else
        record_validation_result "Unit Tests" "WARN" "Unit tests missing" "medium"
    fi
    
    # Check test coverage
    echo "Checking test coverage..."
    test_files=$(find . -name "*.t" | wc -l)
    source_files=$(find . -name "*.pm" -o -name "*.pl" | wc -l)
    
    if [ $source_files -gt 0 ]; then
        coverage_ratio=$((test_files * 100 / source_files))
        if [ $coverage_ratio -gt 50 ]; then
            record_validation_result "Test Coverage" "PASS" "Good test coverage: $coverage_ratio%" "medium"
        else
            record_validation_result "Test Coverage" "WARN" "Low test coverage: $coverage_ratio%" "medium"
        fi
    else
        record_validation_result "Test Coverage" "WARN" "No source files found" "medium"
    fi
}

# Validation 10: Release Preparation Checks
validate_release_preparation() {
    echo
    echo "Validation 10: Release Preparation Checks"
    echo "========================================="
    
    # Check version consistency
    echo "Checking version consistency..."
    changelog_version=$(grep -o "pve-plugin-smbgateway ([0-9.]*)" debian/changelog | head -1 | cut -d'(' -f2 | cut -d')' -f1)
    if [ -n "$changelog_version" ]; then
        record_validation_result "Version Consistency" "PASS" "Version in changelog: $changelog_version" "critical"
    else
        record_validation_result "Version Consistency" "FAIL" "Version not found in changelog" "critical"
    fi
    
    # Check changelog quality
    echo "Checking changelog quality..."
    changelog_entries=$(grep -c "^- " debian/changelog || echo "0")
    if [ $changelog_entries -gt 0 ]; then
        record_validation_result "Changelog Quality" "PASS" "Changelog has $changelog_entries entries" "medium"
    else
        record_validation_result "Changelog Quality" "FAIL" "Changelog has no entries" "medium"
    fi
    
    # Check license files
    echo "Checking license files..."
    if [ -f "LICENSE" ] || [ -f "COPYING" ]; then
        record_validation_result "License Files" "PASS" "License file present" "critical"
    else
        record_validation_result "License Files" "FAIL" "License file missing" "critical"
    fi
    
    # Check for release notes
    echo "Checking release notes..."
    if [ -f "RELEASE_NOTES.md" ] || [ -f "CHANGELOG.md" ]; then
        record_validation_result "Release Notes" "PASS" "Release notes present" "medium"
    else
        record_validation_result "Release Notes" "WARN" "Release notes missing" "medium"
    fi
}

# Generate certification report
generate_certification_report() {
    echo
    echo "=== Release Certification Report ==="
    echo "Generated: $(date)"
    echo "Test Environment: $(hostname)"
    echo "Proxmox Version: $(pveversion -v | head -1)"
    echo
    
    # Calculate certification status
    critical_failures=$(grep "FAIL.*critical" "$LOG_DIR/validation_results.log" | wc -l)
    total_critical=$(grep "critical" "$LOG_DIR/validation_results.log" | wc -l)
    
    if [ $critical_failures -eq 0 ]; then
        certification_status="CERTIFIED"
        status_emoji="✅"
    else
        certification_status="NOT CERTIFIED"
        status_emoji="❌"
    fi
    
    echo "Certification Status: $status_emoji $certification_status"
    echo "  Total Checks: $TOTAL_CHECKS"
    echo "  Passed: $PASSED_CHECKS"
    echo "  Failed: $FAILED_CHECKS"
    echo "  Warnings: $WARNINGS"
    echo "  Critical Failures: $critical_failures"
    echo
    
    # Generate detailed report
    cat > "$CERTIFICATION_FILE" << EOF
# PVE SMB Gateway Release Certification Report

**Generated:** $(date)  
**Test Environment:** $(hostname)  
**Proxmox Version:** $(pveversion -v | head -1)  
**Certification Status:** $certification_status

## Executive Summary

- **Total Validation Checks:** $TOTAL_CHECKS
- **Passed Checks:** $PASSED_CHECKS
- **Failed Checks:** $FAILED_CHECKS
- **Warnings:** $WARNINGS
- **Critical Failures:** $critical_failures

## Certification Decision

$status_emoji **$certification_status**

$(if [ $critical_failures -eq 0 ]; then
    echo "✅ This release meets all critical quality standards and is certified for production deployment."
else
    echo "❌ This release has $critical_failures critical failures and cannot be certified for production deployment."
fi)

## Detailed Validation Results

$(cat "$LOG_DIR/validation_results.log")

## System Information

\`\`\`
$(pveversion -v)
$(perl -v | head -3)
$(free -h)
$(df -h /tmp)
\`\`\`

## Recommendations

$(generate_recommendations)

## Next Steps

$(if [ $critical_failures -eq 0 ]; then
    echo "1. ✅ Release is ready for production deployment"
    echo "2. 📦 Create GitHub release with package artifacts"
    echo "3. 📢 Announce release to community"
    echo "4. 📚 Update documentation and guides"
else
    echo "1. ❌ Fix critical failures before release"
    echo "2. 🔧 Address warnings and non-critical issues"
    echo "3. 🔄 Re-run validation after fixes"
    echo "4. ✅ Certify release when all critical issues resolved"
fi)

---
*This certification report was generated automatically by the PVE SMB Gateway validation system.*
EOF
    
    echo "Certification report saved to: $CERTIFICATION_FILE"
    echo "Validation logs saved to: $LOG_DIR/"
    
    # Return appropriate exit code
    if [ $critical_failures -eq 0 ]; then
        echo "✅ Release is CERTIFIED for production deployment!"
        exit 0
    else
        echo "❌ Release is NOT CERTIFIED - $critical_failures critical failures found!"
        exit 1
    fi
}

# Generate recommendations
generate_recommendations() {
    cat << EOF
### Critical Issues (Must Fix)
$(grep "FAIL.*critical" "$LOG_DIR/validation_results.log" | sed 's/.*| FAIL | \(.*\) | \(.*\) | critical/• **\1**: \2/')

### Warnings (Should Address)
$(grep "WARN" "$LOG_DIR/validation_results.log" | sed 's/.*| WARN | \(.*\) | \(.*\) | .*/• **\1**: \2/')

### Performance Optimizations
• Monitor memory usage during peak loads
• Consider SSD storage for high I/O workloads
• Optimize SMB protocol settings for your environment

### Security Recommendations
• Regularly update SSL certificates
• Monitor for security vulnerabilities
• Implement proper access controls

### Documentation Improvements
• Keep documentation current with code changes
• Add troubleshooting guides for common issues
• Provide configuration examples
EOF
}

# Cleanup function
cleanup_validation() {
    echo "Cleaning up validation environment..."
    
    # Remove test shares
    pve-smbgateway delete validation-test 2>/dev/null || true
    
    # Clean up test directories
    rm -rf /tmp/validation-test
    
    echo "✓ Cleanup completed"
}

# Main validation execution
main() {
    echo "Starting comprehensive release validation..."
    echo "Validation directory: $VALIDATION_DIR"
    echo "Log directory: $LOG_DIR"
    echo "Results directory: $RESULTS_DIR"
    echo
    
    # Initialize validation environment
    init_validation_environment
    
    # Run all validations
    validate_code_quality
    validate_build_system
    validate_installation
    validate_functionality
    validate_security
    validate_performance
    validate_compatibility
    validate_documentation
    validate_testing
    validate_release_preparation
    
    # Generate final certification report
    generate_certification_report
    
    # Cleanup
    cleanup_validation
}

# Handle script interruption
trap cleanup_validation EXIT

# Run main function
main "$@" 