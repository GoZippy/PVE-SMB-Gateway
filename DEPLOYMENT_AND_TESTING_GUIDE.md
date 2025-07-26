# 🚀 PVE SMB Gateway - Deployment and Testing Guide

## 📋 **OVERVIEW**

This guide provides step-by-step instructions for safely deploying and testing the PVE SMB Gateway plugin on a Proxmox VE system. The plugin is now ready for alpha testing with comprehensive validation and safety measures in place.

## 🎯 **PREREQUISITES**

### **System Requirements**
- ✅ **Proxmox VE 8.0+**: Compatible with current Proxmox versions
- ✅ **Root Access**: Must run as root for installation
- ✅ **Network Connectivity**: Internet access for dependencies
- ✅ **Storage Space**: Minimum 1GB available disk space
- ✅ **Memory**: Minimum 2GB RAM (4GB+ recommended)

### **Test Environment**
- ✅ **Dedicated Test System**: Use separate test environment
- ✅ **No Production Data**: Do not test with important data
- ✅ **Backup Available**: System backup before testing
- ✅ **Network Access**: Ability to transfer deployment package

## 📦 **DEPLOYMENT PACKAGE CONTENTS**

The deployment package (`pve-smbgateway-deployment-20250725-214809.zip`) contains:

### **Core Plugin Files**
- `PVE/Storage/Custom/SMBGateway.pm` - Main plugin module
- `PVE/SMBGateway/` - Supporting modules (Monitor, Backup, Security, QuotaManager, CLI)
- `sbin/pve-smbgateway` - CLI management tool
- `www/ext6/pvemanager6/` - Web interface files

### **Installation Files**
- `debian/control` - Package dependencies
- `debian/install` - File installation paths
- `debian/postinst` - Post-installation script

### **Scripts and Tools**
- `scripts/validate_installation.sh` - Pre-installation validation
- `scripts/preflight_check.sh` - System readiness check
- `scripts/rollback.sh` - Safe uninstallation
- `scripts/run_all_tests.sh` - Comprehensive testing
- `deploy.sh` - Automated deployment script

### **Documentation**
- `QUICK_START.md` - Installation guide
- `README.md` - Project documentation
- `FINAL_READINESS_REPORT.md` - Readiness assessment

## 🚀 **DEPLOYMENT PROCESS**

### **Step 1: Transfer Deployment Package**

#### **Option A: SCP Transfer**
```bash
# From Windows/Linux client
scp pve-smbgateway-deployment-20250725-214809.zip root@your-proxmox-host:/tmp/

# SSH to Proxmox host
ssh root@your-proxmox-host
```

#### **Option B: USB Transfer**
```bash
# Copy to USB drive, then transfer to Proxmox host
# Mount USB and copy files
mount /dev/sdX1 /mnt/usb
cp /mnt/usb/pve-smbgateway-deployment-20250725-214809.zip /tmp/
```

#### **Option C: Web Download**
```bash
# If package is hosted online
wget https://your-server.com/pve-smbgateway-deployment-20250725-214809.zip -O /tmp/
```

### **Step 2: Extract and Prepare**

```bash
# Navigate to temporary directory
cd /tmp

# Extract deployment package
unzip pve-smbgateway-deployment-20250725-214809.zip

# Navigate to deployment directory
cd deployment-package

# Make scripts executable
chmod +x deploy.sh
chmod +x scripts/*.sh
```

### **Step 3: Run Pre-Installation Validation**

```bash
# Run comprehensive validation
./scripts/validate_installation.sh
```

**Expected Output**:
```
==========================================
PVE SMB Gateway - Validation Summary
==========================================
Results:
- Errors: 0
- Warnings: 0

✅ VALIDATION PASSED
The plugin is ready for installation.
```

**If validation fails**:
- Review the log file: `/tmp/pve-smbgateway-validation.log`
- Install missing dependencies
- Fix any system issues
- Re-run validation

### **Step 4: Install Dependencies**

```bash
# Update package list
apt update

# Install required packages
apt install -y \
    samba \
    perl \
    libdbi-perl \
    libdbd-sqlite3-perl \
    libjson-pp-perl \
    libfile-path-perl \
    libfile-basename-perl \
    libsys-hostname-perl \
    quota \
    xfsprogs \
    libtime-hires-perl \
    libgetopt-long-perl \
    libpod-usage-perl
```

### **Step 5: Deploy Plugin**

```bash
# Run automated deployment
./deploy.sh
```

**Expected Output**:
```
=== PVE SMB Gateway Deployment ===
✓ PASS: System validation completed
✓ PASS: Dependencies installed
✓ PASS: Plugin files installed
✓ PASS: Web interface configured
✓ PASS: Services restarted
✓ PASS: Deployment completed successfully
```

## 🧪 **TESTING PROCEDURE**

### **Phase 1: Basic Functionality Testing**

#### **1.1 Web Interface Test**
```bash
# Access Proxmox web interface
# Navigate to: Datacenter → Storage → Add Storage
# Select: SMB Gateway
# Verify: ExtJS wizard opens correctly
```

#### **1.2 LXC Mode Test**
```bash
# Create test share using LXC mode
# Share name: test-lxc-share
# Path: /srv/smb/test-lxc
# Quota: 1G
# Mode: LXC

# Verify share creation
pve-smbgateway list-shares

# Check share status
pve-smbgateway status test-lxc-share
```

#### **1.3 Native Mode Test**
```bash
# Create test share using Native mode
# Share name: test-native-share
# Path: /srv/smb/test-native
# Quota: 2G
# Mode: Native

# Verify share creation
pve-smbgateway list-shares

# Check share status
pve-smbgateway status test-native-share
```

### **Phase 2: Advanced Features Testing**

#### **2.1 Quota Management Test**
```bash
# Test quota application
pve-smbgateway quota-status test-lxc-share

# Test quota usage monitoring
pve-smbgateway quota-usage test-lxc-share

# Test quota trend analysis
pve-smbgateway quota-trend test-lxc-share
```

#### **2.2 CLI Tool Test**
```bash
# Test all CLI commands
pve-smbgateway --help
pve-smbgateway list-shares
pve-smbgateway status test-lxc-share
pve-smbgateway metrics test-lxc-share
pve-smbgateway backup-status test-lxc-share
```

#### **2.3 Performance Monitoring Test**
```bash
# Test performance metrics
pve-smbgateway metrics test-lxc-share

# Test historical data
pve-smbgateway metrics-history test-lxc-share

# Test performance alerts
pve-smbgateway performance-alerts test-lxc-share
```

### **Phase 3: Error Handling Test**

#### **3.1 Invalid Configuration Test**
```bash
# Test with invalid quota format
# Expected: Error message and rollback

# Test with non-existent path
# Expected: Error message and rollback

# Test with insufficient permissions
# Expected: Error message and rollback
```

#### **3.2 Service Failure Test**
```bash
# Stop Samba service
systemctl stop smbd

# Try to create share
# Expected: Error message and rollback

# Restart Samba service
systemctl start smbd
```

### **Phase 4: VM Mode Testing (Optional)**

#### **4.1 VM Template Test**
```bash
# Create test share using VM mode
# Share name: test-vm-share
# Path: /srv/smb/test-vm
# Quota: 5G
# Mode: VM
# Memory: 2048MB
# Cores: 2

# Verify VM creation
qm list | grep test-vm

# Check VM status
qm status test-vm-share
```

#### **4.2 VM Template Creation Test**
```bash
# If no suitable template exists
# Expected: Automatic template creation
# Verify: Template created successfully
```

## 📊 **SUCCESS CRITERIA**

### **Basic Functionality** ✅
- [ ] Web interface loads correctly
- [ ] LXC mode share creation works
- [ ] Native mode share creation works
- [ ] CLI tool responds to commands
- [ ] Share status reporting works

### **Advanced Features** ✅
- [ ] Quota management functions correctly
- [ ] Performance monitoring works
- [ ] Error handling and rollback works
- [ ] CLI commands return proper output
- [ ] Web interface shows share information

### **Error Handling** ✅
- [ ] Invalid configurations are rejected
- [ ] Rollback procedures work correctly
- [ ] Error messages are descriptive
- [ ] System remains stable after errors
- [ ] Cleanup procedures work

### **Performance** ✅
- [ ] Share creation completes within 30 seconds (LXC)
- [ ] Share creation completes within 2 minutes (VM)
- [ ] CLI commands respond within 5 seconds
- [ ] Web interface loads within 10 seconds
- [ ] No memory leaks during operation

## 🚨 **TROUBLESHOOTING**

### **Common Issues**

#### **1. Validation Fails**
```bash
# Check validation log
cat /tmp/pve-smbgateway-validation.log

# Install missing dependencies
apt install -y [missing-package]

# Re-run validation
./scripts/validate_installation.sh
```

#### **2. Installation Fails**
```bash
# Check installation log
cat /var/log/pve-smbgateway/install.log

# Run rollback if needed
./scripts/rollback.sh

# Check system requirements
./scripts/preflight_check.sh
```

#### **3. Share Creation Fails**
```bash
# Check Samba configuration
cat /etc/samba/smb.conf

# Check Samba service status
systemctl status smbd

# Check system logs
journalctl -u smbd -f
```

#### **4. Web Interface Not Available**
```bash
# Restart Proxmox services
systemctl restart pveproxy
systemctl restart pvedaemon

# Check service status
systemctl status pveproxy
systemctl status pvedaemon
```

### **Log Files**
- **Installation Log**: `/var/log/pve-smbgateway/install.log`
- **Validation Log**: `/tmp/pve-smbgateway-validation.log`
- **Samba Log**: `/var/log/samba/`
- **System Log**: `journalctl -u smbd`

## 🔄 **ROLLBACK PROCEDURE**

### **If Testing Fails**
```bash
# Run rollback script
./scripts/rollback.sh

# Verify cleanup
pve-smbgateway list-shares

# Check system status
systemctl status smbd
systemctl status pveproxy
```

### **Manual Cleanup**
```bash
# Remove plugin files
rm -rf /usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm
rm -rf /usr/share/perl5/PVE/SMBGateway/
rm -f /usr/sbin/pve-smbgateway
rm -f /usr/sbin/pve-smbgateway-enhanced

# Remove web interface files
rm -rf /usr/share/pve-manager/ext6/pvemanager6/smb-gateway*

# Restart Proxmox services
systemctl restart pveproxy
systemctl restart pvedaemon
```

## 📋 **TESTING CHECKLIST**

### **Pre-Installation** ✅
- [ ] System meets requirements
- [ ] Backup created
- [ ] Test environment ready
- [ ] Deployment package transferred
- [ ] Validation script passes

### **Installation** ✅
- [ ] Dependencies installed
- [ ] Plugin deployed successfully
- [ ] Services restarted
- [ ] Web interface accessible
- [ ] CLI tool functional

### **Basic Testing** ✅
- [ ] LXC mode share creation
- [ ] Native mode share creation
- [ ] Share status reporting
- [ ] CLI command responses
- [ ] Web interface functionality

### **Advanced Testing** ✅
- [ ] Quota management
- [ ] Performance monitoring
- [ ] Error handling
- [ ] Rollback procedures
- [ ] VM mode (if applicable)

### **Post-Testing** ✅
- [ ] All tests passed
- [ ] System stable
- [ ] Documentation updated
- [ ] Issues documented
- [ ] Next steps planned

## 🎉 **SUCCESS INDICATORS**

### **Ready for Production** ✅
- [ ] All basic functionality works
- [ ] Error handling is robust
- [ ] Performance is acceptable
- [ ] Documentation is complete
- [ ] Support procedures are in place

### **Ready for Beta Testing** ✅
- [ ] Single-node testing successful
- [ ] Multi-node testing planned
- [ ] User feedback collected
- [ ] Issues prioritized
- [ ] Release timeline established

## 📞 **SUPPORT AND FEEDBACK**

### **Reporting Issues**
- **Log Files**: Include relevant log files
- **System Info**: Proxmox version, system specs
- **Steps to Reproduce**: Detailed reproduction steps
- **Expected vs Actual**: Clear description of issue

### **Getting Help**
- **Documentation**: Check README.md and guides
- **Validation**: Run validation script for diagnostics
- **Logs**: Review log files for error details
- **Community**: Share issues and solutions

---

**Status**: ✅ **READY FOR DEPLOYMENT**  
**Confidence Level**: **HIGH**  
**Risk Level**: **LOW** (with proper testing procedures)

**Next Action**: Transfer the deployment package to your Proxmox host and follow this guide for safe testing. 