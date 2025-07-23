# Developer Guide

## Quick Start

```bash
git clone https://github.com/ZippyNetworks/proxmox-smb-gateway.git
cd proxmox-smb-gateway
./scripts/build_package.sh   # builds .deb
sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb
systemctl restart pveproxy
```

## Coding Standards

- **Perl**: Follow `perltidy -q -i=4`
- **JavaScript**: ESLint (Airbnb) via `npm run lint`
- **Commit prefix**: `[core]`, `[ui]`, `[docs]`, `[ci]`, `[tests]`

## Useful Make Targets

| Target | Action |
|--------|--------|
| `make lint` | Lint Perl & JavaScript |
| `make deb` | Build .deb into `../` |
| `make clean` | Remove `debian/tmp` and build artifacts |
| `make test` | Run unit tests |
| `make install` | Install plugin and restart pveproxy |

## Development Testing

### VM Mode Testing

VM mode requires additional setup for testing:

```bash
# Create test VM template
./scripts/create_vm_template.sh --template-name test-smb-gateway

# Test VM provisioning
perl -I. t/20-vm-template.t
perl -I. t/30-vm-provisioning.t

# Manual VM share creation
pve-smbgateway create testvm --mode vm --vm-memory 1024 --vm-cores 1
```

### Testing Different Modes

```bash
# Test LXC mode (default)
pve-smbgateway create test-lxc --mode lxc --quota 1G

# Test native mode
pve-smbgateway create test-native --mode native --quota 1G

# Test VM mode
pve-smbgateway create test-vm --mode vm --vm-memory 2048 --quota 1G

# Clean up
pve-smbgateway delete test-lxc
pve-smbgateway delete test-native  
pve-smbgateway delete test-vm
```

### Testing Quota Functionality

```bash
# Test quota monitoring on different filesystem types
# ZFS (if available)
zfs create tank/test-quota
zfs set quota=1G tank/test-quota
pve-smbgateway create test-zfs --path /tank/test-quota --quota 1G

# XFS with project quotas (if available)
# Requires XFS filesystem with project quotas enabled
pve-smbgateway create test-xfs --path /mnt/xfs/test --quota 1G

# Test quota status and trends
pve-smbgateway status test-zfs  # Should show quota usage and trend data

# Generate some usage for trend testing
dd if=/dev/zero of=/tank/test-quota/testfile bs=1M count=100
sleep 60  # Wait for history update
pve-smbgateway status test-zfs  # Should show updated usage and trend
```

### Quota System Requirements

For development and testing, ensure the following tools are available:

```bash
# ZFS quota support
which zfs

# XFS quota support  
which xfs_quota
# Ensure XFS filesystem has project quotas enabled:
# mount -o prjquota /dev/device /mount/point

# Standard quota support
which quota
which setquota
```

## Release Flow

1. Tag `vX.Y.Z` in Git
2. GitHub Actions builds .deb and attaches to release
3. Publish checksum and changelog in `debian/changelog`
4. Announce on Proxmox forum thread

---

*Add (or modify) any sections as the project evolves—these docs give you a complete baseline for specs, timeline, architecture, testing, and developer onboarding.*