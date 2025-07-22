# PVE SMB Gateway Plugin

A Proxmox Virtual Environment (PVE) plugin that provides a GUI-managed, lightweight way to export SMB/CIFS shares from existing Proxmox storage backends (ZFS datasets, CephFS subvolumes, or RBD images) without forcing users to maintain a full NAS VM.

**Phase 1**: SMB Gateway with LXC/Native/VM deployment modes  
**Phase 2**: Storage Service Launcher - deploy TrueNAS, MinIO, Nextcloud, and more with a single click

## Features

- **One-click share creation** via Proxmox web interface
- **Multiple deployment modes**:
  - **LXC Mode** (default): Lightweight containers with Samba
  - **Native Mode**: Direct host installation
  - **VM Mode** (planned): Dedicated VM templates
- **High Availability**: CTDB support for floating IPs
- **Active Directory integration** for enterprise environments
- **Quota management** for storage limits
- **Resource efficient** (≤80MB RAM in LXC mode)
- **CLI tools** for automation

## Quick Start

### Prerequisites

- Proxmox VE 8.x
- Debian 12 PVE hosts
- Samba packages (automatically installed)

### Installation

```bash
# Clone the repository
git clone https://github.com/ZippyNetworks/pve-smb-gateway.git
cd pve-smb-gateway

# Build and install
./scripts/build_package.sh
sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb
sudo systemctl restart pveproxy
```

### Usage

1. **Web Interface**: Navigate to Datacenter → Storage → Add → SMB Gateway
2. **CLI**: Use `pve-smbgateway` command for automation

```bash
# List all shares
pve-smbgateway list

# Create a new share
pve-smbgateway create myshare --mode lxc --quota 10G

# Check share status
pve-smbgateway status myshare

# Delete a share
pve-smbgateway delete myshare
```

## Development

### Setup Development Environment

```bash
# Install dependencies
make dev-setup

# Run tests
make test

# Build package
make deb

# Install plugin
make install
```

### Project Structure

```
pve-smb-gateway/
├── PVE/Storage/Custom/SMBGateway.pm  # Main Perl plugin
├── www/ext6/pvemanager6/smb-gateway.js  # ExtJS wizard
├── scripts/
│   ├── build_package.sh              # Build script
│   └── lxc_setup.sh                  # LXC helper
├── sbin/pve-smbgateway               # CLI tool
├── t/                                # Unit tests
├── debian/                           # Package configuration
└── docs/                             # Documentation
```

### Architecture

```
ExtJS Wizard → REST API → Perl Storage Plugin → Provisioners → Samba Service → Network Clients
```

- **Control Plane**: Web wizard → REST API → Perl plugin
- **Data Plane**: ZFS/Ceph → mount/bind → Samba → network

## Configuration Examples

### Basic LXC Share

```bash
# Add to /etc/pve/storage.cfg
storage: myshare
	type smbgateway
	sharename myshare
	mode lxc
	path /srv/smb/myshare
	quota 10G
```

### Native Mode with AD

```bash
storage: officeshare
	type smbgateway
	sharename officeshare
	mode native
	path /srv/smb/office
	quota 100G
	ad_domain example.com
```

### HA Setup with CTDB

```bash
storage: hashare
	type smbgateway
	sharename hashare
	mode lxc
	path /srv/smb/ha
	quota 50G
	ctdb_vip 192.168.1.100
```

## Testing

### Unit Tests

```bash
# Run all tests
make test

# Run specific test
perl t/00-load.t
perl t/10-create-share.t
```

### Manual Testing

1. Create a share via web interface
2. Verify LXC container is created and running
3. Test SMB connectivity from client
4. Verify quota enforcement
5. Test AD integration (if configured)

## Troubleshooting

### Common Issues

1. **Template not found**: Download a Debian/Ubuntu template
2. **Permission denied**: Check LXC container permissions
3. **SMB not accessible**: Verify firewall and network configuration
4. **AD join fails**: Check domain credentials and DNS

### Logs

- **Plugin logs**: `/var/log/pveproxy/access.log`
- **LXC logs**: `pct logs <ctid>`
- **Samba logs**: Inside LXC container or `/var/log/samba/`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

### Contributor License Agreement

By contributing to this project, you agree that your contributions will be dual-licensed under both the AGPL-3.0 and our commercial license. See [CONTRIBUTOR_LICENSE_AGREEMENT.md](CONTRIBUTOR_LICENSE_AGREEMENT.md) for details.

**Quick sign-off**: Include `Signed-off-by: Your Name <your.email@example.com>` in your commit messages to indicate agreement with the DCO.

### Coding Standards

- **Perl**: Follow `perltidy -q -i=4`
- **JavaScript**: ESLint (Airbnb) via `npm run lint`
- **Commit prefix**: `[core]`, `[ui]`, `[docs]`, `[ci]`, `[tests]`

## Roadmap

### Phase 1: SMB Gateway (v0.1.0 - v1.0.0)
- [x] Basic LXC and native mode support
- [x] ExtJS wizard integration
- [x] CLI tools
- [ ] VM mode implementation
- [ ] Advanced HA features
- [ ] Performance monitoring
- [ ] Backup integration

### Phase 2: Storage Service Launcher (v1.1.0+)
- [ ] **App Store Interface**: GUI for deploying TrueNAS, MinIO, Nextcloud, and more
- [ ] **Template System**: YAML-based service definitions for easy community contributions
- [ ] **Pluggable Backends**: Support for ZFS, CephFS, Gluster, Longhorn
- [ ] **HA Profiles**: Automated high-availability deployment
- [ ] **Secrets Management**: Secure credential injection via PVE or HashiCorp Vault
- [ ] **Resource Planning**: Pre-flight resource impact analysis
- [ ] **Rollback & Uninstall**: Safe deployment with automatic cleanup

*See [docs/ROADMAP.md](docs/ROADMAP.md) for detailed timeline and technical specifications.*

## License

This project is dual-licensed:

- **Community Edition**: GNU Affero General Public License v3.0 (AGPL-3.0) - see the [LICENSE](LICENSE) file for details
- **Commercial Edition**: Commercial license for commercial distribution and OEM bundling - see [docs/COMMERCIAL_LICENSE.md](docs/COMMERCIAL_LICENSE.md) for details

### When do you need a Commercial License?

- **Community Edition (AGPL-3.0)**: Perfect for personal use, homelabs, educational institutions, and non-commercial deployments
- **Commercial License**: Required for commercial distribution, OEM bundling, or when you want to avoid AGPL-3.0 copyleft obligations

For commercial licensing inquiries, contact: eric@gozippy.com

## Support

- **Maintainer**: Eric Henderson <eric@gozippy.com>
- **Issues**: [GitHub Issues](https://github.com/ZippyNetworks/pve-smb-gateway/issues)
- **Documentation**: [docs/](docs/)
- **Community**: Proxmox forum thread (coming soon)

---

[![Donate](https://img.shields.io/badge/Donate-BTC%20%7C%20ETH%20%7C%20USDT-blue)](docs/DONATE.md)
