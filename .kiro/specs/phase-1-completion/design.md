# Design Document - Phase 1 Completion

## Overview

This design document outlines the technical implementation for completing Phase 1 of the PVE SMB Gateway Plugin. The focus is on implementing missing core features (VM mode, enhanced HA, monitoring) while maintaining the existing lightweight architecture and preparing the foundation for Phase 2's Storage Service Launcher.

## Architecture

### Current Architecture (v0.1.0)
```
ExtJS Wizard → REST API → Perl Storage Plugin → [LXC|Native] Provisioner → Samba Service
```

### Enhanced Architecture (Phase 1 Complete)
```
ExtJS Wizard → REST API → Perl Storage Plugin → [LXC|Native|VM] Provisioner → Samba Service
                                            ↓
                                    [CTDB HA Layer] → VIP Management
                                            ↓
                                    [Monitoring Layer] → Metrics API
                                            ↓
                                    [Backup Integration] → Proxmox Backup
```

## Components and Interfaces

### 1. VM Provisioner Implementation

#### VM Template Management
```perl
# New methods in SMBGateway.pm
sub _find_vm_template {
    my ($self) = @_;
    # Search for SMB gateway templates in order of preference
    my @templates = (
        'local:vztmpl/smb-gateway-debian12.qcow2',
        'local:vztmpl/smb-gateway-ubuntu22.qcow2'
    );
    return $self->_select_available_template(@templates);
}

sub _create_vm_template {
    my ($self) = @_;
    # Auto-build template if none exists
    # Use cloud-init with Samba pre-installed
}
```

#### VM Provisioning Workflow
1. **Template Selection**: Find or create SMB gateway VM template
2. **VM Creation**: Clone template with appropriate resources (2GB RAM, 20GB disk)
3. **Storage Attachment**: Attach target storage as virtio-fs or additional disk
4. **Network Configuration**: Configure bridge networking with optional VIP
5. **Service Configuration**: Use cloud-init to configure Samba with share settings

#### Storage Attachment Strategies
- **VirtIO-FS**: For ZFS datasets (best performance)
- **RBD Mapping**: For Ceph storage (native integration)
- **NFS Mount**: For other storage types (compatibility)

### 2. CTDB High Availability Layer

#### CTDB Configuration Management
```perl
sub _setup_ctdb_cluster {
    my ($self, $nodes, $vip) = @_;
    
    # Generate CTDB configuration
    my $ctdb_config = $self->_generate_ctdb_config($nodes, $vip);
    
    # Deploy to all cluster nodes
    foreach my $node (@$nodes) {
        $self->_deploy_ctdb_config($node, $ctdb_config);
        $self->_start_ctdb_service($node);
    }
    
    # Validate cluster formation
    return $self->_validate_ctdb_cluster($nodes);
}
```

#### VIP Management
- **IP Assignment**: Automatic VIP assignment from available ranges
- **Health Monitoring**: Regular health checks with automatic failover
- **Client Notification**: SMB client notification of IP changes
- **Split-Brain Prevention**: Quorum-based decision making

### 3. Enhanced Monitoring System

#### Metrics Collection Architecture
```perl
# New monitoring module
package PVE::SMBGateway::Monitor;

sub collect_metrics {
    my ($self, $share_id) = @_;
    
    return {
        throughput => $self->_get_throughput_stats($share_id),
        connections => $self->_get_connection_count($share_id),
        storage_usage => $self->_get_storage_usage($share_id),
        error_rate => $self->_get_error_rate($share_id),
        timestamp => time()
    };
}
```

#### Metrics Storage
- **Time Series Data**: Store metrics in lightweight SQLite database
- **API Endpoints**: Expose metrics via Proxmox API at `/nodes/{node}/smbgateway/{share}/metrics`
- **Retention Policy**: Keep detailed metrics for 7 days, aggregated for 30 days
- **Export Format**: Prometheus-compatible metrics for external monitoring

### 4. Backup Integration Design

#### Snapshot Coordination
```perl
sub _create_backup_snapshot {
    my ($self, $share_id, $backup_job) = @_;
    
    # Coordinate with Proxmox backup system
    my $snapshot_name = "backup-" . time();
    
    if ($self->_is_lxc_mode($share_id)) {
        return $self->_backup_lxc_with_bindmount($share_id, $snapshot_name);
    } elsif ($self->_is_vm_mode($share_id)) {
        return $self->_backup_vm_with_storage($share_id, $snapshot_name);
    } else {
        return $self->_backup_native_storage($share_id, $snapshot_name);
    }
}
```

#### Backup Strategies by Mode
- **LXC Mode**: Container backup + ZFS snapshot of bind-mounted storage
- **VM Mode**: VM backup including attached storage devices
- **Native Mode**: Direct storage snapshot with metadata backup

### 5. Security Hardening Implementation

#### SMB Security Configuration
```perl
sub _generate_secure_smb_config {
    my ($self, $share_config) = @_;
    
    return {
        'min protocol' => 'SMB2',
        'server signing' => 'mandatory',
        'encrypt passwords' => 'yes',
        'security' => $share_config->{ad_domain} ? 'ads' : 'user',
        'restrict anonymous' => '2',
        'guest account' => 'nobody',
        'map to guest' => 'never'
    };
}
```

#### Container Security Profiles
- **AppArmor Profiles**: Custom profiles for Samba containers
- **Resource Limits**: CPU, memory, and I/O limits
- **Network Isolation**: Dedicated bridge networks where appropriate
- **User Namespace Mapping**: Unprivileged containers by default

### 6. Enhanced CLI Interface

#### Command Structure
```bash
pve-smbgateway [global-options] <command> [command-options]

Commands:
  list                    # List all shares with status
  create <name>          # Create new share
  delete <name>          # Delete share
  status <name>          # Show detailed share status
  metrics <name>         # Show performance metrics
  backup <name>          # Trigger backup
  failover <name>        # Manual failover (HA mode)
  template list          # List available VM templates
  template create        # Create new VM template
```

#### JSON Output Format
```json
{
  "success": true,
  "data": {
    "share_id": "myshare",
    "mode": "lxc",
    "status": "active",
    "metrics": {
      "throughput_mbps": 125.5,
      "connections": 3,
      "uptime_seconds": 86400
    }
  },
  "timestamp": "2025-07-22T10:30:00Z"
}
```

## Data Models

### Enhanced Share Configuration
```perl
# Extended properties in SMBGateway.pm
sub properties {
    return {
        # Existing properties
        mode      => { type => 'string', enum => ['native', 'lxc', 'vm'] },
        sharename => { type => 'string', format => 'pve-storage-id' },
        path      => { type => 'string', optional => 1 },
        quota     => { type => 'string', optional => 1 },
        ad_domain => { type => 'string', optional => 1 },
        
        # New properties
        ctdb_vip  => { type => 'string', optional => 1, format => 'ip' },
        ha_enabled => { type => 'boolean', optional => 1, default => 0 },
        monitoring_enabled => { type => 'boolean', optional => 1, default => 1 },
        backup_enabled => { type => 'boolean', optional => 1, default => 1 },
        security_profile => { type => 'string', enum => ['standard', 'high'], default => 'standard' },
        vm_template => { type => 'string', optional => 1 },
        vm_memory => { type => 'integer', optional => 1, default => 2048 },
        vm_cores => { type => 'integer', optional => 1, default => 2 }
    };
}
```

### Metrics Data Model
```perl
# Metrics storage schema
CREATE TABLE share_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    share_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    throughput_read REAL,
    throughput_write REAL,
    iops_read INTEGER,
    iops_write INTEGER,
    connections INTEGER,
    errors INTEGER,
    storage_used INTEGER,
    storage_total INTEGER
);
```

## Error Handling

### Rollback Strategy
```perl
sub _execute_with_rollback {
    my ($self, $operations, $rollback_steps) = @_;
    
    eval {
        foreach my $op (@$operations) {
            $op->execute();
            push @$rollback_steps, $op->get_rollback();
        }
    };
    
    if ($@) {
        $self->_execute_rollback($rollback_steps);
        die "Operation failed: $@";
    }
}
```

### Error Categories
1. **Configuration Errors**: Invalid parameters, missing dependencies
2. **Resource Errors**: Insufficient storage, memory, or network resources
3. **Service Errors**: Samba configuration, AD join failures
4. **Infrastructure Errors**: Node communication, storage backend issues

## Testing Strategy

### Unit Testing Expansion
```perl
# New test files
t/30-vm-provisioning.t     # VM mode creation and management
t/40-ctdb-ha.t            # CTDB clustering and failover
t/50-monitoring.t         # Metrics collection and API
t/60-backup-integration.t # Backup workflow testing
t/70-security.t           # Security configuration validation
```

### Integration Testing
- **Multi-node Testing**: 3-node cluster with real failover scenarios
- **Performance Testing**: Throughput and latency benchmarks
- **Security Testing**: Penetration testing and vulnerability scanning
- **Backup Testing**: Full backup and restore workflows

### Automated Testing Pipeline
```yaml
# .github/workflows/integration.yml
name: Integration Tests
on: [push, pull_request]
jobs:
  test-cluster:
    runs-on: ubuntu-latest
    steps:
      - name: Setup 3-node Proxmox cluster
      - name: Install plugin
      - name: Test all deployment modes
      - name: Test HA failover
      - name: Validate metrics collection
      - name: Test backup integration
```

## Performance Considerations

### Resource Optimization
- **Memory Usage**: Target <128MB per LXC container, <2GB per VM
- **CPU Efficiency**: Minimize background processes, optimize I/O paths
- **Network Performance**: Direct bridge connections, minimize packet processing
- **Storage Performance**: Optimize for sequential I/O patterns

### Scalability Targets
- **Concurrent Shares**: Support 50+ shares per node
- **Client Connections**: 100+ concurrent SMB connections per share
- **Throughput**: Within 15% of native storage performance
- **Failover Time**: <30 seconds for HA scenarios

## Migration and Upgrade Strategy

### Version Compatibility
- **Configuration Migration**: Automatic upgrade of storage.cfg entries
- **Data Preservation**: No data loss during plugin upgrades
- **Rollback Support**: Ability to downgrade to previous version
- **API Compatibility**: Maintain backward compatibility for CLI tools