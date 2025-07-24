# PVE SMB Gateway - GUI Installer Launcher (Windows)
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

param(
    [switch]$Help,
    [switch]$Version,
    [switch]$CheckOnly,
    [switch]$InstallDeps,
    [switch]$NoRootCheck,
    [switch]$Verbose
)

# Script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$InstallerScript = Join-Path $ScriptDir "pve-smbgateway-installer.py"

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Header {
    Write-Host "================================" -ForegroundColor Magenta
    Write-Host "  PVE SMB Gateway Installer" -ForegroundColor Magenta
    Write-Host "================================" -ForegroundColor Magenta
    Write-Host ""
}

# Function to show help
function Show-Help {
    @"
PVE SMB Gateway - GUI Installer (Windows)

Usage: .\run-installer.ps1 [OPTIONS]

Options:
    -Help          Show this help message
    -Version       Show version information
    -CheckOnly     Only check system requirements
    -InstallDeps   Install dependencies only
    -NoRootCheck   Skip administrator check
    -Verbose       Enable verbose output

Examples:
    .\run-installer.ps1              # Run the GUI installer
    .\run-installer.ps1 -CheckOnly   # Only check system requirements
    .\run-installer.ps1 -InstallDeps # Install dependencies only

The installer will:
1. Check system compatibility
2. Install required dependencies
3. Build the SMB Gateway package
4. Install the plugin into Proxmox
5. Configure services and settings
6. Test the installation

Note: This installer is designed for Linux/Proxmox systems.
On Windows, it will help you prepare for installation on a Proxmox server.

For more information, visit: https://github.com/GoZippy/PVE-SMB-Gateway
"@
}

# Function to show version
function Show-Version {
    @"
PVE SMB Gateway Installer v1.0.0
Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
Dual-licensed under AGPL-3.0 and Commercial License

This installer provides a guided installation process for the PVE SMB Gateway plugin.
"@
}

# Function to check if running as administrator
function Test-Administrator {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains "S-1-5-32-544") {
        Write-Warning "Running as Administrator. This is not recommended for security reasons."
        $response = Read-Host "Continue anyway? (y/N)"
        if ($response -notmatch "^[Yy]$") {
            Write-Error "Installation cancelled."
            exit 1
        }
    }
}

# Function to check system requirements
function Test-SystemRequirements {
    Write-Status "Checking system requirements..."
    
    # Check if we're on Windows
    if ($env:OS -notlike "*Windows*") {
        Write-Error "This installer is designed for Windows systems."
        exit 1
    }
    
    # Check for Python 3
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Python 3 is required but not installed."
            Write-Status "Please install Python 3 from https://python.org"
            Write-Status "Make sure to check 'Add Python to PATH' during installation."
            exit 1
        }
        Write-Success "Python found: $pythonVersion"
    }
    catch {
        Write-Error "Python 3 is required but not installed."
        Write-Status "Please install Python 3 from https://python.org"
        exit 1
    }
    
    # Check for tkinter
    try {
        python -c "import tkinter" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Python tkinter not available."
            Write-Status "This may be included in your Python installation."
        }
        else {
            Write-Success "Python tkinter available."
        }
    }
    catch {
        Write-Warning "Could not verify tkinter availability."
    }
    
    # Check for pip
    try {
        $pipVersion = pip --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "pip is required but not installed."
            Write-Status "Please install pip or upgrade Python."
            exit 1
        }
        Write-Success "pip found: $pipVersion"
    }
    catch {
        Write-Error "pip is required but not installed."
        exit 1
    }
    
    Write-Success "System requirements check completed."
}

# Function to install Python dependencies
function Install-PythonDependencies {
    Write-Status "Installing Python dependencies..."
    
    # Create requirements file if it doesn't exist
    $requirementsFile = Join-Path $ScriptDir "requirements.txt"
    if (-not (Test-Path $requirementsFile)) {
        @"
# Python dependencies for PVE SMB Gateway Installer
# No external dependencies required for basic functionality
"@ | Out-File -FilePath $requirementsFile -Encoding UTF8
    }
    
    # Install dependencies if any
    if ((Get-Item $requirementsFile).Length -gt 0) {
        try {
            pip install -r $requirementsFile
            Write-Success "Python dependencies installed."
        }
        catch {
            Write-Warning "Failed to install Python dependencies: $_"
        }
    }
    else {
        Write-Success "No Python dependencies required."
    }
}

# Function to check if installer script exists
function Test-InstallerScript {
    if (-not (Test-Path $InstallerScript)) {
        Write-Error "Installer script not found: $InstallerScript"
        Write-Status "Please ensure you're running this from the project root directory."
        exit 1
    }
    
    Write-Success "Installer script found."
}

# Function to run installer
function Start-Installer {
    Write-Status "Starting GUI installer..."
    
    # Change to project directory
    Set-Location $ProjectRoot
    
    # Run the installer
    try {
        python $InstallerScript
    }
    catch {
        Write-Error "Failed to start installer: $_"
        exit 1
    }
}

# Function to show Windows-specific information
function Show-WindowsInfo {
    Write-Warning "This installer is designed for Linux/Proxmox systems."
    Write-Status "On Windows, this installer will help you:"
    Write-Status "1. Check system compatibility"
    Write-Status "2. Prepare for installation on a Proxmox server"
    Write-Status "3. Generate installation scripts"
    Write-Status "4. Provide documentation and guidance"
    Write-Host ""
    
    $response = Read-Host "Continue with Windows preparation mode? (Y/n)"
    if ($response -match "^[Nn]$") {
        Write-Status "Installation cancelled."
        exit 0
    }
}

# Main function
function Main {
    # Parse parameters
    if ($Help) {
        Show-Help
        exit 0
    }
    
    if ($Version) {
        Show-Version
        exit 0
    }
    
    # Show header
    Write-Header
    
    # Show Windows-specific information
    Show-WindowsInfo
    
    # Check if running as administrator (unless disabled)
    if (-not $NoRootCheck) {
        Test-Administrator
    }
    
    # Check installer script
    Test-InstallerScript
    
    # Check system requirements
    Test-SystemRequirements
    
    # Install Python dependencies
    Install-PythonDependencies
    
    # If only checking or installing deps, exit here
    if ($CheckOnly) {
        Write-Success "System check completed successfully."
        exit 0
    }
    
    if ($InstallDeps) {
        Write-Success "Dependencies installed successfully."
        exit 0
    }
    
    # Run the installer
    Start-Installer
}

# Run main function
Main 