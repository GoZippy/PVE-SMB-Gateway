#!/usr/bin/env bash

set -euo pipefail

# Build script for Proxmox SMB Gateway plugin
# This script builds a .deb package from the current source

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building Proxmox SMB Gateway plugin..."

# Check if we're in the right directory
if [[ ! -f "$PROJECT_ROOT/debian/control" ]]; then
    echo "Error: debian/control not found. Are you in the project root?"
    exit 1
fi

# Check dependencies
if ! command -v dpkg-buildpackage &> /dev/null; then
    echo "Error: dpkg-buildpackage not found. Install build-essential and devscripts."
    exit 1
fi

# Clean previous builds
echo "Cleaning previous builds..."
rm -f ../pve-plugin-smbgateway_*.deb
rm -f ../pve-plugin-smbgateway_*.changes
rm -f ../pve-plugin-smbgateway_*.buildinfo
rm -f ../pve-plugin-smbgateway_*.dsc
rm -f ../pve-plugin-smbgateway_*.tar.gz

# Build the package
echo "Building package..."
cd "$PROJECT_ROOT"
dpkg-buildpackage -us -uc -b

# Check if build was successful
if [[ -f "../pve-plugin-smbgateway_*.deb" ]]; then
    echo "✅ Package built successfully!"
    echo "📦 Package location: $(ls -la ../pve-plugin-smbgateway_*.deb)"
    
    # Show package info
    echo ""
    echo "Package information:"
    dpkg-deb -I ../pve-plugin-smbgateway_*.deb | grep -E "(Package|Version|Architecture|Depends)"
    
else
    echo "❌ Package build failed!"
    exit 1
fi

echo ""
echo "To install the package:"
echo "  sudo dpkg -i ../pve-plugin-smbgateway_*.deb"
echo "  sudo systemctl restart pveproxy" 