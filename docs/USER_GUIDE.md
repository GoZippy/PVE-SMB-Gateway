# PVE SMB Gateway - User Guide

**Complete guide to using PVE SMB Gateway for SMB/CIFS share management**

## Table of Contents

1. [Installation](#installation)
2. [Getting Started](#getting-started)
3. [Web Interface](#web-interface)
4. [CLI Management](#cli-management)
5. [Deployment Modes](#deployment-modes)
6. [Active Directory Integration](#active-directory-integration)
7. [High Availability](#high-availability)
8. [Performance Monitoring](#performance-monitoring)
9. [Security Features](#security-features)
10. [Backup Integration](#backup-integration)
11. [Troubleshooting](#troubleshooting)
12. [Advanced Configuration](#advanced-configuration)

## Installation

### Prerequisites

- **Proxmox VE 8.x** (8.1, 8.2, 8.3 supported)
- **Debian 12** PVE hosts
- **Network connectivity** for AD integration (if using)
- **Storage backend** (ZFS, CephFS, RBD, or local storage)

### Quick Installation

```bash
# Download the latest release
wget https://github.com/ZippyNetworks/pve-smb-gateway/releases/download/v1.0.0/pve-plugin-smbgateway_1.0.0-1_all.deb

# Install the package
sudo dpkg -i pve-plugin-smbgateway_1.0.0-1_all.deb

# Restart the Proxmox web interface
sudo systemctl restart pveproxy
```

### Verification

After installation, you should see:

1. **SMB Gateway** option in the storage type dropdown
2. **pve-smbgateway** CLI command available
3. **No errors** in `/var/log/pveproxy/access.log`

## Getting Started

### Your First Share

1. **Navigate** to Datacenter → Storage → Add → SMB Gateway
2. **Configure** basic settings:
   - **Storage ID**: `myshare` (unique identifier)
   - **Share Name**: `My Share` (display name)
   - **Deployment Mode**: `LXC` (recommended for beginners)
   - **Path**: `/srv/smb/myshare` (storage location)
   - **Quota**: `10G` (optional storage limit)
3. **Click Create** and wait for provisioning

### Accessing Your Share

Once created, your share will be accessible at:
- **Windows**: `\\your-proxmox-ip\myshare`
- **macOS**: `smb://your-proxmox-ip/myshare`
- **Linux**: `smb://your-proxmox-ip/myshare`

## Web Interface

### Share Creation Wizard

The web interface provides a comprehensive wizard for share creation:

#### Step 1: Basic Configuration
- **Storage ID**: Unique identifier (required)
- **Share Name**: Display name for the share
- **Deployment Mode**: LXC, Native, or VM
- **Storage Path**: Backend storage location
- **Quota**: Optional storage limits

#### Step 2: Advanced Features
- **Active Directory**: Domain integration settings
- **High Availability**: CTDB clustering options
- **Security**: Security hardening options
- **Performance**: Resource allocation settings

#### Step 3: Review and Create
- **Configuration Summary**: Review all settings
- **Validation**: Automatic validation of configuration
- **Create**: Start the provisioning process

### Share Management

#### Viewing Shares
1. Navigate to **Datacenter → Storage**
2. Look for entries with **Type: SMB Gateway**
3. Click on a share to view details

#### Share Status
- **Active**: Share is running and accessible
- **Inactive**: Share is stopped or has errors
- **Creating**: Share is being provisioned
- **Error**: Share creation or operation failed

#### Share Actions
- **Start**: Start a stopped share
- **Stop**: Stop a running share
- **Delete**: Remove a share (with cleanup)
- **Edit**: Modify share configuration

## CLI Management

### Basic Commands

#### List Shares
```bash
# List all shares
pve-smbgateway list

# List with details
pve-smbgateway list --verbose

# JSON output for automation
pve-smbgateway list --json
```

#### Create Share
```bash
# Basic LXC share
pve-smbgateway create myshare \
  --mode lxc \
  --path /srv/smb/myshare \
  --quota 10G

# Native mode share
pve-smbgateway create nativeshare \
  --mode native \
  --path /srv/smb/native \
  --quota 20G

# VM mode share
pve-smbgateway create vmshare \
  --mode vm \
  --path /srv/smb/vm \
  --vm-memory 2048 \
  --vm-cores 2 \
  --quota 50G
```

#### Check Status
```bash
# Basic status
pve-smbgateway status myshare

# Status with metrics
pve-smbgateway status myshare --include-metrics

# Status with history
pve-smbgateway status myshare --include-history

# JSON output
pve-smbgateway status myshare --json
```

#### Delete Share
```bash
# Normal deletion
pve-smbgateway delete myshare

# Force deletion (skip confirmation)
pve-smbgateway delete myshare --force
```

### Enhanced CLI Features

#### Batch Operations
```bash
# Create multiple shares from configuration
pve-smbgateway batch create --config shares.json

# Parallel execution
pve-smbgateway batch create --config shares.json --parallel 3

# Dry run (preview only)
pve-smbgateway batch create --config shares.json --dry-run
```

#### Configuration File Format
```json
{
  "shares": [
    {
      "name": "share1",
      "mode": "lxc",
      "path": "/srv/smb/share1",
      "quota": "10G"
    },
    {
      "name": "share2",
      "mode": "native",
      "path": "/srv/smb/share2",
      "quota": "20G",
      "ad_domain": "example.com"
    }
  ]
}
```

## Deployment Modes

### LXC Mode (Recommended)

**Best for**: Most use cases, lightweight deployment

#### Features
- **Lightweight**: ~80MB RAM usage
- **Fast Provisioning**: < 30 seconds
- **Isolation**: Container-based deployment
- **Resource Limits**: Configurable memory and CPU
- **Bind Mounts**: Direct storage access

#### Configuration
```bash
pve-smbgateway create lxcshare \
  --mode lxc \
  --path /srv/smb/lxc \
  --quota 10G \
  --lxc-memory 128 \
  --lxc-cores 1
```

#### Resource Limits
- **Memory**: 128MB default (configurable)
- **CPU**: 1 core default (configurable)
- **Storage**: Direct access to host storage
- **Network**: Host network access

### Native Mode

**Best for**: Performance-critical applications

#### Features
- **Performance**: Direct host installation
- **Low Overhead**: Minimal resource usage
- **Shared Configuration**: Single Samba instance
- **Host Integration**: Full system access

#### Configuration
```bash
pve-smbgateway create nativeshare \
  --mode native \
  --path /srv/smb/native \
  --quota 20G
```

#### Considerations
- **Shared Resources**: Uses host Samba installation
- **Configuration Management**: Manual Samba config editing
- **Security**: Runs with host privileges
- **Updates**: Requires host package updates

### VM Mode

**Best for**: Maximum isolation and security

#### Features
- **Full Isolation**: Dedicated virtual machine
- **Custom Resources**: Configurable memory and CPU
- **Cloud-init**: Automated provisioning
- **Template-based**: Pre-built VM templates

#### Configuration
```bash
pve-smbgateway create vmshare \
  --mode vm \
  --path /srv/smb/vm \
  --vm-memory 2048 \
  --vm-cores 2 \
  --quota 50G
```

#### Resource Requirements
- **Memory**: 2GB+ recommended
- **CPU**: 2+ cores recommended
- **Storage**: Additional VM disk space
- **Network**: Dedicated network interface

## Active Directory Integration

### Prerequisites

- **Active Directory Domain**: Accessible from Proxmox host
- **Domain Credentials**: Administrative access
- **DNS Resolution**: Proper domain controller resolution
- **Network Connectivity**: Port 389/636 for LDAP

### Configuration

#### Web Interface
1. **Enable AD Integration** in the wizard
2. **Enter Domain**: `example.com`
3. **Enter Credentials**: Domain admin username/password
4. **Optional OU**: Specify organizational unit
5. **Enable Fallback**: Local authentication when AD unavailable

#### CLI Configuration
```bash
# Create share with AD integration
pve-smbgateway create adshare \
  --mode lxc \
  --path /srv/smb/ad \
  --quota 10G \
  --ad-domain example.com \
  --ad-join \
  --ad-username Administrator \
  --ad-password mypassword \
  --ad-ou "OU=Shares,DC=example,DC=com"
```

### Testing AD Integration

#### Test Connectivity
```bash
# Test domain connectivity
pve-smbgateway ad-test \
  --domain example.com \
  --username Administrator \
  --password mypassword
```

#### Check Status
```bash
# Check AD status for a share
pve-smbgateway ad-status myshare
```

### Troubleshooting AD

#### Common Issues
1. **DNS Resolution**: Ensure domain controllers are resolvable
2. **Credentials**: Verify domain admin credentials
3. **Network**: Check firewall rules for LDAP ports
4. **Time Sync**: Ensure host time is synchronized with AD

#### Diagnostic Commands
```bash
# Test DNS resolution
nslookup example.com

# Test LDAP connectivity
ldapsearch -H ldap://example.com -D "Administrator@example.com" -w password -b "DC=example,DC=com"

# Check Kerberos
klist
```

## High Availability

### Prerequisites

- **Multi-node Proxmox cluster**
- **Shared storage** (CephFS, NFS, or similar)
- **Network connectivity** between nodes
- **VIP address** for failover

### Configuration

#### Web Interface
1. **Enable HA** in the wizard
2. **Enter VIP**: `192.168.1.100`
3. **Select Nodes**: Choose cluster nodes
4. **Configure Failover**: Set failover settings

#### CLI Configuration
```bash
# Create HA share
pve-smbgateway create hashare \
  --mode lxc \
  --path /srv/smb/ha \
  --quota 10G \
  --ctdb-vip 192.168.1.100 \
  --ha-enabled
```

### HA Management

#### Check Status
```bash
# Check HA status
pve-smbgateway ha-status myshare
```

#### Test Failover
```bash
# Test HA failover
pve-smbgateway ha-test \
  --vip 192.168.1.100 \
  --share myshare \
  --target-node node2
```

#### Manual Failover
```bash
# Trigger manual failover
pve-smbgateway ha-failover myshare \
  --target-node node2
```

### HA Monitoring

#### Cluster Health
- **Node Status**: All nodes online and healthy
- **VIP Status**: VIP accessible and responding
- **CTDB Status**: CTDB cluster healthy
- **Failover Events**: Automatic failover history

#### Performance Impact
- **Failover Time**: < 30 seconds typical
- **Data Loss**: Zero data loss during failover
- **Client Reconnection**: Automatic client reconnection
- **Performance**: Minimal performance impact

## Performance Monitoring

### Real-Time Metrics

#### I/O Statistics
```bash
# Get current I/O metrics
pve-smbgateway metrics current myshare

# Get specific metric types
pve-smbgateway metrics current myshare --type io
pve-smbgateway metrics current myshare --type connections
pve-smbgateway metrics current myshare --type system
```

#### Quota Monitoring
```bash
# Check quota usage
pve-smbgateway status myshare

# Get quota history
pve-smbgateway metrics history myshare --type quota --hours 24
```

### Historical Analysis

#### Usage Trends
```bash
# Get 24-hour trends
pve-smbgateway metrics history myshare --hours 24

# Get weekly summary
pve-smbgateway metrics summary myshare --days 7

# Get monthly trends
pve-smbgateway metrics history myshare --days 30
```

#### Performance Baselines
- **Throughput**: MB/s read/write rates
- **Latency**: Response time measurements
- **Connections**: Active session counts
- **Resource Usage**: CPU, memory, disk usage

### Alerting

#### Performance Alerts
- **High Usage**: Quota usage > 85%
- **Performance Degradation**: Throughput < baseline
- **Connection Issues**: Failed authentication attempts
- **Resource Exhaustion**: Memory or CPU limits reached

#### Alert Configuration
```bash
# Configure alerts (via API)
curl -X POST "https://localhost:8006/api2/json/nodes/$(hostname)/storage/myshare/alerts" \
  -H "Authorization: PVEAPIToken=..." \
  -d '{"quota_threshold": 85, "performance_threshold": 100}'
```

## Security Features

### SMB Protocol Security

#### Protocol Enforcement
- **SMB2+**: Minimum protocol version enforcement
- **Mandatory Signing**: All connections must be signed
- **Encryption**: Optional SMB encryption
- **Guest Access**: Disabled by default

#### Security Configuration
```bash
# Check security status
pve-smbgateway security status myshare

# Run security scan
pve-smbgateway security scan myshare

# Get security report
pve-smbgateway security report myshare
```

### Container Security

#### AppArmor Profiles
- **Restricted Access**: Limited file system access
- **Network Isolation**: Controlled network access
- **Resource Limits**: Memory and CPU restrictions
- **Service Isolation**: Minimal privilege service users

#### Security Validation
```bash
# Validate security configuration
pve-smbgateway security validate myshare

# Check security compliance
pve-smbgateway security compliance myshare
```

### Access Control

#### User Management
- **Local Users**: Local authentication users
- **AD Users**: Domain user authentication
- **Service Users**: Minimal privilege service accounts
- **Access Logging**: Comprehensive access logs

#### Authentication Methods
- **Kerberos**: Primary authentication method
- **NTLM**: Fallback authentication
- **Local**: Local user authentication
- **Guest**: Disabled by default

## Backup Integration

### Backup Configuration

#### Automatic Backups
- **Snapshot-based**: ZFS/CephFS snapshots
- **Scheduled**: Integration with Proxmox backup scheduler
- **Retention**: Configurable retention policies
- **Verification**: Automatic backup verification

#### Manual Backups
```bash
# Create manual backup
pve-smbgateway backup create myshare

# List backups
pve-smbgateway backup list myshare

# Restore backup
pve-smbgateway backup restore myshare --backup-id backup_20250101_120000
```

### Backup Management

#### Backup Scheduling
```bash
# Schedule regular backups
pve-smbgateway backup schedule myshare --daily --retention 7

# Configure backup settings
pve-smbgateway backup configure myshare \
  --compression gzip \
  --encryption aes256 \
  --retention 30
```

#### Backup Monitoring
- **Backup Status**: Success/failure monitoring
- **Backup Size**: Storage usage tracking
- **Backup Performance**: Backup duration monitoring
- **Backup Verification**: Integrity checking

## Troubleshooting

### Common Issues

#### Share Creation Failures

**Problem**: Share creation fails with template error
```bash
# Solution: Check template availability
pve-smbgateway templates list

# Solution: Download template
pve-smbgateway templates download debian-12-standard
```

**Problem**: Share creation fails with permission error
```bash
# Solution: Check directory permissions
ls -la /srv/smb/

# Solution: Fix permissions
sudo chown -R 100000:100000 /srv/smb/
sudo chmod 755 /srv/smb/
```

#### SMB Access Issues

**Problem**: Cannot access SMB share
```bash
# Solution: Check share status
pve-smbgateway status myshare

# Solution: Check SMB service
pve-smbgateway service status myshare

# Solution: Check firewall
sudo ufw status
```

**Problem**: Authentication fails
```bash
# Solution: Check AD connectivity
pve-smbgateway ad-test --domain example.com

# Solution: Check local users
pve-smbgateway users list myshare
```

#### Performance Issues

**Problem**: Slow SMB performance
```bash
# Solution: Check I/O metrics
pve-smbgateway metrics current myshare

# Solution: Check resource usage
pve-smbgateway status myshare --include-metrics

# Solution: Optimize configuration
pve-smbgateway optimize myshare
```

### Diagnostic Commands

#### System Diagnostics
```bash
# Check system health
pve-smbgateway diagnose system

# Check network connectivity
pve-smbgateway diagnose network

# Check storage health
pve-smbgateway diagnose storage
```

#### Log Analysis
```bash
# View plugin logs
tail -f /var/log/pveproxy/access.log

# View Samba logs (LXC mode)
pct exec <ctid> tail -f /var/log/samba/log.smbd

# View Samba logs (Native mode)
tail -f /var/log/samba/log.smbd
```

### Recovery Procedures

#### Share Recovery
```bash
# Stop problematic share
pve-smbgateway stop myshare

# Clean up resources
pve-smbgateway cleanup myshare

# Restart share
pve-smbgateway start myshare
```

#### Complete Reset
```bash
# Delete and recreate share
pve-smbgateway delete myshare --force
pve-smbgateway create myshare --mode lxc --path /srv/smb/myshare
```

## Advanced Configuration

### Custom Samba Configuration

#### Samba Tuning
```bash
# Optimize for performance
pve-smbgateway configure myshare \
  --samba-option "socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=65536 SO_SNDBUF=65536" \
  --samba-option "read raw = yes" \
  --samba-option "write raw = yes"
```

#### Security Hardening
```bash
# Enable additional security
pve-smbgateway configure myshare \
  --samba-option "server signing = mandatory" \
  --samba-option "client signing = mandatory" \
  --samba-option "restrict anonymous = 2"
```

### Resource Optimization

#### Memory Tuning
```bash
# Optimize memory usage
pve-smbgateway configure myshare \
  --lxc-memory 256 \
  --samba-option "max xmit = 65535" \
  --samba-option "read size = 16384"
```

#### Network Tuning
```bash
# Optimize network performance
pve-smbgateway configure myshare \
  --samba-option "socket options = TCP_NODELAY" \
  --samba-option "max connections = 1000"
```

### Monitoring Integration

#### Prometheus Integration
```bash
# Enable Prometheus metrics
pve-smbgateway configure myshare \
  --prometheus-enabled \
  --prometheus-port 9100
```

#### SNMP Integration
```bash
# Enable SNMP monitoring
pve-smbgateway configure myshare \
  --snmp-enabled \
  --snmp-community public
```

---

**For additional support and advanced configuration options, please refer to the [Developer Guide](DEV_GUIDE.md) or contact support at eric@gozippy.com.** 