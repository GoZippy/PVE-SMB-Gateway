# Project Structure

## Root Directory Layout
```
pve-smb-gateway/
├── PVE/Storage/Custom/SMBGateway.pm  # Main Perl storage plugin
├── www/ext6/pvemanager6/smb-gateway.js  # ExtJS wizard UI
├── sbin/pve-smbgateway               # CLI tool
├── scripts/                          # Build and setup scripts
├── t/                                # Unit tests
├── debian/                           # Debian package configuration
├── docs/                             # Documentation
├── templates/                        # Configuration templates
└── examples/                         # Usage examples
```

## Key Components

### Core Plugin Files
- **`PVE/Storage/Custom/SMBGateway.pm`**: Main storage plugin implementing PVE::Storage::Plugin interface
- **`www/ext6/pvemanager6/smb-gateway.js`**: ExtJS frontend wizard for share creation
- **`sbin/pve-smbgateway`**: Command-line interface using PVE APIClient

### Build System
- **`debian/`**: Package metadata, dependencies, and installation rules
- **`scripts/build_package.sh`**: Main build script using dpkg-buildpackage
- **`scripts/lxc_setup.sh`**: LXC container provisioning helper
- **`Makefile`**: Development targets for linting, testing, and building

### Testing
- **`t/00-load.t`**: Module loading and basic functionality tests
- **`t/10-create-share.t`**: Share creation workflow tests
- Uses Test::More framework with Test::MockModule for mocking PVE APIs

### Documentation
- **`docs/ARCHITECTURE.md`**: System architecture and data flow
- **`docs/DEV_GUIDE.md`**: Developer setup and coding standards
- **`docs/PRD.md`**: Product requirements and specifications
- **`README.md`**: Main project documentation with quick start

## File Organization Patterns

### Perl Code Structure
- Follow PVE plugin conventions with `PVE::Storage::Plugin` base class
- Use `PVE::Tools::run_command` for system operations
- Implement required methods: `type()`, `plugindata()`, `properties()`
- Separate provisioning logic by deployment mode (native/lxc/vm)

### JavaScript UI Structure
- ExtJS components extending `PVE.panel.InputPanel`
- Form validation with regex patterns for user input
- Localized strings using `gettext()` function
- Store configurations for dropdown selections

### Commit Conventions
Use prefixes in commit messages:
- `[core]`: Backend Perl plugin changes
- `[ui]`: Frontend ExtJS changes  
- `[docs]`: Documentation updates
- `[ci]`: Build system and CI changes
- `[tests]`: Test additions or modifications

## Installation Paths
When packaged, files are installed to:
- `/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm`
- `/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js`
- `/usr/sbin/pve-smbgateway`
- `/usr/share/pve-smbgateway/` (scripts and templates)