# Technology Stack

## Build System
- **Package Format**: Debian (.deb) packages for Proxmox VE
- **Build Tool**: `dpkg-buildpackage` with debhelper-compat (= 13)
- **Build Script**: `./scripts/build_package.sh`

## Core Technologies
- **Backend**: Perl 5 (PVE Storage Plugin API)
- **Frontend**: ExtJS 6 (Proxmox web interface integration)
- **CLI**: Perl with PVE APIClient
- **Containerization**: LXC containers for lightweight deployment
- **Storage**: ZFS datasets, CephFS subvolumes, RBD images
- **Network Service**: Samba/CIFS with optional CTDB for HA

## Dependencies
- **Runtime**: `samba`, `pve-manager (>= 8.0)`
- **Build**: `debhelper-compat (= 13)`, `perl`, `pve-manager (>= 8.0)`
- **Development**: `build-essential`, `devscripts`, `perltidy`, `perlcritic`

## Common Commands

### Development
```bash
make dev-setup          # Install development dependencies
make lint               # Run Perl and JavaScript linting
make test               # Run unit tests with prove
make deb                # Build .deb package
make clean              # Remove build artifacts
make install            # Install plugin and restart pveproxy
```

### Testing
```bash
prove -v t/             # Run all tests
perl t/00-load.t        # Run specific test
make quick-test         # Syntax check + basic functionality test
```

### Package Management
```bash
./scripts/build_package.sh                    # Build package
sudo dpkg -i ../pve-plugin-smbgateway_*.deb   # Install
sudo systemctl restart pveproxy               # Restart Proxmox web service
```

## Code Quality Tools
- **Perl**: `perltidy -q -i=4` for formatting, `perlcritic -1` for static analysis
- **JavaScript**: ESLint with Airbnb configuration
- **Testing**: Perl Test::More framework with Test::MockModule for mocking