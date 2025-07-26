# PVE SMB Gateway - Live Testing Checklist

## Pre-Testing Preparation

### ✅ **System Requirements**
- [ ] Proxmox VE 8.0 or later installed
- [ ] Minimum 4GB RAM available
- [ ] At least 20GB free disk space
- [ ] Network connectivity to all cluster nodes
- [ ] Root or sudo access on all nodes

### ✅ **Dependencies Installed**
- [ ] Samba and Winbind packages
- [ ] ACL and attr packages
- [ ] Perl modules: DBI, DBD::SQLite, JSON::PP, File::Path, File::Basename, Sys::Hostname
- [ ] Optional: xfsprogs, quota packages
- [ ] ZFS tools (if using ZFS)

### ✅ **Backup and Safety**
- [ ] Recent backup of Proxmox configuration (`/etc/pve/`)
- [ ] Backup of storage configuration (`/etc/pve/storage.cfg`)
- [ ] Snapshot of critical VMs (if any)
- [ ] Rollback plan documented
- [ ] Emergency contact information available

### ✅ **Environment Validation**
- [ ] Run pre-flight check: `./scripts/preflight_check.sh`
- [ ] Verify all critical checks pass
- [ ] Address any warnings before proceeding
- [ ] Confirm test environment (not production)

## Installation and Setup

### ✅ **Plugin Installation**
- [ ] Build and install the plugin package
- [ ] Verify plugin files are installed correctly
- [ ] Check CLI tool is executable: `pve-smbgateway --help`
- [ ] Verify web interface files are present
- [ ] Restart Proxmox services if needed

### ✅ **Initial Configuration**
- [ ] Create test storage directory: `/srv/smb/test`
- [ ] Verify storage backend is accessible
- [ ] Check ZFS pools (if applicable)
- [ ] Test basic SMB connectivity

## Testing Phases

### Phase 1: Basic Functionality ✅

#### LXC Mode Testing
- [ ] Create LXC share: `pve-smbgateway create test-lxc --mode lxc --path /srv/smb/test --quota 1G`
- [ ] Verify container is created and running
- [ ] Check SMB service is accessible
- [ ] Test file operations (create, read, write, delete)
- [ ] Verify quota enforcement
- [ ] Delete share: `pve-smbgateway delete test-lxc`

#### Native Mode Testing
- [ ] Create native share: `pve-smbgateway create test-native --mode native --path /srv/smb/test --quota 1G`
- [ ] Verify SMB service is running on host
- [ ] Test file operations
- [ ] Verify quota enforcement
- [ ] Delete share: `pve-smbgateway delete test-native`

#### VM Mode Testing
- [ ] Create VM template: `./scripts/create_vm_template.sh`
- [ ] Create VM share: `pve-smbgateway create test-vm --mode vm --path /srv/smb/test --quota 1G`
- [ ] Verify VM is created and running
- [ ] Test SMB connectivity to VM
- [ ] Test file operations
- [ ] Delete share: `pve-smbgateway delete test-vm`

### Phase 2: Advanced Features ✅

#### Quota Management Testing
- [ ] Test ZFS quota enforcement (if applicable)
- [ ] Test XFS quota enforcement (if applicable)
- [ ] Test user quota enforcement
- [ ] Verify quota monitoring and alerts
- [ ] Test quota trend analysis
- [ ] Test quota reporting features

#### Performance Testing
- [ ] Run performance benchmarks: `./scripts/test_performance_benchmarks.sh`
- [ ] Test concurrent file operations
- [ ] Monitor resource usage during operations
- [ ] Verify performance meets expectations
- [ ] Document performance metrics

#### Error Handling Testing
- [ ] Test invalid quota formats
- [ ] Test non-existent paths
- [ ] Test insufficient resources
- [ ] Test network failures
- [ ] Verify proper error messages
- [ ] Test rollback mechanisms

### Phase 3: Cluster Integration ✅

#### Multi-Node Testing
- [ ] Test share creation on different nodes
- [ ] Verify share accessibility across cluster
- [ ] Test failover scenarios
- [ ] Test cluster-wide quota management
- [ ] Verify monitoring works across nodes

#### High Availability Testing
- [ ] Test CTDB configuration (if enabled)
- [ ] Test VIP failover
- [ ] Test cluster health monitoring
- [ ] Verify automatic recovery
- [ ] Test manual failover procedures

### Phase 4: Security Testing ✅

#### Authentication Testing
- [ ] Test local user authentication
- [ ] Test Active Directory integration (if configured)
- [ ] Test Kerberos authentication
- [ ] Test fallback authentication
- [ ] Verify access controls

#### Security Validation
- [ ] Test file permissions
- [ ] Test SMB protocol security
- [ ] Verify audit logging
- [ ] Test security boundaries
- [ ] Validate encryption (if enabled)

### Phase 5: Monitoring and Alerting ✅

#### Monitoring System Testing
- [ ] Verify metrics collection
- [ ] Test quota monitoring
- [ ] Test performance monitoring
- [ ] Verify alert generation
- [ ] Test notification delivery

#### Dashboard Testing
- [ ] Verify web interface functionality
- [ ] Test dashboard widgets
- [ ] Verify real-time updates
- [ ] Test configuration interface
- [ ] Verify status reporting

## Comprehensive Testing

### ✅ **Full Test Suite**
- [ ] Run comprehensive test suite: `./scripts/run_all_tests.sh`
- [ ] Verify all tests pass
- [ ] Review test reports and logs
- [ ] Address any test failures
- [ ] Document test results

### ✅ **Stress Testing**
- [ ] Test with multiple concurrent shares
- [ ] Test with large files and directories
- [ ] Test under high load conditions
- [ ] Monitor system stability
- [ ] Verify resource limits

### ✅ **Integration Testing**
- [ ] Test with existing Proxmox workflows
- [ ] Test with backup systems
- [ ] Test with monitoring systems
- [ ] Test with automation tools
- [ ] Verify compatibility

## Production Readiness

### ✅ **Documentation Review**
- [ ] Verify installation documentation
- [ ] Review user guides
- [ ] Check troubleshooting guides
- [ ] Verify API documentation
- [ ] Review security documentation

### ✅ **Performance Validation**
- [ ] Confirm performance meets requirements
- [ ] Verify resource usage is acceptable
- [ ] Test scalability limits
- [ ] Document performance baselines
- [ ] Plan capacity requirements

### ✅ **Security Validation**
- [ ] Complete security audit
- [ ] Verify compliance requirements
- [ ] Test security controls
- [ ] Review access controls
- [ ] Validate audit trails

## Post-Testing Actions

### ✅ **Cleanup**
- [ ] Remove all test shares
- [ ] Clean up test data
- [ ] Remove test configurations
- [ ] Restore original settings
- [ ] Verify system is clean

### ✅ **Documentation**
- [ ] Document test results
- [ ] Record performance metrics
- [ ] Document any issues found
- [ ] Create deployment guide
- [ ] Update troubleshooting guides

### ✅ **Next Steps**
- [ ] Plan production deployment
- [ ] Schedule user training
- [ ] Prepare support documentation
- [ ] Plan monitoring setup
- [ ] Schedule regular maintenance

## Emergency Procedures

### ✅ **Rollback Plan**
- [ ] Keep rollback script ready: `./scripts/rollback.sh`
- [ ] Document rollback procedures
- [ ] Test rollback process
- [ ] Verify rollback success
- [ ] Plan communication strategy

### ✅ **Support Contacts**
- [ ] Document support contacts
- [ ] Prepare escalation procedures
- [ ] Plan communication channels
- [ ] Document emergency procedures
- [ ] Test support processes

## Success Criteria

### ✅ **Functional Requirements**
- [ ] All deployment modes work correctly
- [ ] Quota management functions properly
- [ ] Monitoring and alerting work
- [ ] Security features are effective
- [ ] Performance meets requirements

### ✅ **Operational Requirements**
- [ ] System is stable under normal load
- [ ] Error handling works correctly
- [ ] Rollback procedures are tested
- [ ] Documentation is complete
- [ ] Support processes are ready

### ✅ **User Experience**
- [ ] Web interface is intuitive
- [ ] CLI tools are easy to use
- [ ] Error messages are helpful
- [ ] Performance is acceptable
- [ ] Features work as expected

## Notes and Observations

### Test Environment Details
- **Cluster Size**: _____ nodes
- **Proxmox Version**: _____
- **Storage Backends**: _____
- **Network Configuration**: _____
- **Test Duration**: _____ hours

### Issues Found
- [ ] Issue 1: _____
- [ ] Issue 2: _____
- [ ] Issue 3: _____

### Recommendations
- [ ] Recommendation 1: _____
- [ ] Recommendation 2: _____
- [ ] Recommendation 3: _____

### Sign-off
- [ ] **Tester**: _____ Date: _____
- [ ] **Reviewer**: _____ Date: _____
- [ ] **Approver**: _____ Date: _____

---

**Important**: This checklist should be completed thoroughly before any production deployment. All items should be checked off and documented before proceeding to production use. 