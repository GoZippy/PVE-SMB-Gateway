FROM debian:12-slim

# Install Proxmox VE dependencies and testing tools
RUN apt-get update && apt-get install -y \
    perl \
    libtest-more-perl \
    libtest-mockmodule-perl \
    samba \
    ctdb \
    fio \
    smbclient \
    curl \
    wget \
    git \
    build-essential \
    devscripts \
    debhelper \
    dh-systemd \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js for frontend testing
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Install testing frameworks
RUN npm install -g mocha chai sinon jsdom

# Create test user
RUN useradd -m -s /bin/bash testuser

# Create test directories
RUN mkdir -p /srv/smb/test-shares \
    /var/log/pve-smbgateway \
    /tmp/test-results

# Copy test scripts
COPY scripts/ /opt/pve-smbgateway/scripts/
COPY t/ /opt/pve-smbgateway/t/
COPY PVE/ /opt/pve-smbgateway/PVE/
COPY sbin/ /opt/pve-smbgateway/sbin/

# Make scripts executable
RUN chmod +x /opt/pve-smbgateway/scripts/*.sh \
    && chmod +x /opt/pve-smbgateway/sbin/*

# Create mock Proxmox environment
RUN mkdir -p /etc/pve \
    && echo "8.0.0" > /etc/pve/version \
    && mkdir -p /etc/pve/nodes/$(hostname) \
    && mkdir -p /var/lib/pve-cluster

# Create mock cluster configuration
RUN echo "cluster: test-cluster" > /etc/pve/cluster.conf \
    && echo "nodeid: 1" >> /etc/pve/cluster.conf \
    && echo "quorum_votes: 1" >> /etc/pve/cluster.conf

# Setup Samba test configuration
RUN echo '[global]' > /etc/samba/smb.conf && \
    echo '   workgroup = WORKGROUP' >> /etc/samba/smb.conf && \
    echo '   server string = Test SMB Server' >> /etc/samba/smb.conf && \
    echo '   security = user' >> /etc/samba/smb.conf && \
    echo '   map to guest = bad user' >> /etc/samba/smb.conf && \
    echo '   dns proxy = no' >> /etc/samba/smb.conf && \
    echo '   log level = 1' >> /etc/samba/smb.conf && \
    echo '   log file = /var/log/samba/%m.log' >> /etc/samba/smb.conf && \
    echo '   max log size = 50' >> /etc/samba/smb.conf && \
    echo '   server role = standalone server' >> /etc/samba/smb.conf && \
    echo '   passdb backend = tdbsam' >> /etc/samba/smb.conf && \
    echo '   unix charset = UTF-8' >> /etc/samba/smb.conf && \
    echo '   dos charset = CP850' >> /etc/samba/smb.conf && \
    echo '   guest account = nobody' >> /etc/samba/smb.conf && \
    echo '   guest ok = yes' >> /etc/samba/smb.conf && \
    echo '   guest only = no' >> /etc/samba/smb.conf && \
    echo '' >> /etc/samba/smb.conf && \
    echo '[test-share]' >> /etc/samba/smb.conf && \
    echo '   path = /srv/smb/test-shares' >> /etc/samba/smb.conf && \
    echo '   browseable = yes' >> /etc/samba/smb.conf && \
    echo '   read only = no' >> /etc/samba/smb.conf && \
    echo '   guest ok = yes' >> /etc/samba/smb.conf && \
    echo '   create mask = 0644' >> /etc/samba/smb.conf && \
    echo '   directory mask = 0755' >> /etc/samba/smb.conf

# Create test entrypoint
RUN cat > /opt/pve-smbgateway/test-entrypoint.sh << 'EOF'
#!/bin/bash

# Start Samba services
echo "Starting Samba services..."
smbd -D
nmbd -D

# Start CTDB if configured
if [ -f /etc/ctdb/ctdb.conf ]; then
    echo "Starting CTDB..."
    ctdbd -D
fi

# Run tests based on environment variable
case "${TEST_TYPE:-all}" in
    "unit")
        echo "Running unit tests..."
        cd /opt/pve-smbgateway && prove -v t/
        ;;
    "integration")
        echo "Running integration tests..."
        cd /opt/pve-smbgateway && ./scripts/test_integration.sh
        ;;
    "cluster")
        echo "Running cluster tests..."
        cd /opt/pve-smbgateway && ./scripts/automated_cluster_test.sh
        ;;
    "all")
        echo "Running all tests..."
        cd /opt/pve-smbgateway && ./scripts/run_all_tests.sh
        ;;
    *)
        echo "Unknown test type: ${TEST_TYPE}"
        echo "Available types: unit, integration, cluster, all"
        exit 1
        ;;
esac

# Keep container running for interactive testing
if [ "${KEEP_ALIVE:-false}" = "true" ]; then
    echo "Keeping container alive for interactive testing..."
    tail -f /dev/null
fi
EOF

RUN chmod +x /opt/pve-smbgateway/test-entrypoint.sh

# Set working directory
WORKDIR /opt/pve-smbgateway

# Expose test results directory
VOLUME ["/tmp/test-results"]

# Default command
CMD ["/opt/pve-smbgateway/test-entrypoint.sh"] 