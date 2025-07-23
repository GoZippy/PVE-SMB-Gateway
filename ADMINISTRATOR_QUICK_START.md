# PVE SMB Gateway - Administrator Quick Start

**For Proxmox VE Administrators - Get SMB shares running in minutes!**

## 🚀 **What This Plugin Does**

The PVE SMB Gateway plugin lets you create SMB/CIFS shares directly from your Proxmox storage (ZFS, CephFS, RBD) **without needing a full NAS VM**. Perfect for:

- ✅ **Quick file sharing** from existing storage
- ✅ **Lightweight deployment** (80MB RAM vs 2GB+ for NAS VM)
- ✅ **Proxmox integration** (uses your existing storage and networking)
- ✅ **Enterprise features** (AD integration, HA, quotas)

## 📦 **Installation (2 minutes)**

```bash
# Download and install
wget https://github.com/ZippyNetworks/pve-smb-gateway/releases/download/v1.0.0/pve-plugin-smbgateway_1.0.0-1_all.deb
sudo dpkg -i pve-plugin-smbgateway_1.0.0-1_all.deb
sudo systemctl restart pveproxy
```

## 🖥️ **Create Your First Share (1 minute)**

1. **Navigate** to Datacenter → Storage → Add → SMB Gateway
2. **Configure**:
   - **Storage ID**: `myshare`
   - **Share Name**: `My Share`
   - **Deployment Mode**: `LXC` (recommended)
   - **Path**: `/srv/smb/myshare`
   - **Quota**: `10G` (optional)
3. **Click Create**

## 🔗 **Access Your Share**

Once created, access from any client:
- **Windows**: `\\your-proxmox-ip\myshare`
- **macOS**: `smb://your-proxmox-ip/myshare`
- **Linux**: `smb://your-proxmox-ip/myshare`

## 🖥️ **CLI Management**

```bash
# List all shares
pve-smbgateway list

# Create share with CLI
pve-smbgateway create myshare --mode lxc --path /srv/smb/myshare --quota 10G

# Check status
pve-smbgateway status myshare

# Delete share
pve-smbgateway delete myshare
```

## 🏗️ **Deployment Modes**

### **LXC Mode (Recommended)**
- **Lightweight**: ~80MB RAM
- **Fast**: < 30 seconds to create
- **Isolated**: Container-based
- **Best for**: Most use cases

### **Native Mode**
- **Performance**: Direct host installation
- **Low overhead**: Minimal resources
- **Best for**: High-performance needs

### **VM Mode**
- **Full isolation**: Dedicated VM
- **Custom resources**: Configurable RAM/CPU
- **Best for**: Maximum security

## 🔐 **Enterprise Features**

### **Active Directory Integration**
```bash
# Create share with AD
pve-smbgateway create adshare \
  --mode lxc \
  --path /srv/smb/ad \
  --ad-domain example.com \
  --ad-join \
  --ad-username Administrator \
  --ad-password mypassword
```

### **High Availability (CTDB)**
```bash
# Create HA share
pve-smbgateway create hashare \
  --mode lxc \
  --path /srv/smb/ha \
  --ctdb-vip 192.168.1.100 \
  --ha-enabled
```

### **Quota Management**
```bash
# Create share with quota
pve-smbgateway create quotashare \
  --mode lxc \
  --path /srv/smb/quota \
  --quota 100G

# Check quota usage
pve-smbgateway status quotashare
```

## 📊 **Monitoring**

### **Real-time Status**
```bash
# Check share status with metrics
pve-smbgateway status myshare --include-metrics

# Get I/O statistics
pve-smbgateway metrics current myshare
```

### **Historical Data**
```bash
# Get 24-hour trends
pve-smbgateway metrics history myshare --hours 24

# Get weekly summary
pve-smbgateway metrics summary myshare --days 7
```

## 🔧 **Common Tasks**

### **Batch Operations**
```bash
# Create multiple shares from config file
pve-smbgateway batch create --config shares.json
```

### **Configuration File Example**
```json
{
  "shares": [
    {
      "name": "documents",
      "mode": "lxc",
      "path": "/srv/smb/documents",
      "quota": "50G"
    },
    {
      "name": "backups",
      "mode": "lxc", 
      "path": "/srv/smb/backups",
      "quota": "200G"
    }
  ]
}
```

### **Testing AD Integration**
```bash
# Test domain connectivity
pve-smbgateway ad-test --domain example.com --username admin --password pass
```

### **Testing HA Failover**
```bash
# Test HA failover
pve-smbgateway ha-test --vip 192.168.1.100 --share myshare
```

## 🚨 **Troubleshooting**

### **Share Not Accessible**
```bash
# Check share status
pve-smbgateway status myshare

# Check SMB service
pve-smbgateway service status myshare

# Check firewall
sudo ufw status
```

### **Permission Issues**
```bash
# Check directory permissions
ls -la /srv/smb/

# Fix permissions
sudo chown -R 100000:100000 /srv/smb/
sudo chmod 755 /srv/smb/
```

### **AD Join Fails**
```bash
# Test AD connectivity
pve-smbgateway ad-test --domain example.com

# Check DNS resolution
nslookup example.com

# Check time sync
timedatectl status
```

## 📈 **Performance Tips**

### **Optimize for Speed**
```bash
# Use LXC mode for most shares
pve-smbgateway create fastshare --mode lxc --path /srv/smb/fast

# Use native mode for high-performance needs
pve-smbgateway create perfshare --mode native --path /srv/smb/perf
```

### **Resource Allocation**
```bash
# Customize LXC resources
pve-smbgateway create customshare \
  --mode lxc \
  --path /srv/smb/custom \
  --lxc-memory 256 \
  --lxc-cores 2
```

## 🎯 **Production Checklist**

### **Before Going Live**
- [ ] Test share creation and access
- [ ] Verify quota enforcement
- [ ] Test AD integration (if using)
- [ ] Test HA failover (if using)
- [ ] Set up monitoring alerts
- [ ] Configure backup schedules

### **Security Best Practices**
- [ ] Use AD authentication when possible
- [ ] Enable SMB signing
- [ ] Set appropriate quotas
- [ ] Monitor access logs
- [ ] Regular security updates

## 📞 **Support**

### **Community Support**
- **GitHub Issues**: Bug reports and feature requests
- **Proxmox Forum**: Community discussion
- **Documentation**: Complete guides in `/docs/`

### **Professional Support**
- **Email**: eric@gozippy.com
- **Commercial License**: Enterprise features and support
- **Custom Development**: Tailored solutions

## 🏆 **Success Metrics**

### **What You Should See**
- ✅ **Share Creation**: < 30 seconds for LXC mode
- ✅ **Performance**: > 50 MB/s typical throughput
- ✅ **Resource Usage**: < 100MB RAM per share
- ✅ **Reliability**: 99.9% uptime with HA
- ✅ **Management**: Simple web interface and CLI

### **ROI for Administrators**
- **Time Savings**: No more NAS VM management
- **Resource Efficiency**: 80% less RAM usage
- **Integration**: Seamless Proxmox workflow
- **Scalability**: Easy to add more shares

---

**Ready to simplify your SMB storage management?** 🚀

*The PVE SMB Gateway makes SMB shares as easy as creating a VM or container in Proxmox.* 