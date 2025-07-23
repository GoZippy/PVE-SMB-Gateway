# Automated Testing Guide for PVE SMB Gateway

This document provides a comprehensive guide for automating testing of the PVE SMB Gateway within Proxmox cluster environments.

## Overview

The PVE SMB Gateway project includes a robust automated testing framework designed to validate functionality across different deployment scenarios:

- **Unit Tests**: Perl-based tests for individual components
- **Integration Tests**: End-to-end workflow validation
- **Cluster Tests**: Multi-node Proxmox cluster testing
- **Performance Tests**: Benchmarking and regression detection
- **HA Tests**: High availability and failover validation

## Quick Start

### 1. Local Development Testing

```bash
# Run all tests locally
make test-all

# Run specific test categories
make test              # Unit tests only
make test-integration  # Integration tests
make test-cluster      # Cluster tests
make test-performance  # Performance benchmarks
make test-ha          # HA failover tests
```

### 2. Docker-based Testing

```bash
# Run tests in isolated Docker environment
make test-docker

# Or manually with Docker Compose
docker-compose -f docker-compose.test.yml up --build
```

### 3. Real Cluster Testing

```bash
# Configure cluster nodes
export CLUSTER_NODES="192.168.1.10 192.168.1.11 192.168.1.12"
export CLUSTER_VIP="192.168.1.100"

# Run automated cluster test
./scripts/automated_cluster_test.sh
```

## Test Architecture

### Test Categories

#### 1. Unit Tests (`t/` directory)
- **Purpose**: Test individual Perl modules and functions
- **Framework**: Test::More with Test::MockModule
- **Coverage**: Storage plugin, CLI commands, monitoring functions
- **Execution**: `prove -v t/`

#### 2. Integration Tests (`scripts/test_*.sh`)
- **Purpose**: End-to-end workflow validation
- **Coverage**: Share creation, SMB connectivity, user management
- **Dependencies**: Real Samba services, Proxmox environment

#### 3. Cluster Tests (`scripts/automated_cluster_test.sh`)
- **Purpose**: Multi-node cluster validation
- **Coverage**: Node connectivity, HA failover, load distribution
- **Requirements**: 3+ node Proxmox cluster

#### 4. Performance Tests (`scripts/test_performance_benchmarks.sh`)
- **Purpose**: Performance benchmarking and regression detection
- **Tools**: fio, custom benchmarks
- **Output**: JSON reports with statistical analysis

#### 5. HA Tests (`scripts/test_ha_failover.sh`)
- **Purpose**: High availability validation
- **Coverage**: Service failover, CTDB clustering, VIP management

## CI/CD Integration

### GitHub Actions Workflow

The project includes a comprehensive GitHub Actions workflow (`/.github/workflows/cluster-test.yml`) that:

1. **Runs unit tests** on GitHub runners
2. **Deploys to test cluster** via SSH
3. **Executes integration tests** on real Proxmox nodes
4. **Collects and reports results** as artifacts

### Configuration

Set up the following secrets in your GitHub repository:

```bash
CLUSTER_SSH_KEY          # SSH private key for cluster access
CLUSTER_NODES            # Comma-separated list of cluster node IPs
AD_DOMAIN               # Active Directory domain for testing
AD_USERNAME             # AD test user
AD_PASSWORD             # AD test password
```

### Manual Trigger

You can manually trigger the workflow with custom parameters:

```yaml
# Example workflow dispatch
workflow_dispatch:
  inputs:
    cluster_nodes:
      description: 'Comma-separated list of cluster node IPs'
      required: true
      default: '192.168.1.10,192.168.1.11,192.168.1.12'
    test_environment:
      description: 'Test environment type'
      required: true
      default: 'staging'
      type: choice
      options:
      - staging
      - production-simulated
```

## Docker Testing Environment

### Local Docker Setup

The project includes a Docker-based testing environment that simulates a Proxmox cluster:

```bash
# Build and run test environment
docker-compose -f docker-compose.test.yml up --build

# Run specific test types
docker run -e TEST_TYPE=unit pve-smbgateway-test
docker run -e TEST_TYPE=integration pve-smbgateway-test
docker run -e TEST_TYPE=cluster pve-smbgateway-test
```

### Test Environment Features

- **Mock Proxmox Environment**: Simulates `/etc/pve` structure
- **Samba Services**: Real SMB/CIFS services for testing
- **CTDB Support**: Clustered Samba testing
- **Performance Tools**: fio, iostat, and custom benchmarks
- **Test Frameworks**: Mocha, Chai, Sinon for JavaScript tests

## Performance Testing

### Automated Performance Analysis

The project includes a Python-based performance analyzer (`scripts/analyze_performance.py`):

```bash
# Analyze performance results
python3 scripts/analyze_performance.py performance-results.json

# Compare against baseline
python3 scripts/analyze_performance.py performance-results.json --baseline baseline.json

# Generate detailed report
python3 scripts/analyze_performance.py performance-results.json --output report.txt
```

### Performance Metrics

The analyzer tracks:

- **IOPS**: Input/Output operations per second
- **Throughput**: Data transfer rates (MB/s)
- **Latency**: Response times (ms)
- **Overall Score**: Weighted performance metric

### Regression Detection

The system automatically detects performance regressions:

- **High Severity**: >50% performance degradation
- **Medium Severity**: 25-50% degradation
- **Low Severity**: 10-25% degradation

## Cluster Testing Scenarios

### 1. Basic Cluster Validation

```bash
# Test cluster connectivity and basic functionality
./scripts/automated_cluster_test.sh
```

**Tests Include:**
- Node connectivity verification
- SMB Gateway installation validation
- Share creation in all modes (LXC, Native, VM)
- SMB connectivity testing

### 2. HA Failover Testing

```bash
# Test high availability scenarios
./scripts/test_ha_failover.sh
```

**Tests Include:**
- Service failover validation
- CTDB cluster health checks
- VIP failover testing
- Data consistency verification

### 3. Performance Benchmarking

```bash
# Run comprehensive performance tests
./scripts/test_performance_benchmarks.sh
```

**Tests Include:**
- Sequential read/write performance
- Random I/O performance
- Concurrent access testing
- Network latency measurement

### 4. Security Testing

```bash
# Test security configurations
./scripts/test_security.sh
```

**Tests Include:**
- SMB protocol version enforcement
- Authentication mechanisms
- Access control validation
- Encryption verification

## Test Configuration

### Environment Variables

Configure test behavior using environment variables:

```bash
# Cluster configuration
export CLUSTER_NODES="192.168.1.10 192.168.1.11 192.168.1.12"
export CLUSTER_VIP="192.168.1.100"

# Active Directory configuration
export AD_DOMAIN="test.example.com"
export AD_USERNAME="Administrator"
export AD_PASSWORD="TestPassword123!"

# Test configuration
export TEST_SHARES="test-share1 test-share2 test-share3"
export TEST_PATHS="/srv/smb/test1 /srv/smb/test2 /srv/smb/test3"
```

### Test Configuration Files

Create custom test configurations:

```json
{
  "test_environment": {
    "cluster_nodes": ["192.168.1.10", "192.168.1.11", "192.168.1.12"],
    "ad_domain": "test.example.com",
    "vip_address": "192.168.1.100",
    "test_shares": [
      {
        "name": "test-lxc-integration",
        "mode": "lxc",
        "path": "/tmp/test-lxc",
        "quota": "1G"
      }
    ]
  }
}
```

## Test Results and Reporting

### Report Formats

The testing framework generates multiple report formats:

1. **HTML Reports**: Human-readable test summaries
2. **JSON Reports**: Machine-readable data for CI/CD integration
3. **Console Output**: Real-time test progress and results
4. **Log Files**: Detailed execution logs for debugging

### Result Analysis

```bash
# View test results
ls -la /tmp/pve-smbgateway-cluster-test-results/

# Analyze performance
python3 scripts/analyze_performance.py performance-results.json

# Generate summary report
cat /tmp/pve-smbgateway-cluster-test-results/reports/*.html
```

### Integration with Monitoring

Test results can be integrated with monitoring systems:

```bash
# Send results to monitoring system
curl -X POST \
  -H "Content-Type: application/json" \
  -d @test-results.json \
  https://monitoring.example.com/api/test-results
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**
   ```bash
   # Verify SSH connectivity
   ssh -i ~/.ssh/id_rsa root@cluster-node ping -c 1 localhost
   ```

2. **Samba Service Issues**
   ```bash
   # Check Samba status
   systemctl status smbd nmbd
   
   # Restart services
   systemctl restart smbd nmbd
   ```

3. **Cluster Configuration Problems**
   ```bash
   # Verify cluster status
   pvecm status
   
   # Check cluster configuration
   cat /etc/pve/cluster.conf
   ```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Enable debug logging
export DEBUG=1
export VERBOSE=1

# Run tests with debug output
./scripts/automated_cluster_test.sh
```

### Test Isolation

Run tests in isolation to avoid interference:

```bash
# Use isolated test directories
export TEST_ISOLATION=1
export TEST_CLEANUP=1

# Run isolated tests
./scripts/automated_cluster_test.sh
```

## Best Practices

### 1. Test Environment Setup

- Use dedicated test clusters when possible
- Maintain consistent test environments
- Document environment configurations
- Use version control for test configurations

### 2. Test Execution

- Run tests during off-peak hours
- Monitor system resources during testing
- Implement proper cleanup procedures
- Use timeouts to prevent hanging tests

### 3. Result Management

- Archive test results for historical analysis
- Implement baseline performance tracking
- Set up automated alerting for failures
- Regular review of test coverage

### 4. Continuous Improvement

- Regularly update test scenarios
- Incorporate new features into test suite
- Optimize test execution time
- Gather feedback from test results

## Contributing to Testing

### Adding New Tests

1. **Unit Tests**: Add to `t/` directory using Test::More
2. **Integration Tests**: Create new scripts in `scripts/` directory
3. **Performance Tests**: Extend `test_performance_benchmarks.sh`
4. **Documentation**: Update this guide with new test procedures

### Test Standards

- Follow existing naming conventions
- Include proper error handling
- Implement cleanup procedures
- Add comprehensive logging
- Document test requirements

### Test Review Process

- Code review for all test changes
- Validation of test coverage
- Performance impact assessment
- Documentation updates

## Support and Resources

### Documentation

- [Test Plan](TEST_PLAN.md): Detailed test planning
- [Testing Report](Testing_Report.md): Current test status
- [Architecture](ARCHITECTURE.md): System architecture overview

### Tools and Utilities

- `scripts/run_all_tests.sh`: Master test runner
- `scripts/automated_cluster_test.sh`: Cluster test automation
- `scripts/analyze_performance.py`: Performance analysis
- `Makefile`: Build and test targets

### Community

- GitHub Issues: Report bugs and request features
- Discussions: Share testing experiences and best practices
- Wiki: Community-maintained documentation

---

*For questions or support with automated testing, please open an issue on GitHub or contact the development team.* 