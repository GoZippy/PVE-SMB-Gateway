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
        ctdb_vip  => { type => 'string',  optional => 1 },
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
    } else {
        die "VM mode not implemented yet";
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
    } else {
        die "VM mode not implemented yet";
    }
    
    return 1;
}

sub status {
    my ($class, $storeid, $scfg, %param) = @_;
    
    my $mode = $scfg->{mode} // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    
    if ($mode eq 'native') {
        return _native_status($sharename, $scfg);
    } elsif ($mode eq 'lxc') {
        return _lxc_status($sharename, $scfg);
    } else {
        return { status => 'unknown', message => 'VM mode not implemented' };
    }
}

# -------- storage creation --------
sub create_storage {
    my ($class, $storeid, $scfg, %param) = @_;

    my $mode      = $scfg->{mode}      // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    my $path      = $scfg->{path}      // "/srv/smb/$sharename";
    my $quota     = $scfg->{quota}     // '';
    my $ad_domain = $scfg->{ad_domain} // '';
    my $ctdb_vip  = $scfg->{ctdb_vip}  // '';

    # Track what we've created for rollback
    my @rollback_steps = ();
    
    eval {
        if ($mode eq 'native') {
            _native_create($path, $sharename, $quota, $ad_domain, \@rollback_steps);
        } elsif ($mode eq 'lxc') {
            _lxc_create($path, $sharename, $quota, $ad_domain, $ctdb_vip, \@rollback_steps);
        } else {
            die "VM mode not implemented yet";
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
    my ($path, $share, $quota, $ad_domain, $rollback_steps) = @_;
    
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
    if ($ad_domain) {
        print $fh "  security = ads\n";
        print $fh "  realm = $ad_domain\n";
    }
    close $fh;
    
    run_command(['systemctl', 'reload', 'smbd']);
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

sub _install_samba_in_lxc {
    my ($ctid, $share, $ad_domain, $ctdb_vip) = @_;
    
    # Install Samba packages
    run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'update']);
    run_command(['pct', 'exec', $ctid, '--', 'apt-get', 'install', '-y', 'samba', 'winbind']);
    
    # Configure Samba
    my $smb_conf = "
[global]
  workgroup = WORKGROUP
  server string = SMB Gateway
  security = user
  map to guest = bad user
  dns proxy = no
  log level = 1

[$share]
  path = /srv/share
  browseable = yes
  writable = yes
  guest ok = no
  read only = no
";
    
    # Write config to container
    open my $fh, '>', "/tmp/smb.conf" or die "Cannot create temp config: $!";
    print $fh $smb_conf;
    close $fh;
    
    run_command(['pct', 'push', $ctid, '/tmp/smb.conf', '/etc/samba/smb.conf']);
    unlink "/tmp/smb.conf";
    
    # Start Samba services
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'enable', 'smbd']);
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'enable', 'nmbd']);
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'start', 'smbd']);
    run_command(['pct', 'exec', $ctid, '--', 'systemctl', 'start', 'nmbd']);
}

sub _apply_quota {
    my ($path, $quota, $rollback_steps) = @_;
    
    # Parse quota (e.g., "10G", "1T")
    if ($quota =~ /^(\d+)([GT])$/) {
        my ($size, $unit) = ($1, $2);
        my $bytes = $unit eq 'G' ? $size * 1024**3 : $size * 1024**4;
        
        # Apply quota using setquota
        run_command(['setquota', '-u', 'root', '0', $bytes, '0', '0', $path]);
    }
}

sub _rollback_creation {
    my ($rollback_steps) = @_;
    
    # Execute rollback steps in reverse order
    for (my $i = $#$rollback_steps; $i >= 0; $i--) {
        my $step = $rollback_steps->[$i];
        my ($action, @args) = @$step;
        
        eval {
            if ($action eq 'rmdir') {
                rmdir $args[0] if -d $args[0];
            } elsif ($action eq 'destroy_ct') {
                run_command(['pct', 'destroy', $args[0], '--force']);
            } elsif ($action eq 'restore_smb_conf') {
                run_command(['cp', $args[0], '/etc/samba/smb.conf']);
                unlink $args[0];
            }
        };
        # Continue rollback even if individual steps fail
    }
}

# -------- required storage methods --------
sub storage_can_create {
    my ($class, $storeid, $scfg, %param) = @_;
    return 1;
}

sub storage_create {
    my ($class, $storeid, $scfg, %param) = @_;
    return $class->create_storage($storeid, $scfg, %param);
}

sub storage_delete {
    my ($class, $storeid, $scfg, %param) = @_;
    
    my $mode = $scfg->{mode} // 'lxc';
    my $sharename = $scfg->{sharename} // die "missing sharename";
    
    if ($mode eq 'native') {
        _native_delete($sharename, $scfg);
    } elsif ($mode eq 'lxc') {
        _lxc_delete($sharename, $scfg);
    } else {
        die "VM mode not implemented yet";
    }
    
    return 1;
}

# -------- delete implementations --------
sub _native_delete {
    my ($sharename, $scfg) = @_;
    # TODO: Remove share stanza from smb.conf
    # For now, just log the deletion
    warn "Native share '$sharename' marked for deletion";
}

sub _lxc_delete {
    my ($sharename, $scfg) = @_;
    my $ctid = $scfg->{ctid};
    
    if ($ctid) {
        run_command(['pct', 'stop', $ctid]);
        run_command(['pct', 'destroy', $ctid, '--force']);
    }
}

1;
