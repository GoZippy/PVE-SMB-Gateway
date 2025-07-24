# Getting Started with PVE SMB Gateway Testing

Welcome to the PVE SMB Gateway! This guide will walk you through testing the SMB Gateway on your Proxmox cluster step by step, like setting up a science experiment. No advanced knowledge required!

## 🎯 What We're Going to Do

We're going to test if the SMB Gateway works properly on your cluster by:
1. Setting up the testing environment
2. Running automated tests
3. Checking the results
4. Understanding what everything means

## 📋 Prerequisites (Stuff You Need First)

Before we start, make sure you have:

1. **A Proxmox cluster** with at least 2 nodes (3 is better)
2. **SSH access** to all your cluster nodes
3. **Root or sudo access** on all nodes
4. **Basic command line knowledge** (you know how to type commands)

## 🚀 Step 1: Get the Code

First, let's get the testing code onto your computer:

### Option A: Clone from GitHub (for developers)
```bash
# Open your terminal/command prompt and type:
git clone https://github.com/GoZippy/PVE-SMB-Gateway.git
cd proxmox-smb-gateway
```

### Option B: Download Pre-compiled Release (for users)
1. Go to the [Releases page](https://github.com/GoZippy/PVE-SMB-Gateway/releases)
2. Download the latest release ZIP file
3. Extract it to a folder on your computer
4. Open terminal/command prompt in that folder

**What to expect:** You'll see a bunch of files. This is normal!

## 🔧 Step 2: Set Up Your Cluster Information

Now we need to tell the tests about your cluster. Think of this like filling out a form:

```bash
# Replace these IP addresses with your actual cluster node IPs
export CLUSTER_NODES="192.168.1.10 192.168.1.11 192.168.1.12"
export CLUSTER_VIP="192.168.1.100"
```

**What to expect:** Nothing visible happens, but the computer now knows about your cluster.

**💡 Pro tip:** If you're not sure of your node IPs, you can check by running `ip addr show` on each node.

## 🔑 Step 3: Set Up SSH Keys (If You Haven't Already)

The tests need to connect to your cluster nodes. Let's make sure SSH works:

```bash
# Test if you can connect to your first node
ssh root@192.168.1.10 "echo 'Connection successful!'"
```

**What to expect:** 
- If it works: You'll see "Connection successful!"
- If it asks for a password: Type your password
- If it fails: You might need to set up SSH keys

**If SSH doesn't work, here's how to fix it:**

```bash
# Generate an SSH key (if you don't have one)
ssh-keygen -t rsa -b 4096

# Copy your key to all cluster nodes
ssh-copy-id root@192.168.1.10
ssh-copy-id root@192.168.1.11
ssh-copy-id root@192.168.1.12
```

## 📦 Step 4: Install the SMB Gateway Plugin

Now let's install the actual SMB Gateway on your cluster:

### For Pre-compiled Releases:
```bash
# Install on all nodes (replace with your actual node IPs)
for node in 192.168.1.10 192.168.1.11 192.168.1.12; do
    echo "Installing on $node..."
    scp pve-plugin-smbgateway_*.deb root@$node:/tmp/
    ssh root@$node "dpkg -i /tmp/pve-plugin-smbgateway_*.deb && systemctl restart pveproxy"
done
```

### For Source Code (if you cloned the repo):
```bash
# Build the plugin package
make deb

# Install on all nodes
for node in 192.168.1.10 192.168.1.11 192.168.1.12; do
    echo "Installing on $node..."
    scp ../pve-plugin-smbgateway_*.deb root@$node:/tmp/
    ssh root@$node "dpkg -i /tmp/pve-plugin-smbgateway_*.deb && systemctl restart pveproxy"
done
```

**What to expect:** You'll see installation messages for each node. Look for "Setting up pve-plugin-smbgateway" messages.

## 🧪 Step 5: Run the Basic Tests

Let's start with a simple test to make sure everything is working:

```bash
# Run the automated cluster test
./scripts/automated_cluster_test.sh
```

**What to expect:** You'll see a lot of output like this:
```
[HEADER] Starting PVE SMB Gateway Cluster Test Suite
[INFO] Setting up test environment...
[INFO] Testing Cluster Connectivity
[PASS] Cluster Node Connectivity
[INFO] Testing SMB Gateway Installation
[PASS] SMB Gateway Installation
```

**⏱️ This might take 5-10 minutes to complete.**

## 📊 Step 6: Check the Results

After the tests finish, let's see what happened:

```bash
# Look at the test results
ls -la /tmp/pve-smbgateway-cluster-test-results/

# Read the summary
cat /tmp/pve-smbgateway-cluster-test-results/reports/*.html
```

**What to expect:** 
- A list of files with test results
- An HTML report showing what passed and failed
- Numbers showing how many tests ran

## 🎯 Step 7: Understand What the Tests Did

The tests checked several things:

### ✅ **What Should Have Passed:**
- **Cluster Connectivity**: Can all nodes talk to each other?
- **SMB Gateway Installation**: Is the plugin installed correctly?
- **Share Creation**: Can we create SMB shares in different modes?
- **SMB Connectivity**: Can we connect to the shares?

### ⚠️ **What Might Have Failed:**
- **HA Failover**: If you don't have proper cluster setup
- **Performance Tests**: If your hardware is slower than expected
- **Security Tests**: If SMB1 protocol is enabled

## 🎯 Step 8: Run Specific Test Categories

Want to test specific things? Here are some options:

```bash
# Test just the basic functionality
make test

# Test integration (more complex scenarios)
make test-integration

# Test high availability (failover scenarios)
make test-ha

# Test performance (benchmarks)
make test-performance
```

**What to expect:** Each test type focuses on different aspects and takes different amounts of time.

## 🐳 Step 9: Try Docker Testing (Optional)

If you want to test in an isolated environment first:

```bash
# Make sure Docker is installed
docker --version

# Run tests in Docker
make test-docker
```

**What to expect:** Docker will build containers and run tests inside them. This is safer but slower.

## 📈 Step 10: Analyze Performance Results

If you ran performance tests, let's analyze them:

```bash
# Look for performance results
find /tmp -name "*performance*" -type f

# Analyze the results (if you have Python installed)
python3 scripts/analyze_performance.py /tmp/performance-results.json
```

**What to expect:** 
- Performance numbers (IOPS, throughput, latency)
- Comparison with baselines
- Recommendations if performance is poor

## 🚨 Troubleshooting Common Issues

### Problem: "SSH connection failed"
**Solution:**
```bash
# Test SSH manually
ssh root@your-node-ip "echo test"

# If it asks for password, set up SSH keys:
ssh-keygen -t rsa
ssh-copy-id root@your-node-ip
```

### Problem: "SMB Gateway not installed"
**Solution:**
```bash
# Check if the package exists
ls -la pve-plugin-smbgateway_*.deb

# If not, and you have source code, build it:
make deb
```

### Problem: "Cluster not found"
**Solution:**
```bash
# Check cluster status on each node
ssh root@your-node-ip "pvecm status"
```

### Problem: "Permission denied"
**Solution:**
```bash
# Make sure you're running as root or with sudo
sudo ./scripts/automated_cluster_test.sh
```

### Problem: "Script not found"
**Solution:**
```bash
# Make sure you're in the right directory
pwd
ls -la scripts/

# Make scripts executable
chmod +x scripts/*.sh
```

## 📋 What Each Test Actually Does

### 🔗 **Cluster Connectivity Test**
- Pings all your cluster nodes
- Makes sure they can talk to each other
- **What you'll see:** "Node 192.168.1.10 is reachable"

### 📦 **Installation Test**
- Checks if the SMB Gateway plugin is loaded
- Verifies it appears in the Proxmox web interface
- **What you'll see:** "SMB Gateway plugin is installed and loaded"

### 🗂️ **Share Creation Test**
- Creates test shares in LXC, Native, and VM modes
- Tests different storage configurations
- **What you'll see:** "Successfully created test-share in lxc mode"

### 🔌 **SMB Connectivity Test**
- Tries to connect to the shares using SMB client
- Tests guest access and authentication
- **What you'll see:** "Successfully connected to test-share"

### ⚡ **Performance Test**
- Runs file I/O benchmarks using fio
- Measures read/write speeds and latency
- **What you'll see:** "IOPS: 1500, Throughput: 100 MB/s"

### 🔄 **HA Failover Test**
- Stops services on one node
- Checks if they fail over to another node
- **What you'll see:** "Services failed over successfully"

## ✅ Success Indicators

You'll know everything is working when you see:
- ✅ All tests show "PASS"
- 📊 Performance numbers are reasonable
- 🔄 HA failover works (if you have a proper cluster)
- 📝 HTML report shows green checkmarks

## 📞 Getting Help

If something goes wrong:

1. **Check the logs:**
   ```bash
   cat /tmp/pve-smbgateway-cluster-test-results/logs/test.log
   ```

2. **Run with debug mode:**
   ```bash
   export DEBUG=1
   ./scripts/automated_cluster_test.sh
   ```

3. **Ask for help:** Create an issue on GitHub with your error messages

## 🎯 Next Steps

Once testing is successful:
1. **Deploy to production** (if you're ready)
2. **Set up monitoring** to watch performance
3. **Configure Active Directory** (if needed)
4. **Set up regular testing** in your CI/CD pipeline

## 📚 Additional Resources

- [User Guide](USER_GUIDE.md) - Detailed usage instructions
- [Administrator Guide](ADMINISTRATOR_BENEFITS.md) - Advanced configuration
- [Architecture](ARCHITECTURE.md) - How the system works
- [Troubleshooting](Project_Fix_Action_Plan.md) - Common problems and solutions

## 🤝 Contributing

Found a bug or have an idea for improvement?
1. Check the [Contributing Guide](CONTRIBUTING.md)
2. Create an issue on GitHub
3. Submit a pull request

---

**Remember:** Testing is like doing a science experiment - you're trying to prove that your system works correctly. Don't worry if some tests fail at first; that's how you learn what needs to be fixed!

Good luck with your testing! 🚀 