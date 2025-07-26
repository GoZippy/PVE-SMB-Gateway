package PVE::SMBGateway::Backup;

# PVE SMB Gateway Backup Integration Module
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# This module provides backup integration with Proxmox backup scheduler
# and implements snapshot-based backup workflows for all deployment modes.

use strict;
use warnings;
use base qw(Exporter);
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::Exception qw(raise_param_exc);
use PVE::JSONSchema qw(get_standard_option);
use Time::HiRes qw(time);
use JSON::PP;
use DBI;
use File::Basename qw(dirname);
use File::Path qw(make_path);

our @EXPORT_OK = qw(
    register_backup_job
    unregister_backup_job
    create_backup_snapshot
    restore_backup_snapshot
    verify_backup_integrity
    get_backup_status
    list_backup_jobs
    test_backup_restoration
    cleanup_old_backups
);

# -------- configuration --------
my $BACKUP_CONFIG_DIR = '/etc/pve/smbgateway/backups';
my $BACKUP_LOG_DIR = '/var/log/pve/smbgateway/backups';
my $BACKUP_DB_PATH = '/var/lib/pve/smbgateway/backups.db';
my $MAX_RETRY_ATTEMPTS = 3;
my $RETRY_DELAY_BASE = 60;  # seconds

# -------- database schema --------
my $DB_SCHEMA = {
    backup_jobs => q{
        CREATE TABLE IF NOT EXISTS backup_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            share_id TEXT NOT NULL,
            mode TEXT NOT NULL,
            schedule TEXT NOT NULL,
            retention_days INTEGER DEFAULT 30,
            enabled INTEGER DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_run INTEGER,
            last_status TEXT DEFAULT 'pending',
            last_error TEXT,
            retry_count INTEGER DEFAULT 0,
            UNIQUE(share_id)
        )
    },
    backup_snapshots => q{
        CREATE TABLE IF NOT EXISTS backup_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            snapshot_name TEXT NOT NULL,
            backup_type TEXT NOT NULL,
            size_bytes INTEGER,
            created_at INTEGER NOT NULL,
            expires_at INTEGER,
            status TEXT DEFAULT 'created',
            verification_status TEXT DEFAULT 'pending',
            restore_tested INTEGER DEFAULT 0,
            metadata TEXT,
            FOREIGN KEY(share_id) REFERENCES backup_jobs(share_id)
        )
    },
    backup_events => q{
        CREATE TABLE IF NOT EXISTS backup_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_status TEXT NOT NULL,
            message TEXT,
            timestamp INTEGER NOT NULL,
            metadata TEXT
        )
    }
};

# -------- constructor --------
sub new {
    my ($class, %param) = @_;
    
    my $self = bless {
        share_name => $param{share_name} // die "missing share_name",
        share_id => $param{share_id} // die "missing share_id",
        mode => $param{mode} // 'lxc',
        path => $param{path} // "/srv/smb/$param{share_name}",
        dbh => undef,
    }, $class;
    
    $self->_init_backup_db();
    $self->_ensure_directories();
    
    return $self;
}

# -------- database initialization --------
sub _init_backup_db {
    my ($self) = @_;
    
    # Create database directory
    my $db_dir = dirname($BACKUP_DB_PATH);
    make_path($db_dir) unless -d $db_dir;
    
    # Connect to SQLite database
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$BACKUP_DB_PATH", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
    }) or die "Cannot connect to backup database: " . DBI->errstr;
    
    # Create tables
    foreach my $table (keys %$DB_SCHEMA) {
        $self->{dbh}->do($DB_SCHEMA->{$table});
    }
    
    # Create indexes for performance
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_backup_jobs_share_id ON backup_jobs(share_id)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_snapshots_share_id ON backup_snapshots(share_id)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_snapshots_created_at ON backup_snapshots(created_at)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_events_share_id ON backup_events(share_id)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_events_timestamp ON backup_events(timestamp)");
}

# -------- directory creation --------
sub _ensure_directories {
    my ($self) = @_;
    
    foreach my $dir ($BACKUP_CONFIG_DIR, $BACKUP_LOG_DIR) {
        make_path($dir) unless -d $dir;
    }
}

# -------- backup job registration --------
sub register_backup_job {
    my ($self, %param) = @_;
    
    my $schedule = $param{schedule} // 'daily';
    my $retention_days = $param{retention_days} // 30;
    my $enabled = $param{enabled} // 1;
    
    # Validate schedule format
    unless ($schedule =~ /^(daily|weekly|monthly|custom)$/) {
        die "Invalid schedule: $schedule. Use daily, weekly, monthly, or custom";
    }
    
    # Check if job already exists
    my $existing = $self->{dbh}->selectrow_hashref(
        "SELECT id FROM backup_jobs WHERE share_id = ?",
        undef, $self->{share_id}
    );
    
    if ($existing) {
        # Update existing job
        $self->{dbh}->do(
            "UPDATE backup_jobs SET schedule = ?, retention_days = ?, enabled = ?, updated_at = ? WHERE share_id = ?",
            undef, $schedule, $retention_days, $enabled, time(), $self->{share_id}
        );
        $self->_log_event('job_updated', 'success', "Backup job updated for share $self->{share_name}");
    } else {
        # Create new job
        $self->{dbh}->do(
            "INSERT INTO backup_jobs (share_name, share_id, mode, schedule, retention_days, enabled, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            undef, $self->{share_name}, $self->{share_id}, $self->{mode}, $schedule, $retention_days, $enabled, time(), time()
        );
        $self->_log_event('job_created', 'success', "Backup job created for share $self->{share_name}");
    }
    
    # Register with Proxmox backup scheduler if enabled
    if ($enabled) {
        $self->_register_with_pve_scheduler($schedule);
    }
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        schedule => $schedule,
        retention_days => $retention_days,
        enabled => $enabled,
        status => 'registered'
    };
}

# -------- unregister backup job --------
sub unregister_backup_job {
    my ($self) = @_;
    
    # Remove from database
    $self->{dbh}->do("DELETE FROM backup_jobs WHERE share_id = ?", undef, $self->{share_id});
    
    # Remove from Proxmox scheduler
    $self->_unregister_from_pve_scheduler();
    
    # Clean up snapshots
    $self->cleanup_old_backups(days => 0);
    
    $self->_log_event('job_deleted', 'success', "Backup job deleted for share $self->{share_name}");
    
    return { status => 'unregistered' };
}

# -------- create backup snapshot --------
sub create_backup_snapshot {
    my ($self, %param) = @_;
    
    my $backup_type = $param{type} // 'scheduled';
    my $snapshot_name = $param{snapshot_name} // "backup_" . time();
    
    $self->_log_event('backup_started', 'info', "Starting backup for share $self->{share_name}");
    
    my $result = {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        backup_type => $backup_type,
        created_at => time(),
        status => 'creating'
    };
    
    # Create snapshot based on deployment mode
    eval {
        if ($self->{mode} eq 'lxc') {
            $result = $self->_create_lxc_backup($snapshot_name, $backup_type);
        } elsif ($self->{mode} eq 'vm') {
            $result = $self->_create_vm_backup($snapshot_name, $backup_type);
        } elsif ($self->{mode} eq 'native') {
            $result = $self->_create_native_backup($snapshot_name, $backup_type);
        } else {
            die "Unsupported mode: $self->{mode}";
        }
        
        # Store snapshot record
        $self->{dbh}->do(
            "INSERT INTO backup_snapshots (share_id, snapshot_name, backup_type, size_bytes, created_at, status, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)",
            undef, $self->{share_id}, $snapshot_name, $backup_type, $result->{size_bytes}, time(), 'created', encode_json($result->{metadata})
        );
        
        # Update job status
        $self->{dbh}->do(
            "UPDATE backup_jobs SET last_run = ?, last_status = ?, retry_count = 0 WHERE share_id = ?",
            undef, time(), 'success', $self->{share_id}
        );
        
        $self->_log_event('backup_completed', 'success', "Backup completed for share $self->{share_name}: $snapshot_name");
        
    };
    
    if ($@) {
        my $error = $@;
        $result->{status} = 'failed';
        $result->{error} = $error;
        
        # Update job status with error
        $self->{dbh}->do(
            "UPDATE backup_jobs SET last_run = ?, last_status = ?, last_error = ?, retry_count = retry_count + 1 WHERE share_id = ?",
            undef, time(), 'failed', $error, $self->{share_id}
        );
        
        $self->_log_event('backup_failed', 'error', "Backup failed for share $self->{share_name}: $error");
        
        # Retry logic
        if ($self->_should_retry_backup()) {
            $self->_schedule_retry();
        }
    }
    
    return $result;
}

# -------- LXC backup creation --------
sub _create_lxc_backup {
    my ($self, $snapshot_name, $backup_type) = @_;
    
    # Find the LXC container for this share
    my $container_id = $self->_find_lxc_container();
    die "No LXC container found for share $self->{share_name}" unless $container_id;
    
    # Create LXC snapshot
    my $snapshot_cmd = ['pct', 'snapshot', $container_id, $snapshot_name];
    run_command($snapshot_cmd);
    
    # Get snapshot size
    my $size_bytes = $self->_get_snapshot_size($container_id, $snapshot_name);
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        backup_type => $backup_type,
        size_bytes => $size_bytes,
        created_at => time(),
        status => 'created',
        metadata => {
            container_id => $container_id,
            snapshot_type => 'lxc',
            bind_mounts => $self->_get_bind_mounts($container_id)
        }
    };
}

# -------- VM backup creation --------
sub _create_vm_backup {
    my ($self, $snapshot_name, $backup_type) = @_;
    
    # Find the VM for this share
    my $vm_id = $self->_find_vm();
    die "No VM found for share $self->{share_name}" unless $vm_id;
    
    # Create VM snapshot
    my $snapshot_cmd = ['qm', 'snapshot', $vm_id, $snapshot_name];
    run_command($snapshot_cmd);
    
    # Get snapshot size
    my $size_bytes = $self->_get_vm_snapshot_size($vm_id, $snapshot_name);
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        backup_type => $backup_type,
        size_bytes => $size_bytes,
        created_at => time(),
        status => 'created',
        metadata => {
            vm_id => $vm_id,
            snapshot_type => 'vm',
            storage_attachments => $self->_get_vm_storage_attachments($vm_id)
        }
    };
}

# -------- native backup creation --------
sub _create_native_backup {
    my ($self, $snapshot_name, $backup_type) = @_;
    
    # Create filesystem snapshot if supported
    my $snapshot_result = $self->_create_filesystem_snapshot($snapshot_name);
    
    # Get snapshot size
    my $size_bytes = $snapshot_result->{size_bytes} // 0;
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        backup_type => $backup_type,
        size_bytes => $size_bytes,
        created_at => time(),
        status => 'created',
        metadata => {
            snapshot_type => 'filesystem',
            filesystem_type => $snapshot_result->{filesystem_type},
            snapshot_path => $snapshot_result->{snapshot_path}
        }
    };
}

# -------- filesystem snapshot creation --------
sub _create_filesystem_snapshot {
    my ($self, $snapshot_name) = @_;
    
    # Check if path is on ZFS
    my $zfs_dataset = $self->_get_zfs_dataset($self->{path});
    if ($zfs_dataset) {
        return $self->_create_zfs_snapshot($zfs_dataset, $snapshot_name);
    }
    
    # Check if path is on LVM
    my $lvm_volume = $self->_get_lvm_volume($self->{path});
    if ($lvm_volume) {
        return $self->_create_lvm_snapshot($lvm_volume, $snapshot_name);
    }
    
    # Fallback: create tar archive
    return $self->_create_tar_backup($snapshot_name);
}

# -------- ZFS snapshot creation --------
sub _create_zfs_snapshot {
    my ($self, $dataset, $snapshot_name) = @_;
    
    my $snapshot_path = "$dataset@$snapshot_name";
    run_command(['zfs', 'snapshot', $snapshot_path]);
    
    my $size_bytes = 0;
    eval {
        my $size_output = `zfs get -H -o value used $snapshot_path 2>/dev/null`;
        $size_bytes = $self->_parse_size($size_output) if $size_output;
    };
    
    return {
        size_bytes => $size_bytes,
        filesystem_type => 'zfs',
        snapshot_path => $snapshot_path
    };
}

# -------- LVM snapshot creation --------
sub _create_lvm_snapshot {
    my ($self, $volume, $snapshot_name) = @_;
    
    my $snapshot_volume = "${volume}_${snapshot_name}";
    run_command(['lvcreate', '-s', '-n', $snapshot_name, '-L', '10G', $volume]);
    
    my $size_bytes = 0;
    eval {
        my $size_output = `lvs --noheadings --units b --nosuffix -o lv_size $snapshot_volume 2>/dev/null`;
        $size_bytes = int($size_output) if $size_output;
    };
    
    return {
        size_bytes => $size_bytes,
        filesystem_type => 'lvm',
        snapshot_path => "/dev/mapper/$snapshot_volume"
    };
}

# -------- tar backup creation --------
sub _create_tar_backup {
    my ($self, $snapshot_name) = @_;
    
    my $backup_file = "$BACKUP_CONFIG_DIR/${self->{share_name}}_${snapshot_name}.tar.gz";
    
    run_command(['tar', '-czf', $backup_file, '-C', dirname($self->{path}), basename($self->{path})]);
    
    my $size_bytes = -s $backup_file;
    
    return {
        size_bytes => $size_bytes,
        filesystem_type => 'tar',
        snapshot_path => $backup_file
    };
}

# -------- restore backup snapshot --------
sub restore_backup_snapshot {
    my ($self, $snapshot_name, %param) = @_;
    
    my $dry_run = $param{dry_run} // 0;
    
    $self->_log_event('restore_started', 'info', "Starting restore for share $self->{share_name}: $snapshot_name");
    
    # Get snapshot details
    my $snapshot = $self->{dbh}->selectrow_hashref(
        "SELECT * FROM backup_snapshots WHERE share_id = ? AND snapshot_name = ?",
        undef, $self->{share_id}, $snapshot_name
    );
    
    die "Snapshot $snapshot_name not found for share $self->{share_name}" unless $snapshot;
    
    my $result = {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        status => 'restoring',
        dry_run => $dry_run
    };
    
    eval {
        if ($self->{mode} eq 'lxc') {
            $result = $self->_restore_lxc_backup($snapshot, $dry_run);
        } elsif ($self->{mode} eq 'vm') {
            $result = $self->_restore_vm_backup($snapshot, $dry_run);
        } elsif ($self->{mode} eq 'native') {
            $result = $self->_restore_native_backup($snapshot, $dry_run);
        } else {
            die "Unsupported mode: $self->{mode}";
        }
        
        $self->_log_event('restore_completed', 'success', "Restore completed for share $self->{share_name}: $snapshot_name");
        
    };
    
    if ($@) {
        my $error = $@;
        $result->{status} = 'failed';
        $result->{error} = $error;
        
        $self->_log_event('restore_failed', 'error', "Restore failed for share $self->{share_name}: $error");
    }
    
    return $result;
}

# -------- verify backup integrity --------
sub verify_backup_integrity {
    my ($self, $snapshot_name) = @_;
    
    # Get snapshot details
    my $snapshot = $self->{dbh}->selectrow_hashref(
        "SELECT * FROM backup_snapshots WHERE share_id = ? AND snapshot_name = ?",
        undef, $self->{share_id}, $snapshot_name
    );
    
    die "Snapshot $snapshot_name not found for share $self->{share_name}" unless $snapshot;
    
    my $verification_status = 'pending';
    my $verification_message = '';
    
    eval {
        if ($self->{mode} eq 'lxc') {
            ($verification_status, $verification_message) = $self->_verify_lxc_backup($snapshot);
        } elsif ($self->{mode} eq 'vm') {
            ($verification_status, $verification_message) = $self->_verify_vm_backup($snapshot);
        } elsif ($self->{mode} eq 'native') {
            ($verification_status, $verification_message) = $self->_verify_native_backup($snapshot);
        } else {
            die "Unsupported mode: $self->{mode}";
        }
        
        # Update verification status
        $self->{dbh}->do(
            "UPDATE backup_snapshots SET verification_status = ? WHERE id = ?",
            undef, $verification_status, $snapshot->{id}
        );
        
    };
    
    if ($@) {
        $verification_status = 'failed';
        $verification_message = $@;
    }
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        snapshot_name => $snapshot_name,
        verification_status => $verification_status,
        message => $verification_message
    };
}

# -------- get backup status --------
sub get_backup_status {
    my ($self) = @_;
    
    # Get job status
    my $job = $self->{dbh}->selectrow_hashref(
        "SELECT * FROM backup_jobs WHERE share_id = ?",
        undef, $self->{share_id}
    );
    
    # Get recent snapshots
    my $snapshots = $self->{dbh}->selectall_arrayref(
        "SELECT * FROM backup_snapshots WHERE share_id = ? ORDER BY created_at DESC LIMIT 10",
        { Slice => {} }, $self->{share_id}
    );
    
    # Get recent events
    my $events = $self->{dbh}->selectall_arrayref(
        "SELECT * FROM backup_events WHERE share_id = ? ORDER BY timestamp DESC LIMIT 20",
        { Slice => {} }, $self->{share_id}
    );
    
    return {
        share_id => $self->{share_id},
        share_name => $self->{share_name},
        job => $job,
        snapshots => $snapshots,
        events => $events,
        total_snapshots => scalar(@$snapshots),
        total_size_bytes => $self->_calculate_total_backup_size()
    };
}

# -------- list backup jobs --------
sub list_backup_jobs {
    my ($class) = @_;
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$BACKUP_DB_PATH", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
    });
    
    my $jobs = $dbh->selectall_arrayref(
        "SELECT * FROM backup_jobs ORDER BY created_at DESC",
        { Slice => {} }
    );
    
    return $jobs;
}

# -------- test backup restoration --------
sub test_backup_restoration {
    my ($self, $snapshot_name) = @_;
    
    $self->_log_event('test_restore_started', 'info', "Starting test restore for share $self->{share_name}: $snapshot_name");
    
    # Perform dry-run restore
    my $result = $self->restore_backup_snapshot($snapshot_name, dry_run => 1);
    
    if ($result->{status} eq 'restored') {
        # Mark snapshot as tested
        $self->{dbh}->do(
            "UPDATE backup_snapshots SET restore_tested = 1 WHERE share_id = ? AND snapshot_name = ?",
            undef, $self->{share_id}, $snapshot_name
        );
        
        $self->_log_event('test_restore_completed', 'success', "Test restore completed for share $self->{share_name}: $snapshot_name");
    }
    
    return $result;
}

# -------- cleanup old backups --------
sub cleanup_old_backups {
    my ($self, %param) = @_;
    
    my $days = $param{days} // 30;
    my $cutoff_time = time() - ($days * 24 * 60 * 60);
    
    # Get old snapshots
    my $old_snapshots = $self->{dbh}->selectall_arrayref(
        "SELECT * FROM backup_snapshots WHERE share_id = ? AND created_at < ?",
        { Slice => {} }, $self->{share_id}, $cutoff_time
    );
    
    my $deleted_count = 0;
    my $freed_bytes = 0;
    
    foreach my $snapshot (@$old_snapshots) {
        eval {
            if ($self->{mode} eq 'lxc') {
                $self->_delete_lxc_snapshot($snapshot);
            } elsif ($self->{mode} eq 'vm') {
                $self->_delete_vm_snapshot($snapshot);
            } elsif ($self->{mode} eq 'native') {
                $self->_delete_native_snapshot($snapshot);
            }
            
            # Remove from database
            $self->{dbh}->do(
                "DELETE FROM backup_snapshots WHERE id = ?",
                undef, $snapshot->{id}
            );
            
            $deleted_count++;
            $freed_bytes += $snapshot->{size_bytes} // 0;
            
        };
        
        if ($@) {
            $self->_log_event('cleanup_failed', 'error', "Failed to delete snapshot $snapshot->{snapshot_name}: $@");
        }
    }
    
    # Clean up old events
    $self->{dbh}->do(
        "DELETE FROM backup_events WHERE share_id = ? AND timestamp < ?",
        undef, $self->{share_id}, $cutoff_time
    );
    
    $self->_log_event('cleanup_completed', 'info', "Cleaned up $deleted_count old backups, freed $freed_bytes bytes");
    
    return {
        deleted_count => $deleted_count,
        freed_bytes => $freed_bytes,
        cutoff_time => $cutoff_time
    };
}

# -------- helper methods --------

sub _log_event {
    my ($self, $event_type, $event_status, $message, $metadata) = @_;
    
    $self->{dbh}->do(
        "INSERT INTO backup_events (share_id, event_type, event_status, message, timestamp, metadata) VALUES (?, ?, ?, ?, ?, ?)",
        undef, $self->{share_id}, $event_type, $event_status, $message, time(), $metadata ? encode_json($metadata) : undef
    );
    
    # Also log to syslog
    system("logger -t pve-smbgw-backup \"[$event_type] $message\"");
}

sub _find_lxc_container {
    my ($self) = @_;
    
    my $containers = `pct list 2>/dev/null`;
    foreach my $line (split /\n/, $containers) {
        if ($line =~ /^\s*(\d+)\s+\S+\s+\S+\s+smbgateway-$self->{share_name}\s*$/) {
            return $1;
        }
    }
    
    return undef;
}

sub _find_vm {
    my ($self) = @_;
    
    my $vms = `qm list 2>/dev/null`;
    foreach my $line (split /\n/, $vms) {
        if ($line =~ /^\s*(\d+)\s+\S+\s+\S+\s+smbgateway-$self->{share_name}\s*$/) {
            return $1;
        }
    }
    
    return undef;
}

sub _get_snapshot_size {
    my ($self, $container_id, $snapshot_name) = @_;
    
    my $size_output = `pct snapshot list $container_id 2>/dev/null | grep $snapshot_name`;
    if ($size_output =~ /(\d+)/) {
        return $1 * 1024;  # Convert KB to bytes
    }
    
    return 0;
}

sub _get_vm_snapshot_size {
    my ($self, $vm_id, $snapshot_name) = @_;
    
    my $size_output = `qm snapshot list $vm_id 2>/dev/null | grep $snapshot_name`;
    if ($size_output =~ /(\d+)/) {
        return $1 * 1024;  # Convert KB to bytes
    }
    
    return 0;
}

sub _get_zfs_dataset {
    my ($self, $path) = @_;
    
    my $dataset_output = `zfs list -H -o name 2>/dev/null`;
    foreach my $dataset (split /\n/, $dataset_output) {
        if ($path =~ /^\/$dataset\//) {
            return $dataset;
        }
    }
    
    return undef;
}

sub _get_lvm_volume {
    my ($self, $path) = @_;
    
    my $mount_output = `mount 2>/dev/null`;
    foreach my $line (split /\n/, $mount_output) {
        if ($line =~ /^\/dev\/mapper\/(\S+)\s+$path\s+/) {
            return $1;
        }
    }
    
    return undef;
}

sub _parse_size {
    my ($self, $size_str) = @_;
    
    if ($size_str =~ /^(\d+(?:\.\d+)?)([KMGT]?)$/) {
        my ($value, $unit) = ($1, $2);
        my $multiplier = 1;
        
        $multiplier = 1024 if $unit eq 'K';
        $multiplier = 1024 * 1024 if $unit eq 'M';
        $multiplier = 1024 * 1024 * 1024 if $unit eq 'G';
        $multiplier = 1024 * 1024 * 1024 * 1024 if $unit eq 'T';
        
        return int($value * $multiplier);
    }
    
    return 0;
}

sub _calculate_total_backup_size {
    my ($self) = @_;
    
    my $result = $self->{dbh}->selectrow_array(
        "SELECT SUM(size_bytes) FROM backup_snapshots WHERE share_id = ?",
        undef, $self->{share_id}
    );
    
    return $result // 0;
}

sub _should_retry_backup {
    my ($self) = @_;
    
    my $retry_count = $self->{dbh}->selectrow_array(
        "SELECT retry_count FROM backup_jobs WHERE share_id = ?",
        undef, $self->{share_id}
    );
    
    return $retry_count < $MAX_RETRY_ATTEMPTS;
}

sub _schedule_retry {
    my ($self) = @_;
    
    my $retry_count = $self->{dbh}->selectrow_array(
        "SELECT retry_count FROM backup_jobs WHERE share_id = ?",
        undef, $self->{share_id}
    );
    
    my $delay = $RETRY_DELAY_BASE * (2 ** $retry_count);
    
    # Schedule retry using at command
    my $retry_script = "cd /tmp && pve-smbgateway backup retry $self->{share_id}";
    system("echo '$retry_script' | at now + $delay minutes 2>/dev/null");
    
    $self->_log_event('retry_scheduled', 'info', "Backup retry scheduled in $delay minutes");
}

sub _register_with_pve_scheduler {
    my ($self, $schedule) = @_;
    
    # This would integrate with Proxmox backup scheduler
    # For now, we'll use cron for scheduling
    
    my $cron_schedule = $self->_schedule_to_cron($schedule);
    my $backup_command = "pve-smbgateway backup create $self->{share_id}";
    
    # Add to crontab
    system("(crontab -l 2>/dev/null; echo '$cron_schedule $backup_command') | crontab -");
}

sub _unregister_from_pve_scheduler {
    my ($self) = @_;
    
    # Remove from crontab
    my $backup_command = "pve-smbgateway backup create $self->{share_id}";
    system("crontab -l 2>/dev/null | grep -v '$backup_command' | crontab -");
}

sub _schedule_to_cron {
    my ($self, $schedule) = @_;
    
    if ($schedule eq 'daily') {
        return '0 2 * * *';  # 2 AM daily
    } elsif ($schedule eq 'weekly') {
        return '0 2 * * 0';  # 2 AM Sunday
    } elsif ($schedule eq 'monthly') {
        return '0 2 1 * *';  # 2 AM 1st of month
    } else {
        return '0 2 * * *';  # Default to daily
    }
}

# -------- cleanup on destruction --------
sub DESTROY {
    my ($self) = @_;
    
    if ($self->{dbh}) {
        $self->{dbh}->disconnect();
    }
}

1; 