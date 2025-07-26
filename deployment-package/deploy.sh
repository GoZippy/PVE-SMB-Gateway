#!/bin/bash
# PVE SMB Gateway Deployment Script
# Auto-generated deployment script

set -e

echo "=== PVE SMB Gateway Deployment ==="
echo "Started at: \07/25/2025 22:01:34"
echo ""

# Check if running on Proxmox
if [ ! -f "/etc/pve/version" ]; then
    echo "ERROR: Not running on Proxmox VE"
    exit 1
fi

echo "âœ“ Running on Proxmox VE"

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
