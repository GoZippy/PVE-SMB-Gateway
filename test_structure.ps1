# PVE SMB Gateway - Project Structure Test
# This script validates the project structure and key components

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PVE SMB Gateway - Structure Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$testResults = @()

# Test 1: Check if we're in the right directory
Write-Host "Test 1: Project Root Validation..." -ForegroundColor Yellow
if (Test-Path "README.md") {
    Write-Host "  ✅ README.md found" -ForegroundColor Green
    $testResults += "Project root: PASS"
} else {
    Write-Host "  ❌ README.md not found" -ForegroundColor Red
    $testResults += "Project root: FAIL"
}

# Test 2: Check core Perl module
Write-Host "Test 2: Core Perl Module..." -ForegroundColor Yellow
if (Test-Path "PVE/Storage/Custom/SMBGateway.pm") {
    $content = Get-Content "PVE/Storage/Custom/SMBGateway.pm" -Raw
    if ($content -match "package PVE::Storage::Custom::SMBGateway") {
        Write-Host "  ✅ SMBGateway.pm found and properly formatted" -ForegroundColor Green
        $testResults += "Perl module: PASS"
    } else {
        Write-Host "  ⚠️  SMBGateway.pm found but may have formatting issues" -ForegroundColor Yellow
        $testResults += "Perl module: WARNING"
    }
} else {
    Write-Host "  ❌ SMBGateway.pm not found" -ForegroundColor Red
    $testResults += "Perl module: FAIL"
}

# Test 3: Check CLI tool
Write-Host "Test 3: CLI Management Tool..." -ForegroundColor Yellow
if (Test-Path "sbin/pve-smbgateway") {
    $content = Get-Content "sbin/pve-smbgateway" -Raw
    if ($content -match "#!/usr/bin/env perl") {
        Write-Host "  ✅ pve-smbgateway CLI tool found and properly formatted" -ForegroundColor Green
        $testResults += "CLI tool: PASS"
    } else {
        Write-Host "  ⚠️  pve-smbgateway found but may have formatting issues" -ForegroundColor Yellow
        $testResults += "CLI tool: WARNING"
    }
} else {
    Write-Host "  ❌ pve-smbgateway not found" -ForegroundColor Red
    $testResults += "CLI tool: FAIL"
}

# Test 4: Check ExtJS web interface
Write-Host "Test 4: ExtJS Web Interface..." -ForegroundColor Yellow
if (Test-Path "www/ext6/pvemanager6/smb-gateway.js") {
    $content = Get-Content "www/ext6/pvemanager6/smb-gateway.js" -Raw
    if ($content -match "Ext.define") {
        Write-Host "  ✅ smb-gateway.js found and properly formatted" -ForegroundColor Green
        $testResults += "Web interface: PASS"
    } else {
        Write-Host "  ⚠️  smb-gateway.js found but may have formatting issues" -ForegroundColor Yellow
        $testResults += "Web interface: WARNING"
    }
} else {
    Write-Host "  ❌ smb-gateway.js not found" -ForegroundColor Red
    $testResults += "Web interface: FAIL"
}

# Test 5: Check unit tests
Write-Host "Test 5: Unit Tests..." -ForegroundColor Yellow
$testFiles = Get-ChildItem "t/" -Filter "*.t" -ErrorAction SilentlyContinue
if ($testFiles.Count -gt 0) {
    Write-Host "  ✅ Found $($testFiles.Count) unit test files" -ForegroundColor Green
    $testResults += "Unit tests: PASS ($($testFiles.Count) files)"
} else {
    Write-Host "  ❌ No unit test files found" -ForegroundColor Red
    $testResults += "Unit tests: FAIL"
}

# Test 6: Check documentation
Write-Host "Test 6: Documentation..." -ForegroundColor Yellow
$docFiles = @("README.md", "docs/USER_GUIDE.md", "docs/DEV_GUIDE.md", "ALPHA_RELEASE_NOTES.md")
$docCount = 0
foreach ($doc in $docFiles) {
    if (Test-Path $doc) {
        $docCount++
    }
}
if ($docCount -eq $docFiles.Count) {
    Write-Host "  ✅ All documentation files present" -ForegroundColor Green
    $testResults += "Documentation: PASS"
} else {
    Write-Host "  ⚠️  Found $docCount of $($docFiles.Count) documentation files" -ForegroundColor Yellow
    $testResults += "Documentation: WARNING"
}

# Test 7: Check build scripts
Write-Host "Test 7: Build System..." -ForegroundColor Yellow
$buildFiles = @("scripts/build_package.sh", "Makefile", "debian/control")
$buildCount = 0
foreach ($file in $buildFiles) {
    if (Test-Path $file) {
        $buildCount++
    }
}
if ($buildCount -eq $buildFiles.Count) {
    Write-Host "  ✅ All build system files present" -ForegroundColor Green
    $testResults += "Build system: PASS"
} else {
    Write-Host "  ⚠️  Found $buildCount of $($buildFiles.Count) build files" -ForegroundColor Yellow
    $testResults += "Build system: WARNING"
}

# Test 8: Check installer
Write-Host "Test 8: Installer System..." -ForegroundColor Yellow
$installerFiles = @("installer/run-installer.sh", "installer/run-installer.ps1", "launch.bat")
$installerCount = 0
foreach ($file in $installerFiles) {
    if (Test-Path $file) {
        $installerCount++
    }
}
if ($installerCount -eq $installerFiles.Count) {
    Write-Host "  ✅ All installer files present" -ForegroundColor Green
    $testResults += "Installer: PASS"
} else {
    Write-Host "  ⚠️  Found $installerCount of $($installerFiles.Count) installer files" -ForegroundColor Yellow
    $testResults += "Installer: WARNING"
}

# Test 9: Check license and legal
Write-Host "Test 9: License and Legal..." -ForegroundColor Yellow
$legalFiles = @("LICENSE", "CONTRIBUTOR_LICENSE_AGREEMENT.md", "docs/COMMERCIAL_LICENSE.md")
$legalCount = 0
foreach ($file in $legalFiles) {
    if (Test-Path $file) {
        $legalCount++
    }
}
if ($legalCount -eq $legalFiles.Count) {
    Write-Host "  ✅ All legal files present" -ForegroundColor Green
    $testResults += "Legal: PASS"
} else {
    Write-Host "  ⚠️  Found $legalCount of $($legalFiles.Count) legal files" -ForegroundColor Yellow
    $testResults += "Legal: WARNING"
}

# Test 10: Check CI/CD
Write-Host "Test 10: CI/CD Configuration..." -ForegroundColor Yellow
$ciFiles = @(".github/workflows/ci-cd.yml", ".github/workflows/deb.yml")
$ciCount = 0
foreach ($file in $ciFiles) {
    if (Test-Path $file) {
        $ciCount++
    }
}
if ($ciCount -eq $ciFiles.Count) {
    Write-Host "  ✅ All CI/CD files present" -ForegroundColor Green
    $testResults += "CI/CD: PASS"
} else {
    Write-Host "  ⚠️  Found $ciCount of $($ciFiles.Count) CI/CD files" -ForegroundColor Yellow
    $testResults += "CI/CD: WARNING"
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$passCount = ($testResults | Where-Object { $_ -match "PASS" }).Count
$warningCount = ($testResults | Where-Object { $_ -match "WARNING" }).Count
$failCount = ($testResults | Where-Object { $_ -match "FAIL" }).Count

foreach ($result in $testResults) {
    if ($result -match "PASS") {
        Write-Host "  ✅ $result" -ForegroundColor Green
    } elseif ($result -match "WARNING") {
        Write-Host "  ⚠️  $result" -ForegroundColor Yellow
    } else {
        Write-Host "  ❌ $result" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Overall Results:" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Warnings: $warningCount" -ForegroundColor Yellow
Write-Host "  Failed: $failCount" -ForegroundColor Red

if ($failCount -eq 0) {
    Write-Host ""
    Write-Host "🎉 Project structure validation PASSED!" -ForegroundColor Green
    Write-Host "The PVE SMB Gateway project is ready for Linux/Proxmox testing." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "⚠️  Project structure has issues that need attention." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Set up a Linux/Proxmox testing environment" -ForegroundColor White
Write-Host "2. Install Perl and required dependencies" -ForegroundColor White
Write-Host "3. Build the Debian package" -ForegroundColor White
Write-Host "4. Run unit tests and integration tests" -ForegroundColor White
Write-Host "5. Test all deployment modes" -ForegroundColor White 