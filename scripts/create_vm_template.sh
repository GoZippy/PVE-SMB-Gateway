#!/bin/bash

# PVE SMB Gateway VM Template Creation Script
# Creates a minimal Debian VM template with Samba pre-installed

set -e

# Configuration
TEMPLATE_NAME=${1:-"smb-gateway-debian12"}
MEMORY=${2:-2048}
DISK_SIZE=${3:-"20G"}
PACKAGES=${4:-"samba,winbind,cloud-init"}

echo "Creating SMB Gateway VM template: $TEMPLATE_NAME"

# Check prerequisites
if ! command -v qemu-img &> /dev/null; then
    echo "Error: qemu-img not found. Install qemu-utils package."
    exit 1
fi

if ! command -v debootstrap &> /dev/null; then
    echo "Error: debootstrap not found. Install debootstrap package."
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Download Debian cloud image
echo "Downloading Debian 12 cloud image..."
wget -O "$TEMP_DIR/debian-12-generic-amd64.qcow2" \
    "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"

# Create template directory
TEMPLATE_DIR="/var/lib/vz/template/iso"
mkdir -p "$TEMPLATE_DIR"

# Copy and customize the image
echo "Customizing VM template..."
cp "$TEMP_DIR/debian-12-generic-amd64.qcow2" "$TEMPLATE_DIR/$TEMPLATE_NAME.qcow2"

# Create cloud-init configuration
cat > "$TEMP_DIR/user-data" << 'EOF'
#cloud-config
package_update: true
package_upgrade: true

packages:
  - samba
  - winbind
  - acl
  - attr

runcmd:
  - systemctl enable smbd
  - systemctl enable nmbd
  - systemctl enable winbind
  - mkdir -p /etc/samba/smb.conf.d
  - echo "workgroup = WORKGROUP" > /etc/samba/smb.conf.d/global.conf
  - echo "server string = SMB Gateway" >> /etc/samba/smb.conf.d/global.conf
  - echo "security = user" >> /etc/samba/smb.conf.d/global.conf
  - echo "map to guest = bad user" >> /etc/samba/smb.conf.d/global.conf
  - echo "dns proxy = no" >> /etc/samba/smb.conf.d/global.conf
  - echo "log level = 1" >> /etc/samba/smb.conf.d/global.conf

ssh_pwauth: false
disable_root: false
EOF

cat > "$TEMP_DIR/meta-data" << 'EOF'
instance-id: smb-gateway-template
local-hostname: smb-gateway
EOF

# Create cloud-init ISO
echo "Creating cloud-init configuration..."
genisoimage -output "$TEMPLATE_DIR/$TEMPLATE_NAME-cloud-init.iso" \
    -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data"

# Create VM configuration file
cat > "$TEMPLATE_DIR/$TEMPLATE_NAME.conf" << EOF
# SMB Gateway VM Template Configuration
name: $TEMPLATE_NAME
ostype: l26
memory: $MEMORY
cores: 2
sockets: 1
cpu: host
net0: virtio,bridge=vmbr0
scsi0: local:iso/$TEMPLATE_NAME.qcow2,size=20G
ide2: local:iso/$TEMPLATE_NAME-cloud-init.iso,media=cdrom
boot: order=scsi0;ide2
scsihw: virtio-scsi-pci
agent: 1
onboot: 0
template: 1
EOF

echo "Template created successfully!"
echo "Template files:"
echo "  - Image: $TEMPLATE_DIR/$TEMPLATE_NAME.qcow2"
echo "  - Cloud-init: $TEMPLATE_DIR/$TEMPLATE_NAME-cloud-init.iso"
echo "  - Config: $TEMPLATE_DIR/$TEMPLATE_NAME.conf"

# Clean up
rm -rf "$TEMP_DIR"

echo "SMB Gateway VM template '$TEMPLATE_NAME' is ready for use!"
echo "You can now use VM mode in the SMB Gateway plugin."