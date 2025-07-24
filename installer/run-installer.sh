#!/bin/bash

# PVE SMB Gateway - GUI Installer Launcher
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

# Installer script
INSTALLER_SCRIPT="$SCRIPT_DIR/pve-smbgateway-installer.py"

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
    echo -e "${PURPLE}  PVE SMB Gateway Installer${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled."
            exit 1
        fi
    fi
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check if we're on a supported system
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine operating system."
        exit 1
    fi
    
    # Check for Debian/Ubuntu
    if ! grep -qi "debian\|ubuntu" /etc/os-release; then
        print_warning "This installer is designed for Debian/Ubuntu systems."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled."
            exit 1
        fi
    fi
    
    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed."
        print_status "Installing Python 3..."
        sudo apt update
        sudo apt install -y python3 python3-pip
    fi
    
    # Check for tkinter
    if ! python3 -c "import tkinter" 2>/dev/null; then
        print_status "Installing Python tkinter..."
        sudo apt update
        sudo apt install -y python3-tk
    fi
    
    # Check for pip
    if ! command -v pip3 &> /dev/null; then
        print_status "Installing pip3..."
        sudo apt install -y python3-pip
    fi
    
    print_success "System requirements check completed."
}

# Function to install Python dependencies
install_python_deps() {
    print_status "Installing Python dependencies..."
    
    # Create requirements file if it doesn't exist
    if [[ ! -f "$SCRIPT_DIR/requirements.txt" ]]; then
        cat > "$SCRIPT_DIR/requirements.txt" << EOF
# Python dependencies for PVE SMB Gateway Installer
# No external dependencies required for basic functionality
EOF
    fi
    
    # Install dependencies if any
    if [[ -s "$SCRIPT_DIR/requirements.txt" ]]; then
        pip3 install -r "$SCRIPT_DIR/requirements.txt"
    fi
    
    print_success "Python dependencies installed."
}

# Function to check if installer script exists
check_installer() {
    if [[ ! -f "$INSTALLER_SCRIPT" ]]; then
        print_error "Installer script not found: $INSTALLER_SCRIPT"
        print_status "Please ensure you're running this from the project root directory."
        exit 1
    fi
    
    # Make installer executable
    chmod +x "$INSTALLER_SCRIPT"
}

# Function to show help
show_help() {
    cat << EOF
PVE SMB Gateway - GUI Installer

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --version       Show version information
    -c, --check-only    Only check system requirements
    -i, --install-deps  Install dependencies only
    --no-root-check     Skip root user check
    --verbose           Enable verbose output

Examples:
    $0                    # Run the GUI installer
    $0 --check-only       # Only check system requirements
    $0 --install-deps     # Install dependencies only

The installer will:
1. Check system compatibility
2. Install required dependencies
3. Build the SMB Gateway package
4. Install the plugin into Proxmox
5. Configure services and settings
6. Test the installation

For more information, visit: https://github.com/GoZippy/PVE-SMB-Gateway
EOF
}

# Function to show version
show_version() {
    cat << EOF
PVE SMB Gateway Installer v1.0.0
Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
Dual-licensed under AGPL-3.0 and Commercial License

This installer provides a guided installation process for the PVE SMB Gateway plugin.
EOF
}

# Function to run installer
run_installer() {
    print_status "Starting GUI installer..."
    
    # Change to project directory
    cd "$PROJECT_ROOT"
    
    # Run the installer
    python3 "$INSTALLER_SCRIPT"
}

# Main function
main() {
    local check_only=false
    local install_deps_only=false
    local no_root_check=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--check-only)
                check_only=true
                shift
                ;;
            -i|--install-deps)
                install_deps_only=true
                shift
                ;;
            --no-root-check)
                no_root_check=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Enable verbose output if requested
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    # Show header
    print_header
    
    # Check if running as root (unless disabled)
    if [[ "$no_root_check" == false ]]; then
        check_root
    fi
    
    # Check installer script
    check_installer
    
    # Check system requirements
    check_requirements
    
    # Install Python dependencies
    install_python_deps
    
    # If only checking or installing deps, exit here
    if [[ "$check_only" == true ]]; then
        print_success "System check completed successfully."
        exit 0
    fi
    
    if [[ "$install_deps_only" == true ]]; then
        print_success "Dependencies installed successfully."
        exit 0
    fi
    
    # Run the installer
    run_installer
}

# Run main function
main "$@" 