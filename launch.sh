#!/bin/bash

# PVE SMB Gateway - Easy Launcher
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
    echo -e "${PURPLE}  PVE SMB Gateway Launcher${NC}"
    echo -e "${PURPLE}================================${NC}"
    echo
}

# Function to show menu
show_menu() {
    cat << EOF
Available Options:

${CYAN}1.${NC} Install PVE SMB Gateway (GUI Installer)
${CYAN}2.${NC} Install PVE SMB Gateway (Quick Install)
${CYAN}3.${NC} Validate All Modes (Comprehensive Testing)
${CYAN}4.${NC} Test LXC Mode Only
${CYAN}5.${NC} Test Native Mode Only
${CYAN}6.${NC} Test VM Mode Only
${CYAN}7.${NC} Build Package
${CYAN}8.${NC} Show Documentation
${CYAN}9.${NC} Show Help
${CYAN}0.${NC} Exit

EOF
}

# Function to install via GUI
install_gui() {
    print_status "Starting GUI installer..."
    
    if [[ -f "$SCRIPT_DIR/installer/run-installer.sh" ]]; then
        "$SCRIPT_DIR/installer/run-installer.sh"
    else
        print_error "GUI installer not found"
        print_status "Please ensure you're running from the project root directory"
        exit 1
    fi
}

# Function to quick install
install_quick() {
    print_status "Starting quick installation..."
    
    # Check if we're on Proxmox
    if [[ ! -f "/etc/pve/version" ]]; then
        print_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    # Check if package exists
    local package_file="pve-plugin-smbgateway_*.deb"
    if ! ls $package_file 1> /dev/null 2>&1; then
        print_status "Package not found, building..."
        make deb
    fi
    
    # Install package
    local package=$(ls $package_file | head -1)
    print_status "Installing $package..."
    
    if dpkg -i "$package"; then
        print_success "Package installed successfully"
    else
        print_error "Package installation failed"
        print_status "Attempting to fix dependencies..."
        apt-get install -f -y
        if dpkg -i "$package"; then
            print_success "Package installed successfully after dependency fix"
        else
            print_error "Package installation failed even after dependency fix"
            exit 1
        fi
    fi
    
    # Restart pveproxy
    print_status "Restarting Proxmox web interface..."
    if systemctl restart pveproxy; then
        print_success "Proxmox web interface restarted"
    else
        print_error "Failed to restart Proxmox web interface"
        exit 1
    fi
    
    # Verify installation
    print_status "Verifying installation..."
    if [[ -f "/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm" ]]; then
        print_success "Plugin files installed"
    else
        print_error "Plugin files not found"
        exit 1
    fi
    
    if command -v pve-smbgateway &> /dev/null; then
        print_success "CLI tool installed"
    else
        print_error "CLI tool not found"
        exit 1
    fi
    
    print_success "Installation completed successfully!"
    print_status "You can now access SMB Gateway in the Proxmox web interface"
    print_status "Navigate to: Datacenter → Storage → Add → SMB Gateway"
}

# Function to validate all modes
validate_all() {
    print_status "Running comprehensive validation..."
    
    if [[ -f "$SCRIPT_DIR/scripts/validate_all_modes.sh" ]]; then
        "$SCRIPT_DIR/scripts/validate_all_modes.sh"
    else
        print_error "Validation script not found"
        exit 1
    fi
}

# Function to test specific mode
test_mode() {
    local mode="$1"
    print_status "Testing $mode mode..."
    
    local test_share="test-$mode-validation"
    local test_path="/tmp/test-$mode-validation"
    
    # Clean up any existing test share
    pve-smbgateway delete "$test_share" 2>/dev/null || true
    rm -rf "$test_path" 2>/dev/null || true
    
    # Create test directory
    mkdir -p "$test_path"
    
    # Create share
    if pve-smbgateway create "$test_share" --mode "$mode" --path "$test_path" --quota 1G 2>/dev/null; then
        print_success "$mode mode share created successfully"
        
        # Test status
        if pve-smbgateway status "$test_share" >/dev/null 2>&1; then
            print_success "$mode mode status accessible"
        else
            print_error "$mode mode status failed"
        fi
        
        # Cleanup
        pve-smbgateway delete "$test_share" 2>/dev/null || true
        rm -rf "$test_path" 2>/dev/null || true
        
        print_success "$mode mode test completed successfully"
    else
        print_error "$mode mode test failed"
        exit 1
    fi
}

# Function to build package
build_package() {
    print_status "Building package..."
    
    if [[ -f "$SCRIPT_DIR/Makefile" ]]; then
        make -C "$SCRIPT_DIR" deb
        print_success "Package built successfully"
        
        # Show package info
        local package=$(ls ../pve-plugin-smbgateway_*.deb 2>/dev/null | head -1)
        if [[ -n "$package" ]]; then
            print_status "Package created: $package"
            ls -la "$package"
        fi
    else
        print_error "Makefile not found"
        exit 1
    fi
}

# Function to show documentation
show_documentation() {
    cat << EOF
${CYAN}PVE SMB Gateway Documentation${NC}

${GREEN}Quick Start:${NC}
1. Install the plugin: ./launch.sh (option 1 or 2)
2. Create a share: Navigate to Datacenter → Storage → Add → SMB Gateway
3. Access your share: \\\\your-proxmox-ip\\sharename

${GREEN}Deployment Modes:${NC}
- ${YELLOW}LXC Mode${NC}: Lightweight containers (~80MB RAM) - Recommended
- ${YELLOW}Native Mode${NC}: Direct host installation - Best performance
- ${YELLOW}VM Mode${NC}: Dedicated VMs - Maximum isolation

${GREEN}CLI Usage:${NC}
- List shares: pve-smbgateway list
- Create share: pve-smbgateway create myshare --mode lxc --path /srv/smb/myshare
- Check status: pve-smbgateway status myshare
- Delete share: pve-smbgateway delete myshare

${GREEN}Documentation Files:${NC}
- README.md - Main documentation
- docs/USER_GUIDE.md - Complete user guide
- docs/DEV_GUIDE.md - Developer guide
- docs/INSTALLER_GUIDE.md - Installer documentation
- ALPHA_RELEASE_NOTES.md - Release notes

${GREEN}Support:${NC}
- GitHub: https://github.com/GoZippy/PVE-SMB-Gateway
- Issues: https://github.com/GoZippy/PVE-SMB-Gateway/issues
- Email: eric@gozippy.com

EOF
}

# Function to show help
show_help() {
    cat << EOF
${CYAN}PVE SMB Gateway Launcher - Help${NC}

${GREEN}Usage:${NC}
    ./launch.sh [OPTION]

${GREEN}Options:${NC}
    ${YELLOW}1${NC} - Install via GUI installer (recommended)
    ${YELLOW}2${NC} - Quick install (command line)
    ${YELLOW}3${NC} - Validate all deployment modes
    ${YELLOW}4${NC} - Test LXC mode only
    ${YELLOW}5${NC} - Test Native mode only
    ${YELLOW}6${NC} - Test VM mode only
    ${YELLOW}7${NC} - Build Debian package
    ${YELLOW}8${NC} - Show documentation
    ${YELLOW}9${NC} - Show this help
    ${YELLOW}0${NC} - Exit

${GREEN}Examples:${NC}
    ./launch.sh 1          # Install via GUI
    ./launch.sh 2          # Quick install
    ./launch.sh 3          # Run all tests
    ./launch.sh 4          # Test LXC mode

${GREEN}Requirements:${NC}
    - Proxmox VE 8.x
    - Root or sudo access
    - Internet connection (for dependencies)

${GREEN}Note:${NC}
    This is alpha software. Test thoroughly before production use.
    See ALPHA_RELEASE_NOTES.md for important warnings.

EOF
}

# Main function
main() {
    print_header
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "$SCRIPT_DIR/README.md" ]]; then
        print_error "README.md not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Parse command line arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            1)
                install_gui
                ;;
            2)
                install_quick
                ;;
            3)
                validate_all
                ;;
            4)
                test_mode "lxc"
                ;;
            5)
                test_mode "native"
                ;;
            6)
                test_mode "vm"
                ;;
            7)
                build_package
                ;;
            8)
                show_documentation
                ;;
            9)
                show_help
                ;;
            0)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option: $1"
                show_help
                exit 1
                ;;
        esac
    else
        # Interactive mode
        while true; do
            show_menu
            read -p "Enter your choice (0-9): " choice
            
            case "$choice" in
                1)
                    install_gui
                    break
                    ;;
                2)
                    install_quick
                    break
                    ;;
                3)
                    validate_all
                    break
                    ;;
                4)
                    test_mode "lxc"
                    break
                    ;;
                5)
                    test_mode "native"
                    break
                    ;;
                6)
                    test_mode "vm"
                    break
                    ;;
                7)
                    build_package
                    break
                    ;;
                8)
                    show_documentation
                    break
                    ;;
                9)
                    show_help
                    ;;
                0)
                    print_status "Exiting..."
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice. Please enter a number between 0 and 9."
                    ;;
            esac
        done
    fi
}

# Run main function
main "$@" 