# PVE SMB Gateway - Quick Start Guide

## 🚀 Fast Setup (5 minutes)

### 1. Set your cluster info
```bash
export CLUSTER_NODES="192.168.1.10 192.168.1.11 192.168.1.12"
export CLUSTER_VIP="192.168.1.100"
```

### 2. Test SSH connection
```bash
ssh root@192.168.1.10 "echo 'Connection successful!'"
```

### 3. Install the plugin
```bash
for node in 192.168.1.10 192.168.1.11 192.168.1.12; do
    scp pve-plugin-smbgateway_*.deb root@$node:/tmp/
    ssh root@$node "dpkg -i /tmp/pve-plugin-smbgateway_*.deb && systemctl restart pveproxy"
done
```

### 4. Run tests
```bash
./scripts/automated_cluster_test.sh
```

### 5. Check results
```bash
ls -la /tmp/pve-smbgateway-cluster-test-results/
```

## 📋 What You Need
- Proxmox cluster (2+ nodes)
- SSH access to all nodes
- Root/sudo access

## 🚨 Common Issues

**SSH fails?**
```bash
ssh-keygen -t rsa
ssh-copy-id root@your-node-ip
```

**Script not found?**
```bash
chmod +x scripts/*.sh
```

**Permission denied?**
```bash
sudo ./scripts/automated_cluster_test.sh
```

## 📊 Expected Results
- ✅ All tests show "PASS"
- 📝 HTML report in `/tmp/pve-smbgateway-cluster-test-results/reports/`
- 🔄 HA failover works (if cluster is set up)

## 📚 More Info
- [Full Getting Started Guide](docs/GETTING_STARTED.md)
- [User Guide](docs/USER_GUIDE.md)
- [Troubleshooting](docs/Project_Fix_Action_Plan.md)

## 🆘 Need Help?
1. Check logs: `cat /tmp/pve-smbgateway-cluster-test-results/logs/test.log`
2. Run debug mode: `export DEBUG=1 && ./scripts/automated_cluster_test.sh`
3. Create GitHub issue with error messages

---

**Quick Test Commands:**
```bash
make test              # Unit tests only
make test-integration  # Integration tests  
make test-ha          # HA failover tests
make test-performance # Performance benchmarks
``` 