# Development Roadmap - PVE SMB Gateway

## Current Status: v0.1.0 - Solid Foundation ✅

The PVE SMB Gateway project has a strong foundation with all three deployment modes (LXC, Native, VM) implemented and functional. This roadmap outlines the next development priorities to reach v1.0.0 and beyond.

## Phase 1 Completion (v0.2.0 - v1.0.0)

### **Priority 1: VM Mode Testing & Refinement** 🔥
**Status**: Backend implemented, needs testing and refinement
**Effort**: 2-3 days
**Impact**: High - Completes core functionality

#### Tasks:
- [ ] **Test VM template creation script**
  ```bash
  # Test template creation
  sudo ./scripts/create_vm_template.sh
  # Verify template appears in Proxmox
  pvesh get /nodes/$(hostname)/storage/local/content
  ```

- [ ] **Test VM mode end-to-end**
  ```bash
  # Test VM share creation
  pve-smbgateway create testvm --mode vm --vm-memory 2048 --quota 10G
  # Verify VM is created and running
  qm status <vmid>
  # Test SMB connectivity
  smbclient //<vm-ip>/testvm -U guest
  ```

- [ ] **Run comprehensive VM tests**
  ```bash
  # Run VM mode tests
  perl t/20-vm-mode.t
  # Test template validation
  perl t/30-vm-template.t
  ```

- [ ] **Refine VM provisioning**
  - Add better error handling for template creation
  - Improve cloud-init configuration
  - Add VM resource validation
  - Enhance rollback procedures

### **Priority 2: Enhanced Quota Management** 🔥
**Status**: Basic implementation, needs enhancement
**Effort**: 3-4 days
**Impact**: High - Core feature for production use

#### Tasks:
- [ ] **Implement quota monitoring system**
  ```perl
  # Add to SMBGateway.pm
  sub _monitor_quota {
      my ($self, $path, $quota) = @_;
      # Real-time quota monitoring
      # Usage tracking and alerts
      # Trend analysis
  }
  ```

- [ ] **Add quota validation and enforcement**
  - Validate quota format and limits
  - Implement quota enforcement for different filesystems
  - Add quota cleanup on share deletion

- [ ] **Create quota reporting API**
  ```bash
  # Add to CLI
  pve-smbgateway quota-status myshare
  pve-smbgateway quota-history myshare --days 7
  ```

- [ ] **Add quota alerts and notifications**
  - Email alerts for quota thresholds
  - Integration with Proxmox notification system
  - Quota trend analysis and predictions

### **Priority 3: Active Directory Integration** 🔥
**Status**: UI complete, backend needs implementation
**Effort**: 4-5 days
**Impact**: High - Enterprise requirement

#### Tasks:
- [ ] **Implement domain joining workflow**
  ```perl
  # Add to SMBGateway.pm
  sub _join_ad_domain {
      my ($self, $domain, $username, $password, $ou) = @_;
      # Domain controller discovery
      # Kerberos configuration
      # Samba domain join
      # Fallback authentication
  }
  ```

- [ ] **Add Kerberos authentication**
  - Configure krb5.conf
  - Set up SMB service principals
  - Enable Kerberos authentication in Samba

- [ ] **Create AD troubleshooting tools**
  ```bash
  # Add to CLI
  pve-smbgateway ad-test --domain example.com
  pve-smbgateway ad-status myshare
  ```

- [ ] **Implement fallback authentication**
  - Local user authentication as fallback
  - Hybrid authentication modes
  - Authentication method switching

### **Priority 4: CTDB High Availability** 🔥
**Status**: UI complete, backend needs implementation
**Effort**: 5-6 days
**Impact**: High - Production HA requirement

#### Tasks:
- [ ] **Implement CTDB cluster setup**
  ```perl
  # Add to SMBGateway.pm
  sub _setup_ctdb_cluster {
      my ($self, $nodes, $vip) = @_;
      # CTDB configuration
      # Cluster node discovery
      # VIP management
      # Failover testing
  }
  ```

- [ ] **Add VIP management system**
  - VIP allocation and assignment
  - Health monitoring
  - Automatic failover
  - VIP conflict detection

- [ ] **Create HA testing framework**
  ```bash
  # Add to CLI
  pve-smbgateway ha-test --nodes node1,node2 --vip 192.168.1.100
  pve-smbgateway ha-status myshare
  ```

- [ ] **Implement HA monitoring**
  - Cluster health monitoring
  - Failover event logging
  - Performance impact analysis

## Phase 2: Advanced Features (v1.1.0+)

### **Performance Monitoring System**
**Effort**: 1-2 weeks
**Impact**: Medium - Production monitoring

#### Features:
- Real-time I/O statistics collection
- Connection and session monitoring
- Performance trend analysis
- Prometheus metrics export
- Performance alerting system

### **Backup Integration System**
**Effort**: 1-2 weeks
**Impact**: Medium - Production backup

#### Features:
- Integration with Proxmox backup scheduler
- Snapshot-based backup workflows
- Backup verification and testing
- Backup failure handling and retry logic

### **Security Hardening**
**Effort**: 1 week
**Impact**: High - Production security

#### Features:
- SMB protocol security hardening
- Container and VM security profiles
- Security validation and testing
- Security monitoring and alerting

### **Enhanced CLI Management**
**Effort**: 1 week
**Impact**: Medium - Automation support

#### Features:
- Structured JSON output
- Batch operations support
- Configuration file support
- Comprehensive command coverage

## Phase 3: Storage Service Launcher (v2.0.0+)

### **App Store Interface**
**Effort**: 2-3 weeks
**Impact**: High - Platform expansion

#### Features:
- YAML-based service templates
- TrueNAS, MinIO, Nextcloud deployment
- Template validation and testing
- Community template repository

### **Advanced Provisioning**
**Effort**: 2-3 weeks
**Impact**: High - Platform expansion

#### Features:
- Pluggable storage backends
- HA profile system
- Secrets management integration
- Resource planning and validation

## Development Workflow

### **Testing Strategy**
```bash
# Unit tests
make test

# Integration tests
./scripts/test_integration.sh

# Performance tests
./scripts/test_performance.sh

# Security tests
./scripts/test_security.sh
```

### **Release Process**
```bash
# Version bump
perl -pi -e 's/0\.1\.0/0.2.0/' debian/changelog

# Build package
make deb

# Create release
git tag v0.2.0
git push origin v0.2.0
```

### **Quality Assurance**
- [ ] All tests pass
- [ ] Linting clean
- [ ] Documentation updated
- [ ] Performance benchmarks met
- [ ] Security review completed

## Success Metrics

### **Phase 1 Completion (v1.0.0)**
- ✅ All three deployment modes working
- ✅ AD integration functional
- ✅ HA with CTDB working
- ✅ Quota management complete
- ✅ Performance monitoring active
- ✅ Backup integration working

### **Phase 2 Completion (v1.5.0)**
- ✅ Security hardening complete
- ✅ Enhanced CLI functional
- ✅ Comprehensive testing suite
- ✅ Production deployment ready

### **Phase 3 Completion (v2.0.0)**
- ✅ App Store interface working
- ✅ Community templates available
- ✅ Advanced provisioning active
- ✅ Platform expansion complete

## Community Engagement

### **Development Communication**
- **GitHub Issues**: Feature requests and bug reports
- **Proxmox Forum**: Community discussion and feedback
- **Documentation**: Comprehensive guides and examples
- **Examples**: Real-world configuration examples

### **Contributor Guidelines**
- **Code Standards**: Perl and JavaScript linting
- **Testing**: Unit and integration test coverage
- **Documentation**: Inline comments and user guides
- **Review Process**: Pull request review and testing

## Timeline

### **Q3 2025 (Current)**
- Week 1-2: VM mode testing and refinement
- Week 3-4: Enhanced quota management
- Week 5-6: AD integration implementation

### **Q4 2025**
- Week 1-3: CTDB HA implementation
- Week 4-6: Performance monitoring system
- Week 7-8: Backup integration

### **Q1 2026**
- Week 1-2: Security hardening
- Week 3-4: Enhanced CLI management
- Week 5-6: v1.0.0 release preparation

### **Q2 2026**
- Week 1-4: App Store interface development
- Week 5-8: Advanced provisioning features

## Conclusion

The PVE SMB Gateway project has a solid foundation and clear path forward. The next priorities focus on completing core functionality (VM mode, AD integration, HA) to reach a production-ready v1.0.0 release. The roadmap then expands into advanced features and the ambitious Phase 3 Storage Service Launcher vision.

**Key Success Factors:**
1. **Incremental Development**: Build and test features incrementally
2. **Community Feedback**: Regular testing and feedback from users
3. **Quality Assurance**: Comprehensive testing and security review
4. **Documentation**: Keep documentation current with development
5. **Performance**: Maintain lightweight resource usage

This roadmap provides a clear path from the current solid foundation to a comprehensive, production-ready SMB gateway solution for the Proxmox ecosystem. 