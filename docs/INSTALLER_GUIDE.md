# PVE SMB Gateway - GUI Installer Guide

**Complete guide to using the guided GUI installer for PVE SMB Gateway**

## 🎯 **Overview**

The PVE SMB Gateway includes a **comprehensive GUI installer** that provides a guided, step-by-step installation process. This installer gives users full control and understanding of what will happen during installation.

## 🚀 **Key Features**

### **✅ User Control & Transparency**
- **Step-by-step guidance**: Clear explanation of each installation step
- **Command preview**: See exactly what commands will be executed
- **Real-time progress**: Live progress tracking with detailed status
- **Pause/Resume**: Stop and resume installation at any time
- **Detailed logging**: Complete log of all operations

### **✅ Safety & Validation**
- **System compatibility check**: Validates your system before installation
- **Dependency verification**: Ensures all required packages are available
- **Permission validation**: Checks user permissions and access rights
- **Rollback capability**: Safe installation with cleanup options
- **Error handling**: Graceful error recovery and reporting

### **✅ Configuration Options**
- **Custom paths**: Choose installation, config, and log directories
- **Feature selection**: Enable/disable specific features
- **Advanced options**: Verbose logging, force installation, cleanup
- **Settings preview**: Review all configuration before installation

## 📋 **System Requirements**

### **Minimum Requirements**
- **Operating System**: Debian 12, Ubuntu 22.04+, or Proxmox VE 8.x
- **Python**: Python 3.8 or higher
- **Memory**: 1GB RAM minimum
- **Disk Space**: 1GB free space
- **Permissions**: Root or sudo access

### **Recommended Requirements**
- **Operating System**: Proxmox VE 8.2 or 8.3
- **Python**: Python 3.10 or higher
- **Memory**: 2GB RAM or more
- **Disk Space**: 2GB free space
- **Network**: Internet connection for dependencies

## 🛠️ **Installation Methods**

### **Method 1: GUI Installer (Recommended)**

#### **Linux/Proxmox Systems**
```bash
# Clone the repository
git clone https://github.com/GoZippy/PVE-SMB-Gateway.git
cd PVE-SMB-Gateway

# Run the GUI installer
./installer/run-installer.sh
```

#### **Windows Systems**
```powershell
# Clone the repository
git clone https://github.com/GoZippy/PVE-SMB-Gateway.git
cd PVE-SMB-Gateway

# Run the GUI installer
.\installer\run-installer.ps1
```

### **Method 2: Command Line Options**

#### **System Check Only**
```bash
./installer/run-installer.sh --check-only
```

#### **Install Dependencies Only**
```bash
./installer/run-installer.sh --install-deps
```

#### **Verbose Mode**
```bash
./installer/run-installer.sh --verbose
```

## 🖥️ **GUI Installer Walkthrough**

### **Step 1: Welcome Screen**

The installer starts with a welcome screen that provides:
- **Overview**: What the installer will do
- **System Requirements**: Minimum and recommended specs
- **Safety Information**: Installation safety and rollback options
- **Next Steps**: How to proceed

**What you'll see:**
```
Welcome to the PVE SMB Gateway Installer!

This guided installation process will help you install and configure 
the PVE SMB Gateway plugin for Proxmox VE.

What this installer will do:
• Check your system compatibility
• Install required dependencies
• Build the SMB Gateway package
• Install the plugin into Proxmox
• Configure services and settings
• Test the installation

System Requirements:
• Proxmox VE 8.x (8.1, 8.2, 8.3)
• Debian 12 base system
• Root or sudo access
• Internet connection for dependencies
• At least 1GB free disk space
```

### **Step 2: System Check**

The system check validates your environment:

#### **Automatic Checks**
- **Proxmox VE Installation**: Verifies Proxmox is installed
- **System Requirements**: Checks OS, kernel, architecture
- **Dependencies**: Validates required packages
- **Disk Space**: Ensures sufficient storage
- **Permissions**: Verifies user access rights
- **Network Connectivity**: Tests internet access

#### **Manual Checks**
- **Run System Check**: Click to start validation
- **View Detailed Log**: See comprehensive check results
- **Check Results**: Pass/fail status for each component

**Example Output:**
```
System Check Results:
✓ Checking Proxmox VE installation: PASS
✓ Checking system requirements: PASS
✓ Checking dependencies: PASS
✓ Checking disk space: PASS
✓ Checking permissions: PASS
✓ Checking network connectivity: PASS
```

### **Step 3: Configuration**

Configure installation options:

#### **Installation Paths**
- **Install Path**: Where the plugin will be installed (default: `/usr/share/pve-smbgateway`)
- **Config Path**: Configuration directory (default: `/etc/pve/smbgateway`)
- **Log Path**: Log file directory (default: `/var/log/pve/smbgateway`)

#### **Features**
- **Backup Integration**: Enable Proxmox backup integration
- **Performance Monitoring**: Enable metrics collection
- **High Availability**: Enable HA/CTDB support

#### **Advanced Options**
- **Verbose Logging**: Detailed installation logs
- **Force Installation**: Overwrite existing installation
- **Cleanup**: Remove temporary files after installation

### **Step 4: Installation Progress**

Real-time installation tracking:

#### **Progress Indicators**
- **Progress Bar**: Visual progress indicator
- **Current Step**: Description of active operation
- **Command Preview**: Shows commands being executed
- **Status Updates**: Real-time status messages

#### **Control Options**
- **Pause**: Temporarily stop installation
- **Resume**: Continue paused installation
- **Stop**: Cancel installation (with confirmation)

#### **Installation Steps**
1. **Installing Dependencies**: System packages and Python modules
2. **Building Package**: Compile the SMB Gateway package
3. **Installing Package**: Install into Proxmox system
4. **Configuring Services**: Setup services and permissions
5. **Testing Installation**: Validate installation success

### **Step 5: Installation Log**

Complete log of all operations:

#### **Log Features**
- **Real-time Updates**: Live log viewing
- **Timestamped Entries**: All operations with timestamps
- **Error Highlighting**: Clear error identification
- **Export Options**: Save log to file

#### **Log Controls**
- **Clear Log**: Remove all log entries
- **Save Log**: Export to file
- **Copy to Clipboard**: Copy log content

## 🔧 **Installation Process Details**

### **What the Installer Does**

#### **1. System Validation**
```bash
# Check Proxmox installation
pveversion -v

# Verify system requirements
cat /etc/os-release
uname -r
df -h /

# Check dependencies
which perl python3 make dpkg-buildpackage git
```

#### **2. Dependency Installation**
```bash
# Update package list
apt update

# Install build dependencies
apt install -y build-essential devscripts debhelper perl python3

# Install SMB dependencies
apt install -y samba ctdb libpve-common-perl libpve-storage-perl
```

#### **3. Package Building**
```bash
# Build the package
make deb

# Verify package creation
ls -la ../pve-plugin-smbgateway_*.deb
```

#### **4. Package Installation**
```bash
# Install the package
dpkg -i ../pve-plugin-smbgateway_*.deb

# Verify installation
dpkg -l | grep pve-plugin-smbgateway
```

#### **5. Service Configuration**
```bash
# Create directories
mkdir -p /etc/pve/smbgateway
mkdir -p /var/log/pve/smbgateway

# Set permissions
chown -R root:root /etc/pve/smbgateway
chmod 755 /etc/pve/smbgateway

# Restart Proxmox services
systemctl restart pveproxy
```

#### **6. Installation Testing**
```bash
# Test CLI command
pve-smbgateway --version

# Test web interface integration
# (Verifies GUI components are accessible)
```

## 🛡️ **Safety Features**

### **Pre-Installation Safety**
- **System Compatibility**: Validates environment before installation
- **Dependency Check**: Ensures all requirements are met
- **Permission Validation**: Verifies user access rights
- **Disk Space Check**: Confirms sufficient storage

### **Installation Safety**
- **Command Preview**: Shows all commands before execution
- **Progress Tracking**: Real-time monitoring of operations
- **Error Handling**: Graceful error recovery
- **Rollback Capability**: Safe installation with cleanup

### **Post-Installation Safety**
- **Installation Verification**: Tests all components
- **Service Validation**: Ensures services start correctly
- **Logging**: Complete audit trail of operations
- **Documentation**: Installation summary and next steps

## 🔍 **Troubleshooting**

### **Common Issues**

#### **System Check Failures**
```bash
# Check Proxmox installation
pveversion -v

# Verify system requirements
cat /etc/os-release
uname -r

# Check disk space
df -h /

# Verify permissions
whoami
sudo -n true
```

#### **Dependency Issues**
```bash
# Update package list
sudo apt update

# Install missing dependencies
sudo apt install -y python3 python3-tk python3-pip

# Check Python installation
python3 --version
python3 -c "import tkinter"
```

#### **Permission Issues**
```bash
# Check user permissions
whoami
groups

# Verify sudo access
sudo -n true

# Check file permissions
ls -la installer/
```

### **Installation Failures**

#### **Package Build Failures**
```bash
# Check build dependencies
dpkg -l | grep -E "(build-essential|devscripts|debhelper)"

# Clean build environment
make clean

# Retry build
make deb
```

#### **Package Installation Failures**
```bash
# Check package file
ls -la ../pve-plugin-smbgateway_*.deb

# Verify package integrity
dpkg-deb -I ../pve-plugin-smbgateway_*.deb

# Force installation
sudo dpkg -i --force-overwrite ../pve-plugin-smbgateway_*.deb
```

#### **Service Configuration Failures**
```bash
# Check service status
systemctl status pveproxy

# Restart services manually
sudo systemctl restart pveproxy

# Check logs
journalctl -u pveproxy -f
```

## 📊 **Installation Verification**

### **Post-Installation Checks**

#### **CLI Verification**
```bash
# Test CLI command
pve-smbgateway --version

# Check help
pve-smbgateway --help

# List available commands
pve-smbgateway list-commands
```

#### **Web Interface Verification**
1. **Access Proxmox**: Open browser to `https://your-proxmox-ip:8006`
2. **Check Storage Menu**: Navigate to Datacenter → Storage → Add
3. **Verify SMB Gateway**: Should appear in storage type dropdown
4. **Test Dashboard**: Access SMB Gateway from main menu

#### **Service Verification**
```bash
# Check service status
systemctl status pveproxy

# Verify log files
ls -la /var/log/pve/smbgateway/

# Check configuration
ls -la /etc/pve/smbgateway/
```

## 🔄 **Uninstallation**

### **Using the Installer**
The GUI installer includes uninstallation capabilities:
1. **Access Uninstall**: Available in installer options
2. **Confirmation**: Confirm uninstallation
3. **Cleanup**: Remove all components
4. **Verification**: Confirm removal

### **Manual Uninstallation**
```bash
# Remove package
sudo dpkg -r pve-plugin-smbgateway

# Remove configuration
sudo rm -rf /etc/pve/smbgateway

# Remove logs
sudo rm -rf /var/log/pve/smbgateway

# Restart services
sudo systemctl restart pveproxy
```

## 📈 **Performance Considerations**

### **Installation Performance**
- **Parallel Operations**: Dependencies installed in parallel
- **Progress Tracking**: Real-time progress updates
- **Resource Monitoring**: CPU and memory usage tracking
- **Optimized Builds**: Efficient package building

### **System Impact**
- **Minimal Footprint**: Lightweight installer
- **Temporary Files**: Cleanup after installation
- **Service Restarts**: Minimal service disruption
- **Rollback Support**: Safe installation process

## 🔮 **Future Enhancements**

### **Planned Features**
- **Network Installation**: Install from remote repository
- **Cluster Installation**: Multi-node installation support
- **Configuration Import**: Import existing configurations
- **Backup Integration**: Backup before installation

### **Advanced Options**
- **Custom Repositories**: Use custom package repositories
- **Offline Installation**: Install without internet access
- **Silent Installation**: Unattended installation mode
- **Configuration Templates**: Pre-defined configuration templates

## 📞 **Support & Documentation**

### **Getting Help**
- **Installation Logs**: Check logs for detailed error information
- **System Requirements**: Verify your system meets requirements
- **Documentation**: Review this guide and other documentation
- **Community Support**: Visit GitHub issues for community help

### **Additional Resources**
- **User Guide**: Complete usage documentation
- **API Documentation**: Technical API reference
- **Video Tutorials**: Step-by-step video guides
- **Community Forum**: User community discussions

---

## 🎉 **Conclusion**

The PVE SMB Gateway GUI installer provides a **comprehensive, user-friendly installation experience** that gives users full control and understanding of the installation process. With its step-by-step guidance, real-time progress tracking, and comprehensive safety features, it makes installing the SMB Gateway plugin simple and reliable.

**Key Benefits:**
- ✅ **User Control**: Full transparency and control over installation
- ✅ **Safety**: Comprehensive validation and error handling
- ✅ **Simplicity**: Guided process with clear explanations
- ✅ **Reliability**: Robust installation with rollback support
- ✅ **Monitoring**: Real-time progress and detailed logging

The installer ensures that users can confidently install the PVE SMB Gateway with full understanding of what will happen and complete control over the process. 