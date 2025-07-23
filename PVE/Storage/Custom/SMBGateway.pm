package PVE::Storage::Custom::SMBGateway;

# PVE SMB Gateway Plugin
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# This plugin provides GUI-managed SMB/CIFS gateway functionality
# for Proxmox Virtual Environment storage backends.

use strict;
use warnings;
use base qw(PVE::Storage::Plugin);
use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);
use PVE::Exception qw(raise_param_exc);
use PVE::SMBGateway::Monitor;

# -------- mandatory identifiers --------
sub type        { 'smbgateway' }
sub plugindata  { { content => [ 'images', 'iso', 'backup', 'snippets' ] } }

sub properties {
    return {
        mode      => { type => 'string',  enum => [ 'native', 'lxc', 'vm' ] },
        sharename => { type => 'string',  format => 'pve-storage-id' },
        path      => { type => 'string',  optional => 1 },
        quota     => { type => 'string',  optional => 1 },
        ad_domain => { type => 'string',  optional => 1 },
        ad_join   => { type => 'boolean', optional => 1, default => 0 },
        ad_ou     => { type => 'string',  optional => 1 },
        ad_fallback => { type => 'boolean', optional => 1, default => 1 },
        ctdb_vip  => { type => 'string',  optional => 1 },
        ha_enabled => { type => 'boolean', optional => 1, default => 0 },
        ha_nodes  => { type => 'string',  optional => 1 },
        vm_memory => { type => 'integer', optional => 1, default => 2048 },
        vm_cores  => { type => 'integer', optional => 1, default => 2 },
        vm_template => { type => 'string', optional => 1 },
    };
}

# -------- storage lifecycle methods --------
sub activate_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    
    my $mode = $scfg->{mode} // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    
    if ($mode eq 'native') {
        _native_activate($sharename, $scfg);
    } elsif ($mode eq 'lxc') {
        _lxc_activate($sharename, $scfg);
    } elsif ($mode eq 'vm') {
        _vm_activate($sharename, $scfg);
    } else {
        die "Unknown mode: $mode";
    }
    
    return 1;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, %param) = @_;
    
    my $mode = $scfg->{mode} // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    
    if ($mode eq 'native') {
        _native_deactivate($sharename, $scfg);
    } elsif ($mode eq 'lxc') {
        _lxc_deactivate($sharename, $scfg);
    } elsif ($mode eq 'vm') {
        _vm_deactivate($sharename, $scfg);
    } else {
        die "Unknown mode: $mode";
    }
    
    return 1;
}

sub status {
    my ($class, $storeid, $scfg, %param) = @_;
    
    my $mode = $scfg->{mode} // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    my $path = $scfg->{path} // "/srv/smb/$sharename";
    my $quota = $scfg->{quota} // '';
    my $ha_enabled = $scfg->{ha_enabled} // 0;
    my $ctdb_vip = $scfg->{ctdb_vip} // '';
    
    # Get basic status based on mode
    my $status;
    if ($mode eq 'native') {
        $status = _native_status($sharename, $scfg);
    } elsif ($mode eq 'lxc') {
        $status = _lxc_status($sharename, $scfg);
    } elsif ($mode eq 'vm') {
        $status = _vm_status($sharename, $scfg);
    } else {
        $status = { status => 'unknown', message => "Unknown mode: $mode" };
    }
    
    # Add HA status if enabled
    if ($ha_enabled && $ctdb_vip) {
        my $self = 'PVE::Storage::Custom::SMBGateway';
        
        # Get cluster nodes
        my @nodes = ();
        if ($scfg->{ha_nodes} && $scfg->{ha_nodes} ne 'all') {
            @nodes = split /,/, $scfg->{ha_nodes};
        } else {
            # Get all cluster nodes
            eval {
                my $cluster_status = `pvesh get /cluster/status -output-format=json 2>/dev/null`;
                if ($cluster_status) {
                    # Parse JSON output
                    foreach my $line (split /\n/, $cluster_status) {
                        if ($line =~ /"name"\s*:\s*"([^"]+)"/) {
                            push @nodes, $1;
                        }
                    }
                } else {
                    # No cluster, just use local node
                    my $hostname = `hostname`;
                    chomp $hostname;
                    push @nodes, $hostname;
                }
            };
        }
        
        # Get VIP status
        my $vip_status = $self->_monitor_vip_health($ctdb_vip, \@nodes);
        
        # Add VIP status to overall status
        $status->{ha_enabled} = 1;
        $status->{ctdb_status} = $vip_status;
    }
    
    # Add quota information if quota is set
    if ($quota) {
        my $self = 'PVE::Storage::Custom::SMBGateway';
        
        # Get quota usage
        my $quota_usage = $self->_get_quota_usage($path);
        
        if ($quota_usage) {
            $status->{quota} = {
                limit => $quota_usage->{quota},
                used => $quota_usage->{used},
                percent => $quota_usage->{percent},
                filesystem_type => $quota_usage->{fs_type} || _get_fs_type($path),
                last_checked => time()
            };
            
            # Add error message if there was an error getting usage
            if ($quota_usage->{error}) {
                $status->{quota}->{error} = $quota_usage->{error};
            }
            
            # Add warning levels based on usage
            if ($quota_usage->{percent} >= 95) {
                $status->{quota}->{status} = 'critical';
                $status->{quota}->{warning} = "Critical: Quota usage is at $quota_usage->{percent}%";
            } elsif ($quota_usage->{percent} >= 85) {
                $status->{quota}->{status} = 'warning';
                $status->{quota}->{warning} = "Warning: Quota usage is at $quota_usage->{percent}%";
            } elsif ($quota_usage->{percent} >= 75) {
                $status->{quota}->{status} = 'notice';
                $status->{quota}->{warning} = "Notice: Quota usage is at $quota_usage->{percent}%";
            } else {
                $status->{quota}->{status} = 'ok';
            }
            
            # Add trend information if we have historical data
            my $trend = _get_quota_trend($path);
            if ($trend) {
                $status->{quota}->{trend} = $trend;
            }
        } else {
            $status->{quota} = {
                limit => $quota,
                used => 'unknown',
                percent => 0,
                status => 'unknown',
                error => 'Failed to get quota usage information',
                filesystem_type => _get_fs_type($path),
                last_checked => time()
            };
        }
    }
    
    # Add performance metrics if monitoring is enabled
    if ($param{include_metrics}) {
        eval {
            my $monitor = PVE::SMBGateway::Monitor->new();
            my $metrics = $monitor->collect_performance_metrics($sharename, $path, $quota);
            
            # Store metrics for historical tracking
            $monitor->store_metrics($metrics);
            
            # Add current metrics to status
            $status->{metrics} = {
                io_stats => $metrics->{io_stats},
                connection_stats => $metrics->{connection_stats},
                system_stats => $metrics->{system_stats},
                last_updated => time()
            };
        };
        
        # Add historical metrics if requested
        if ($param{include_history}) {
            eval {
                my $monitor = PVE::SMBGateway::Monitor->new();
                my $start_time = time() - (24 * 60 * 60); # Last 24 hours
                my $historical_metrics = $monitor->get_metrics($sharename, $start_time);
                
                $status->{metrics}->{history} = $historical_metrics;
            };
        }
    }
    
    return $status;
}

# -------- storage creation --------
sub create_storage {
    my ($class, $storeid, $scfg, %param) = @_;

    my $mode      = $scfg->{mode}      // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    my $path      = $scfg->{path}      // "/srv/smb/$sharename";
    my $quota     = $scfg->{quota}     // '';
    my $ad_domain = $scfg->{ad_domain} // '';
    my $ad_join   = $scfg->{ad_join}   // 0;
    my $ad_ou     = $scfg->{ad_ou}     // '';
    my $ha_enabled = $scfg->{ha_enabled} // 0;
    my $ha_nodes  = $scfg->{ha_nodes}  // 'all';
    my $ctdb_vip  = $scfg->{ctdb_vip}  // '';
    my $vm_memory = $scfg->{vm_memory} // 2048;
    my $vm_cores  = $scfg->{vm_cores}  // 2;
    
    # Set environment variables for AD credentials if domain join is requested
    if ($ad_domain && $ad_join) {
        # Check for credentials in parameters
        my $ad_username = $param{ad_username} // 'Administrator';
        my $ad_password = $param{ad_password};
        my $ad_fallback = $scfg->{ad_fallback} // 1;
        
        # Set environment variables for the domain join process
        $ENV{SMB_AD_USERNAME} = $ad_username if $ad_username;
        $ENV{SMB_AD_PASSWORD} = $ad_password if $ad_password;
        $ENV{SMB_AD_OU} = $ad_ou if $ad_ou;
        $ENV{SMB_AD_FALLBACK} = $ad_fallback ? '1' : '0';
    }

    # Handle auto VIP allocation if HA is enabled
    if ($ha_enabled && $ctdb_vip eq 'auto') {
        my $self = 'PVE::Storage::Custom::SMBGateway';
        $ctdb_vip = $self->_allocate_vip();
    }

    # Get cluster nodes if HA is enabled
    my @cluster_nodes = ();
    if ($ha_enabled) {
        if ($ha_nodes eq 'all') {
            # Get all cluster nodes
            eval {
                my $cluster_status = `pvesh get /cluster/status -output-format=json 2>/dev/null`;
                if ($cluster_status) {
                    # Parse JSON output
                    foreach my $line (split /\n/, $cluster_status) {
                        if ($line =~ /"name"\s*:\s*"([^"]+)"/) {
                            push @cluster_nodes, $1;
                        }
                    }
                } else {
                    # No cluster, just use local node
                    my $hostname = `hostname`;
                    chomp $hostname;
                    push @cluster_nodes, $hostname;
                }
            };
        } else {
            # Use specified nodes
            @cluster_nodes = split /,/, $ha_nodes;
        }
    }

    # Track what we've created for rollback
    my @rollback_steps = ();
    
    eval {
        if ($mode eq 'native') {
            _native_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
        } elsif ($mode eq 'lxc') {
            _lxc_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
        } elsif ($mode eq 'vm') {
            _vm_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, $vm_memory, $vm_cores, \@rollback_steps);
        } else {
            die "Unknown mode: $mode";
        }
    };
    
    if ($@) {
        # Rollback on failure
        _rollback_creation(\@rollback_steps);
        die "Failed to create share: $@";
    }
}

# -------- native mode implementations --------
sub _native_create {
    my ($path, $share, $quota, $ad_domain, $ctdb_vip, $rollback_steps) = @_;
    
    # Create directory
    mkdir $path unless -d $path;
    push @$rollback_steps, ['rmdir', $path];
    
    run_command(['chown', 'root:root', $path]);
    
    # Apply quota if specified
    if ($quota) {
        _apply_quota($path, $quota, $rollback_steps);
    }
    
    # Append samba config
    my $smb_conf = "/etc/samba/smb.conf";
    my $backup_conf = "/etc/samba/smb.conf.backup." . time();
    
    # Backup original config
    if (-f $smb_conf) {
        run_command(['cp', $smb_conf, $backup_conf]);
        push @$rollback_steps, ['restore_smb_conf', $backup_conf];
    }
    
    open my $fh, '>>', $smb_conf or die "Cannot append to $smb_conf: $!";
    print $fh "
[$share]
  path = $path
  browseable = yes
  writable = yes
  guest ok = no
  read only = no
";
    
    # Handle AD domain integration
    if ($ad_domain) {
        # Check if we have credentials in the environment
        my $ad_username = $ENV{SMB_AD_USERNAME} // 'Administrator';
        my $ad_password = $ENV{SMB_AD_PASSWORD};
        my $ad_ou = $ENV{SMB_AD_OU};
        my $ad_fallback = $ENV{SMB_AD_FALLBACK} // '1';
        
        if ($ad_password) {
            # Join domain with provided credentials
            my $self = 'PVE::Storage::Custom::SMBGateway';
            my $domain_info = $self->_join_ad_domain(
                $ad_domain, 
                $ad_username, 
                $ad_password, 
                $ad_ou, 
                'native', 
                undef, 
                $rollback_steps,
                $share,
                $ad_fallback eq '1'
            );
            
            # Add domain-specific configuration
            print $fh "  security = ads\n";
            print $fh "  realm = $domain_info->{realm}\n";
            print $fh "  workgroup = $domain_info->{workgroup}\n";
            print $fh "  idmap config * : backend = tdb\n";
            print $fh "  idmap config * : range = 10000-20000\n";
            print $fh "  winbind use default domain = yes\n";
            print $fh "  winbind enum users = yes\n";
            print $fh "  winbind enum groups = yes\n";
            
            # Add fallback authentication if enabled
            if ($ad_fallback eq '1') {
                print $fh "  auth methods = kerberos winbind sam\n";
                print $fh "  winbind offline logon = yes\n";
            }
        } else {
            # Just add basic AD configuration without joining
            print $fh "  security = ads\n";
            print $fh "  realm = $ad_domain\n";
            
            # Extract workgroup from domain
            my $workgroup = uc(substr($ad_domain, 0, index($ad_domain, '.')));
            print $fh "  workgroup = $workgroup\n";
            
            # Add warning to log
            warn "AD domain specified but no credentials provided. Domain join not performed.";
        }
    }
    
    close $fh;
    
    # Set up CTDB if HA is enabled and VIP is specified
    if ($ha_enabled && $ctdb_vip) {
        # Get current hostname
        my $hostname = `hostname`;
        chomp $hostname;
        
        # Set up CTDB cluster
        my $self = 'PVE::Storage::Custom::SMBGateway';
        my $nodes = \@cluster_nodes;
        
        # If no nodes specified, use local node
        if (!@$nodes) {
            $nodes = [$hostname];
        }
        
        # Set up CTDB cluster
        $self->_setup_ctdb_cluster($nodes, $ctdb_vip, $rollback_steps);
    } else {
        # Just reload Samba if no CTDB
        run_command(['systemctl', 'reload', 'smbd']);
    }
}

sub _native_activate {
    my ($sharename, $scfg) = @_;
    run_command(['systemctl', 'start', 'smbd']);
    run_command(['systemctl', 'start', 'nmbd']);
}

sub _native_deactivate {
    my ($sharename, $scfg) = @_;
    # Don't stop smbd/nmbd as other shares might be using them
    # Just remove the specific share config
    my $smb_conf = "/etc/samba/smb.conf";
    # TODO: Remove share stanza from smb.conf
}

sub _native_status {
    my ($sharename, $scfg) = @_;
    my $status = 'unknown';
    my $message = '';
    
    eval {
        my $output = `systemctl is-active smbd 2>/dev/null`;
        chomp $output;
        if ($output eq 'active') {
            $status = 'active';
            $message = 'Samba service running';
        } else {
            $status = 'inactive';
            $message = 'Samba service not running';
        }
    };
    
    return { status => $status, message => $message };
}

# -------- LXC mode implementations --------
sub _lxc_create {
    my ($path, $share, $quota, $ad_domain, $ctdb_vip, $rollback_steps) = @_;
    
    # Get next available CT ID
    my $ctid = `pvesh get /cluster/nextid`; 
    chomp $ctid;
    die "Failed to get next CT ID" unless $ctid =~ /^\d+$/;
    
    push @$rollback_steps, ['destroy_ct', $ctid];
    
    # Create directory
    mkdir $path unless -d $path;
    push @$rollback_steps, ['rmdir', $path];
    
    # Find available template
    my $template = _find_template();
    
    # Create LXC container
    run_command(['pct', 'create', $ctid, $template,
                 '--rootfs', "local-lvm:2",
                 '--hostname', "smb-$share",
                 '--unprivileged', '1',
                 '--memory', '128',
                 '--net0', 'name=eth0,bridge=vmbr0,ip=dhcp'],
                errmsg => "failed to create LXC");
    
    # Bind mount the path
    run_command(['pct', 'set', $ctid, '-mp0', "$path,mp=/srv/share,ro=0"]);
    
    # Start the container
    run_command(['pct', 'start', $ctid]);
    
    # Install Samba inside the container
    _install_samba_in_lxc($ctid, $share, $ad_domain, $ctdb_vip);
    
    # Apply quota if specified
    if ($quota) {
        _apply_quota($path, $quota, $rollback_steps);
    }
    
    # Set up CTDB if VIP is specified
    if ($ctdb_vip) {
        # Get container IP address
        my $ct_ip = '';
        my $max_attempts = 10;
        my $attempt = 0;
        
        while ($attempt < $max_attempts) {
            my $ip_output = `pct exec $ctid -- ip -4 addr show eth0 2>/dev/null`;
            if ($ip_output =~ /inet\s+(\d+\.\d+\.\d+\.\d+)/) {
                $ct_ip = $1;
                last;
            }
            sleep 2;
            $attempt++;
        }
        
        die "Failed to get container IP address" unless $ct_ip;
        
        # Set up CTDB inside the container
        run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'update']);
        run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'install', '-y', 'ctdb']);
        
        # Create CTDB configuration
        run_command(['pct', 'exec', $ctid, '--', 'mkdir', '-p', '/etc/ctdb']);
        
        # Create nodes file with container IP
        open my $nodes_fh, '>', "/tmp/ctdb-nodes-$ctid" or die "Cannot create nodes file: $!";
        print $nodes_fh "$ct_ip\n";
        close $nodes_fh;
        
        # Create public addresses file with VIP
        open my $pa_fh, '>', "/tmp/ctdb-pa-$ctid" or die "Cannot create public addresses file: $!";
        print $pa_fh "$ctdb_vip/24 eth0\n";
        close $pa_fh;
        
        # Copy files to container
        run_command(['pct', 'push', $ctid, "/tmp/ctdb-nodes-$ctid", '/etc/ctdb/nodes']);
        run_command(['pct', 'push', $ctid, "/tmp/ctdb-pa-$ctid", '/etc/ctdb/public_addresses']);
        
        # Clean up temporary files
        unlink "/tmp/ctdb-nodes-$ctid";
        unlink "/tmp/ctdb-pa-$ctid";
        
        # Enable and start CTDB
        run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'enable', 'ctdb']);
        run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'start', 'ctdb']);
        
        # Update smb.conf for CTDB
        run_command(['pct', 'exec', $ctid, '--', 'bash', '-c', 
                    "echo -e '\n# CTDB configuration\nclustering = yes\nctdb socket = /var/run/ctdb/ctdbd.socket\n' >> /etc/samba/smb.conf"]);
        
        # Restart Samba services
        run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'restart', 'smbd']);
        run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'restart', 'nmbd']);
    }
    
    # Store CT ID in config for later reference
    $scfg->{ctid} = $ctid;
}

sub _lxc_activate {
    my ($sharename, $scfg) = @_;
    my $ctid = $scfg->{ctid};
    return unless $ctid;
    
    run_command(['pct', 'start', $ctid]);
}

sub _lxc_deactivate {
    my ($sharename, $scfg) = @_;
    my $ctid = $scfg->{ctid};
    return unless $ctid;
    
    run_command(['pct', 'stop', $ctid]);
}

sub _lxc_status {
    my ($sharename, $scfg) = @_;
    my $ctid = $scfg->{ctid};
    
    if (!$ctid) {
        return { status => 'unknown', message => 'No CT ID found' };
    }
    
    my $status = 'unknown';
    my $message = '';
    
    eval {
        my $output = `pct status $ctid 2>/dev/null`;
        if ($output =~ /running/) {
            $status = 'active';
            $message = "LXC container $ctid is running";
        } elsif ($output =~ /stopped/) {
            $status = 'inactive';
            $message = "LXC container $ctid is stopped";
        } else {
            $status = 'error';
            $message = "LXC container $ctid not found";
        }
    };
    
    return { status => $status, message => $message };
}

# -------- helper methods --------
sub _find_template {
    # Look for common Debian templates
    my @templates = (
        'local:vztmpl/debian-12-standard_20240410_amd64.tar.zst',
        'local:vztmpl/debian-11-standard_20240410_amd64.tar.zst',
        'local:vztmpl/ubuntu-22.04-standard_20240410_amd64.tar.zst'
    );
    
    foreach my $template (@templates) {
        my $output = `pvesh get /nodes/\$(hostname)/storage/local/content 2>/dev/null | grep -q "$template"`;
        if ($? == 0) {
            return $template;
        }
    }
    
    die "No suitable template found. Please download a Debian or Ubuntu template.";
}

# -------- quota management methods --------
sub _apply_quota {
    my ($path, $quota, $rollback_steps) = @_;
    
    # Validate quota format
    unless ($quota =~ /^(\d+)([KMGT])$/) {
        die "Invalid quota format: $quota. Use format like 10G or 1T.";
    }
    
    my ($size, $unit) = ($1, $2);
    my $bytes;
    
    # Convert to bytes
    if ($unit eq 'K') {
        $bytes = $size * 1024;
    } elsif ($unit eq 'M') {
        $bytes = $size * 1024**2;
    } elsif ($unit eq 'G') {
        $bytes = $size * 1024**3;
    } elsif ($unit eq 'T') {
        $bytes = $size * 1024**4;
    }
    
    # Check if path exists
    unless (-d $path) {
        die "Path does not exist: $path";
    }
    
    # Check if path is on a filesystem that supports quotas
    my $fs_type = _get_fs_type($path);
    my $quota_applied = 0;
    my $error_message = "";
    
    eval {
        if ($fs_type eq 'zfs') {
            # For ZFS, use zfs quota
            _apply_zfs_quota($path, $quota, $rollback_steps);
            $quota_applied = 1;
        } elsif ($fs_type eq 'xfs') {
            # For XFS, use project quotas
            _apply_xfs_quota($path, $bytes, $rollback_steps);
            $quota_applied = 1;
        } else {
            # For other filesystems, use standard user quotas
            _apply_user_quota($path, $bytes, $rollback_steps);
            $quota_applied = 1;
        }
    };
    
    if ($@) {
        $error_message = $@;
        warn "Failed to apply quota: $error_message";
        
        # Try fallback method if primary method failed
        if (!$quota_applied) {
            eval {
                warn "Trying fallback quota method for $path";
                _apply_user_quota($path, $bytes, $rollback_steps);
                $quota_applied = 1;
            };
            
            if ($@) {
                die "Failed to apply quota using fallback method: $@\nOriginal error: $error_message";
            }
        }
    }
    
    # Verify quota was applied successfully
    if ($quota_applied) {
        # Store quota information for monitoring
        _store_quota_info($path, $quota, $bytes);
        
        # Add quota to rollback steps
        push @$rollback_steps, ['remove_quota', $path, $fs_type];
        
        # Log success
        warn "Successfully applied quota of $quota to $path";
    } else {
        die "Failed to apply quota to $path: $error_message";
    }
}

sub _get_fs_type {
    my ($path) = @_;
    
    # Get filesystem type
    my $df_output = `df -T "$path" 2>/dev/null | tail -1`;
    my @fields = split /\s+/, $df_output;
    
    if (@fields >= 2) {
        return $fields[1];
    }
    
    # Check if it's a ZFS dataset
    my $zfs_output = `zfs list | grep "$path" 2>/dev/null`;
    if ($zfs_output) {
        return 'zfs';
    }
    
    # Default to ext4
    return 'ext4';
}

sub _apply_zfs_quota {
    my ($path, $quota, $rollback_steps) = @_;
    
    # Get ZFS dataset name
    my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
    chomp $dataset;
    
    if ($dataset) {
        # Apply quota
        run_command(['zfs', 'set', "quota=$quota", $dataset]);
        
        # Add rollback step
        push @$rollback_steps, ['zfs_remove_quota', $dataset];
    } else {
        die "No ZFS dataset found for path: $path";
    }
}

sub _apply_xfs_quota {
    my ($path, $bytes, $rollback_steps) = @_;
    
    # Get mount point
    my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Check if xfs_quota is available
    my $has_xfs_quota = system('which xfs_quota >/dev/null 2>&1') == 0;
    
    if ($has_xfs_quota) {
        # Check if project quotas are enabled
        my $quota_output = `xfs_quota -x -c "state" "$mount_point" 2>/dev/null`;
        my $project_quotas_enabled = $quota_output =~ /project quota accounting: on/;
        
        if ($project_quotas_enabled) {
            # Find next available project ID
            my $next_id = 1000;
            if (-f "/etc/projects") {
                my $max_id = 0;
                open my $fh, '<', "/etc/projects" or die "Cannot read /etc/projects: $!";
                while (my $line = <$fh>) {
                    if ($line =~ /^(\d+):/) {
                        $max_id = $1 if $1 > $max_id;
                    }
                }
                close $fh;
                $next_id = $max_id + 1;
            }
            
            # Add project entry
            open my $proj_fh, '>>', "/etc/projects" or die "Cannot append to /etc/projects: $!";
            print $proj_fh "$next_id:$path\n";
            close $proj_fh;
            
            # Add project name entry
            open my $name_fh, '>>', "/etc/projid" or die "Cannot append to /etc/projid: $!";
            print $name_fh "smb_share_$next_id:$next_id\n";
            close $name_fh;
            
            # Initialize project
            run_command(['xfs_quota', '-x', '-c', "project -s smb_share_$next_id", $mount_point]);
            
            # Set quota
            my $blocks = int($bytes / 1024);
            run_command(['xfs_quota', '-x', '-c', "limit -p bhard=$blocks $next_id", $mount_point]);
            
            # Add rollback step
            push @$rollback_steps, ['xfs_remove_quota', $next_id, $mount_point];
        } else {
            die "Project quotas not enabled on $mount_point";
        }
    } else {
        # Fall back to user quota
        _apply_user_quota($path, $bytes, $rollback_steps);
    }
}

sub _apply_user_quota {
    my ($path, $bytes, $rollback_steps) = @_;
    
    # Check if quota tools are available
    my $has_quota = system('which setquota >/dev/null 2>&1') == 0;
    
    if ($has_quota) {
        # Get mount point
        my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
        chomp $mount_point;
        
        # Apply quota using setquota
        run_command(['setquota', '-u', 'root', '0', $bytes, '0', '0', $mount_point]);
        
        # Add rollback step
        push @$rollback_steps, ['user_remove_quota', 'root', $mount_point];
    } else {
        warn "Quota tools not available, quota not applied";
    }
}

sub _store_quota_info {
    my ($path, $quota, $bytes) = @_;
    
    # Create quota info directory if it doesn't exist
    my $quota_dir = "/etc/pve/smbgateway/quotas";
    unless (-d $quota_dir) {
        eval { 
            mkdir $quota_dir;
        };
        if ($@) {
            warn "Failed to create quota directory: $@";
            return;
        }
    }
    
    # Create quota info file
    my $quota_file = "$quota_dir/" . _path_to_filename($path) . ".quota";
    
    eval {
        open my $fh, '>', $quota_file or die "Cannot write to $quota_file: $!";
        print $fh "path=$path\n";
        print $fh "quota=$quota\n";
        print $fh "bytes=$bytes\n";
        print $fh "timestamp=" . time() . "\n";
        close $fh;
    };
    
    if ($@) {
        warn "Failed to store quota information: $@";
    }
}

sub _get_stored_quota_info {
    my ($path) = @_;
    
    # Get quota info file path
    my $quota_dir = "/etc/pve/smbgateway/quotas";
    my $quota_file = "$quota_dir/" . _path_to_filename($path) . ".quota";
    
    # Check if file exists
    return undef unless -f $quota_file;
    
    # Read quota info
    my %info;
    eval {
        open my $fh, '<', $quota_file or die "Cannot read $quota_file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            if ($line =~ /^(\w+)=(.*)$/) {
                $info{$1} = $2;
            }
        }
        close $fh;
    };
    
    if ($@) {
        warn "Failed to read quota information: $@";
        return undef;
    }
    
    # Validate required fields
    return undef unless $info{path} && $info{quota} && $info{bytes};
    
    return \%info;
}

sub _path_to_filename {
    my ($path) = @_;
    
    # Convert path to a valid filename
    $path =~ s/\//_/g;
    $path =~ s/^_//;
    
    return $path;
}

sub _get_quota_usage {
    my ($self, $path) = @_;
    
    # Check if path exists
    unless (-d $path) {
        warn "Path does not exist: $path";
        return undef;
    }
    
    # First check if we have stored quota information
    my $quota_info = _get_stored_quota_info($path);
    
    # Get filesystem type
    my $fs_type = _get_fs_type($path);
    my $usage = undef;
    
    # Try to get actual usage from filesystem
    eval {
        if ($fs_type eq 'zfs') {
            $usage = _get_zfs_quota_usage($path);
        } elsif ($fs_type eq 'xfs') {
            $usage = _get_xfs_quota_usage($path);
        } else {
            $usage = _get_user_quota_usage($path);
        }
    };
    
    if ($@) {
        warn "Error getting quota usage: $@";
        
        # If we have stored quota info but couldn't get actual usage,
        # return the stored quota with unknown usage
        if ($quota_info) {
            return {
                quota => $quota_info->{quota},
                used => 'unknown',
                quota_bytes => $quota_info->{bytes},
                used_bytes => 0,
                percent => 0,
                error => "Failed to get actual usage: $@",
                fs_type => $fs_type
            };
        }
        return undef;
    }
    
    # If we got usage from filesystem, update history and return it
    if ($usage) {
        # Add filesystem type to usage info
        $usage->{fs_type} = $fs_type;
        
        # Update history if we have valid usage data
        if ($usage->{used_bytes} && $usage->{percent}) {
            _update_quota_history($path, $usage->{used_bytes}, $usage->{percent});
        }
        
        return $usage;
    }
    
    # If we have stored quota info but couldn't get actual usage,
    # return the stored quota with unknown usage
    if ($quota_info) {
        return {
            quota => $quota_info->{quota},
            used => 'unknown',
            quota_bytes => $quota_info->{bytes},
            used_bytes => 0,
            percent => 0,
            fs_type => $fs_type
        };
    }
    
    return undef;
}

sub _get_zfs_quota_usage {
    my ($path) = @_;
    
    # Get ZFS dataset name
    my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
    chomp $dataset;
    
    if ($dataset) {
        # Get ZFS quota and used space
        my $quota = `zfs get -H -o value quota $dataset`;
        chomp $quota;
        
        my $used = `zfs get -H -o value used $dataset`;
        chomp $used;
        
        # Convert to bytes
        my $quota_bytes = _human_to_bytes($quota);
        my $used_bytes = _human_to_bytes($used);
        
        return {
            quota => $quota,
            used => $used,
            quota_bytes => $quota_bytes,
            used_bytes => $used_bytes,
            percent => $quota_bytes > 0 ? int(($used_bytes * 100) / $quota_bytes) : 0
        };
    }
    
    return undef;
}

sub _get_xfs_quota_usage {
    my ($path) = @_;
    
    # Get mount point
    my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Find project ID
    my $project_id = undef;
    if (-f "/etc/projects") {
        open my $fh, '<', "/etc/projects" or die "Cannot read /etc/projects: $!";
        while (my $line = <$fh>) {
            if ($line =~ /^(\d+):$path$/) {
                $project_id = $1;
                last;
            }
        }
        close $fh;
    }
    
    if ($project_id) {
        # Get quota usage
        my $quota_output = `xfs_quota -x -c "report -p" $mount_point | grep "#$project_id"`;
        my @fields = split /\s+/, $quota_output;
        
        if (@fields >= 4) {
            my $used_blocks = $fields[2];
            my $quota_blocks = $fields[3];
            
            # Convert to bytes (blocks are 1KB)
            my $used_bytes = $used_blocks * 1024;
            my $quota_bytes = $quota_blocks * 1024;
            
            return {
                quota => _bytes_to_human($quota_bytes),
                used => _bytes_to_human($used_bytes),
                quota_bytes => $quota_bytes,
                used_bytes => $used_bytes,
                percent => $quota_bytes > 0 ? int(($used_bytes * 100) / $quota_bytes) : 0
            };
        }
    }
    
    return undef;
}

sub _get_user_quota_usage {
    my ($path) = @_;
    
    # Get mount point
    my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Get quota usage
    my $quota_output = `quota -u root | tail -1`;
    my @fields = split /\s+/, $quota_output;
    
    if (@fields >= 3) {
        my $used_blocks = $fields[1];
        my $quota_blocks = $fields[2];
        
        # Convert to bytes (blocks are 1KB)
        my $used_bytes = $used_blocks * 1024;
        my $quota_bytes = $quota_blocks * 1024;
        
        return {
            quota => _bytes_to_human($quota_bytes),
            used => _bytes_to_human($used_bytes),
            quota_bytes => $quota_bytes,
            used_bytes => $used_bytes,
            percent => $quota_bytes > 0 ? int(($used_bytes * 100) / $quota_bytes) : 0
        };
    }
    
    return undef;
}

sub _human_to_bytes {
    my ($human) = @_;
    
    if ($human =~ /^(\d+)([KMGT]?)$/) {
        my ($size, $unit) = ($1, $2);
        
        if ($unit eq 'K') {
            return $size * 1024;
        } elsif ($unit eq 'M') {
            return $size * 1024**2;
        } elsif ($unit eq 'G') {
            return $size * 1024**3;
        } elsif ($unit eq 'T') {
            return $size * 1024**4;
        } else {
            return $size;
        }
    }
    
    return 0;
}

sub _bytes_to_human {
    my ($bytes) = @_;
    
    if ($bytes >= 1024**4) {
        return sprintf("%.1fT", $bytes / 1024**4);
    } elsif ($bytes >= 1024**3) {
        return sprintf("%.1fG", $bytes / 1024**3);
    } elsif ($bytes >= 1024**2) {
        return sprintf("%.1fM", $bytes / 1024**2);
    } elsif ($bytes >= 1024) {
        return sprintf("%.1fK", $bytes / 1024);
    } else {
        return "${bytes}B";
    }
}

sub _get_quota_trend {
    my ($path) = @_;
    
    # Get quota info file path
    my $quota_dir = "/etc/pve/smbgateway/quotas";
    my $history_file = "$quota_dir/" . _path_to_filename($path) . ".history";
    
    # Check if history file exists
    return undef unless -f $history_file;
    
    # Read history data
    my @history;
    eval {
        open my $fh, '<', $history_file or die "Cannot read $history_file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            if ($line =~ /^(\d+):(\d+):(\d+)$/) {
                push @history, {
                    timestamp => $1,
                    used_bytes => $2,
                    percent => $3
                };
            }
        }
        close $fh;
    };
    
    if ($@) {
        warn "Failed to read quota history: $@";
        return undef;
    }
    
    # Need at least 2 data points for trend
    return undef if @history < 2;
    
    # Sort by timestamp
    @history = sort { $a->{timestamp} <=> $b->{timestamp} } @history;
    
    # Get last two data points
    my $prev = $history[-2];
    my $curr = $history[-1];
    
    # Calculate trend
    my $time_diff = $curr->{timestamp} - $prev->{timestamp};
    return undef if $time_diff <= 0;
    
    my $percent_diff = $curr->{percent} - $prev->{percent};
    my $bytes_diff = $curr->{used_bytes} - $prev->{used_bytes};
    
    # Calculate daily growth rate
    my $days_diff = $time_diff / (24 * 60 * 60);
    my $daily_percent_growth = $percent_diff / $days_diff;
    my $daily_bytes_growth = $bytes_diff / $days_diff;
    
    # Estimate days until full
    my $days_until_full = undef;
    if ($daily_percent_growth > 0) {
        $days_until_full = (100 - $curr->{percent}) / $daily_percent_growth;
    }
    
    return {
        daily_growth_percent => sprintf("%.2f", $daily_percent_growth),
        daily_growth_bytes => _bytes_to_human($daily_bytes_growth),
        days_until_full => defined($days_until_full) ? int($days_until_full) : undef,
        direction => $percent_diff > 0 ? 'increasing' : ($percent_diff < 0 ? 'decreasing' : 'stable')
    };
}

sub _update_quota_history {
    my ($path, $used_bytes, $percent) = @_;
    
    # Get quota info file path
    my $quota_dir = "/etc/pve/smbgateway/quotas";
    my $history_file = "$quota_dir/" . _path_to_filename($path) . ".history";
    
    # Create directory if it doesn't exist
    unless (-d $quota_dir) {
        eval { 
            mkdir $quota_dir;
        };
        if ($@) {
            warn "Failed to create quota directory: $@";
            return;
        }
    }
    
    # Read existing history
    my @history;
    if (-f $history_file) {
        eval {
            open my $fh, '<', $history_file or die "Cannot read $history_file: $!";
            while (my $line = <$fh>) {
                chomp $line;
                if ($line =~ /^(\d+):(\d+):(\d+)$/) {
                    push @history, {
                        timestamp => $1,
                        used_bytes => $2,
                        percent => $3
                    };
                }
            }
            close $fh;
        };
        
        if ($@) {
            warn "Failed to read quota history: $@";
        }
    }
    
    # Add new data point
    push @history, {
        timestamp => time(),
        used_bytes => $used_bytes,
        percent => $percent
    };
    
    # Keep only last 30 data points
    if (@history > 30) {
        @history = @history[-30..-1];
    }
    
    # Write history file
    eval {
        open my $fh, '>', $history_file or die "Cannot write to $history_file: $!";
        foreach my $point (@history) {
            print $fh "$point->{timestamp}:$point->{used_bytes}:$point->{percent}\n";
        }
        close $fh;
    };
    
    if ($@) {
        warn "Failed to write quota history: $@";
    }
}

1;
# -------
- VM mode implementations --------
sub _vm_create {
    my ($path, $share, $quota, $ad_domain, $ctdb_vip, $vm_memory, $vm_cores, $rollback_steps) = @_;
    
    # Get next available VM ID
    my $vmid = `pvesh get /cluster/nextid`; 
    chomp $vmid;
    die "Failed to get next VM ID" unless $vmid =~ /^\d+$/;
    
    push @$rollback_steps, ['destroy_vm', $vmid];
    
    # Create directory
    mkdir $path unless -d $path;
    push @$rollback_steps, ['rmdir', $path];
    
    # Find or create VM template
    my $template = _find_vm_template();
    
    # Create VM from template
    run_command(['qm', 'clone', $template, $vmid, 
                 '--name', "smb-$share",
                 '--full', '1'],
                errmsg => "failed to clone VM template");
    
    # Configure VM resources
    run_command(['qm', 'set', $vmid, 
                 '--memory', $vm_memory,
                 '--cores', $vm_cores,
                 '--net0', 'virtio,bridge=vmbr0']);
    
    # Add cloud-init configuration
    run_command(['qm', 'set', $vmid, 
                 '--ide2', 'local:iso/smb-gateway-cloud-init.iso,media=cdrom'],
                errmsg => "failed to add cloud-init configuration");
    
    # Add virtio-fs mount for the share path
    run_command(['qm', 'set', $vmid, 
                 '--virtio9p0', "path=$path,mount_tag=share"],
                errmsg => "failed to add virtio-fs mount");
    
    # Start the VM
    run_command(['qm', 'start', $vmid]);
    
    # Wait for VM to boot and get IP
    my $vm_ip = _wait_for_vm_ip($vmid);
    die "Failed to get VM IP address" unless $vm_ip;
    
    # Configure Samba inside the VM
    _configure_samba_in_vm($vmid, $vm_ip, $share, $ad_domain, $ctdb_vip);
    
    # Apply quota if specified
    if ($quota) {
        _apply_quota($path, $quota, $rollback_steps);
    }
    
    # Set up CTDB if VIP is specified
    if ($ctdb_vip) {
        _setup_ctdb_in_vm($vmid, $vm_ip, $ctdb_vip, $rollback_steps);
    }
    
    # Store VM ID in config for later reference
    $scfg->{vmid} = $vmid;
}

sub _vm_activate {
    my ($sharename, $scfg) = @_;
    my $vmid = $scfg->{vmid};
    return unless $vmid;
    
    run_command(['qm', 'start', $vmid]);
}

sub _vm_deactivate {
    my ($sharename, $scfg) = @_;
    my $vmid = $scfg->{vmid};
    return unless $vmid;
    
    run_command(['qm', 'stop', $vmid]);
}

sub _vm_status {
    my ($sharename, $scfg) = @_;
    my $vmid = $scfg->{vmid};
    
    if (!$vmid) {
        return { status => 'unknown', message => 'No VM ID found' };
    }
    
    my $status = 'unknown';
    my $message = '';
    
    eval {
        my $output = `qm status $vmid 2>/dev/null`;
        if ($output =~ /running/) {
            $status = 'active';
            $message = "VM $vmid is running";
        } elsif ($output =~ /stopped/) {
            $status = 'inactive';
            $message = "VM $vmid is stopped";
        } else {
            $status = 'error';
            $message = "VM $vmid not found";
        }
    };
    
    return { status => $status, message => $message };
}

# -------- VM helper methods --------
sub _find_vm_template {
    my ($self) = @_;
    
    # Look for existing SMB gateway template first
    my $hostname = `hostname`;
    chomp $hostname;
    
    my $template_list = `pvesh get /nodes/$hostname/storage/local/content --type iso 2>/dev/null`;
    
    # Preferred templates in order
    my @preferred_templates = (
        'local:iso/smb-gateway-debian12.qcow2',
        'local:iso/debian-12-generic-amd64.qcow2',
        'local:iso/debian-11-generic-amd64.qcow2',
        'local:iso/ubuntu-22.04-server-cloudimg-amd64.img'
    );
    
    foreach my $template (@preferred_templates) {
        if ($template_list =~ /\Q$template\E/) {
            return $template;
        }
    }
    
    # If no template found, try to create one
    warn "No suitable VM template found. Attempting to create one...";
    return $self->_create_vm_template();
}

sub _validate_vm_template {
    my ($self, $template) = @_;
    
    # Check if template exists
    my $hostname = `hostname`;
    chomp $hostname;
    
    my $template_list = `pvesh get /nodes/$hostname/storage/local/content --type iso 2>/dev/null`;
    
    if ($template_list =~ /\Q$template\E/) {
        return 1;
    }
    
    return 0;
}

sub _create_vm_template {
    my ($self, $force_create) = @_;
    
    # Check if template already exists
    unless ($force_create) {
        my $existing_template = $self->_find_vm_template();
        if ($existing_template && $existing_template ne '') {
            return $existing_template;
        }
    }
    
    # Check if required tools are available
    my @required_tools = ('qemu-img', 'wget', 'genisoimage');
    my @missing_tools = ();
    
    foreach my $tool (@required_tools) {
        if (system("which $tool >/dev/null 2>&1") != 0) {
            push @missing_tools, $tool;
        }
    }
    
    if (@missing_tools) {
        die "Missing required tools for VM template creation. Please install: " . join(', ', @missing_tools);
    }
    
    # Create template directory
    my $template_dir = "/var/lib/vz/template/iso";
    mkdir $template_dir unless -d $template_dir;
    
    # Create temporary directory for template building
    my $temp_dir = "/tmp/smb-gateway-template-$$";
    mkdir $temp_dir or die "Cannot create temp directory: $!";
    
    eval {
        # Download Debian cloud image
        my $debian_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2";
        my $image_path = "$temp_dir/debian-12-generic-amd64.qcow2";
        
        print "Downloading Debian 12 cloud image...\n";
        run_command(['wget', '-O', $image_path, $debian_url], 
                   errmsg => "Failed to download Debian cloud image");
        
        # Create cloud-init configuration
        my $user_data = "$temp_dir/user-data";
        open(my $fh, '>', $user_data) or die "Cannot create user-data: $!";
        print $fh <<'EOF';
#cloud-config
package_update: true
package_upgrade: true

packages:
  - samba
  - winbind
  - acl
  - attr
  - cloud-init

runcmd:
  - systemctl enable smbd
  - systemctl enable nmbd
  - systemctl enable winbind
  - mkdir -p /etc/samba/smb.conf.d
  - echo "workgroup = WORKGROUP" > /etc/samba/smb.conf.d/global.conf
  - echo "server string = SMB Gateway" >> /etc/samba/smb.conf.d/global.conf
  - echo "security = user" >> /etc/samba/smb.conf.d/global.conf
  - echo "map to guest = bad user" >> /etc/samba/smb.conf.d/global.conf
  - echo "dns proxy = no" >> /etc/samba/smb.conf.d/global.conf
  - echo "log level = 1" >> /etc/samba/smb.conf.d/global.conf

ssh_pwauth: false
disable_root: false
EOF
        close $fh;
        
        my $meta_data = "$temp_dir/meta-data";
        open($fh, '>', $meta_data) or die "Cannot create meta-data: $!";
        print $fh <<'EOF';
instance-id: smb-gateway-template
local-hostname: smb-gateway
EOF
        close $fh;
        
        # Create cloud-init ISO
        print "Creating cloud-init configuration...\n";
        run_command(['genisoimage', '-output', "$temp_dir/smb-gateway-cloud-init.iso",
                    '-volid', 'cidata', '-joliet', '-rock', $user_data, $meta_data],
                   errmsg => "Failed to create cloud-init ISO");
        
        # Copy files to final location
        my $final_image = "$template_dir/smb-gateway-debian12.qcow2";
        my $final_iso = "$template_dir/smb-gateway-cloud-init.iso";
        
        run_command(['cp', $image_path, $final_image], 
                   errmsg => "Failed to copy VM image");
        run_command(['cp', "$temp_dir/smb-gateway-cloud-init.iso", $final_iso],
                   errmsg => "Failed to copy cloud-init ISO");
        
        # Clean up temp directory
        run_command(['rm', '-rf', $temp_dir]);
        
        print "VM template created successfully!\n";
        return 'local:iso/smb-gateway-debian12.qcow2';
    };
    
    if ($@) {
        # Clean up on error
        run_command(['rm', '-rf', $temp_dir]);
        die "Failed to create VM template: $@";
    }
}

sub _wait_for_vm_ip {
    my ($vmid) = @_;
    
    my $max_attempts = 30;
    my $attempt = 0;
    
    while ($attempt < $max_attempts) {
        my $ip_output = `qm guest cmd $vmid network-get-interfaces 2>/dev/null`;
        if ($ip_output =~ /"ip-address":\s*"(\d+\.\d+\.\d+\.\d+)"/) {
            my $ip = $1;
            # Skip loopback
            next if $ip eq '127.0.0.1';
            return $ip;
        }
        
        sleep 5;
        $attempt++;
    }
    
    return undef;
}

sub _configure_samba_in_vm {
    my ($vmid, $vm_ip, $share, $ad_domain, $ctdb_vip) = @_;
    
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    
    # Create mount point for virtio-fs
    run_command([$ssh_cmd, 'mkdir', '-p', '/srv/share']);
    
    # Mount virtio-fs share
    run_command([$ssh_cmd, 'mount', '-t', '9p', '-o', 'trans=virtio,version=9p2000.L', 'share', '/srv/share']);
    
    # Add to fstab for persistence
    run_command([$ssh_cmd, 'echo', 'share /srv/share 9p trans=virtio,version=9p2000.L 0 0', '>>', '/etc/fstab']);
    
    # Configure Samba
    my $smb_config = "
[$share]
  path = /srv/share
  browseable = yes
  writable = yes
  guest ok = no
  read only = no
";
    
    # Handle AD domain integration
    if ($ad_domain) {
        my $ad_username = $ENV{SMB_AD_USERNAME} // 'Administrator';
        my $ad_password = $ENV{SMB_AD_PASSWORD};
        my $ad_ou = $ENV{SMB_AD_OU};
        my $ad_fallback = $ENV{SMB_AD_FALLBACK} // '1';
        
        if ($ad_password) {
            # Join domain
            my $domain_info = _join_ad_domain_vm($vmid, $vm_ip, $ad_domain, $ad_username, $ad_password, $ad_ou, $ad_fallback eq '1');
            
            # Add domain-specific configuration
            $smb_config .= "  security = ads\n";
            $smb_config .= "  realm = $domain_info->{realm}\n";
            $smb_config .= "  workgroup = $domain_info->{workgroup}\n";
            $smb_config .= "  idmap config * : backend = tdb\n";
            $smb_config .= "  idmap config * : range = 10000-20000\n";
            $smb_config .= "  winbind use default domain = yes\n";
            $smb_config .= "  winbind enum users = yes\n";
            $smb_config .= "  winbind enum groups = yes\n";
            
            if ($ad_fallback eq '1') {
                $smb_config .= "  auth methods = kerberos winbind sam\n";
                $smb_config .= "  winbind offline logon = yes\n";
            }
        }
    }
    
    # Write Samba configuration
    run_command([$ssh_cmd, 'echo', "'$smb_config'", '>>', '/etc/samba/smb.conf']);
    
    # Restart Samba services
    run_command([$ssh_cmd, 'systemctl', 'restart', 'smbd', 'nmbd']);
}

sub _setup_ctdb_in_vm {
    my ($vmid, $vm_ip, $ctdb_vip, $rollback_steps) = @_;
    
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    
    # Install CTDB
    run_command([$ssh_cmd, 'apt-get', 'update']);
    run_command([$ssh_cmd, 'apt-get', 'install', '-y', 'ctdb']);
    
    # Create CTDB configuration
    run_command([$ssh_cmd, 'mkdir', '-p', '/etc/ctdb']);
    
    # Create nodes file
    run_command([$ssh_cmd, 'echo', $vm_ip, '>', '/etc/ctdb/nodes']);
    
    # Create public addresses file
    run_command([$ssh_cmd, 'echo', "$ctdb_vip/24 eth0", '>', '/etc/ctdb/public_addresses']);
    
    # Update smb.conf for CTDB
    my $ctdb_config = "
# CTDB configuration
clustering = yes
ctdb socket = /var/run/ctdb/ctdbd.socket
";
    
    run_command([$ssh_cmd, 'echo', "'$ctdb_config'", '>>', '/etc/samba/smb.conf']);
    
    # Enable and start CTDB
    run_command([$ssh_cmd, 'systemctl', 'enable', 'ctdb']);
    run_command([$ssh_cmd, 'systemctl', 'start', 'ctdb']);
    
    # Restart Samba services
    run_command([$ssh_cmd, 'systemctl', 'restart', 'smbd', 'nmbd']);
}

sub _join_ad_domain_vm {
    my ($vmid, $vm_ip, $domain, $username, $password, $ou, $fallback) = @_;
    
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    
    # Install AD integration packages
    run_command([$ssh_cmd, 'apt-get', 'install', '-y', 'realmd', 'sssd', 'sssd-tools', 'libnss-sss', 'libpam-sss', 'adcli', 'samba-common-bin']);
    
    # Discover domain
    my $realm_output = `$ssh_cmd realm discover $domain 2>/dev/null`;
    unless ($realm_output =~ /domain-name:\s*(\S+)/) {
        die "Failed to discover domain: $domain";
    }
    
    my $realm = uc($1);
    my $workgroup = uc(substr($domain, 0, index($domain, '.')));
    
    # Join domain
    my $join_cmd = "$ssh_cmd realm join --user=$username";
    $join_cmd .= " --computer-ou='$ou'" if $ou;
    $join_cmd .= " $domain";
    
    # Use expect to handle password prompt
    my $expect_script = "
expect -c '
spawn $join_cmd
expect \"Password for $username:\"
send \"$password\\r\"
expect eof
'";
    
    my $join_result = system($expect_script);
    if ($join_result != 0) {
        if ($fallback) {
            warn "Domain join failed, continuing with fallback authentication";
        } else {
            die "Failed to join domain: $domain";
        }
    }
    
    return {
        realm => $realm,
        workgroup => $workgroup,
        domain => $domain
    };
}

# -------- CTDB High Availability methods --------
sub _setup_ctdb_cluster {
    my ($self, $nodes, $vip, $rollback_steps) = @_;
    
    # Install CTDB if not present
    my $ctdb_installed = system("dpkg -l ctdb >/dev/null 2>&1") == 0;
    if (!$ctdb_installed) {
        run_command(['apt-get', 'update']);
        run_command(['apt-get', 'install', '-y', 'ctdb']);
        push @$rollback_steps, ['ctdb_package_installed'];
    }
    
    # Create CTDB configuration directory
    unless (-d '/etc/ctdb') {
        mkdir '/etc/ctdb' or die "Cannot create /etc/ctdb: $!";
        push @$rollback_steps, ['remove_ctdb_config_dir'];
    }
    
    # Create nodes file
    my $nodes_file = '/etc/ctdb/nodes';
    open my $nodes_fh, '>', $nodes_file or die "Cannot create $nodes_file: $!";
    foreach my $node (@$nodes) {
        # Resolve node name to IP if needed
        my $node_ip = _resolve_node_ip($node);
        print $nodes_fh "$node_ip\n";
    }
    close $nodes_fh;
    push @$rollback_steps, ['remove_ctdb_nodes_file'];
    
    # Create public addresses file
    my $pa_file = '/etc/ctdb/public_addresses';
    open my $pa_fh, '>', $pa_file or die "Cannot create $pa_file: $!";
    print $pa_fh "$vip/24 eth0\n";
    close $pa_fh;
    push @$rollback_steps, ['remove_ctdb_pa_file'];
    
    # Enable and start CTDB
    run_command(['systemctl', 'enable', 'ctdb']);
    run_command(['systemctl', 'start', 'ctdb']);
    push @$rollback_steps, ['stop_ctdb_service'];
    
    # Wait for CTDB to become healthy
    my $max_attempts = 30;
    my $attempt = 0;
    my $ctdb_healthy = 0;
    
    while ($attempt < $max_attempts && !$ctdb_healthy) {
        my $status_output = `ctdb status 2>/dev/null`;
        if ($status_output =~ /Number of nodes:\s*(\d+)/ && $1 > 0) {
            $ctdb_healthy = 1;
        } else {
            sleep 2;
            $attempt++;
        }
    }
    
    unless ($ctdb_healthy) {
        die "CTDB cluster failed to become healthy after $max_attempts attempts";
    }
    
    return {
        nodes => $nodes,
        vip => $vip,
        status => 'healthy'
    };
}

sub _resolve_node_ip {
    my ($node) = @_;
    
    # If it's already an IP address, return it
    if ($node =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        return $node;
    }
    
    # Try to resolve hostname to IP
    my $ip_output = `getent hosts $node 2>/dev/null | awk '{print \$1}' | head -1`;
    chomp $ip_output;
    
    if ($ip_output && $ip_output =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        return $ip_output;
    }
    
    # If resolution fails, try ping to get IP
    my $ping_output = `ping -c 1 $node 2>/dev/null | grep 'PING' | grep -o '([0-9.]*)'`;
    if ($ping_output =~ /\((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\)/) {
        return $1;
    }
    
    die "Cannot resolve IP address for node: $node";
}

sub _allocate_vip {
    my ($self) = @_;
    
    # Get network information from the first network interface
    my $ip_output = `ip route get 8.8.8.8 2>/dev/null | head -1`;
    my $network_base;
    
    if ($ip_output =~ /src\s+(\d+\.\d+\.\d+)\.\d+/) {
        $network_base = $1;
    } else {
        # Fallback to common private network ranges
        $network_base = '192.168.1';
    }
    
    # Try to find an available IP in the same subnet
    for my $last_octet (100..199) {
        my $test_ip = "$network_base.$last_octet";
        
        # Check if IP is available (no ping response)
        my $ping_result = system("ping -c 1 -W 1 $test_ip >/dev/null 2>&1");
        if ($ping_result != 0) {
            # IP appears to be available
            return $test_ip;
        }
    }
    
    die "Cannot find available IP address for VIP allocation";
}

sub _monitor_vip_health {
    my ($self, $vip, $nodes) = @_;
    
    my $status = {
        vip => $vip,
        nodes => $nodes,
        active_node => undef,
        status => 'unknown',
        last_check => time()
    };
    
    # Check if CTDB is running
    my $ctdb_status = `systemctl is-active ctdb 2>/dev/null`;
    chomp $ctdb_status;
    
    if ($ctdb_status ne 'active') {
        $status->{status} = 'ctdb_down';
        $status->{message} = 'CTDB service is not running';
        return $status;
    }
    
    # Check CTDB cluster status
    my $cluster_status = `ctdb status 2>/dev/null`;
    if ($cluster_status =~ /Number of nodes:\s*(\d+)/) {
        $status->{cluster_size} = $1;
        
        # Check which node has the VIP
        my $ip_status = `ctdb ip 2>/dev/null`;
        if ($ip_status =~ /$vip\s+(\d+)\s+(\S+)/) {
            $status->{active_node} = $1;
            $status->{node_status} = $2;
            
            if ($2 eq 'OK') {
                $status->{status} = 'healthy';
                $status->{message} = "VIP $vip is active on node $1";
            } else {
                $status->{status} = 'degraded';
                $status->{message} = "VIP $vip on node $1 has status: $2";
            }
        } else {
            $status->{status} = 'vip_missing';
            $status->{message} = "VIP $vip not found in CTDB";
        }
    } else {
        $status->{status} = 'cluster_error';
        $status->{message} = 'Cannot get CTDB cluster status';
    }
    
    return $status;
}

# -------- rollback system --------
sub _rollback_creation {
    my ($rollback_steps) = @_;
    
    # Execute rollback steps in reverse order
    foreach my $step (reverse @$rollback_steps) {
        my ($action, @args) = @$step;
        
        eval {
            if ($action eq 'rmdir') {
                rmdir $args[0] if -d $args[0];
            } elsif ($action eq 'destroy_ct') {
                run_command(['pct', 'destroy', $args[0]], undef, undef, 1);
            } elsif ($action eq 'destroy_vm') {
                run_command(['qm', 'destroy', $args[0]], undef, undef, 1);
            } elsif ($action eq 'restore_smb_conf') {
                run_command(['cp', $args[0], '/etc/samba/smb.conf']) if -f $args[0];
                unlink $args[0];
            } elsif ($action eq 'remove_quota') {
                _remove_quota($args[0], $args[1]);
            } elsif ($action eq 'zfs_remove_quota') {
                run_command(['zfs', 'inherit', 'quota', $args[0]], undef, undef, 1);
            } elsif ($action eq 'xfs_remove_quota') {
                # Remove XFS project quota
                my ($project_id, $mount_point) = @args;
                run_command(['xfs_quota', '-x', '-c', "limit -p bhard=0 $project_id", $mount_point], undef, undef, 1);
            } elsif ($action eq 'user_remove_quota') {
                # Remove user quota
                my ($user, $mount_point) = @args;
                run_command(['setquota', '-u', $user, '0', '0', '0', '0', $mount_point], undef, undef, 1);
            } elsif ($action eq 'ad_packages_installed') {
                # Note: We don't automatically remove AD packages as they might be used elsewhere
                warn "AD packages were installed during setup";
            } elsif ($action eq 'leave_ad_domain') {
                # Leave AD domain
                my ($domain) = @args;
                run_command(['realm', 'leave', $domain], undef, undef, 1);
            } elsif ($action eq 'ctdb_package_installed') {
                # Note: We don't automatically remove CTDB package as it might be used elsewhere
                warn "CTDB package was installed during setup";
            } elsif ($action eq 'remove_ctdb_config_dir') {
                # Remove CTDB configuration directory
                run_command(['rm', '-rf', '/etc/ctdb'], undef, undef, 1);
            } elsif ($action eq 'remove_ctdb_nodes_file') {
                # Remove CTDB nodes file
                unlink '/etc/ctdb/nodes';
            } elsif ($action eq 'remove_ctdb_pa_file') {
                # Remove CTDB public addresses file
                unlink '/etc/ctdb/public_addresses';
            } elsif ($action eq 'stop_ctdb_service') {
                # Stop and disable CTDB service
                run_command(['systemctl', 'stop', 'ctdb'], undef, undef, 1);
                run_command(['systemctl', 'disable', 'ctdb'], undef, undef, 1);
            }
        };
        
        if ($@) {
            warn "Rollback step failed: $action - $@";
        }
    }
}

sub _remove_quota {
    my ($path, $fs_type) = @_;
    
    eval {
        if ($fs_type eq 'zfs') {
            # Get ZFS dataset name
            my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
            chomp $dataset;
            if ($dataset) {
                run_command(['zfs', 'inherit', 'quota', $dataset]);
            }
        } elsif ($fs_type eq 'xfs') {
            # Remove XFS project quota (implementation depends on how it was set)
            warn "XFS quota removal not fully implemented";
        } else {
            # Remove user quota
            my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
            chomp $mount_point;
            run_command(['setquota', '-u', 'root', '0', '0', '0', '0', $mount_point]);
        }
    };
    
    if ($@) {
        warn "Failed to remove quota for $path: $@";
    }
}

# -------- missing helper methods --------
sub _install_samba_in_lxc {
    my ($ctid, $share, $ad_domain, $ctdb_vip) = @_;
    
    # Update package list
    run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'update']);
    
    # Install Samba
    run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'install', '-y', 'samba', 'samba-common-bin']);
    
    # Create Samba configuration
    my $smb_config = "
[global]
  workgroup = WORKGROUP
  server string = SMB Gateway
  security = user
  map to guest = bad user
  dns proxy = no

[$share]
  path = /srv/share
  browseable = yes
  writable = yes
  guest ok = no
  read only = no
";
    
    # Handle AD domain integration
    if ($ad_domain) {
        my $ad_username = $ENV{SMB_AD_USERNAME} // 'Administrator';
        my $ad_password = $ENV{SMB_AD_PASSWORD};
        my $ad_ou = $ENV{SMB_AD_OU};
        my $ad_fallback = $ENV{SMB_AD_FALLBACK} // '1';
        
        if ($ad_password) {
            # Install AD integration packages
            run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'install', '-y', 'realmd', 'sssd', 'sssd-tools', 'libnss-sss', 'libpam-sss', 'adcli']);
            
            # Join domain
            my $domain_info = _join_ad_domain_lxc($ctid, $ad_domain, $ad_username, $ad_password, $ad_ou, $ad_fallback eq '1');
            
            # Update Samba configuration for AD
            $smb_config = "
[global]
  workgroup = $domain_info->{workgroup}
  realm = $domain_info->{realm}
  security = ads
  idmap config * : backend = tdb
  idmap config * : range = 10000-20000
  winbind use default domain = yes
  winbind enum users = yes
  winbind enum groups = yes
";
            
            if ($ad_fallback eq '1') {
                $smb_config .= "  auth methods = kerberos winbind sam\n";
                $smb_config .= "  winbind offline logon = yes\n";
            }
            
            $smb_config .= "
[$share]
  path = /srv/share
  browseable = yes
  writable = yes
  guest ok = no
  read only = no
";
        }
    }
    
    # Write configuration to container
    run_command(['pct', 'exec', $ctid, '--', 'bash', '-c', "cat > /etc/samba/smb.conf << 'EOF'\n$smb_config\nEOF"]);
    
    # Enable and start services
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'enable', 'smbd', 'nmbd']);
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'start', 'smbd', 'nmbd']);
}

# -------- AD domain integration methods --------
sub _join_ad_domain {
    my ($self, $domain, $username, $password, $ou, $mode, $container_or_vm_id, $rollback_steps, $share, $fallback) = @_;
    
    if ($mode eq 'native') {
        return _join_ad_domain_native($domain, $username, $password, $ou, $fallback, $rollback_steps);
    } elsif ($mode eq 'lxc') {
        return _join_ad_domain_lxc($container_or_vm_id, $domain, $username, $password, $ou, $fallback);
    } elsif ($mode eq 'vm') {
        # VM joining is handled in _join_ad_domain_vm
        die "VM domain joining should use _join_ad_domain_vm directly";
    } else {
        die "Unknown mode for AD domain join: $mode";
    }
}

sub _join_ad_domain_native {
    my ($domain, $username, $password, $ou, $fallback, $rollback_steps) = @_;
    
    # Install AD integration packages if not present
    my $packages_needed = 0;
    my @required_packages = ('realmd', 'sssd', 'sssd-tools', 'libnss-sss', 'libpam-sss', 'adcli', 'samba-common-bin');
    
    foreach my $package (@required_packages) {
        my $check_result = system("dpkg -l $package >/dev/null 2>&1");
        if ($check_result != 0) {
            $packages_needed = 1;
            last;
        }
    }
    
    if ($packages_needed) {
        run_command(['apt-get', 'update']);
        run_command(['apt-get', 'install', '-y', @required_packages]);
        push @$rollback_steps, ['ad_packages_installed'];
    }
    
    # Discover domain
    my $realm_output = `realm discover $domain 2>/dev/null`;
    unless ($realm_output =~ /domain-name:\s*(\S+)/) {
        die "Failed to discover domain: $domain";
    }
    
    my $realm = uc($1);
    my $workgroup = uc(substr($domain, 0, index($domain, '.')));
    
    # Join domain
    my $join_cmd = "realm join --user=$username";
    $join_cmd .= " --computer-ou='$ou'" if $ou;
    $join_cmd .= " $domain";
    
    # Use expect to handle password prompt
    my $expect_script = "
expect -c '
spawn $join_cmd
expect \"Password for $username:\"
send \"$password\\r\"
expect eof
'";
    
    my $join_result = system($expect_script);
    if ($join_result != 0) {
        if ($fallback) {
            warn "Domain join failed, continuing with fallback authentication";
        } else {
            die "Failed to join domain: $domain";
        }
    } else {
        # Add rollback step for domain leave
        push @$rollback_steps, ['leave_ad_domain', $domain];
    }
    
    return {
        realm => $realm,
        workgroup => $workgroup,
        domain => $domain
    };
}

sub _join_ad_domain_lxc {
    my ($ctid, $domain, $username, $password, $ou, $fallback) = @_;
    
    # Discover domain
    my $realm_output = `pct exec $ctid -- realm discover $domain 2>/dev/null`;
    unless ($realm_output =~ /domain-name:\s*(\S+)/) {
        die "Failed to discover domain: $domain";
    }
    
    my $realm = uc($1);
    my $workgroup = uc(substr($domain, 0, index($domain, '.')));
    
    # Join domain
    my $join_cmd = "pct exec $ctid -- realm join --user=$username";
    $join_cmd .= " --computer-ou='$ou'" if $ou;
    $join_cmd .= " $domain";
    
    # Use expect to handle password prompt
    my $expect_script = "
expect -c '
spawn $join_cmd
expect \"Password for $username:\"
send \"$password\\r\"
expect eof
'";
    
    my $join_result = system($expect_script);
    if ($join_result != 0) {
        if ($fallback) {
            warn "Domain join failed, continuing with fallback authentication";
        } else {
            die "Failed to join domain: $domain";
        }
    }
    
    return {
        realm => $realm,
        workgroup => $workgroup,
        domain => $domain
    };
}

1;# 
-------- quota monitoring methods --------
sub _get_zfs_quota_usage {
    my ($path) = @_;
    
    # Get ZFS dataset name
    my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
    chomp $dataset;
    
    return undef unless $dataset;
    
    # Get quota and used space
    my $quota_output = `zfs get -H quota,used $dataset 2>/dev/null`;
    my ($quota_line, $used_line) = split /\n/, $quota_output;
    
    return undef unless $quota_line && $used_line;
    
    my (undef, undef, $quota_str) = split /\t/, $quota_line;
    my (undef, undef, $used_str) = split /\t/, $used_line;
    
    return undef if $quota_str eq 'none' || $quota_str eq '-';
    
    # Convert to bytes
    my $quota_bytes = _parse_size_string($quota_str);
    my $used_bytes = _parse_size_string($used_str);
    
    return undef unless $quota_bytes && $used_bytes;
    
    my $percent = int(($used_bytes / $quota_bytes) * 100);
    
    return {
        quota => $quota_str,
        used => $used_str,
        quota_bytes => $quota_bytes,
        used_bytes => $used_bytes,
        percent => $percent
    };
}

sub _get_xfs_quota_usage {
    my ($path) = @_;
    
    # Get mount point
    my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Check if xfs_quota is available
    return undef unless system('which xfs_quota >/dev/null 2>&1') == 0;
    
    # Get project quota information
    my $quota_output = `xfs_quota -x -c "report -p" "$mount_point" 2>/dev/null`;
    
    # Parse quota output to find our path
    foreach my $line (split /\n/, $quota_output) {
        if ($line =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {
            my ($project_id, $used_kb, $soft_kb, $hard_kb) = ($1, $2, $3, $4);
            
            # Check if this project matches our path
            my $project_path = `grep "^$project_id:" /etc/projects 2>/dev/null | cut -d: -f2`;
            chomp $project_path;
            
            if ($project_path eq $path) {
                my $quota_bytes = $hard_kb * 1024;
                my $used_bytes = $used_kb * 1024;
                my $percent = $quota_bytes > 0 ? int(($used_bytes / $quota_bytes) * 100) : 0;
                
                return {
                    quota => _format_size($quota_bytes),
                    used => _format_size($used_bytes),
                    quota_bytes => $quota_bytes,
                    used_bytes => $used_bytes,
                    percent => $percent
                };
            }
        }
    }
    
    return undef;
}

sub _get_user_quota_usage {
    my ($path) = @_;
    
    # Check if quota tools are available
    return undef unless system('which quota >/dev/null 2>&1') == 0;
    
    # Get mount point
    my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Get user quota for root
    my $quota_output = `quota -u root 2>/dev/null`;
    
    # Parse quota output
    foreach my $line (split /\n/, $quota_output) {
        if ($line =~ /^\s*(\S+)\s+(\d+)\s+(\d+)\s+(\d+)/) {
            my ($filesystem, $used_kb, $soft_kb, $hard_kb) = ($1, $2, $3, $4);
            
            if ($filesystem eq $mount_point) {
                my $quota_bytes = $hard_kb * 1024;
                my $used_bytes = $used_kb * 1024;
                my $percent = $quota_bytes > 0 ? int(($used_bytes / $quota_bytes) * 100) : 0;
                
                return {
                    quota => _format_size($quota_bytes),
                    used => _format_size($used_bytes),
                    quota_bytes => $quota_bytes,
                    used_bytes => $used_bytes,
                    percent => $percent
                };
            }
        }
    }
    
    return undef;
}

sub _parse_size_string {
    my ($size_str) = @_;
    
    return 0 unless $size_str;
    
    if ($size_str =~ /^(\d+(?:\.\d+)?)([KMGT]?)$/) {
        my ($num, $unit) = ($1, $2);
        
        if ($unit eq 'K') {
            return int($num * 1024);
        } elsif ($unit eq 'M') {
            return int($num * 1024**2);
        } elsif ($unit eq 'G') {
            return int($num * 1024**3);
        } elsif ($unit eq 'T') {
            return int($num * 1024**4);
        } else {
            return int($num);
        }
    }
    
    return 0;
}

sub _format_size {
    my ($bytes) = @_;
    
    return '0' unless $bytes;
    
    if ($bytes >= 1024**4) {
        return sprintf("%.1fT", $bytes / (1024**4));
    } elsif ($bytes >= 1024**3) {
        return sprintf("%.1fG", $bytes / (1024**3));
    } elsif ($bytes >= 1024**2) {
        return sprintf("%.1fM", $bytes / (1024**2));
    } elsif ($bytes >= 1024) {
        return sprintf("%.1fK", $bytes / 1024);
    } else {
        return "${bytes}B";
    }
}

sub _update_quota_history {
    my ($path, $used_bytes, $percent) = @_;
    
    # Create history directory if it doesn't exist
    my $history_dir = "/etc/pve/smbgateway/history";
    unless (-d $history_dir) {
        eval { 
            mkdir $history_dir;
        };
        return if $@;
    }
    
    # Create history file
    my $history_file = "$history_dir/" . _path_to_filename($path) . ".history";
    
    eval {
        # Read existing history
        my @history = ();
        if (-f $history_file) {
            open my $fh, '<', $history_file or die "Cannot read $history_file: $!";
            @history = <$fh>;
            close $fh;
        }
        
        # Add new entry
        my $timestamp = time();
        push @history, "$timestamp,$used_bytes,$percent\n";
        
        # Keep only last 100 entries
        if (@history > 100) {
            @history = @history[-100..-1];
        }
        
        # Write back to file
        open my $fh, '>', $history_file or die "Cannot write to $history_file: $!";
        print $fh @history;
        close $fh;
    };
    
    if ($@) {
        warn "Failed to update quota history: $@";
    }
}

sub _get_quota_trend {
    my ($path) = @_;
    
    # Get history file path
    my $history_dir = "/etc/pve/smbgateway/history";
    my $history_file = "$history_dir/" . _path_to_filename($path) . ".history";
    
    # Check if file exists
    return undef unless -f $history_file;
    
    # Read history
    my @history = ();
    eval {
        open my $fh, '<', $history_file or die "Cannot read $history_file: $!";
        @history = <$fh>;
        close $fh;
    };
    
    return undef if $@ || @history < 2;
    
    # Parse history entries
    my @entries = ();
    foreach my $line (@history) {
        chomp $line;
        my ($timestamp, $used_bytes, $percent) = split /,/, $line;
        push @entries, {
            timestamp => $timestamp,
            used_bytes => $used_bytes,
            percent => $percent
        };
    }
    
    # Calculate trend over last 24 hours
    my $now = time();
    my $day_ago = $now - (24 * 60 * 60);
    
    my @recent_entries = grep { $_->{timestamp} >= $day_ago } @entries;
    return undef if @recent_entries < 2;
    
    # Calculate average change per hour
    my $first_entry = $recent_entries[0];
    my $last_entry = $recent_entries[-1];
    
    my $time_diff = $last_entry->{timestamp} - $first_entry->{timestamp};
    return undef if $time_diff <= 0;
    
    my $percent_change = $last_entry->{percent} - $first_entry->{percent};
    my $bytes_change = $last_entry->{used_bytes} - $first_entry->{used_bytes};
    
    my $hours = $time_diff / 3600;
    my $percent_per_hour = $percent_change / $hours;
    my $bytes_per_hour = $bytes_change / $hours;
    
    return {
        percent_per_hour => sprintf("%.2f", $percent_per_hour),
        bytes_per_hour => $bytes_per_hour,
        direction => $percent_change > 0 ? 'increasing' : ($percent_change < 0 ? 'decreasing' : 'stable'),
        data_points => scalar(@recent_entries),
        time_span_hours => sprintf("%.1f", $hours)
    };
}

1;