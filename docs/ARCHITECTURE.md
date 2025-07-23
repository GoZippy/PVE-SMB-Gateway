# Architecture Overview

```mermaid
flowchart LR
    A[ExtJS Wizard] -->|REST| B(API2 :: SMBGateway)
    B -->|Perl call| C[Storage Plugin :: SMBGateway.pm]
    C -- mode=lxc --> D[LXC Provisioner]
    C -- mode=native --> E[Host Provisioner]
    C -- mode=vm --> F[VM Provisioner]
    D & E & F --> G[Backing Storage]
    F -->|Cloud-init| F1[VM Template]
    G -->|ZFS dataset<br/>CephFS subvolume<br/>RBD map| H(Samba Service)
    H --> I[CTDB VIP (optional)]
    I --> J[Windows / macOS Clients]
    
    C --> K[Quota Monitor]
    K -->|ZFS quotas| L[ZFS Commands]
    K -->|XFS project quotas| M[xfs_quota]
    K -->|User quotas| N[quota tools]
    K --> O[Usage History]
    O --> P[Trend Analysis]
```

## Control and Data Planes

**Control Plane**: ExtJS wizard → REST API → Perl plugin → provisioners
**Data Plane**: Storage backend → mount/bind → Samba → network clients

## Deployment Modes

### LXC Mode (Default)
- Lightweight containers (≤128MB RAM)
- Bind-mount host storage into container
- Isolated Samba service per share
- Fast provisioning and cleanup

### Native Mode
- Direct host Samba installation
- Shared smb.conf with multiple shares
- Lower resource overhead
- Requires careful configuration management

### VM Mode (Beta)
- Dedicated VMs with cloud-init
- Full isolation and security
- Custom resource allocation
- Template-based deployment

## High Availability

CTDB clustering provides:
- Virtual IP (VIP) failover
- Shared storage coordination
- Client connection migration
- Split-brain prevention

## Quota Monitoring System

The plugin includes comprehensive quota monitoring with support for multiple filesystem types:

### Supported Quota Systems
- **ZFS**: Native ZFS quotas using `zfs get quota,used`
- **XFS**: Project quotas using `xfs_quota` with `/etc/projects` mapping
- **Other filesystems**: User quotas using standard `quota` tools

### Monitoring Features
- Real-time usage tracking with percentage calculations
- Historical data storage in `/etc/pve/smbgateway/history/`
- Trend analysis showing usage patterns over 24-hour periods
- Automatic cleanup of old history data (keeps last 100 entries)
- Warning levels at 75%, 85%, and 95% usage

### Data Storage
```
/etc/pve/smbgateway/quotas/     # Quota configuration metadata
/etc/pve/smbgateway/history/    # Usage history for trend analysis
```

## Key Files

```
/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm  # Main plugin
/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js  # Web UI
/usr/sbin/pve-smbgateway  # CLI tool
/usr/share/pve-smbgateway/scripts/  # Helper scripts
```