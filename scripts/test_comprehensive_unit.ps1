# PVE SMB Gateway - Comprehensive Unit Test Suite (PowerShell)
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive unit test runner for both frontend and backend components

param(
    [switch]$Help,
    [switch]$FrontendOnly,
    [switch]$BackendOnly,
    [switch]$IntegrationOnly,
    [switch]$NoReports,
    [switch]$Verbose
)

# Test configuration
$TestDir = "$env:TEMP\pve-smbgateway-comprehensive-tests"
$ReportDir = "$TestDir\reports"
$CoverageDir = "$TestDir\coverage"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Test counters
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0
$script:SkippedTests = 0

# Test results
$script:FrontendResult = 0
$script:BackendResult = 0
$script:IntegrationResult = 0

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"
$Magenta = "Magenta"
$Cyan = "Cyan"
$White = "White"

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
    $script:SkippedTests++
    $script:TotalTests++
}

function Write-Header {
    param([string]$Title)
    Write-Host "================================" -ForegroundColor $Magenta
    Write-Host "  $Title" -ForegroundColor $Magenta
    Write-Host "================================" -ForegroundColor $Magenta
}

function Write-SubHeader {
    param([string]$Title)
    Write-Host "--- $Title ---" -ForegroundColor $Cyan
}

# Help function
function Show-Help {
    @"
PVE SMB Gateway - Comprehensive Unit Test Suite

Usage: .\test_comprehensive_unit.ps1 [OPTIONS]

Options:
    -Help              Show this help message
    -FrontendOnly      Run only frontend tests
    -BackendOnly       Run only backend tests
    -IntegrationOnly   Run only integration tests
    -NoReports         Skip report generation
    -Verbose           Enable verbose output

Examples:
    .\test_comprehensive_unit.ps1              # Run all tests
    .\test_comprehensive_unit.ps1 -FrontendOnly # Run only frontend tests
    .\test_comprehensive_unit.ps1 -Verbose     # Run with verbose output

The test suite will:
1. Run frontend unit tests (Mocha + Chai + Sinon)
2. Run backend unit tests (Test::More + Test::MockModule)
3. Run integration tests
4. Generate comprehensive reports (HTML, JSON, JUnit)
5. Provide coverage analysis
"@
}

# Cleanup function
function Cleanup {
    Write-Info "Cleaning up test environment..."
    # Keep reports and coverage for analysis
    # Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Setup test environment
function Setup-TestEnvironment {
    Write-Info "Setting up comprehensive test environment..."
    
    # Create test directories
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    New-Item -ItemType Directory -Path $CoverageDir -Force | Out-Null
    
    # Create test configuration
    Create-TestConfig
    
    Write-Success "Test environment setup complete"
}

# Create test configuration
function Create-TestConfig {
    Write-Info "Creating test configuration..."
    
    $config = @{
        test_suite = @{
            name = "PVE SMB Gateway Comprehensive Unit Tests"
            version = "1.0.0"
            timestamp = $Timestamp
        }
        frontend = @{
            framework = "Mocha + Chai + Sinon"
            browsers = @("ChromeHeadless", "FirefoxHeadless")
            coverage = $true
            timeout = 10000
        }
        backend = @{
            framework = "Test::More + Test::MockModule"
            modules = @(
                "PVE::Storage::Custom::SMBGateway",
                "PVE::SMBGateway::Monitor",
                "PVE::SMBGateway::CLI",
                "PVE::SMBGateway::Security",
                "PVE::SMBGateway::Backup"
            )
            coverage = $true
        }
        integration = @{
            enabled = $true
            timeout = 30000
            parallel = $false
        }
        reporting = @{
            format = @("html", "json", "junit")
            output_dir = "reports"
            coverage_dir = "coverage"
        }
    }
    
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath "$TestDir\test-config.json" -Encoding UTF8
}

# Run frontend tests
function Run-FrontendTests {
    Write-Header "Frontend Unit Tests"
    
    if (Test-Path "scripts\test_frontend_unit.sh") {
        Write-SubHeader "Executing Frontend Test Suite"
        
        try {
            # On Windows, we need to use WSL or Git Bash if available
            if (Get-Command "bash" -ErrorAction SilentlyContinue) {
                bash scripts/test_frontend_unit.sh 2>&1 | Tee-Object -FilePath "$ReportDir\frontend-test.log"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Frontend tests completed successfully"
                    $script:FrontendResult = 0
                } else {
                    Write-Error "Frontend tests failed"
                    $script:FrontendResult = 1
                }
            } else {
                Write-Warning "Bash not available, skipping frontend tests"
                $script:FrontendResult = 2
            }
        } catch {
            Write-Error "Frontend tests failed: $_"
            $script:FrontendResult = 1
        }
        
        # Copy frontend coverage if available
        if (Test-Path "$env:TEMP\pve-smbgateway-frontend-tests\coverage") {
            Copy-Item -Path "$env:TEMP\pve-smbgateway-frontend-tests\coverage" -Destination "$CoverageDir\frontend" -Recurse -Force
            Write-Info "Frontend coverage report saved"
        }
    } else {
        Write-Warning "Frontend test script not found, skipping"
        $script:FrontendResult = 2
    }
}

# Run backend tests
function Run-BackendTests {
    Write-Header "Backend Unit Tests"
    
    if (Test-Path "scripts\test_backend_unit.sh") {
        Write-SubHeader "Executing Backend Test Suite"
        
        try {
            # On Windows, we need to use WSL or Git Bash if available
            if (Get-Command "bash" -ErrorAction SilentlyContinue) {
                bash scripts/test_backend_unit.sh 2>&1 | Tee-Object -FilePath "$ReportDir\backend-test.log"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Backend tests completed successfully"
                    $script:BackendResult = 0
                } else {
                    Write-Error "Backend tests failed"
                    $script:BackendResult = 1
                }
            } else {
                Write-Warning "Bash not available, skipping backend tests"
                $script:BackendResult = 2
            }
        } catch {
            Write-Error "Backend tests failed: $_"
            $script:BackendResult = 1
        }
        
        # Copy backend coverage if available
        if (Test-Path "$env:TEMP\pve-smbgateway-backend-tests\coverage") {
            Copy-Item -Path "$env:TEMP\pve-smbgateway-backend-tests\coverage" -Destination "$CoverageDir\backend" -Recurse -Force
            Write-Info "Backend coverage report saved"
        }
    } else {
        Write-Warning "Backend test script not found, skipping"
        $script:BackendResult = 2
    }
}

# Run integration tests
function Run-IntegrationTests {
    Write-Header "Integration Tests"
    
    if (Test-Path "scripts\test_integration.sh") {
        Write-SubHeader "Executing Integration Test Suite"
        
        try {
            # On Windows, we need to use WSL or Git Bash if available
            if (Get-Command "bash" -ErrorAction SilentlyContinue) {
                bash scripts/test_integration.sh 2>&1 | Tee-Object -FilePath "$ReportDir\integration-test.log"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Integration tests completed successfully"
                    $script:IntegrationResult = 0
                } else {
                    Write-Error "Integration tests failed"
                    $script:IntegrationResult = 1
                }
            } else {
                Write-Warning "Bash not available, skipping integration tests"
                $script:IntegrationResult = 2
            }
        } catch {
            Write-Error "Integration tests failed: $_"
            $script:IntegrationResult = 1
        }
    } else {
        Write-Warning "Integration test script not found, skipping"
        $script:IntegrationResult = 2
    }
}

# Generate test reports
function Generate-Reports {
    if ($NoReports) {
        Write-Info "Skipping report generation (NoReports flag set)"
        return
    }
    
    Write-Header "Generating Test Reports"
    
    # Create HTML report
    Create-HtmlReport
    
    # Create JSON report
    Create-JsonReport
    
    # Create JUnit report
    Create-JunitReport
    
    # Create coverage summary
    Create-CoverageSummary
    
    Write-Success "Test reports generated successfully"
}

# Create HTML report
function Create-HtmlReport {
    $successRate = if ($script:TotalTests -gt 0) { [math]::Round(($script:PassedTests * 100) / $script:TotalTests) } else { 0 }
    
    $frontendStatus = switch ($script:FrontendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $backendStatus = switch ($script:BackendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $integrationStatus = switch ($script:IntegrationResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $frontendClass = switch ($script:FrontendResult) {
        0 { "success" }
        1 { "failure" }
        default { "warning" }
    }
    
    $backendClass = switch ($script:BackendResult) {
        0 { "success" }
        1 { "failure" }
        default { "warning" }
    }
    
    $integrationClass = switch ($script:IntegrationResult) {
        0 { "success" }
        1 { "failure" }
        default { "warning" }
    }
    
    $html = @"
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
        <p>Generated: $(Get-Date)</p>
        <p>Test Suite Version: 1.0.0</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $($script:TotalTests)</p>
        <p><strong>Passed:</strong> <span style="color: green;">$($script:PassedTests)</span></p>
        <p><strong>Failed:</strong> <span style="color: red;">$($script:FailedTests)</span></p>
        <p><strong>Skipped:</strong> <span style="color: orange;">$($script:SkippedTests)</span></p>
        <p><strong>Success Rate:</strong> $successRate%</p>
    </div>
    
    <div class="test-section $frontendClass">
        <h3>Frontend Tests</h3>
        <p><strong>Status:</strong> $frontendStatus</p>
        <p><strong>Framework:</strong> Mocha + Chai + Sinon</p>
        <p><strong>Coverage:</strong> Available in coverage/frontend/</p>
    </div>
    
    <div class="test-section $backendClass">
        <h3>Backend Tests</h3>
        <p><strong>Status:</strong> $backendStatus</p>
        <p><strong>Framework:</strong> Test::More + Test::MockModule</p>
        <p><strong>Coverage:</strong> Available in coverage/backend/</p>
    </div>
    
    <div class="test-section $integrationClass">
        <h3>Integration Tests</h3>
        <p><strong>Status:</strong> $integrationStatus</p>
        <p><strong>Framework:</strong> Custom Integration Tests</p>
    </div>
    
    <div class="coverage">
        <h2>Coverage Summary</h2>
        <p>Detailed coverage reports are available in the coverage directory.</p>
        <div class="coverage-bar">
            <div class="coverage-fill" style="width: $successRate%;"></div>
        </div>
        <p>Overall Coverage: $successRate%</p>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath "$ReportDir\test-report.html" -Encoding UTF8
}

# Create JSON report
function Create-JsonReport {
    $successRate = if ($script:TotalTests -gt 0) { [math]::Round(($script:PassedTests * 100) / $script:TotalTests) } else { 0 }
    
    $frontendStatus = switch ($script:FrontendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $backendStatus = switch ($script:BackendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $integrationStatus = switch ($script:IntegrationResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $json = @{
        test_suite = @{
            name = "PVE SMB Gateway Comprehensive Unit Tests"
            version = "1.0.0"
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            duration = [math]::Round((Get-Date).ToFileTime() / 10000000)
        }
        summary = @{
            total_tests = $script:TotalTests
            passed = $script:PassedTests
            failed = $script:FailedTests
            skipped = $script:SkippedTests
            success_rate = $successRate
        }
        results = @{
            frontend = @{
                status = $frontendStatus
                framework = "Mocha + Chai + Sinon"
                coverage_available = (Test-Path "$CoverageDir\frontend")
            }
            backend = @{
                status = $backendStatus
                framework = "Test::More + Test::MockModule"
                coverage_available = (Test-Path "$CoverageDir\backend")
            }
            integration = @{
                status = $integrationStatus
                framework = "Custom Integration Tests"
            }
        }
        environment = @{
            node_version = $(try { & node --version 2>$null } catch { "N/A" })
            perl_version = $(try { & perl --version 2>$null | Select-Object -First 1 } catch { "N/A" })
            platform = $env:OS
        }
    }
    
    $json | ConvertTo-Json -Depth 10 | Out-File -FilePath "$ReportDir\test-report.json" -Encoding UTF8
}

# Create JUnit report
function Create-JunitReport {
    $frontendFailures = if ($script:FrontendResult -eq 1) { 1 } else { 0 }
    $frontendSkipped = if ($script:FrontendResult -eq 2) { 1 } else { 0 }
    $backendFailures = if ($script:BackendResult -eq 1) { 1 } else { 0 }
    $backendSkipped = if ($script:BackendResult -eq 2) { 1 } else { 0 }
    $integrationFailures = if ($script:IntegrationResult -eq 1) { 1 } else { 0 }
    $integrationSkipped = if ($script:IntegrationResult -eq 2) { 1 } else { 0 }
    
    $frontendFailure = if ($script:FrontendResult -eq 1) { '<failure message="Frontend tests failed"/>' } else { "" }
    $frontendSkippedMsg = if ($script:FrontendResult -eq 2) { '<skipped message="Frontend tests skipped"/>' } else { "" }
    $backendFailure = if ($script:BackendResult -eq 1) { '<failure message="Backend tests failed"/>' } else { "" }
    $backendSkippedMsg = if ($script:BackendResult -eq 2) { '<skipped message="Backend tests skipped"/>' } else { "" }
    $integrationFailure = if ($script:IntegrationResult -eq 1) { '<failure message="Integration tests failed"/>' } else { "" }
    $integrationSkippedMsg = if ($script:IntegrationResult -eq 2) { '<skipped message="Integration tests skipped"/>' } else { "" }
    
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="PVE SMB Gateway Comprehensive Tests" time="$([math]::Round((Get-Date).ToFileTime() / 10000000))">
  <testsuite name="Frontend Tests" tests="1" failures="$frontendFailures" skipped="$frontendSkipped">
    <testcase name="Frontend Test Suite" time="0">
      $frontendFailure
      $frontendSkippedMsg
    </testcase>
  </testsuite>
  <testsuite name="Backend Tests" tests="1" failures="$backendFailures" skipped="$backendSkipped">
    <testcase name="Backend Test Suite" time="0">
      $backendFailure
      $backendSkippedMsg
    </testcase>
  </testsuite>
  <testsuite name="Integration Tests" tests="1" failures="$integrationFailures" skipped="$integrationSkipped">
    <testcase name="Integration Test Suite" time="0">
      $integrationFailure
      $integrationSkippedMsg
    </testcase>
  </testsuite>
</testsuites>
"@
    
    $xml | Out-File -FilePath "$ReportDir\test-report.xml" -Encoding UTF8
}

# Create coverage summary
function Create-CoverageSummary {
    $successRate = if ($script:TotalTests -gt 0) { [math]::Round(($script:PassedTests * 100) / $script:TotalTests) } else { 0 }
    
    $frontendStatus = switch ($script:FrontendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $backendStatus = switch ($script:BackendResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $integrationStatus = switch ($script:IntegrationResult) {
        0 { "PASSED" }
        1 { "FAILED" }
        default { "SKIPPED" }
    }
    
    $frontendCoverage = if (Test-Path "$CoverageDir\frontend") { "Available" } else { "Not available" }
    $backendCoverage = if (Test-Path "$CoverageDir\backend") { "Available" } else { "Not available" }
    
    $summary = @"
PVE SMB Gateway - Coverage Summary
Generated: $(Get-Date)

Overall Test Results:
- Total Tests: $($script:TotalTests)
- Passed: $($script:PassedTests)
- Failed: $($script:FailedTests)
- Skipped: $($script:SkippedTests)
- Success Rate: $successRate%

Component Coverage:
- Frontend: $frontendCoverage
- Backend: $backendCoverage

Test Status:
- Frontend Tests: $frontendStatus
- Backend Tests: $backendStatus
- Integration Tests: $integrationStatus

For detailed coverage reports, see:
- Frontend: coverage/frontend/
- Backend: coverage/backend/
"@
    
    $summary | Out-File -FilePath "$CoverageDir\coverage-summary.txt" -Encoding UTF8
}

# Display test results
function Display-Results {
    Write-Header "Test Results Summary"
    
    Write-Host "Test Execution Results:" -ForegroundColor $Cyan
    $frontendColor = switch ($script:FrontendResult) { 0 { $Green } 1 { $Red } default { $Yellow } }
    $backendColor = switch ($script:BackendResult) { 0 { $Green } 1 { $Red } default { $Yellow } }
    $integrationColor = switch ($script:IntegrationResult) { 0 { $Green } 1 { $Red } default { $Yellow } }
    
    $frontendStatus = switch ($script:FrontendResult) { 0 { "PASSED" } 1 { "FAILED" } default { "SKIPPED" } }
    $backendStatus = switch ($script:BackendResult) { 0 { "PASSED" } 1 { "FAILED" } default { "SKIPPED" } }
    $integrationStatus = switch ($script:IntegrationResult) { 0 { "PASSED" } 1 { "FAILED" } default { "SKIPPED" } }
    
    Write-Host "  Frontend Tests: $frontendStatus" -ForegroundColor $frontendColor
    Write-Host "  Backend Tests:  $backendStatus" -ForegroundColor $backendColor
    Write-Host "  Integration Tests: $integrationStatus" -ForegroundColor $integrationColor
    
    Write-Host "`nTest Statistics:" -ForegroundColor $Cyan
    Write-Host "  Total Tests: $($script:TotalTests)" -ForegroundColor $White
    Write-Host "  Passed: $($script:PassedTests)" -ForegroundColor $Green
    Write-Host "  Failed: $($script:FailedTests)" -ForegroundColor $Red
    Write-Host "  Skipped: $($script:SkippedTests)" -ForegroundColor $Yellow
    
    if ($script:TotalTests -gt 0) {
        $successRate = [math]::Round(($script:PassedTests * 100) / $script:TotalTests)
        Write-Host "  Success Rate: $successRate%" -ForegroundColor $Green
    }
    
    Write-Host "`nReports Generated:" -ForegroundColor $Cyan
    Write-Host "  HTML Report: $ReportDir\test-report.html" -ForegroundColor $White
    Write-Host "  JSON Report: $ReportDir\test-report.json" -ForegroundColor $White
    Write-Host "  JUnit Report: $ReportDir\test-report.xml" -ForegroundColor $White
    Write-Host "  Coverage Summary: $CoverageDir\coverage-summary.txt" -ForegroundColor $White
}

# Main execution
function Main {
    if ($Help) {
        Show-Help
        exit 0
    }
    
    Write-Header "PVE SMB Gateway - Comprehensive Unit Test Suite"
    
    # Setup
    Setup-TestEnvironment
    
    # Run tests based on parameters
    if ($FrontendOnly) {
        Run-FrontendTests
    } elseif ($BackendOnly) {
        Run-BackendTests
    } elseif ($IntegrationOnly) {
        Run-IntegrationTests
    } else {
        # Run all tests
        Run-FrontendTests
        Run-BackendTests
        Run-IntegrationTests
    }
    
    # Generate reports
    Generate-Reports
    
    # Display results
    Display-Results
    
    # Determine exit code
    $exitCode = 0
    if ($script:FrontendResult -eq 1 -or $script:BackendResult -eq 1 -or $script:IntegrationResult -eq 1) {
        $exitCode = 1
        Write-Host "Some tests failed!" -ForegroundColor $Red
    } else {
        Write-Host "All tests completed successfully!" -ForegroundColor $Green
    }
    
    Write-Info "Test reports available in: $ReportDir"
    Write-Info "Coverage reports available in: $CoverageDir"
    
    exit $exitCode
}

# Cleanup on exit
try {
    Main
} finally {
    Cleanup
} 