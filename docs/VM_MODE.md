# VM Mode Documentation

VM Mode provides dedicated virtual machines for SMB shares, offering the highest level of isolation and security. This mode is currently in beta.

## Features

- **Full Isolation**: Each share runs in its own VM
- **Custom Resources**: Configurable CPU, memory, and storage
- **Cloud-init**: Automated VM configuration
- **Template-based**: Uses pre-built VM templates with Samba

## Configuration

### Basic VM Share

```bash
storage: vmshare
    type smbgateway
    sharename vmshare
    mode vm
    path /srv/smb/data
    quota 50G
    vm_memory 2048    # 2GB RAM (default)
    vm_cores 2        # 2 CPU cores (default)
```

### Advanced VM Configuration

```bash
storage: enterprise-vm
    type smbgateway
    sharename enterprise
    mode vm
    path /srv/smb/enterprise
    quota 500G
    vm_memory 8192    # 8GB RAM
    vm_cores 4        # 4 CPU cores
    vm_template local:vztmpl/smb-gateway-debian12.qcow2
    ad_domain company.local
    ad_join 1
    ctdb_vip 192.168.1.200
    ha_enabled 1
```

## VM Templates

### Automatic Template Creation

If no suitable template is found, the plugin will attempt to create one automatically:

1. Downloads minimal Debian 12 cloud image
2. Installs Samba and required packages
3. Configures cloud-init for automated setup
4. Stores template for future use

### Manual Template Creation

Use the provided script to create custom templates:

```bash
# Create VM template with specific configuration
./scripts/create_vm_template.sh \
    --template-name smb-gateway-custom \
    --memory 4096 \
    --disk-size 20G \
    --packages "samba,ctdb,winbind"
```

### Template Requirements

VM templates must include:
- Samba server packages
- Cloud-init support
- SSH access for management
- Basic networking configuration

## Storage Attachment

VM mode supports multiple storage attachment methods:

### VirtIO-FS (Recommended for ZFS)
- Direct filesystem sharing
- Best performance
- Requires modern guest kernel

### RBD Mapping (For Ceph)
- Native Ceph integration
- Block-level access
- Supports snapshots

### NFS Mount (Compatibility)
- Works with any storage backend
- Network-based access
- Lower performance

## Resource Planning

### Minimum Requirements
- **Memory**: 1GB (2GB recommended)
- **CPU**: 1 core (2 cores recommended)
- **Disk**: 10GB for OS + share data
- **Network**: 1 virtual NIC

### Performance Considerations
- More memory improves caching
- Additional CPU cores help with encryption
- Fast storage improves I/O performance
- Dedicated network improves throughput

## Troubleshooting

### Common Issues

**VM fails to start**
- Check available resources on host
- Verify template exists and is valid
- Check VM configuration in Proxmox

**Storage not accessible**
- Verify storage attachment method
- Check mount points inside VM
- Validate permissions

**Poor performance**
- Increase VM memory allocation
- Use VirtIO-FS for ZFS storage
- Enable hardware acceleration

### Debugging

```bash
# Check VM status
qm status <vmid>

# View VM logs
qm monitor <vmid>

# Access VM console
qm terminal <vmid>

# Check storage attachment
qm config <vmid>
```

## Migration from LXC/Native

To migrate existing shares to VM mode:

1. **Backup data** from existing share
2. **Create new VM share** with same configuration
3. **Copy data** to new share location
4. **Update client connections** to new share
5. **Remove old share** after verification

## Security Considerations

- VMs provide better isolation than containers
- Use dedicated VLANs for SMB traffic
- Enable VM firewall rules
- Regular security updates via cloud-init
- Consider encrypted storage for sensitive data

## Performance Benchmarks

Typical performance compared to native mode:
- **Throughput**: 85-95% of native performance
- **Latency**: +2-5ms additional latency
- **Memory**: +1-2GB overhead per share
- **CPU**: +10-20% CPU usage

## Future Enhancements

- GPU passthrough for hardware acceleration
- Container-optimized VM templates
- Automated scaling based on load
- Integration with Proxmox backup