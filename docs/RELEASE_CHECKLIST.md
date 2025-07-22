# Release Checklist - v0.1.0

## Pre-Release Testing

### ✅ Code Quality
- [ ] Perl syntax check passes
- [ ] Unit tests pass (`make test`)
- [ ] Linting passes (`make lint`)
- [ ] No critical warnings or errors

### ✅ Build Testing
- [ ] Package builds successfully (`make deb`)
- [ ] Package installs without errors (dry-run)
- [ ] All required files included in package
- [ ] Dependencies correctly specified

### ✅ Functionality Testing
- [ ] ExtJS wizard loads in Proxmox web interface
- [ ] Storage creation works (LXC mode)
- [ ] Storage creation works (Native mode)
- [ ] CLI tool functions correctly
- [ ] Error handling works as expected

## Documentation

### ✅ README
- [ ] Installation instructions clear
- [ ] Usage examples provided
- [ ] Troubleshooting section complete
- [ ] License information correct

### ✅ Developer Guide
- [ ] Build instructions clear
- [ ] Development setup documented
- [ ] Contributing guidelines included

### ✅ Examples
- [ ] Sample storage configurations provided
- [ ] CLI usage examples included

## Release Process

### ✅ Version Management
- [ ] Version bumped to 0.1.0
- [ ] Changelog updated with features
- [ ] Git tag created: `v0.1.0`

### ✅ Package Preparation
- [ ] .deb package built
- [ ] Package checksums generated
- [ ] Package tested on clean Proxmox system

### ✅ GitHub Release
- [ ] Release notes written
- [ ] .deb package attached
- [ ] Checksums included
- [ ] Known issues documented

## Post-Release

### ✅ Community
- [ ] Proxmox forum announcement posted
- [ ] GitHub repository public
- [ ] Issue templates configured
- [ ] Contributing guidelines visible

### ✅ Monitoring
- [ ] Watch for installation issues
- [ ] Monitor GitHub issues
- [ ] Respond to community feedback

## Known Limitations (v0.1.0)

- VM mode not implemented
- Advanced HA features pending
- Limited AD integration testing
- No performance benchmarks yet

## Future Roadmap

- [ ] VM mode implementation
- [ ] Enhanced HA with CTDB
- [ ] Performance monitoring
- [ ] Backup integration
- [ ] Multi-language support 