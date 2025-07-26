# PVE SMB Gateway - Windows Deployment Preparation Script
# Prepares the project for deployment to a Linux Proxmox system

param(
    [string]$TargetHost = "",
    [string]$Username = "root",
    [string]$DeployPath = "/tmp/pve-smbgateway"
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"
$Purple = "Magenta"

function Write-Status {
    param(
        [string]$Status,
        [string]$Message
    )
    
    switch ($Status) {
        "PASS" { Write-Host "✓ PASS" -ForegroundColor $Green -NoNewline; Write-Host ": $Message" }
        "FAIL" { Write-Host "✗ FAIL" -ForegroundColor $Red -NoNewline; Write-Host ": $Message" }
        "WARN" { Write-Host "⚠ WARN" -ForegroundColor $Yellow -NoNewline; Write-Host ": $Message" }
        "INFO" { Write-Host "ℹ INFO" -ForegroundColor $Blue -NoNewline; Write-Host ": $Message" }
        "HEADER" { Write-Host "=== $Message ===" -ForegroundColor $Purple }
    }
}

Write-Status "HEADER" "PVE SMB Gateway Deployment Preparation"
Write-Host "This script prepares the project for deployment to a Linux Proxmox system"
Write-Host "Started at: $(Get-Date)"
Write-Host ""

# Check if we're in the right directory
if (-not (Test-Path "PVE/Storage/Custom/SMBGateway.pm")) {
    Write-Status "FAIL" "Not in the correct project directory"
    Write-Host "Please run this script from the project root directory"
    exit 1
}

Write-Status "PASS" "Project directory structure verified"

# Check for required files
$RequiredFiles = @(
    "PVE/Storage/Custom/SMBGateway.pm",
    "PVE/SMBGateway/Monitor.pm",
    "PVE/SMBGateway/Backup.pm",
    "PVE/SMBGateway/Security.pm",
    "PVE/SMBGateway/CLI.pm",
    "PVE/SMBGateway/QuotaManager.pm",
    "debian/control",
    "debian/install",
    "scripts/preflight_check.sh",
    "scripts/rollback.sh",
    "scripts/test_vm_mode.sh",
    "scripts/test_quota_management.sh",
    "scripts/run_all_tests.sh"
)

Write-Status "HEADER" "Checking Required Files"

$MissingFiles = @()
foreach ($file in $RequiredFiles) {
    if (Test-Path $file) {
        Write-Status "PASS" "Found: $file"
    } else {
        Write-Status "FAIL" "Missing: $file"
        $MissingFiles += $file
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Host ""
    Write-Status "FAIL" "Missing required files. Please ensure all files are present before deployment."
    exit 1
}

Write-Host ""
Write-Status "PASS" "All required files are present"

# Create deployment package
Write-Status "HEADER" "Creating Deployment Package"

$DeploymentDir = "deployment-package"
if (Test-Path $DeploymentDir) {
    Remove-Item -Recurse -Force $DeploymentDir
}

New-Item -ItemType Directory -Path $DeploymentDir | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/PVE" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/PVE/Storage" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/PVE/Storage/Custom" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/PVE/SMBGateway" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/debian" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/scripts" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/www" | Out-Null
New-Item -ItemType Directory -Path "$DeploymentDir/sbin" | Out-Null

# Copy files
Write-Status "INFO" "Copying project files..."

# Copy PVE modules
Copy-Item "PVE/Storage/Custom/SMBGateway.pm" "$DeploymentDir/PVE/Storage/Custom/"
Copy-Item "PVE/SMBGateway/*.pm" "$DeploymentDir/PVE/SMBGateway/"

# Copy debian package files
Copy-Item "debian/*" "$DeploymentDir/debian/"

# Copy scripts
Copy-Item "scripts/*.sh" "$DeploymentDir/scripts/"

# Copy web interface files
if (Test-Path "www") {
    Copy-Item "www" -Destination "$DeploymentDir/" -Recurse
}

# Copy CLI tools
if (Test-Path "sbin") {
    Copy-Item "sbin" -Destination "$DeploymentDir/" -Recurse
}

# Copy documentation
Copy-Item "README.md" "$DeploymentDir/"
Copy-Item "LICENSE" "$DeploymentDir/"
Copy-Item "LIVE_TESTING_CHECKLIST.md" "$DeploymentDir/"

Write-Status "PASS" "Deployment package created"

# Create deployment script
$DeployScript = @"
#!/bin/bash
# PVE SMB Gateway Deployment Script
# Auto-generated deployment script

set -e

echo "=== PVE SMB Gateway Deployment ==="
echo "Started at: \$(date)"
echo ""

# Check if running on Proxmox
if [ ! -f "/etc/pve/version" ]; then
    echo "ERROR: Not running on Proxmox VE"
    exit 1
fi

echo "✓ Running on Proxmox VE"

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y samba winbind acl attr libdbi-perl libdbd-sqlite3-perl libjson-pp-perl libfile-path-perl libfile-basename-perl libsys-hostname-perl quota xfsprogs

# Build package
echo "Building package..."
dpkg-buildpackage -b -us -uc

# Install package
echo "Installing package..."
dpkg -i ../pve-plugin-smbgateway_*.deb

# Restart Proxmox services
echo "Restarting Proxmox services..."
systemctl restart pveproxy pvedaemon pvestatd

echo ""
echo "=== Deployment Complete ==="
echo "Next steps:"
echo "1. Run pre-flight check: ./scripts/preflight_check.sh"
echo "2. Follow testing checklist: cat LIVE_TESTING_CHECKLIST.md"
echo "3. Start with basic testing: ./scripts/run_all_tests.sh"
echo ""
"@

$DeployScript | Out-File -FilePath "$DeploymentDir/deploy.sh" -Encoding UTF8

Write-Status "PASS" "Deployment script created"

# Create quick start guide
$QuickStart = @"
# PVE SMB Gateway - Quick Start Guide

## Deployment Instructions

1. **Transfer files to Proxmox host:**
   ```bash
   scp -r deployment-package root@your-proxmox-host:/tmp/
   ```

2. **SSH to Proxmox host:**
   ```bash
   ssh root@your-proxmox-host
   ```

3. **Navigate to deployment directory:**
   ```bash
   cd /tmp/deployment-package
   ```

4. **Make scripts executable:**
   ```bash
   chmod +x scripts/*.sh deploy.sh
   ```

5. **Run deployment:**
   ```bash
   ./deploy.sh
   ```

6. **Run pre-flight check:**
   ```bash
   ./scripts/preflight_check.sh
   ```

7. **Start testing:**
   ```bash
   ./scripts/run_all_tests.sh
   ```

## Important Notes

- Always test in a non-production environment first
- Have backups of your Proxmox configuration
- Keep the rollback script ready: \`./scripts/rollback.sh\`
- Follow the testing checklist: \`LIVE_TESTING_CHECKLIST.md\`

## Support

For issues or questions, contact: eric@gozippy.com
"@

$QuickStart | Out-File -FilePath "$DeploymentDir/QUICK_START.md" -Encoding UTF8

Write-Status "PASS" "Quick start guide created"

# Create archive
Write-Status "HEADER" "Creating Deployment Archive"

$ArchiveName = "pve-smbgateway-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').tar.gz"

# Note: We can't create tar.gz on Windows without additional tools
# Instead, create a ZIP file
$ZipName = "pve-smbgateway-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"

Compress-Archive -Path $DeploymentDir -DestinationPath $ZipName -Force

Write-Status "PASS" "Deployment archive created: $ZipName"

# Summary
Write-Status "HEADER" "Deployment Preparation Summary"

Write-Status "INFO" "Deployment package created in: $DeploymentDir"
Write-Status "INFO" "Deployment archive: $ZipName"
Write-Status "INFO" "Deployment script: $DeploymentDir/deploy.sh"
Write-Status "INFO" "Quick start guide: $DeploymentDir/QUICK_START.md"

Write-Host ""
Write-Status "PASS" "Deployment preparation completed successfully!"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Transfer the deployment package to your Proxmox host"
Write-Host "2. Follow the quick start guide for installation"
Write-Host "3. Run the pre-flight check before testing"
Write-Host "4. Use the testing checklist for comprehensive validation"
Write-Host ""
Write-Host "Files created:"
Write-Host "- $DeploymentDir/ (deployment package)"
Write-Host "- $ZipName (compressed archive)"
Write-Host "- $DeploymentDir/QUICK_START.md (installation guide)"
Write-Host "" 