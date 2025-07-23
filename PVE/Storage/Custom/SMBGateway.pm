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
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::Exception qw(raise_param_exc);
use PVE::SMBGateway::Monitor;
use PVE::JSONSchema qw(get_standard_option);
use Time::HiRes qw(time);
use JSON::PP;

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

    # Start operation tracking
    my $operation_id = _start_operation('create_storage', {
        mode => $mode,
        sharename => $sharename,
        path => $path,
        quota => $quota,
        ad_domain => $ad_domain,
        ctdb_vip => $ctdb_vip,
        ha_enabled => $ha_enabled,
        ha_nodes => $ha_nodes
    });
    
    # Track what we've created for rollback
    my @rollback_steps = ();
    
    eval {
        _add_operation_step('validation', 'Validating storage parameters', {
            mode => $mode,
            sharename => $sharename,
            path => $path
        });
        
        if ($mode eq 'native') {
            _native_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
        } elsif ($mode eq 'lxc') {
            _lxc_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
        } elsif ($mode eq 'vm') {
            _vm_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, $vm_memory, $vm_cores, \@rollback_steps);
        } else {
            die "Unknown mode: $mode";
        }
        
        _add_operation_step('completion', 'Storage creation completed successfully', {
            mode => $mode,
            sharename => $sharename
        });
    };
    
    if ($@) {
        my $error_message = "Failed to create share: $@";
        
        _log_operation('ERROR', $error_message, {
            operation_id => $operation_id,
            mode => $mode,
            sharename => $sharename
        });
        
        # Rollback on failure
        _add_operation_step('rollback', 'Starting rollback procedure', {
            steps_count => scalar @rollback_steps
        });
        
        my $rollback_result = _rollback_creation_enhanced(\@rollback_steps);
        
        # Create cleanup report
        _create_cleanup_report($operation_id);
        
        _end_operation(0, $error_message);
        die $error_message;
    }
    
    _end_operation(1, undef);
}

# -------- native mode implementations --------
sub _native_create {
    my ($path, $share, $quota, $ad_domain, $ctdb_vip, $rollback_steps) = @_;
    
    # Create directory
    mkdir $path unless -d $path;
    _add_rollback_step('rmdir', "Remove directory: $path", $path);
    
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
        _add_rollback_step('restore_smb_conf', "Restore Samba configuration from backup", $backup_conf);
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
    
    _add_rollback_step('destroy_ct', "Destroy LXC container: $ctid", $ctid);
    
    # Create directory
    mkdir $path unless -d $path;
    _add_rollback_step('rmdir', "Remove directory: $path", $path);
    
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
        _add_rollback_step('remove_quota', "Remove quota from: $path", $path, $fs_type);
        
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
        _add_rollback_step('zfs_remove_quota', "Remove ZFS quota from dataset: $dataset", $dataset);
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
            _add_rollback_step('xfs_remove_quota', "Remove XFS quota for project: $next_id", $next_id, $mount_point);
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
        _add_rollback_step('user_remove_quota', "Remove user quota for root", 'root', $mount_point);
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

# -------- Active Directory integration --------
sub _join_ad_domain {
    my ($self, $domain, $username, $password, $ou, $mode, $container_or_vm_id, $rollback_steps, $share, $fallback) = @_;
    
    # Validate domain format
    unless ($domain =~ /^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/) {
        die "Invalid domain format: $domain";
    }
    
    # Validate credentials
    unless ($username && $password) {
        die "AD username and password are required for domain join";
    }
    
    # Discover domain controllers
    my $dc_info = _discover_domain_controllers($domain);
    unless ($dc_info) {
        die "Cannot discover domain controllers for $domain";
    }
    
    # Test connectivity to domain controllers
    my $dc_online = _test_dc_connectivity($dc_info);
    unless ($dc_online) {
        if ($fallback) {
            warn "Domain controller connectivity failed, using fallback authentication";
            return _setup_fallback_auth($share, $rollback_steps);
        } else {
            die "Cannot connect to domain controllers for $domain";
        }
    }
    
    # Configure Kerberos
    _configure_kerberos($domain, $dc_info, $mode, $container_or_vm_id);
    
    # Join domain based on mode
    my $join_result;
    if ($mode eq 'lxc') {
        $join_result = _join_ad_domain_lxc($container_or_vm_id, $domain, $username, $password, $ou, $fallback);
    } elsif ($mode eq 'vm') {
        $join_result = _join_ad_domain_vm($container_or_vm_id, $domain, $username, $password, $ou, $fallback);
    } else {
        $join_result = _join_ad_domain_native($domain, $username, $password, $ou, $fallback);
    }
    
    # Configure Samba for AD authentication
    _configure_samba_ad($share, $domain, $dc_info, $fallback);
    
    return $join_result;
}

sub _discover_domain_controllers {
    my ($domain) = @_;
    
    my $dc_info = {
        domain => $domain,
        realm => uc($domain),
        workgroup => uc((split /\./, $domain)[0]),
        controllers => []
    };
    
    # Try DNS SRV records first
    my $srv_records = `nslookup -type=srv _ldap._tcp.$domain 2>/dev/null`;
    if ($srv_records =~ /(\w+\.$domain)/g) {
        push @{$dc_info->{controllers}}, $1;
    }
    
    # Fallback to direct domain lookup
    unless (@{$dc_info->{controllers}}) {
        my $domain_lookup = `nslookup $domain 2>/dev/null`;
        if ($domain_lookup =~ /Address:\s*(\d+\.\d+\.\d+\.\d+)/) {
            push @{$dc_info->{controllers}}, $1;
        }
    }
    
    # Try common DC names
    unless (@{$dc_info->{controllers}}) {
        my @common_dc_names = ("dc1", "dc", "ad", "ldap");
        foreach my $dc_name (@common_dc_names) {
            my $dc_test = `nslookup $dc_name.$domain 2>/dev/null`;
            if ($dc_test =~ /Address:\s*(\d+\.\d+\.\d+\.\d+)/) {
                push @{$dc_info->{controllers}}, "$dc_name.$domain";
                last;
            }
        }
    }
    
    return @{$dc_info->{controllers}} ? $dc_info : undef;
}

sub _test_dc_connectivity {
    my ($dc_info) = @_;
    
    foreach my $dc (@{$dc_info->{controllers}}) {
        # Test LDAP connectivity
        my $ldap_test = `timeout 5 ldapsearch -H ldap://$dc -x -b "" -s base 2>/dev/null`;
        if ($ldap_test && $ldap_test !~ /error/i) {
            return $dc;
        }
        
        # Test SMB connectivity
        my $smb_test = `timeout 5 smbclient -L $dc -U guest% 2>/dev/null`;
        if ($smb_test && $smb_test !~ /error/i) {
            return $dc;
        }
    }
    
    return undef;
}

sub _configure_kerberos {
    my ($domain, $dc_info, $mode, $container_or_vm_id) = @_;
    
    my $krb5_conf = "
[libdefaults]
    default_realm = $dc_info->{realm}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    $dc_info->{realm} = {
        kdc = $dc_info->{controllers}[0]
        admin_server = $dc_info->{controllers}[0]
        default_domain = $domain
    }

[domain_realm]
    .$domain = $dc_info->{realm}
    $domain = $dc_info->{realm}
";
    
    if ($mode eq 'lxc') {
        # Write krb5.conf to container
        my $temp_file = "/tmp/krb5.conf.$$";
        open(my $fh, '>', $temp_file) or die "Cannot create temp krb5.conf: $!";
        print $fh $krb5_conf;
        close $fh;
        
        run_command(['pct', 'push', $container_or_vm_id, $temp_file, '/etc/krb5.conf']);
        unlink $temp_file;
        
    } elsif ($mode eq 'vm') {
        # Write krb5.conf to VM
        my $temp_file = "/tmp/krb5.conf.$$";
        open(my $fh, '>', $temp_file) or die "Cannot create temp krb5.conf: $!";
        print $fh $krb5_conf;
        close $fh;
        
        # Get VM IP
        my $vm_ip = _wait_for_vm_ip($container_or_vm_id);
        if ($vm_ip) {
            run_command(['scp', $temp_file, "root\@$vm_ip:/etc/krb5.conf"]);
        }
        unlink $temp_file;
        
    } else {
        # Write krb5.conf to host
        open(my $fh, '>', '/etc/krb5.conf') or die "Cannot write /etc/krb5.conf: $!";
        print $fh $krb5_conf;
        close $fh;
    }
}

sub _join_ad_domain_lxc {
    my ($container_id, $domain, $username, $password, $ou, $fallback) = @_;
    
    # Install required packages in container
    run_command(['pct', 'exec', $container_id, '--', 'apt-get', 'update']);
    run_command(['pct', 'exec', $container_id, '--', 'apt-get', 'install', '-y', 'samba', 'winbind', 'krb5-user', 'libpam-krb5']);
    
    # Configure Samba for AD join
    my $smb_conf = "
[global]
    workgroup = " . uc((split /\./, $domain)[0]) . "
    realm = " . uc($domain) . "
    security = ads
    encrypt passwords = yes
    password server = $domain
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    template homedir = /home/%D/%U
    template shell = /bin/bash
    client use spnego = yes
    client ntlmv2 auth = yes
    restrict anonymous = 2
";
    
    # Write smb.conf to container
    my $temp_file = "/tmp/smb.conf.$$";
    open(my $fh, '>', $temp_file) or die "Cannot create temp smb.conf: $!";
    print $fh $smb_conf;
    close $fh;
    
    run_command(['pct', 'push', $container_id, $temp_file, '/etc/samba/smb.conf']);
    unlink $temp_file;
    
    # Join domain
    my $join_cmd = "net ads join -U $username%$password";
    if ($ou) {
        $join_cmd .= " -s $ou";
    }
    
    my $join_result = `pct exec $container_id -- $join_cmd 2>&1`;
    if ($join_result =~ /Joined/) {
        # Start winbind service
        run_command(['pct', 'exec', $container_id, '--', 'systemctl', 'enable', 'winbind']);
        run_command(['pct', 'exec', $container_id, '--', 'systemctl', 'start', 'winbind']);
        
        return {
            success => 1,
            message => "Successfully joined domain $domain",
            realm => uc($domain),
            workgroup => uc((split /\./, $domain)[0])
        };
    } else {
        if ($fallback) {
            warn "Domain join failed: $join_result, using fallback authentication";
            return _setup_fallback_auth_lxc($container_id);
        } else {
            die "Domain join failed: $join_result";
        }
    }
}

sub _join_ad_domain_vm {
    my ($vm_id, $domain, $username, $password, $ou, $fallback) = @_;
    
    # Get VM IP
    my $vm_ip = _wait_for_vm_ip($vm_id);
    unless ($vm_ip) {
        die "Cannot get VM IP address for domain join";
    }
    
    # Install required packages in VM
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    run_command([$ssh_cmd, 'apt-get', 'update']);
    run_command([$ssh_cmd, 'apt-get', 'install', '-y', 'samba', 'winbind', 'krb5-user', 'libpam-krb5']);
    
    # Configure Samba for AD join
    my $smb_conf = "
[global]
    workgroup = " . uc((split /\./, $domain)[0]) . "
    realm = " . uc($domain) . "
    security = ads
    encrypt passwords = yes
    password server = $domain
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    template homedir = /home/%D/%U
    template shell = /bin/bash
    client use spnego = yes
    client ntlmv2 auth = yes
    restrict anonymous = 2
";
    
    # Write smb.conf to VM
    run_command([$ssh_cmd, 'cat > /etc/samba/smb.conf << EOF' . $smb_conf . 'EOF']);
    
    # Join domain
    my $join_cmd = "net ads join -U $username%$password";
    if ($ou) {
        $join_cmd .= " -s $ou";
    }
    
    my $join_result = `$ssh_cmd '$join_cmd' 2>&1`;
    if ($join_result =~ /Joined/) {
        # Start winbind service
        run_command([$ssh_cmd, 'systemctl', 'enable', 'winbind']);
        run_command([$ssh_cmd, 'systemctl', 'start', 'winbind']);
        
        return {
            success => 1,
            message => "Successfully joined domain $domain",
            realm => uc($domain),
            workgroup => uc((split /\./, $domain)[0])
        };
    } else {
        if ($fallback) {
            warn "Domain join failed: $join_result, using fallback authentication";
            return _setup_fallback_auth_vm($vm_id, $vm_ip);
        } else {
            die "Domain join failed: $join_result";
        }
    }
}

sub _join_ad_domain_native {
    my ($domain, $username, $password, $ou, $fallback) = @_;
    
    # Install required packages
    run_command(['apt-get', 'update']);
    run_command(['apt-get', 'install', '-y', 'samba', 'winbind', 'krb5-user', 'libpam-krb5']);
    
    # Configure Samba for AD join
    my $smb_conf = "
[global]
    workgroup = " . uc((split /\./, $domain)[0]) . "
    realm = " . uc($domain) . "
    security = ads
    encrypt passwords = yes
    password server = $domain
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    template homedir = /home/%D/%U
    template shell = /bin/bash
    client use spnego = yes
    client ntlmv2 auth = yes
    restrict anonymous = 2
";
    
    # Write smb.conf
    open(my $fh, '>', '/etc/samba/smb.conf') or die "Cannot write /etc/samba/smb.conf: $!";
    print $fh $smb_conf;
    close $fh;
    
    # Join domain
    my $join_cmd = "net ads join -U $username%$password";
    if ($ou) {
        $join_cmd .= " -s $ou";
    }
    
    my $join_result = `$join_cmd 2>&1`;
    if ($join_result =~ /Joined/) {
        # Start winbind service
        run_command(['systemctl', 'enable', 'winbind']);
        run_command(['systemctl', 'start', 'winbind']);
        
        return {
            success => 1,
            message => "Successfully joined domain $domain",
            realm => uc($domain),
            workgroup => uc((split /\./, $domain)[0])
        };
    } else {
        if ($fallback) {
            warn "Domain join failed, continuing with fallback authentication";
        } else {
            die "Failed to join domain: $domain";
        }
    }
}

sub _configure_samba_ad {
    my ($share, $domain, $dc_info, $fallback) = @_;
    
    my $share_config = "
[$share]
    path = /srv/smb/$share
    browseable = yes
    writable = yes
    guest ok = no
    read only = no
    security = ads
    realm = $dc_info->{realm}
    workgroup = $dc_info->{workgroup}
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    template homedir = /home/%D/%U
    template shell = /bin/bash
    client use spnego = yes
    client ntlmv2 auth = yes
    restrict anonymous = 2
";
    
    # Add to existing smb.conf
    open(my $fh, '>>', '/etc/samba/smb.conf') or die "Cannot append to /etc/samba/smb.conf: $!";
    print $fh $share_config;
    close $fh;
    
    # Reload Samba configuration
    run_command(['systemctl', 'reload', 'smbd']);
    run_command(['systemctl', 'reload', 'nmbd']);
}

sub _setup_fallback_auth {
    my ($share, $rollback_steps) = @_;
    
    # Create local user for fallback authentication
    my $fallback_user = "smb_$share";
    my $fallback_password = `openssl rand -base64 12`;
    chomp $fallback_password;
    
    # Add user to system
    run_command(['useradd', '-m', '-s', '/bin/bash', $fallback_user]);
    run_command(['echo', "$fallback_user:$fallback_password", '|', 'chpasswd']);
    
    # Add to rollback steps
    _add_rollback_step('remove_user', "Remove fallback user: $fallback_user", $fallback_user);
    
    # Configure Samba for local authentication
    my $fallback_config = "
[$share]
    path = /srv/smb/$share
    browseable = yes
    writable = yes
    guest ok = no
    read only = no
    security = user
    valid users = $fallback_user
    create mask = 0644
    directory mask = 0755
";
    
    # Add to existing smb.conf
    open(my $fh, '>>', '/etc/samba/smb.conf') or die "Cannot append to /etc/samba/smb.conf: $!";
    print $fh $fallback_config;
    close $fh;
    
    # Add Samba user
    run_command(['smbpasswd', '-a', $fallback_user]);
    run_command(['smbpasswd', '-e', $fallback_user]);
    
    # Reload Samba configuration
    run_command(['systemctl', 'reload', 'smbd']);
    run_command(['systemctl', 'reload', 'nmbd']);
    
    return {
        success => 1,
        message => "Fallback authentication configured for user $fallback_user",
        fallback_user => $fallback_user,
        fallback_password => $fallback_password
    };
}

# -------- VM mode implementations --------
sub _vm_create {
    my ($path, $share, $quota, $ad_domain, $ctdb_vip, $vm_memory, $vm_cores, $rollback_steps) = @_;
    
    # Get next available VM ID
    my $vmid = `pvesh get /cluster/nextid`; 
    chomp $vmid;
    die "Failed to get next VM ID" unless $vmid =~ /^\d+$/;
    
    _add_rollback_step('destroy_vm', "Destroy VM: $vmid", $vmid);
    
    # Create directory
    mkdir $path unless -d $path;
    _add_rollback_step('rmdir', "Remove directory: $path", $path);
    
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
    my ($vm_id, $domain, $username, $password, $ou, $fallback) = @_;
    
    # Get VM IP
    my $vm_ip = _wait_for_vm_ip($vm_id);
    unless ($vm_ip) {
        die "Cannot get VM IP address for domain join";
    }
    
    # Install required packages in VM
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    run_command([$ssh_cmd, 'apt-get', 'update']);
    run_command([$ssh_cmd, 'apt-get', 'install', '-y', 'samba', 'winbind', 'krb5-user', 'libpam-krb5']);
    
    # Configure Samba for AD join
    my $smb_conf = "
[global]
    workgroup = " . uc((split /\./, $domain)[0]) . "
    realm = " . uc($domain) . "
    security = ads
    encrypt passwords = yes
    password server = $domain
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    template homedir = /home/%D/%U
    template shell = /bin/bash
    client use spnego = yes
    client ntlmv2 auth = yes
    restrict anonymous = 2
";
    
    # Write smb.conf to VM
    run_command([$ssh_cmd, 'cat > /etc/samba/smb.conf << EOF' . $smb_conf . 'EOF']);
    
    # Join domain
    my $join_cmd = "net ads join -U $username%$password";
    if ($ou) {
        $join_cmd .= " -s $ou";
    }
    
    my $join_result = `$ssh_cmd '$join_cmd' 2>&1`;
    if ($join_result =~ /Joined/) {
        # Start winbind service
        run_command([$ssh_cmd, 'systemctl', 'enable', 'winbind']);
        run_command([$ssh_cmd, 'systemctl', 'start', 'winbind']);
        
        return {
            success => 1,
            message => "Successfully joined domain $domain",
            realm => uc($domain),
            workgroup => uc((split /\./, $domain)[0])
        };
    } else {
        if ($fallback) {
            warn "Domain join failed: $join_result, using fallback authentication";
            return _setup_fallback_auth_vm($vm_id, $vm_ip);
        } else {
            die "Domain join failed: $join_result";
        }
    }
}

# -------- CTDB High Availability methods --------
sub _setup_ctdb_cluster {
    my ($self, $nodes, $vip, $mode, $container_or_vm_id, $rollback_steps, $share) = @_;
    
    # Validate VIP format
    unless ($vip =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
        die "Invalid VIP format: $vip";
    }
    
    # Validate nodes list
    unless ($nodes && ref($nodes) eq 'ARRAY' && @$nodes > 0) {
        die "Invalid nodes list for CTDB cluster";
    }
    
    # Check if VIP is available
    unless (_check_vip_availability($vip)) {
        die "VIP $vip is not available or already in use";
    }
    
    # Setup CTDB based on mode
    my $ctdb_result;
    if ($mode eq 'lxc') {
        $ctdb_result = _setup_ctdb_lxc($container_or_vm_id, $nodes, $vip, $rollback_steps, $share);
    } elsif ($mode eq 'vm') {
        $ctdb_result = _setup_ctdb_vm($container_or_vm_id, $nodes, $vip, $rollback_steps, $share);
    } else {
        $ctdb_result = _setup_ctdb_native($nodes, $vip, $rollback_steps, $share);
    }
    
    return $ctdb_result;
}

sub _check_vip_availability {
    my ($vip) = @_;
    
    # Check if VIP is already in use
    my $ping_result = `ping -c 1 -W 1 $vip 2>/dev/null`;
    if ($ping_result =~ /1 received/) {
        return 0; # VIP is in use
    }
    
    # Check if VIP is in our network range
    my $hostname = `hostname`;
    chomp $hostname;
    my $host_ip = `hostname -I | awk '{print \$1}'`;
    chomp $host_ip;
    
    # Extract network prefix
    if ($host_ip =~ /^(\d+\.\d+\.\d+)\./) {
        my $network_prefix = $1;
        if ($vip =~ /^$network_prefix\./) {
            return 1; # VIP is in our network range
        }
    }
    
    return 0; # VIP is not in our network range
}

sub _setup_ctdb_lxc {
    my ($container_id, $nodes, $vip, $rollback_steps, $share) = @_;
    
    # Install CTDB packages in container
    run_command(['pct', 'exec', $container_id, '--', 'apt-get', 'update']);
    run_command(['pct', 'exec', $container_id, '--', 'apt-get', 'install', '-y', 'ctdb', 'ctdb-dev']);
    
    # Create CTDB configuration
    my $ctdb_conf = "
CTDB_RECOVERY_LOCK=/var/lib/ctdb/ctdb.lock
CTDB_PUBLIC_ADDRESSES=/etc/ctdb/public_addresses
CTDB_NODES=/etc/ctdb/nodes
CTDB_MANAGES_SAMBA=yes
CTDB_MANAGES_WINBIND=yes
CTDB_STARTUP_TIMEOUT=60
CTDB_SHUTDOWN_TIMEOUT=60
CTDB_MONITORING_INTERVAL=15
CTDB_DEBUGLEVEL=1
";
    
    # Write CTDB configuration to container
    my $temp_file = "/tmp/ctdb.conf.$$";
    open(my $fh, '>', $temp_file) or die "Cannot create temp ctdb.conf: $!";
    print $fh $ctdb_conf;
    close $fh;
    
    run_command(['pct', 'push', $container_id, $temp_file, '/etc/ctdb/ctdb.conf']);
    unlink $temp_file;
    
    # Create nodes file
    my $nodes_content = join("\n", @$nodes) . "\n";
    my $nodes_file = "/tmp/nodes.$$";
    open(my $fh, '>', $nodes_file) or die "Cannot create temp nodes file: $!";
    print $fh $nodes_content;
    close $fh;
    
    run_command(['pct', 'push', $container_id, $nodes_file, '/etc/ctdb/nodes']);
    unlink $nodes_file;
    
    # Create public addresses file
    my $public_addresses = "$vip/24 eth0\n";
    my $pub_addr_file = "/tmp/public_addresses.$$";
    open(my $fh, '>', $pub_addr_file) or die "Cannot create temp public_addresses file: $!";
    print $fh $public_addresses;
    close $fh;
    
    run_command(['pct', 'push', $container_id, $pub_addr_file, '/etc/ctdb/public_addresses']);
    unlink $pub_addr_file;
    
    # Configure Samba for CTDB
    my $smb_conf = "
[global]
    clustering = yes
    ctdbd socket = /var/lib/ctdb/ctdb.socket
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    workgroup = WORKGROUP
    security = user
    map to guest = bad user
    dns proxy = no
    log level = 1

[$share]
    path = /srv/smb/$share
    browseable = yes
    writable = yes
    guest ok = no
    read only = no
    vfs objects = ctdb
";
    
    # Write Samba configuration to container
    my $smb_file = "/tmp/smb.conf.$$";
    open(my $fh, '>', $smb_file) or die "Cannot create temp smb.conf: $!";
    print $fh $smb_conf;
    close $fh;
    
    run_command(['pct', 'push', $container_id, $smb_file, '/etc/samba/smb.conf']);
    unlink $smb_file;
    
    # Start CTDB service
    run_command(['pct', 'exec', $container_id, '--', 'systemctl', 'enable', 'ctdb']);
    run_command(['pct', 'exec', $container_id, '--', 'systemctl', 'start', 'ctdb']);
    
    # Wait for CTDB to be ready
    my $max_attempts = 30;
    my $attempt = 0;
    while ($attempt < $max_attempts) {
        my $ctdb_status = `pct exec $container_id -- ctdb status 2>/dev/null`;
        if ($ctdb_status =~ /OK/) {
            last;
        }
        sleep 2;
        $attempt++;
    }
    
    if ($attempt >= $max_attempts) {
        die "CTDB failed to start properly in container $container_id";
    }
    
    # Add to rollback steps
    _add_rollback_step('stop_ctdb_lxc', "Stop CTDB service in LXC container: $container_id", $container_id);
    
    return {
        success => 1,
        message => "CTDB cluster setup successful in LXC container",
        vip => $vip,
        nodes => $nodes,
        container_id => $container_id
    };
}

sub _setup_ctdb_vm {
    my ($vm_id, $nodes, $vip, $rollback_steps, $share) = @_;
    
    # Get VM IP
    my $vm_ip = _wait_for_vm_ip($vm_id);
    unless ($vm_ip) {
        die "Cannot get VM IP address for CTDB setup";
    }
    
    # Install CTDB packages in VM
    my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
    run_command([$ssh_cmd, 'apt-get', 'update']);
    run_command([$ssh_cmd, 'apt-get', 'install', '-y', 'ctdb', 'ctdb-dev']);
    
    # Create CTDB configuration
    my $ctdb_conf = "
CTDB_RECOVERY_LOCK=/var/lib/ctdb/ctdb.lock
CTDB_PUBLIC_ADDRESSES=/etc/ctdb/public_addresses
CTDB_NODES=/etc/ctdb/nodes
CTDB_MANAGES_SAMBA=yes
CTDB_MANAGES_WINBIND=yes
CTDB_STARTUP_TIMEOUT=60
CTDB_SHUTDOWN_TIMEOUT=60
CTDB_MONITORING_INTERVAL=15
CTDB_DEBUGLEVEL=1
";
    
    # Write CTDB configuration to VM
    run_command([$ssh_cmd, 'cat > /etc/ctdb/ctdb.conf << EOF' . $ctdb_conf . 'EOF']);
    
    # Create nodes file
    my $nodes_content = join("\n", @$nodes) . "\n";
    run_command([$ssh_cmd, 'cat > /etc/ctdb/nodes << EOF' . $nodes_content . 'EOF']);
    
    # Create public addresses file
    my $public_addresses = "$vip/24 eth0\n";
    run_command([$ssh_cmd, 'cat > /etc/ctdb/public_addresses << EOF' . $public_addresses . 'EOF']);
    
    # Configure Samba for CTDB
    my $smb_conf = "
[global]
    clustering = yes
    ctdbd socket = /var/lib/ctdb/ctdb.socket
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    workgroup = WORKGROUP
    security = user
    map to guest = bad user
    dns proxy = no
    log level = 1

[$share]
    path = /srv/smb/$share
    browseable = yes
    writable = yes
    guest ok = no
    read only = no
    vfs objects = ctdb
";
    
    # Write Samba configuration to VM
    run_command([$ssh_cmd, 'cat > /etc/samba/smb.conf << EOF' . $smb_conf . 'EOF']);
    
    # Start CTDB service
    run_command([$ssh_cmd, 'systemctl', 'enable', 'ctdb']);
    run_command([$ssh_cmd, 'systemctl', 'start', 'ctdb']);
    
    # Wait for CTDB to be ready
    my $max_attempts = 30;
    my $attempt = 0;
    while ($attempt < $max_attempts) {
        my $ctdb_status = `$ssh_cmd 'ctdb status' 2>/dev/null`;
        if ($ctdb_status =~ /OK/) {
            last;
        }
        sleep 2;
        $attempt++;
    }
    
    if ($attempt >= $max_attempts) {
        die "CTDB failed to start properly in VM $vm_id";
    }
    
    # Add to rollback steps
    _add_rollback_step('stop_ctdb_vm', "Stop CTDB service in VM: $vm_id", $vm_id, $vm_ip);
    
    return {
        success => 1,
        message => "CTDB cluster setup successful in VM",
        vip => $vip,
        nodes => $nodes,
        vm_id => $vm_id
    };
}

sub _setup_ctdb_native {
    my ($nodes, $vip, $rollback_steps, $share) = @_;
    
    # Install CTDB packages
    run_command(['apt-get', 'update']);
    run_command(['apt-get', 'install', '-y', 'ctdb', 'ctdb-dev']);
    
    # Create CTDB configuration
    my $ctdb_conf = "
CTDB_RECOVERY_LOCK=/var/lib/ctdb/ctdb.lock
CTDB_PUBLIC_ADDRESSES=/etc/ctdb/public_addresses
CTDB_NODES=/etc/ctdb/nodes
CTDB_MANAGES_SAMBA=yes
CTDB_MANAGES_WINBIND=yes
CTDB_STARTUP_TIMEOUT=60
CTDB_SHUTDOWN_TIMEOUT=60
CTDB_MONITORING_INTERVAL=15
CTDB_DEBUGLEVEL=1
";
    
    # Write CTDB configuration
    open(my $fh, '>', '/etc/ctdb/ctdb.conf') or die "Cannot write /etc/ctdb/ctdb.conf: $!";
    print $fh $ctdb_conf;
    close $fh;
    
    # Create nodes file
    open(my $fh, '>', '/etc/ctdb/nodes') or die "Cannot write /etc/ctdb/nodes: $!";
    print $fh join("\n", @$nodes) . "\n";
    close $fh;
    
    # Create public addresses file
    open(my $fh, '>', '/etc/ctdb/public_addresses') or die "Cannot write /etc/ctdb/public_addresses: $!";
    print $fh "$vip/24 eth0\n";
    close $fh;
    
    # Configure Samba for CTDB
    my $smb_conf = "
[global]
    clustering = yes
    ctdbd socket = /var/lib/ctdb/ctdb.socket
    idmap config * : backend = tdb
    idmap config * : range = 10000-20000
    workgroup = WORKGROUP
    security = user
    map to guest = bad user
    dns proxy = no
    log level = 1

[$share]
    path = /srv/smb/$share
    browseable = yes
    writable = yes
    guest ok = no
    read only = no
    vfs objects = ctdb
";
    
    # Write Samba configuration
    open(my $fh, '>', '/etc/samba/smb.conf') or die "Cannot write /etc/samba/smb.conf: $!";
    print $fh $smb_conf;
    close $fh;
    
    # Start CTDB service
    run_command(['systemctl', 'enable', 'ctdb']);
    run_command(['systemctl', 'start', 'ctdb']);
    
    # Wait for CTDB to be ready
    my $max_attempts = 30;
    my $attempt = 0;
    while ($attempt < $max_attempts) {
        my $ctdb_status = `ctdb status 2>/dev/null`;
        if ($ctdb_status =~ /OK/) {
            last;
        }
        sleep 2;
        $attempt++;
    }
    
    if ($attempt >= $max_attempts) {
        die "CTDB failed to start properly";
    }
    
    # Add to rollback steps
    _add_rollback_step('stop_ctdb_native', "Stop CTDB service on native host");
    
    return {
        success => 1,
        message => "CTDB cluster setup successful in native mode",
        vip => $vip,
        nodes => $nodes
    };
}

sub _get_ctdb_status {
    my ($mode, $container_or_vm_id) = @_;
    
    my $status = {
        cluster_healthy => 0,
        vip_active => 0,
        nodes_online => 0,
        total_nodes => 0,
        active_node => undef,
        details => {}
    };
    
    if ($mode eq 'lxc') {
        # Get CTDB status from container
        my $ctdb_status = `pct exec $container_or_vm_id -- ctdb status 2>/dev/null`;
        $status = _parse_ctdb_status($ctdb_status);
        
        # Get VIP status
        my $vip_status = `pct exec $container_or_vm_id -- ip addr show | grep -E "inet.*eth0"`;
        if ($vip_status =~ /(\d+\.\d+\.\d+\.\d+)/) {
            $status->{vip_active} = 1;
            $status->{active_vip} = $1;
        }
        
    } elsif ($mode eq 'vm') {
        # Get VM IP
        my $vm_ip = _wait_for_vm_ip($container_or_vm_id);
        if ($vm_ip) {
            my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
            my $ctdb_status = `$ssh_cmd 'ctdb status' 2>/dev/null`;
            $status = _parse_ctdb_status($ctdb_status);
            
            # Get VIP status
            my $vip_status = `$ssh_cmd 'ip addr show | grep -E "inet.*eth0"'`;
            if ($vip_status =~ /(\d+\.\d+\.\d+\.\d+)/) {
                $status->{vip_active} = 1;
                $status->{active_vip} = $1;
            }
        }
        
    } else {
        # Get CTDB status from host
        my $ctdb_status = `ctdb status 2>/dev/null`;
        $status = _parse_ctdb_status($ctdb_status);
        
        # Get VIP status
        my $vip_status = `ip addr show | grep -E "inet.*eth0"`;
        if ($vip_status =~ /(\d+\.\d+\.\d+\.\d+)/) {
            $status->{vip_active} = 1;
            $status->{active_vip} = $1;
        }
    }
    
    return $status;
}

sub _parse_ctdb_status {
    my ($ctdb_output) = @_;
    
    my $status = {
        cluster_healthy => 0,
        nodes_online => 0,
        total_nodes => 0,
        active_node => undef,
        details => {}
    };
    
    # Parse CTDB status output
    foreach my $line (split /\n/, $ctdb_output) {
        if ($line =~ /Number of nodes:(\d+)/) {
            $status->{total_nodes} = $1;
        } elsif ($line =~ /Online:(\d+)/) {
            $status->{nodes_online} = $1;
        } elsif ($line =~ /OK/) {
            $status->{cluster_healthy} = 1;
        } elsif ($line =~ /THIS NODE/) {
            $status->{active_node} = 'this_node';
        }
    }
    
    return $status;
}

sub _trigger_ctdb_failover {
    my ($mode, $container_or_vm_id, $target_node) = @_;
    
    if ($mode eq 'lxc') {
        # Trigger failover in LXC container
        run_command(['pct', 'exec', $container_or_vm_id, '--', 'ctdb', 'reloadnodes']);
        
    } elsif ($mode eq 'vm') {
        # Get VM IP and trigger failover
        my $vm_ip = _wait_for_vm_ip($container_or_vm_id);
        if ($vm_ip) {
            my $ssh_cmd = "ssh -o StrictHostKeyChecking=no root\@$vm_ip";
            run_command([$ssh_cmd, 'ctdb', 'reloadnodes']);
        }
        
    } else {
        # Trigger failover in native mode
        run_command(['ctdb', 'reloadnodes']);
    }
    
    return {
        success => 1,
        message => "CTDB failover triggered",
        target_node => $target_node
    };
}

sub _test_ctdb_connectivity {
    my ($vip, $share) = @_;
    
    # Test SMB connectivity to VIP
    my $smb_test = `timeout 10 smbclient -L //$vip -U guest% 2>/dev/null`;
    if ($smb_test && $smb_test !~ /error/i) {
        return {
            success => 1,
            message => "SMB connectivity to VIP $vip successful",
            vip => $vip
        };
    } else {
        return {
            success => 0,
            message => "SMB connectivity to VIP $vip failed",
            vip => $vip
        };
    }
}

# -------- rollback system --------
sub _rollback_creation {
    my ($rollback_steps) = @_;
    
    # Start operation tracking if not already started
    unless ($current_operation) {
        _start_operation('rollback', { steps_count => scalar @$rollback_steps });
    }
    
    my $result = _rollback_creation_enhanced($rollback_steps);
    
    _end_operation(1, undef);
    
    return $result;
}

# -------- enhanced rollback system --------
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::JSONSchema qw(get_standard_option);
use Time::HiRes qw(time);
use JSON::PP;

# Operation tracking and logging
my $OPERATION_LOG_FILE = '/var/log/pve/smbgateway-operations.log';
my $ERROR_LOG_FILE = '/var/log/pve/smbgateway-errors.log';
my $AUDIT_LOG_FILE = '/var/log/pve/smbgateway-audit.log';

# Operation context tracking
my $current_operation = undef;
my $operation_start_time = undef;

sub _init_operation_logging {
    # Ensure log directories exist
    my $log_dir = '/var/log/pve';
    mkdir $log_dir, 0755 unless -d $log_dir;
    
    # Create log files if they don't exist
    foreach my $log_file ($OPERATION_LOG_FILE, $ERROR_LOG_FILE, $AUDIT_LOG_FILE) {
        unless (-f $log_file) {
            open(my $fh, '>', $log_file) or warn "Cannot create log file $log_file: $!";
            close($fh) if $fh;
            chmod 0644, $log_file;
        }
    }
}

sub _log_operation {
    my ($level, $message, $context) = @_;
    
    _init_operation_logging();
    
    my $timestamp = POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $operation_id = $current_operation ? $current_operation->{id} : 'unknown';
    my $context_str = $context ? encode_json($context) : '{}';
    
    my $log_entry = sprintf("[%s] [%s] [%s] %s %s\n", 
        $timestamp, $level, $operation_id, $message, $context_str);
    
    my $log_file;
    if ($level eq 'ERROR') {
        $log_file = $ERROR_LOG_FILE;
    } elsif ($level eq 'AUDIT') {
        $log_file = $AUDIT_LOG_FILE;
    } else {
        $log_file = $OPERATION_LOG_FILE;
    }
    
    open(my $fh, '>>', $log_file) or warn "Cannot write to log file $log_file: $!";
    print $fh $log_entry if $fh;
    close($fh) if $fh;
}

sub _start_operation {
    my ($operation_type, $params) = @_;
    
    $current_operation = {
        id => sprintf("%s_%d_%d", $operation_type, time(), int(rand(10000))),
        type => $operation_type,
        start_time => time(),
        params => $params,
        steps => [],
        rollback_steps => []
    };
    
    $operation_start_time = time();
    
    _log_operation('INFO', "Operation started", {
        operation_id => $current_operation->{id},
        type => $operation_type,
        params => $params
    });
    
    return $current_operation->{id};
}

sub _end_operation {
    my ($success, $error_message) = @_;
    
    return unless $current_operation;
    
    my $duration = time() - $operation_start_time;
    my $status = $success ? 'SUCCESS' : 'FAILED';
    
    _log_operation('INFO', "Operation completed", {
        operation_id => $current_operation->{id},
        status => $status,
        duration => sprintf("%.2f", $duration),
        error_message => $error_message
    });
    
    if ($success) {
        _log_operation('AUDIT', "Operation successful", {
            operation_id => $current_operation->{id},
            type => $current_operation->{type},
            duration => sprintf("%.2f", $duration)
        });
    } else {
        _log_operation('ERROR', "Operation failed", {
            operation_id => $current_operation->{id},
            type => $current_operation->{type},
            error_message => $error_message,
            duration => sprintf("%.2f", $duration)
        });
    }
    
    $current_operation = undef;
    $operation_start_time = undef;
}

sub _add_operation_step {
    my ($step_type, $description, $params) = @_;
    
    return unless $current_operation;
    
    my $step = {
        type => $step_type,
        description => $description,
        timestamp => time(),
        params => $params
    };
    
    push @{$current_operation->{steps}}, $step;
    
    _log_operation('INFO', "Operation step: $description", {
        operation_id => $current_operation->{id},
        step_type => $step_type,
        params => $params
    });
}

sub _add_rollback_step {
    my ($action, $description, @args) = @_;
    
    return unless $current_operation;
    
    my $step = {
        action => $action,
        description => $description,
        args => \@args,
        timestamp => time()
    };
    
    push @{$current_operation->{rollback_steps}}, $step;
    
    _log_operation('INFO', "Rollback step added: $description", {
        operation_id => $current_operation->{id},
        action => $action,
        args => \@args
    });
}

sub _validate_rollback_step {
    my ($step) = @_;
    
    my ($action, $description, @args) = @$step;
    
    # Validate action type
    my $valid_actions = {
        'rmdir' => 1,
        'destroy_ct' => 1,
        'destroy_vm' => 1,
        'restore_smb_conf' => 1,
        'remove_quota' => 1,
        'zfs_remove_quota' => 1,
        'xfs_remove_quota' => 1,
        'user_remove_quota' => 1,
        'ad_packages_installed' => 1,
        'leave_ad_domain' => 1,
        'ctdb_package_installed' => 1,
        'remove_ctdb_config_dir' => 1,
        'remove_ctdb_nodes_file' => 1,
        'remove_ctdb_pa_file' => 1,
        'stop_ctdb_service' => 1,
        'stop_ctdb_lxc' => 1,
        'stop_ctdb_vm' => 1,
        'stop_ctdb_native' => 1,
        'remove_user' => 1,
        'restore_network_config' => 1,
        'restore_firewall_rules' => 1,
        'restore_systemd_services' => 1
    };
    
    unless ($valid_actions->{$action}) {
        _log_operation('ERROR', "Invalid rollback action: $action", {
            action => $action,
            description => $description
        });
        return 0;
    }
    
    # Validate arguments based on action
    if ($action eq 'rmdir' && @args < 1) {
        _log_operation('ERROR', "rmdir action requires path argument", { args => \@args });
        return 0;
    }
    
    if (($action eq 'destroy_ct' || $action eq 'destroy_vm') && @args < 1) {
        _log_operation('ERROR', "$action action requires ID argument", { args => \@args });
        return 0;
    }
    
    return 1;
}

sub _execute_rollback_step {
    my ($step) = @_;
    
    my ($action, $description, @args) = @$step;
    
    _log_operation('INFO', "Executing rollback step: $description", {
        action => $action,
        args => \@args
    });
    
    eval {
        if ($action eq 'rmdir') {
            my $path = $args[0];
            if (-d $path) {
                # Check if directory is empty
                my @contents = glob("$path/*");
                if (@contents == 0) {
                    rmdir $path;
                    _log_operation('INFO', "Removed directory: $path");
                } else {
                    _log_operation('WARN', "Directory not empty, skipping removal: $path", {
                        contents_count => scalar @contents
                    });
                }
            } else {
                _log_operation('INFO', "Directory does not exist, skipping: $path");
            }
        } elsif ($action eq 'destroy_ct') {
            my $ctid = $args[0];
            # Check if container exists and is stopped
            my $status = `pct status $ctid 2>/dev/null`;
            if ($status =~ /stopped/i) {
                run_command(['pct', 'destroy', $ctid], undef, undef, 1);
                _log_operation('INFO', "Destroyed container: $ctid");
            } else {
                _log_operation('WARN', "Container not stopped, skipping destruction: $ctid", {
                    status => $status
                });
            }
        } elsif ($action eq 'destroy_vm') {
            my $vmid = $args[0];
            # Check if VM exists and is stopped
            my $status = `qm status $vmid 2>/dev/null`;
            if ($status =~ /stopped/i) {
                run_command(['qm', 'destroy', $vmid], undef, undef, 1);
                _log_operation('INFO', "Destroyed VM: $vmid");
            } else {
                _log_operation('WARN', "VM not stopped, skipping destruction: $vmid", {
                    status => $status
                });
            }
        } elsif ($action eq 'restore_smb_conf') {
            my $backup_file = $args[0];
            if (-f $backup_file) {
                run_command(['cp', $backup_file, '/etc/samba/smb.conf'], undef, undef, 1);
                unlink $backup_file;
                _log_operation('INFO', "Restored Samba configuration from: $backup_file");
            } else {
                _log_operation('WARN', "Samba backup file not found: $backup_file");
            }
        } elsif ($action eq 'remove_quota') {
            my ($path, $fs_type) = @args;
            _remove_quota_enhanced($path, $fs_type);
        } elsif ($action eq 'zfs_remove_quota') {
            my $dataset = $args[0];
            run_command(['zfs', 'inherit', 'quota', $dataset], undef, undef, 1);
            _log_operation('INFO', "Removed ZFS quota from dataset: $dataset");
        } elsif ($action eq 'xfs_remove_quota') {
            my ($project_id, $mount_point) = @args;
            run_command(['xfs_quota', '-x', '-c', "limit -p bhard=0 $project_id", $mount_point], undef, undef, 1);
            _log_operation('INFO', "Removed XFS quota for project: $project_id");
        } elsif ($action eq 'user_remove_quota') {
            my ($user, $mount_point) = @args;
            run_command(['setquota', '-u', $user, '0', '0', '0', '0', $mount_point], undef, undef, 1);
            _log_operation('INFO', "Removed user quota for: $user");
        } elsif ($action eq 'ad_packages_installed') {
            _log_operation('INFO', "AD packages were installed during setup - manual cleanup may be required");
        } elsif ($action eq 'leave_ad_domain') {
            my $domain = $args[0];
            run_command(['realm', 'leave', $domain], undef, undef, 1);
            _log_operation('INFO', "Left AD domain: $domain");
        } elsif ($action eq 'ctdb_package_installed') {
            _log_operation('INFO', "CTDB package was installed during setup - manual cleanup may be required");
        } elsif ($action eq 'remove_ctdb_config_dir') {
            if (-d '/etc/ctdb') {
                run_command(['rm', '-rf', '/etc/ctdb'], undef, undef, 1);
                _log_operation('INFO', "Removed CTDB configuration directory");
            }
        } elsif ($action eq 'remove_ctdb_nodes_file') {
            if (-f '/etc/ctdb/nodes') {
                unlink '/etc/ctdb/nodes';
                _log_operation('INFO', "Removed CTDB nodes file");
            }
        } elsif ($action eq 'remove_ctdb_pa_file') {
            if (-f '/etc/ctdb/public_addresses') {
                unlink '/etc/ctdb/public_addresses';
                _log_operation('INFO', "Removed CTDB public addresses file");
            }
        } elsif ($action eq 'stop_ctdb_service') {
            run_command(['systemctl', 'stop', 'ctdb'], undef, undef, 1);
            run_command(['systemctl', 'disable', 'ctdb'], undef, undef, 1);
            _log_operation('INFO', "Stopped and disabled CTDB service");
        } elsif ($action eq 'stop_ctdb_lxc') {
            my $ctid = $args[0];
            run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'stop', 'ctdb'], undef, undef, 1);
            _log_operation('INFO', "Stopped CTDB service in LXC container: $ctid");
        } elsif ($action eq 'stop_ctdb_vm') {
            my ($vmid, $vm_ip) = @args;
            run_command(['ssh', "root\@$vm_ip", 'systemctl', 'stop', 'ctdb'], undef, undef, 1);
            _log_operation('INFO', "Stopped CTDB service in VM: $vmid");
        } elsif ($action eq 'stop_ctdb_native') {
            run_command(['systemctl', 'stop', 'ctdb'], undef, undef, 1);
            _log_operation('INFO', "Stopped CTDB service on native host");
        } elsif ($action eq 'remove_user') {
            my $username = $args[0];
            run_command(['userdel', '-r', $username], undef, undef, 1);
            _log_operation('INFO', "Removed user: $username");
        } elsif ($action eq 'restore_network_config') {
            my $backup_file = $args[0];
            if (-f $backup_file) {
                run_command(['cp', $backup_file, '/etc/network/interfaces'], undef, undef, 1);
                unlink $backup_file;
                _log_operation('INFO', "Restored network configuration from: $backup_file");
            }
        } elsif ($action eq 'restore_firewall_rules') {
            my $backup_file = $args[0];
            if (-f $backup_file) {
                run_command(['iptables-restore', '<', $backup_file], undef, undef, 1);
                unlink $backup_file;
                _log_operation('INFO', "Restored firewall rules from: $backup_file");
            }
        } elsif ($action eq 'restore_systemd_services') {
            my $backup_file = $args[0];
            if (-f $backup_file) {
                my $backup_data = file_read_all($backup_file);
                my $services = decode_json($backup_data);
                foreach my $service (keys %$services) {
                    my $state = $services->{$service};
                    if ($state eq 'enabled') {
                        run_command(['systemctl', 'enable', $service], undef, undef, 1);
                    } else {
                        run_command(['systemctl', 'disable', $service], undef, undef, 1);
                    }
                }
                unlink $backup_file;
                _log_operation('INFO', "Restored systemd service states from: $backup_file");
            }
        }
    };
    
    if ($@) {
        _log_operation('ERROR', "Rollback step failed: $description", {
            action => $action,
            error => $@,
            args => \@args
        });
        return 0;
    }
    
    return 1;
}

sub _rollback_creation_enhanced {
    my ($rollback_steps) = @_;
    
    return unless $rollback_steps && @$rollback_steps;
    
    _log_operation('INFO', "Starting enhanced rollback procedure", {
        steps_count => scalar @$rollback_steps
    });
    
    my $successful_steps = 0;
    my $failed_steps = 0;
    
    # Execute rollback steps in reverse order
    foreach my $step (reverse @$rollback_steps) {
        # Validate step before execution
        unless (_validate_rollback_step($step)) {
            _log_operation('ERROR', "Invalid rollback step, skipping", { step => $step });
            $failed_steps++;
            next;
        }
        
        # Execute the step
        if (_execute_rollback_step($step)) {
            $successful_steps++;
        } else {
            $failed_steps++;
        }
    }
    
    _log_operation('INFO', "Rollback procedure completed", {
        successful_steps => $successful_steps,
        failed_steps => $failed_steps,
        total_steps => scalar @$rollback_steps
    });
    
    return {
        successful_steps => $successful_steps,
        failed_steps => $failed_steps,
        total_steps => scalar @$rollback_steps
    };
}

sub _remove_quota_enhanced {
    my ($path, $fs_type) = @_;
    
    _log_operation('INFO', "Removing quota", {
        path => $path,
        fs_type => $fs_type
    });
    
    eval {
        if ($fs_type eq 'zfs') {
            # Get ZFS dataset name
            my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
            chomp $dataset;
            if ($dataset) {
                run_command(['zfs', 'inherit', 'quota', $dataset], undef, undef, 1);
                _log_operation('INFO', "Removed ZFS quota from dataset: $dataset");
            } else {
                _log_operation('WARN', "ZFS dataset not found for path: $path");
            }
        } elsif ($fs_type eq 'xfs') {
            # Remove XFS project quota
            my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
            chomp $mount_point;
            if ($mount_point) {
                # Find project ID for the path
                my $project_id = `xfs_quota -x -c "report -p" $mount_point | grep "$path" | awk '{print \$1}'`;
                chomp $project_id;
                if ($project_id && $project_id =~ /^\d+$/) {
                    run_command(['xfs_quota', '-x', '-c', "limit -p bhard=0 $project_id", $mount_point], undef, undef, 1);
                    _log_operation('INFO', "Removed XFS quota for project: $project_id");
                } else {
                    _log_operation('WARN', "XFS project ID not found for path: $path");
                }
            }
        } else {
            # Remove user quota
            my $mount_point = `df $path | tail -1 | awk '{print \$6}'`;
            chomp $mount_point;
            if ($mount_point) {
                run_command(['setquota', '-u', 'root', '0', '0', '0', '0', $mount_point], undef, undef, 1);
                _log_operation('INFO', "Removed user quota from mount point: $mount_point");
            } else {
                _log_operation('WARN', "Mount point not found for path: $path");
            }
        }
    };
    
    if ($@) {
        _log_operation('ERROR', "Failed to remove quota", {
            path => $path,
            fs_type => $fs_type,
            error => $@
        });
        return 0;
    }
    
    return 1;
}

# -------- manual cleanup tools --------
sub _create_cleanup_report {
    my ($operation_id) = @_;
    
    my $report_file = "/var/log/pve/smbgateway-cleanup-$operation_id.json";
    
    my $report = {
        operation_id => $operation_id,
        timestamp => POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime),
        system_state => _get_system_state(),
        recommendations => _generate_cleanup_recommendations()
    };
    
    file_set_contents($report_file, encode_json($report));
    
    _log_operation('INFO', "Cleanup report generated", {
        operation_id => $operation_id,
        report_file => $report_file
    });
    
    return $report_file;
}

sub _get_system_state {
    my $state = {
        containers => [],
        vms => [],
        samba_shares => [],
        ctdb_status => undef,
        ad_status => undef,
        quota_status => []
    };
    
    # Check for SMB Gateway containers
    my $ct_list = `pct list | grep smbgateway`;
    if ($ct_list) {
        foreach my $line (split /\n/, $ct_list) {
            my ($vmid, $status, $name) = split /\s+/, $line;
            push @{$state->{containers}}, {
                vmid => $vmid,
                status => $status,
                name => $name
            };
        }
    }
    
    # Check for SMB Gateway VMs
    my $vm_list = `qm list | grep smbgateway`;
    if ($vm_list) {
        foreach my $line (split /\n/, $vm_list) {
            my ($vmid, $status, $name) = split /\s+/, $line;
            push @{$state->{vms}}, {
                vmid => $vmid,
                status => $status,
                name => $name
            };
        }
    }
    
    # Check Samba shares
    if (-f '/etc/samba/smb.conf') {
        my $smb_conf = file_read_all('/etc/samba/smb.conf');
        while ($smb_conf =~ /\[([^\]]+)\]/g) {
            my $share = $1;
            next if $share =~ /^(global|homes|printers)$/;
            push @{$state->{samba_shares}}, $share;
        }
    }
    
    # Check CTDB status
    if (-f '/etc/ctdb/nodes') {
        $state->{ctdb_status} = 'configured';
        my $ctdb_status = `ctdb status 2>/dev/null`;
        if ($ctdb_status) {
            $state->{ctdb_status} = 'running';
        }
    }
    
    # Check AD status
    my $realm_status = `realm list 2>/dev/null`;
    if ($realm_status) {
        $state->{ad_status} = 'joined';
    }
    
    return $state;
}

sub _generate_cleanup_recommendations {
    my $state = _get_system_state();
    my $recommendations = [];
    
    # Check for orphaned containers
    foreach my $ct (@{$state->{containers}}) {
        push @$recommendations, {
            type => 'container_cleanup',
            severity => 'medium',
            description => "SMB Gateway container found: $ct->{name} (ID: $ct->{vmid})",
            action => "pct destroy $ct->{vmid}",
            details => "Container status: $ct->{status}"
        };
    }
    
    # Check for orphaned VMs
    foreach my $vm (@{$state->{vms}}) {
        push @$recommendations, {
            type => 'vm_cleanup',
            severity => 'medium',
            description => "SMB Gateway VM found: $vm->{name} (ID: $vm->{vmid})",
            action => "qm destroy $vm->{vmid}",
            details => "VM status: $vm->{status}"
        };
    }
    
    # Check for orphaned Samba shares
    foreach my $share (@{$state->{samba_shares}}) {
        push @$recommendations, {
            type => 'share_cleanup',
            severity => 'low',
            description => "Samba share found: $share",
            action => "Remove from /etc/samba/smb.conf",
            details => "Manual cleanup required"
        };
    }
    
    # Check for CTDB configuration
    if ($state->{ctdb_status}) {
        push @$recommendations, {
            type => 'ctdb_cleanup',
            severity => 'medium',
            description => "CTDB configuration found",
            action => "Remove /etc/ctdb directory",
            details => "CTDB status: $state->{ctdb_status}"
        };
    }
    
    # Check for AD domain
    if ($state->{ad_status}) {
        push @$recommendations, {
            type => 'ad_cleanup',
            severity => 'high',
            description => "AD domain joined",
            action => "realm leave <domain>",
            details => "Manual cleanup required"
        };
    }
    
    return $recommendations;
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
        _add_rollback_step('ad_packages_installed', "AD packages were installed during setup");
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
        _add_rollback_step('leave_ad_domain', "Leave AD domain: $domain", $domain);
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

1;