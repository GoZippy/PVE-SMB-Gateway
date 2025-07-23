# SMB Gateway VM Template Creation Guide

This document provides instructions for creating VM templates for the SMB Gateway plugin.

## Automatic Template Creation

The SMB Gateway plugin includes an automatic template creation feature that can be used to create a VM template with Samba pre-installed. This is the recommended approach for most users.

When you select VM mode in the SMB Gateway wizard, the plugin will automatically check for an existing template. If no suitable template is found, it will offer to create one for you.

The automatic template creation process requires:
- Proxmox VE 8.0 or later
- qemu-utils package
- debootstrap package
- At least 5GB of free space in the template storage

## Manual Template Creation

If you prefer to create a VM template manually, follow these steps:

### Option 1: Using the Template Creation Script

1. Ensure you have the required packages installed:
   ```bash
   apt-get install qemu-utils debootstrap kpartx
   ```

2. Run the template creation script:
   ```bash
   /usr/share/pve-smbgateway/scripts/create_vm_template.sh
   ```

3. The script will create a template at `/var/lib/vz/template/iso/smb-gateway-debian12.qcow2` and register it with Proxmox.

### Option 2: Creating a Template from an Existing VM

1. Create a new VM in Proxmox with:
   - Debian 12 or Ubuntu 22.04
   - At least 2GB RAM
   - 5GB disk space
   - VirtIO SCSI controller

2. Install the required packages:
   ```bash
   apt-get update
   apt-get install -y samba winbind cloud-init
   ```

3. Configure Samba:
   ```bash
   cat > /etc/samba/smb.conf << 'EOF'
   [global]
     workgroup = WORKGROUP
     server string = SMB Gateway
     security = user
     map to guest = bad user
     dns proxy = no
     log level = 1
   EOF
   ```

4. Configure cloud-init:
   ```bash
   cat > /etc/cloud/cloud.cfg.d/99-smb-gateway.cfg << 'EOF'
   # SMB Gateway cloud-init configuration
   runcmd:
     - [ systemctl, enable, smbd ]
     - [ systemctl, enable, nmbd ]
     - [ systemctl, start, smbd ]
     - [ systemctl, start, nmbd ]
   EOF
   ```

5. Clean up the VM:
   ```bash
   apt-get clean
   rm -rf /var/lib/apt/lists/*
   ```

6. Shut down the VM and convert it to a template:
   ```bash
   qm shutdown <vmid>
   qm template <vmid>
   ```

7. Alternatively, export the disk as a template:
   ```bash
   qm exportdisk <vmid> <storage> --format qcow2
   ```

## Template Requirements

For a VM template to be compatible with the SMB Gateway plugin, it must:

1. Be based on Debian 12 or Ubuntu 22.04 (or later)
2. Have Samba and Winbind pre-installed
3. Have cloud-init installed for automated configuration
4. Be accessible in a storage that allows ISO content

## Template Versioning

The SMB Gateway plugin looks for templates in the following order:
1. `smb-gateway-debian12.qcow2` (preferred)
2. `smb-gateway-ubuntu22.qcow2`
3. Generic Debian or Ubuntu cloud images

When creating custom templates, use the naming convention `smb-gateway-<distro><version>.qcow2` for best compatibility.

## Troubleshooting

If you encounter issues with template creation:

1. Check the log file at `/var/log/smb-gateway-template-creation.log`
2. Ensure you have sufficient disk space
3. Verify that all required packages are installed
4. Check that the template storage is writable

For additional help, please refer to the main documentation or contact support.