# PVE SMB Gateway - Deploy to Proxmox Script
# Helps transfer and deploy the plugin to a Proxmox host

param(
    [Parameter(Mandatory=$true)]
    [string]$ProxmoxHost,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "root",
    
    [Parameter(Mandatory=$false)]
    [string]$SSHKey = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTransfer = $false
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

Write-Status "HEADER" "PVE SMB Gateway Deployment to Proxmox"
Write-Host "Target Host: $ProxmoxHost"
Write-Host "Username: $Username"
Write-Host "Started at: $(Get-Date)"
Write-Host ""

# Check if deployment package exists
if (-not (Test-Path "deployment-package")) {
    Write-Status "FAIL" "Deployment package not found"
    Write-Host "Please run prepare_for_deployment.ps1 first"
    exit 1
}

Write-Status "PASS" "Deployment package found"

# Check if ZIP file exists
$ZipFile = Get-ChildItem -Name "pve-smbgateway-deployment-*.zip" | Select-Object -First 1
if (-not $ZipFile) {
    Write-Status "FAIL" "Deployment ZIP file not found"
    exit 1
}

Write-Status "PASS" "Deployment ZIP found: $ZipFile"

# Transfer files to Proxmox host
if (-not $SkipTransfer) {
    Write-Status "HEADER" "Transferring Files to Proxmox Host"
    
    $ScpCommand = "scp"
    if ($SSHKey) {
        $ScpCommand += " -i `"$SSHKey`""
    }
    $ScpCommand += " `"$ZipFile`" $Username@$ProxmoxHost`:/tmp/"
    
    Write-Status "INFO" "Executing: $ScpCommand"
    
    try {
        Invoke-Expression $ScpCommand
        Write-Status "PASS" "Files transferred successfully"
    }
    catch {
        Write-Status "FAIL" "File transfer failed: $($_.Exception.Message)"
        Write-Host ""
        Write-Host "Manual transfer instructions:"
        Write-Host "1. Copy $ZipFile to your Proxmox host"
        Write-Host "2. Place it in /tmp/ directory"
        Write-Host "3. Continue with the deployment steps below"
        Write-Host ""
    }
}
else {
    Write-Status "INFO" "Skipping file transfer (SkipTransfer flag set)"
}

# Generate deployment commands
Write-Status "HEADER" "Deployment Commands for Proxmox Host"
Write-Host ""
Write-Host "SSH to your Proxmox host and run these commands:"
Write-Host ""

$DeployCommands = @"
# 1. SSH to Proxmox host
ssh $Username@$ProxmoxHost

# 2. Navigate to /tmp and extract the package
cd /tmp
unzip $ZipFile
cd deployment-package

# 3. Make scripts executable
chmod +x scripts/*.sh deploy.sh

# 4. Run pre-flight safety check (CRITICAL!)
./scripts/preflight_check.sh

# 5. If pre-flight check passes, deploy the plugin
./deploy.sh

# 6. Verify installation
pvesh get /storage | grep smbgateway
pve-smbgateway --help

# 7. Run comprehensive tests
./scripts/run_all_tests.sh

# 8. Follow testing checklist
cat LIVE_TESTING_CHECKLIST.md
"@

Write-Host $DeployCommands -ForegroundColor $Blue
Write-Host ""

# Generate quick reference
Write-Status "HEADER" "Quick Reference"
Write-Host ""
Write-Host "Important Files:"
Write-Host "- Deployment Package: deployment-package/"
Write-Host "- ZIP Archive: $ZipFile"
Write-Host "- Deployment Guide: DEPLOYMENT_GUIDE.md"
Write-Host "- Testing Checklist: LIVE_TESTING_CHECKLIST.md"
Write-Host ""

Write-Host "Key Commands:"
Write-Host "- Pre-flight Check: ./scripts/preflight_check.sh"
Write-Host "- Deploy Plugin: ./deploy.sh"
Write-Host "- Run Tests: ./scripts/run_all_tests.sh"
Write-Host "- Rollback: ./scripts/rollback.sh"
Write-Host ""

Write-Host "Safety Notes:"
Write-Host "- Always test in non-production environment first"
Write-Host "- Have backups of your Proxmox configuration"
Write-Host "- Keep rollback script ready"
Write-Host "- Monitor system resources during testing"
Write-Host ""

Write-Status "PASS" "Deployment preparation completed!"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Transfer files to your Proxmox host"
Write-Host "2. SSH to the host and run the deployment commands above"
Write-Host "3. Follow the pre-flight check and testing procedures"
Write-Host "4. Use the testing checklist for comprehensive validation"
Write-Host ""

Write-Host "For support: eric@gozippy.com"
Write-Host "" 