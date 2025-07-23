#!/bin/bash
# SMB Gateway VM Template Creation Script
# This script creates a minimal Debian VM template with Samba pre-installed
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Configuration
TEMPLATE_NAME="smb-gateway-debian12.qcow2"
TEMPLATE_SIZE="5G"
TEMPLATE_DIR="/var/lib/vz/template/iso"
MOUNT_DIR="/tmp/smb-gateway-template"
LOG_FILE="/var/log/smb-gateway-template-creation.log"
DEBIAN_VERSION="bookworm"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Check for required tools
for cmd in qemu-img debootstrap kpartx losetup; do
    if ! command -v $cmd &> /dev/null; then
        echo "Required tool $cmd not found. Please install it." >&2
        exit 1
    fi
done

echo "Creating SMB Gateway VM template at $TEMPLATE_DIR/$TEMPLATE_NAME" | tee -a $LOG_FILE
echo "Logging to $LOG_FILE"

# Create template directory if it doesn't exist
mkdir -p $TEMPLATE_DIR

# Create a new disk image
echo "Creating disk image..." | tee -a $LOG_FILE
qemu-img create -f qcow2 $TEMPLATE_DIR/$TEMPLATE_NAME $TEMPLATE_SIZE >> $LOG_FILE 2>&1

# Create a temporary raw image for partitioning
TMP_RAW="/tmp/smb-gateway-raw.img"
echo "Creating temporary raw image for partitioning..." | tee -a $LOG_FILE
qemu-img create -f raw $TMP_RAW $TEMPLATE_SIZE >> $LOG_FILE 2>&1

# Create partitions
echo "Creating partitions..." | tee -a $LOG_FILE
parted $TMP_RAW --script mklabel msdos >> $LOG_FILE 2>&1
parted $TMP_RAW --script mkpart primary ext4 1MiB 100% >> $LOG_FILE 2>&1
parted $TMP_RAW --script set 1 boot on >> $LOG_FILE 2>&1

# Set up loop device
echo "Setting up loop device..." | tee -a $LOG_FILE
LOOP_DEV=$(losetup -f --show $TMP_RAW)
echo "Using loop device: $LOOP_DEV" | tee -a $LOG_FILE

# Map partitions
echo "Mapping partitions..." | tee -a $LOG_FILE
kpartx -a $LOOP_DEV >> $LOG_FILE 2>&1
PART_DEV="/dev/mapper/$(basename $LOOP_DEV)p1"
echo "Partition device: $PART_DEV" | tee -a $LOG_FILE

# Format partition
echo "Formatting partition..." | tee -a $LOG_FILE
mkfs.ext4 $PART_DEV >> $LOG_FILE 2>&1

# Mount the filesystem
echo "Mounting filesystem..." | tee -a $LOG_FILE
mkdir -p $MOUNT_DIR
mount $PART_DEV $MOUNT_DIR

# Use debootstrap to create a minimal Debian system
echo "Installing minimal Debian system..." | tee -a $LOG_FILE
debootstrap --variant=minbase $DEBIAN_VERSION $MOUNT_DIR http://deb.debian.org/debian/ >> $LOG_FILE 2>&1

# Configure system
echo "Configuring system..." | tee -a $LOG_FILE

# Set up sources.list
cat > $MOUNT_DIR/etc/apt/sources.list << EOF
deb http://deb.debian.org/debian $DEBIAN_VERSION main contrib non-free
deb http://security.debian.org/debian-security $DEBIAN_VERSION-security main contrib non-free
deb http://deb.debian.org/debian $DEBIAN_VERSION-updates main contrib non-free
EOF

# Set up fstab
cat > $MOUNT_DIR/etc/fstab << EOF
/dev/sda1 / ext4 defaults 0 1
EOF

# Set up hostname
echo "smb-gateway" > $MOUNT_DIR/etc/hostname

# Set up hosts
cat > $MOUNT_DIR/etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 smb-gateway

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Chroot and install packages
echo "Installing packages..." | tee -a $LOG_FILE
mount -t proc none $MOUNT_DIR/proc
mount -t sysfs none $MOUNT_DIR/sys
mount -o bind /dev $MOUNT_DIR/dev

cat > $MOUNT_DIR/install-packages.sh << 'EOF'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y linux-image-amd64 grub-pc samba winbind cloud-init openssh-server sudo vim
apt-get clean
EOF

chmod +x $MOUNT_DIR/install-packages.sh
chroot $MOUNT_DIR /install-packages.sh >> $LOG_FILE 2>&1

# Configure cloud-init
echo "Configuring cloud-init..." | tee -a $LOG_FILE
mkdir -p $MOUNT_DIR/etc/cloud/cloud.cfg.d/

cat > $MOUNT_DIR/etc/cloud/cloud.cfg.d/99-smb-gateway.cfg << EOF
# SMB Gateway cloud-init configuration
runcmd:
  - [ systemctl, enable, smbd ]
  - [ systemctl, enable, nmbd ]
  - [ systemctl, start, smbd ]
  - [ systemctl, start, nmbd ]
EOF

# Configure Samba
echo "Configuring Samba..." | tee -a $LOG_FILE
cat > $MOUNT_DIR/etc/samba/smb.conf << EOF
[global]
  workgroup = WORKGROUP
  server string = SMB Gateway
  security = user
  map to guest = bad user
  dns proxy = no
  log level = 1
EOF

# Install GRUB
echo "Installing GRUB..." | tee -a $LOG_FILE
chroot $MOUNT_DIR grub-install --no-floppy --modules="biosdisk part_msdos" $LOOP_DEV >> $LOG_FILE 2>&1
chroot $MOUNT_DIR update-grub >> $LOG_FILE 2>&1

# Clean up
echo "Cleaning up..." | tee -a $LOG_FILE
rm $MOUNT_DIR/install-packages.sh

# Unmount everything
umount $MOUNT_DIR/dev
umount $MOUNT_DIR/sys
umount $MOUNT_DIR/proc
umount $MOUNT_DIR

# Remove partition mappings
kpartx -d $LOOP_DEV

# Detach loop device
losetup -d $LOOP_DEV

# Convert raw image to qcow2
echo "Converting raw image to qcow2..." | tee -a $LOG_FILE
mv $TEMPLATE_DIR/$TEMPLATE_NAME $TEMPLATE_DIR/$TEMPLATE_NAME.bak
qemu-img convert -f raw -O qcow2 $TMP_RAW $TEMPLATE_DIR/$TEMPLATE_NAME >> $LOG_FILE 2>&1

# Clean up temporary files
rm $TMP_RAW
rm -f $TEMPLATE_DIR/$TEMPLATE_NAME.bak

# Register the template with Proxmox
echo "Registering template with Proxmox..." | tee -a $LOG_FILE
pvesh create /nodes/$(hostname)/storage/local/content --volume $TEMPLATE_DIR/$TEMPLATE_NAME --content iso >> $LOG_FILE 2>&1

echo "Template creation complete!" | tee -a $LOG_FILE
echo "Template available at: local:iso/$TEMPLATE_NAME" | tee -a $LOG_FILE
echo "Log file: $LOG_FILE"

exit 0