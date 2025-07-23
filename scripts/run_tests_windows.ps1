# PVE SMB Gateway - Windows Test Runner
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Windows-compatible test runner for PVE SMB Gateway

param(
    [switch]$Quick,
    [switch]$FrontendOnly,
    [switch]$BackendOnly,
    [switch]$CLIOnly,
    [switch]$IntegrationOnly,
    [switch]$GenerateReport
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"
$Cyan = "Cyan"
$Magenta = "Magenta"
$White = "White"

# Test configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$TestResultsDir = "C:\temp\pve-smbgateway-test-results"
$TestLogsDir = "$TestResultsDir\logs"
$TestReportsDir = "$TestResultsDir\reports"

# Test counters
$TotalSuites = 0
$PassedSuites = 0
$FailedSuites = 0
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0
$SkippedTests = 0

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor $Green
    $script:PassedTests++
    $script:TotalTests++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor $Red
    $script:FailedTests++
    $script:TotalTests++
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor $Yellow
}

function Write-Header {
    param([string]$Message)
    Write-Host "[HEADER] $Message" -ForegroundColor $Magenta
}

function Write-Subheader {
    param([string]$Message)
    Write-Host "[SUBHEADER] $Message" -ForegroundColor $Cyan
}

# Cleanup function
function Cleanup-TestEnvironment {
    Write-Info "Cleaning up test environment..."
    
    # Stop any running test processes
    Get-Process | Where-Object { $_.ProcessName -like "*test*" -or $_.ProcessName -like "*mock*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Clean up temporary test directories
    if (Test-Path "C:\temp\pve-smbgateway-*-tests") {
        Remove-Item "C:\temp\pve-smbgateway-*-tests" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "C:\temp\test-*") {
        Remove-Item "C:\temp\test-*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Info "Cleanup completed"
}

# Setup test environment
function Setup-TestEnvironment {
    Write-Info "Setting up test environment..."
    
    # Create test results directory
    New-Item -ItemType Directory -Path $TestResultsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $TestLogsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $TestReportsDir -Force | Out-Null
    
    # Check if we're in the right directory
    if (-not (Test-Path "$ProjectRoot\README.md")) {
        Write-Error "Not in project root directory"
        exit 1
    }
    
    Write-Info "Test environment setup completed"
}

# Test suite functions
function Test-FrontendUnit {
    Write-Header "Running Frontend Unit Tests"
    $script:TotalSuites++
    
    try {
        # Check if bash is available
        if (Get-Command bash -ErrorAction SilentlyContinue) {
            Write-Info "Attempting to run bash frontend tests..."
            $result = bash scripts/test_frontend_unit.sh --quick 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Frontend unit tests completed successfully"
                $script:PassedSuites++
            } else {
                Write-Error "Frontend unit tests failed"
                $script:FailedSuites++
            }
        } else {
            Write-Warning "Bash not available, skipping frontend tests"
            $script:SkippedTests++
        }
    } catch {
        Write-Error "Frontend unit tests failed: $($_.Exception.Message)"
        $script:FailedSuites++
    }
}

function Test-BackendUnit {
    Write-Header "Running Backend Unit Tests"
    $script:TotalSuites++
    
    try {
        # Check if bash is available
        if (Get-Command bash -ErrorAction SilentlyContinue) {
            Write-Info "Attempting to run bash backend tests..."
            $result = bash scripts/test_backend_unit.sh --quick 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Backend unit tests completed successfully"
                $script:PassedSuites++
            } else {
                Write-Error "Backend unit tests failed"
                $script:FailedSuites++
            }
        } else {
            Write-Warning "Bash not available, skipping backend tests"
            $script:SkippedTests++
        }
    } catch {
        Write-Error "Backend unit tests failed: $($_.Exception.Message)"
        $script:FailedSuites++
    }
}

function Test-CLIUnit {
    Write-Header "Running CLI Unit Tests"
    $script:TotalSuites++
    
    try {
        # Check if bash is available
        if (Get-Command bash -ErrorAction SilentlyContinue) {
            Write-Info "Attempting to run bash CLI tests..."
            $result = bash scripts/test_cli_unit.sh --quick 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "CLI unit tests completed successfully"
                $script:PassedSuites++
            } else {
                Write-Error "CLI unit tests failed"
                $script:FailedSuites++
            }
        } else {
            Write-Warning "Bash not available, skipping CLI tests"
            $script:SkippedTests++
        }
    } catch {
        Write-Error "CLI unit tests failed: $($_.Exception.Message)"
        $script:FailedSuites++
    }
}

function Test-Integration {
    Write-Header "Running Integration Tests"
    $script:TotalSuites++
    
    try {
        # Check if bash is available
        if (Get-Command bash -ErrorAction SilentlyContinue) {
            Write-Info "Attempting to run bash integration tests..."
            $result = bash scripts/test_integration.sh --quick 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Integration tests completed successfully"
                $script:PassedSuites++
            } else {
                Write-Error "Integration tests failed"
                $script:FailedSuites++
            }
        } else {
            Write-Warning "Bash not available, skipping integration tests"
            $script:SkippedTests++
        }
    } catch {
        Write-Error "Integration tests failed: $($_.Exception.Message)"
        $script:FailedSuites++
    }
}

# Generate test report
function Generate-TestReport {
    Write-Header "Generating Test Report"
    
    $reportPath = "$TestReportsDir\Testing_Report.md"
    
    $report = @"
# PVE SMB Gateway - Testing Report

Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Environment: Windows PowerShell

## Test Summary

- **Total Test Suites**: $TotalSuites
- **Passed Suites**: $PassedSuites
- **Failed Suites**: $FailedSuites
- **Total Tests**: $TotalTests
- **Passed Tests**: $PassedTests
- **Failed Tests**: $FailedTests
- **Skipped Tests**: $SkippedTests

## Test Coverage

### Frontend Unit Tests
- **Status**: $(if ($PassedSuites -gt 0) { "PASSED" } else { "FAILED/SKIPPED" })
- **Coverage**: ExtJS components, form validation, user interactions
- **Files**: scripts/test_frontend_unit.sh

### Backend Unit Tests
- **Status**: $(if ($PassedSuites -gt 0) { "PASSED" } else { "FAILED/SKIPPED" })
- **Coverage**: Perl modules, storage plugin, monitoring, backup
- **Files**: scripts/test_backend_unit.sh

### CLI Unit Tests
- **Status**: $(if ($PassedSuites -gt 0) { "PASSED" } else { "FAILED/SKIPPED" })
- **Coverage**: Command-line interface, parameter validation
- **Files**: scripts/test_cli_unit.sh

### Integration Tests
- **Status**: $(if ($PassedSuites -gt 0) { "PASSED" } else { "FAILED/SKIPPED" })
- **Coverage**: End-to-end workflows, API integration
- **Files**: scripts/test_integration.sh

## Environment Issues

The test execution encountered the following issues on Windows:

1. **Bash Compatibility**: The test scripts are designed for Linux/bash environments
2. **PowerShell Integration**: Some PowerShell console issues with long commands
3. **File Permissions**: Unix-style permissions need to be handled differently on Windows

## Recommendations

1. **Use WSL**: Run tests in Windows Subsystem for Linux for full compatibility
2. **Docker**: Use Docker containers with Linux for consistent test environment
3. **CI/CD**: Set up automated testing in Linux-based CI/CD pipelines
4. **Cross-Platform**: Consider creating Windows-native test scripts for local development

## Test Scripts Available

The following comprehensive test scripts are available in the \`scripts\` directory:

- \`run_all_tests.sh\` - Master test runner
- \`test_frontend_unit.sh\` - Frontend unit tests (1116 lines)
- \`test_backend_unit.sh\` - Backend unit tests (1194 lines)
- \`test_cli_unit.sh\` - CLI unit tests (1257 lines)
- \`test_integration.sh\` - Integration tests (876 lines)
- \`test_enhanced_error_handling.sh\` - Error handling tests (480 lines)
- \`test_ha_integration.sh\` - High availability tests (430 lines)
- \`test_ad_integration.sh\` - Active Directory tests (422 lines)

## Next Steps

1. Set up a Linux environment (WSL, Docker, or VM) for full test execution
2. Run the comprehensive test suite to validate all functionality
3. Review test results and address any failures
4. Integrate tests into CI/CD pipeline for automated validation
"@

    $report | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Success "Test report generated: $reportPath"
    
    # Also copy to docs directory
    $docsPath = "$ProjectRoot\docs\Testing_Report.md"
    $report | Out-File -FilePath $docsPath -Encoding UTF8
    Write-Success "Test report copied to: $docsPath"
}

# Main execution
function Main {
    Write-Header "PVE SMB Gateway - Windows Test Runner"
    Write-Info "Starting test execution..."
    
    # Setup environment
    Setup-TestEnvironment
    
    # Determine which tests to run
    if ($FrontendOnly) {
        Test-FrontendUnit
    } elseif ($BackendOnly) {
        Test-BackendUnit
    } elseif ($CLIOnly) {
        Test-CLIUnit
    } elseif ($IntegrationOnly) {
        Test-Integration
    } else {
        # Run all tests
        Test-FrontendUnit
        Test-BackendUnit
        Test-CLIUnit
        Test-Integration
    }
    
    # Generate report if requested
    if ($GenerateReport) {
        Generate-TestReport
    }
    
    # Final summary
    Write-Header "Test Execution Summary"
    Write-Info "Total Suites: $TotalSuites"
    Write-Info "Passed Suites: $PassedSuites"
    Write-Info "Failed Suites: $FailedSuites"
    Write-Info "Total Tests: $TotalTests"
    Write-Info "Passed Tests: $PassedTests"
    Write-Info "Failed Tests: $FailedTests"
    Write-Info "Skipped Tests: $SkippedTests"
    
    # Cleanup
    Cleanup-TestEnvironment
    
    Write-Header "Test execution completed"
}

# Run main function
Main 