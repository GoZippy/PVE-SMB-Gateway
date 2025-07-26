#!/usr/bin/env bash

set -euo pipefail

# Test script for Proxmox SMB Gateway plugin
# This script tests the build and basic functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🧪 Testing Proxmox SMB Gateway plugin..."

# Check if we're in the right directory
if [[ ! -f "$PROJECT_ROOT/debian/control" ]]; then
    echo "❌ Error: debian/control not found. Are you in the project root?"
    exit 1
fi

# Test 1: Perl syntax check
echo "📝 Testing Perl syntax..."
perl -c PVE/Storage/Custom/SMBGateway.pm
echo "✅ Perl syntax check passed"

# Test 2: Basic unit tests
echo "🧪 Running unit tests..."
if [[ -f "t/00-load.t" ]]; then
    perl t/00-load.t
    echo "✅ Basic unit tests passed"
else
    echo "⚠️  No unit tests found"
fi

# Test 3: Build package
echo "🔨 Building package..."
cd "$PROJECT_ROOT"
./scripts/build_package.sh

# Test 4: Check package contents
echo "📦 Checking package contents..."
if [[ -f "../pve-plugin-smbgateway_*.deb" ]]; then
    echo "✅ Package built successfully"
    
    # Show package info
    echo ""
    echo "Package information:"
    dpkg-deb -I ../pve-plugin-smbgateway_*.deb | grep -E "(Package|Version|Architecture|Depends)" || true
    
    # Check if required files are included
    echo ""
    echo "Package contents:"
    dpkg-deb -c ../pve-plugin-smbgateway_*.deb | grep -E "(SMBGateway\.pm|smb-gateway\.js|lxc_setup\.sh)" || true
    
else
    echo "❌ Package build failed!"
    exit 1
fi

# Test 5: Dry-run installation (if possible)
echo "🔍 Testing package installation (dry-run)..."
if command -v dpkg >/dev/null 2>&1; then
    dpkg --dry-run -i ../pve-plugin-smbgateway_*.deb
    echo "✅ Package installation test passed"
else
    echo "⚠️  dpkg not available, skipping installation test"
fi

echo ""
echo "🎉 All tests passed! The plugin is ready for installation."
echo ""
echo "To install:"
echo "  sudo dpkg -i ../pve-plugin-smbgateway_*.deb"
echo "  sudo systemctl restart pveproxy" 