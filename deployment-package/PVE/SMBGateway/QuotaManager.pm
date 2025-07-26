package PVE::SMBGateway::QuotaManager;

# PVE SMB Gateway Quota Management Module
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

use strict;
use warnings;
use base qw(Exporter);
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::Exception qw(raise_param_exc);
use DBI;
use JSON::PP;
use Time::HiRes qw(time);
use File::Path qw(make_path);
use File::Basename;
use Sys::Hostname;

our @EXPORT_OK = qw(
    apply_quota
    get_quota_usage
    get_quota_trend
    set_quota_alert
    send_quota_alert
    cleanup_quota_history
    get_quota_report
    validate_quota_format
    get_filesystem_type
    apply_zfs_quota
    apply_xfs_quota
    apply_user_quota
    remove_quota
);

# -------- configuration --------
my $QUOTA_DB = "/etc/pve/smbgateway/quotas.db";
my $QUOTA_HISTORY_DIR = "/etc/pve/smbgateway/history";
my $QUOTA_RETENTION_DAYS = 90;
my $QUOTA_ALERT_THRESHOLDS = [75, 85, 95]; # percentage
my $QUOTA_CHECK_INTERVAL = 300; # 5 minutes

# -------- database connection --------
my $dbh = undef;

# -------- database initialization --------
sub _init_quota_db {
    my ($self) = @_;
    
    # Create quota directory with proper permissions
    eval {
        make_path($QUOTA_HISTORY_DIR, { mode => 0755 }) unless -d $QUOTA_HISTORY_DIR;
    };
    if ($@) {
        die "Failed to create quota directory: $@";
    }
    
    # Connect to SQLite database with error handling
    eval {
        $dbh = DBI->connect("dbi:SQLite:dbname=$QUOTA_DB", "", "", {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
            sqlite_use_immediate_transaction => 1
        });
    };
    if ($@ || !$dbh) {
        die "Cannot connect to quota database: " . ($@ || DBI->errstr);
    }
    
    # Create tables if they don't exist
    my $create_tables_sql = "
        CREATE TABLE IF NOT EXISTS quota_config (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL UNIQUE,
            path TEXT NOT NULL,
            quota_limit BIGINT NOT NULL,
            quota_unit TEXT NOT NULL,
            filesystem_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            status TEXT DEFAULT 'active'
        );
        
        CREATE TABLE IF NOT EXISTS quota_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            quota_limit BIGINT NOT NULL,
            quota_used BIGINT NOT NULL,
            quota_percent REAL NOT NULL,
            files_count INTEGER DEFAULT 0,
            directories_count INTEGER DEFAULT 0,
            largest_file_size BIGINT DEFAULT 0,
            filesystem_type TEXT NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS quota_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            alert_type TEXT NOT NULL,
            threshold INTEGER NOT NULL,
            current_percent REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            sent_at INTEGER,
            acknowledged_at INTEGER,
            message TEXT
        );
        
        CREATE INDEX IF NOT EXISTS idx_quota_history_share_timestamp 
        ON quota_history(share_name, timestamp);
        
        CREATE INDEX IF NOT EXISTS idx_quota_alerts_share_timestamp 
        ON quota_alerts(share_name, timestamp);
    ";
    
    # Create tables with error handling
    eval {
        $dbh->do($create_tables_sql);
    };
    if ($@) {
        die "Failed to create quota tables: $@";
    }
}

# -------- quota validation --------
sub validate_quota_format {
    my ($quota) = @_;
    
    # Check format: number + unit (K, M, G, T)
    unless ($quota =~ /^(\d+)([KMGT])$/) {
        return (0, "Invalid quota format: $quota. Use format like 10G or 1T.");
    }
    
    my ($size, $unit) = ($1, $2);
    
    # Validate size
    if ($size <= 0) {
        return (0, "Quota size must be greater than 0");
    }
    
    # Validate unit
    unless ($unit =~ /^[KMGT]$/) {
        return (0, "Invalid quota unit: $unit. Use K, M, G, or T.");
    }
    
    return (1, "Valid quota format");
}

# -------- filesystem detection --------
sub get_filesystem_type {
    my ($path) = @_;
    
    # Check if path exists
    unless (-d $path) {
        die "Path does not exist: $path";
    }
    
    # Get filesystem type using df
    my $df_output = `df -T "$path" 2>/dev/null | tail -1`;
    my @fields = split /\s+/, $df_output;
    
    if (@fields >= 2) {
        return lc($fields[1]);
    }
    
    # Check if it's a ZFS dataset
    my $zfs_output = `zfs list | grep "$path" 2>/dev/null`;
    if ($zfs_output) {
        return 'zfs';
    }
    
    # Default to ext4
    return 'ext4';
}

# -------- quota application methods --------
sub apply_quota {
    my ($path, $quota, $share_name, $rollback_steps) = @_;
    
    # Validate quota format
    my ($is_valid, $error_msg) = validate_quota_format($quota);
    unless ($is_valid) {
        die $error_msg;
    }
    
    # Parse quota
    my ($size, $unit) = ($quota =~ /^(\d+)([KMGT])$/);
    my $bytes = _convert_to_bytes($size, $unit);
    
    # Get filesystem type
    my $fs_type = get_filesystem_type($path);
    
    # Apply quota based on filesystem type
    my $quota_applied = 0;
    my $error_message = "";
    
    eval {
        if ($fs_type eq 'zfs') {
            apply_zfs_quota($path, $quota, $rollback_steps);
            $quota_applied = 1;
        } elsif ($fs_type eq 'xfs') {
            apply_xfs_quota($path, $bytes, $rollback_steps);
            $quota_applied = 1;
        } else {
            apply_user_quota($path, $bytes, $rollback_steps);
            $quota_applied = 1;
        }
    };
    
    if ($@) {
        $error_message = $@;
        warn "Failed to apply quota: $error_message";
        
        # Try fallback method
        if (!$quota_applied) {
            eval {
                warn "Trying fallback quota method for $path";
                apply_user_quota($path, $bytes, $rollback_steps);
                $quota_applied = 1;
            };
            
            if ($@) {
                die "Failed to apply quota using fallback method: $@\nOriginal error: $error_message";
            }
        }
    }
    
    # Store quota configuration
    if ($quota_applied) {
        _store_quota_config($share_name, $path, $quota, $size, $unit, $fs_type);
        warn "Successfully applied quota of $quota to $path";
    } else {
        die "Failed to apply quota to $path: $error_message";
    }
    
    return 1;
}

sub apply_zfs_quota {
    my ($path, $quota, $rollback_steps) = @_;
    
    # Get ZFS dataset name
    my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
    chomp $dataset;
    
    if ($dataset) {
        # Apply quota
        run_command(['zfs', 'set', "quota=$quota", $dataset]);
        
        # Add rollback step
        _add_rollback_step($rollback_steps, 'zfs_remove_quota', "Remove ZFS quota from dataset: $dataset", $dataset);
    } else {
        die "No ZFS dataset found for path: $path";
    }
}

sub apply_xfs_quota {
    my ($path, $bytes, $rollback_steps) = @_;
    
    # Get mount point
    my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Check if xfs_quota is available
    unless (system('which xfs_quota >/dev/null 2>&1') == 0) {
        die "xfs_quota command not available";
    }
    
    # Create project ID
    my $project_id = time(); # Use timestamp as project ID
    
    # Add project to /etc/projects
    my $project_line = "$project_id:$path\n";
    open(my $fh, '>>', '/etc/projects') or die "Cannot open /etc/projects: $!";
    print $fh $project_line;
    close $fh;
    
    # Add project to /etc/projid
    my $projid_line = "$project_id:$path\n";
    open($fh, '>>', '/etc/projid') or die "Cannot open /etc/projid: $!";
    print $fh $projid_line;
    close $fh;
    
    # Set project quota
    run_command(['xfs_quota', '-x', '-c', "project -s $project_id", $mount_point]);
    run_command(['xfs_quota', '-x', '-c', "limit -p bhard=$bytes $project_id", $mount_point]);
    
    # Add rollback step
    _add_rollback_step($rollback_steps, 'xfs_remove_quota', "Remove XFS project quota: $project_id", $project_id);
}

sub apply_user_quota {
    my ($path, $bytes, $rollback_steps) = @_;
    
    # Check if quota tools are available
    unless (system('which quota >/dev/null 2>&1') == 0) {
        die "quota command not available";
    }
    
    # Get mount point
    my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
    chomp $mount_point;
    
    # Enable quotas on filesystem
    run_command(['quotacheck', '-cugm', $mount_point]);
    run_command(['quotaon', '-ug', $mount_point]);
    
    # Set user quota (using current user or root)
    my $user = $ENV{USER} || 'root';
    run_command(['setquota', '-u', $user, '0', $bytes, '0', '0', $mount_point]);
    
    # Add rollback step
    _add_rollback_step($rollback_steps, 'user_remove_quota', "Remove user quota for: $user", $user);
}

# -------- quota monitoring --------
sub get_quota_usage {
    my ($path, $share_name) = @_;
    
    # Get quota configuration
    my $config = _get_quota_config($share_name);
    unless ($config) {
        return undef;
    }
    
    my $fs_type = $config->{filesystem_type};
    my $quota_limit = $config->{quota_limit};
    
    # Get current usage based on filesystem type
    my $usage = undef;
    
    if ($fs_type eq 'zfs') {
        $usage = _get_zfs_usage($path);
    } elsif ($fs_type eq 'xfs') {
        $usage = _get_xfs_usage($path);
    } else {
        $usage = _get_user_usage($path);
    }
    
    if ($usage) {
        $usage->{quota} = $config->{quota_limit} . $config->{quota_unit};
        $usage->{fs_type} = $fs_type;
        $usage->{percent} = ($usage->{used} / $quota_limit) * 100;
        
        # Store in history
        _store_quota_history($share_name, $usage);
        
        # Check for alerts
        _check_quota_alerts($share_name, $usage);
    }
    
    return $usage;
}

sub _get_zfs_usage {
    my ($path) = @_;
    
    my $dataset = `zfs list | grep "$path" | awk '{print \$1}'`;
    chomp $dataset;
    
    if ($dataset) {
        my $used = `zfs get -H -o value used "$dataset"`;
        chomp $used;
        
        # Convert to bytes
        my $bytes = _parse_size($used);
        
        return {
            used => $bytes,
            files_count => _count_files($path),
            directories_count => _count_directories($path),
            largest_file_size => _get_largest_file($path)
        };
    }
    
    return undef;
}

sub _get_xfs_usage {
    my ($path) = @_;
    
    # Get project ID
    my $project_id = `grep "$path" /etc/projects | cut -d: -f1`;
    chomp $project_id;
    
    if ($project_id) {
        my $mount_point = `df "$path" | tail -1 | awk '{print \$6}'`;
        chomp $mount_point;
        
        my $quota_output = `xfs_quota -x -c "report -p" $mount_point | grep "^$project_id"`;
        my @fields = split /\s+/, $quota_output;
        
        if (@fields >= 4) {
            my $used = $fields[2]; # Used blocks
            my $bytes = $used * 4096; # Assuming 4K blocks
            
            return {
                used => $bytes,
                files_count => _count_files($path),
                directories_count => _count_directories($path),
                largest_file_size => _get_largest_file($path)
            };
        }
    }
    
    return undef;
}

sub _get_user_usage {
    my ($path) = @_;
    
    my $user = $ENV{USER} || 'root';
    my $quota_output = `quota -u $user 2>/dev/null | tail -1`;
    my @fields = split /\s+/, $quota_output;
    
    if (@fields >= 3) {
        my $used = $fields[1]; # Used blocks
        my $bytes = $used * 1024; # Assuming 1K blocks
        
        return {
            used => $bytes,
            files_count => _count_files($path),
            directories_count => _count_directories($path),
            largest_file_size => _get_largest_file($path)
        };
    }
    
    return undef;
}

# -------- quota trend analysis --------
sub get_quota_trend {
    my ($share_name, $days) = @_;
    $days ||= 7;
    
    my $stmt = $dbh->prepare("
        SELECT timestamp, quota_percent, quota_used, quota_limit
        FROM quota_history 
        WHERE share_name = ? 
        AND timestamp >= ?
        ORDER BY timestamp ASC
    ");
    
    my $cutoff_time = time() - ($days * 24 * 60 * 60);
    $stmt->execute($share_name, $cutoff_time);
    
    my @data_points;
    while (my $row = $stmt->fetchrow_hashref) {
        push @data_points, {
            timestamp => $row->{timestamp},
            percent => $row->{quota_percent},
            used => $row->{quota_used},
            limit => $row->{quota_limit}
        };
    }
    
    # Calculate trend
    my $trend = _calculate_trend(\@data_points);
    
    return {
        data_points => \@data_points,
        trend => $trend,
        days_analyzed => $days
    };
}

sub _calculate_trend {
    my ($data_points) = @_;
    
    return 'stable' unless @$data_points >= 2;
    
    my $first = $data_points->[0]->{percent};
    my $last = $data_points->[-1]->{percent};
    my $change = $last - $first;
    
    if ($change > 5) {
        return 'increasing';
    } elsif ($change < -5) {
        return 'decreasing';
    } else {
        return 'stable';
    }
}

# -------- quota alerts --------
sub _check_quota_alerts {
    my ($share_name, $usage) = @_;
    
    my $percent = $usage->{percent};
    
    foreach my $threshold (@$QUOTA_ALERT_THRESHOLDS) {
        if ($percent >= $threshold) {
            # Check if alert already sent recently
            my $recent_alert = _get_recent_alert($share_name, $threshold);
            unless ($recent_alert) {
                _create_quota_alert($share_name, $threshold, $percent, $usage);
                send_quota_alert($share_name, $threshold, $percent, $usage);
            }
        }
    }
}

sub _create_quota_alert {
    my ($share_name, $threshold, $percent, $usage) = @_;
    
    my $stmt = $dbh->prepare("
        INSERT INTO quota_alerts 
        (share_name, alert_type, threshold, current_percent, timestamp, message)
        VALUES (?, ?, ?, ?, ?, ?)
    ");
    
    my $message = "Quota usage for share '$share_name' has reached ${percent}% (threshold: ${threshold}%)";
    $stmt->execute($share_name, 'quota_threshold', $threshold, $percent, time(), $message);
}

sub send_quota_alert {
    my ($share_name, $threshold, $percent, $usage) = @_;
    
    # Log alert
    my $message = "QUOTA ALERT: Share '$share_name' at ${percent}% usage (threshold: ${threshold}%)";
    warn $message;
    
    # Send email alert if configured
    if ($ENV{SMTP_SERVER}) {
        _send_email_alert($share_name, $threshold, $percent, $usage);
    }
    
    # Send system notification
    _send_system_notification($share_name, $threshold, $percent, $usage);
}

sub _send_email_alert {
    my ($share_name, $threshold, $percent, $usage) = @_;
    
    # Implementation for email alerts
    # This would integrate with the system's email configuration
    my $subject = "Quota Alert: $share_name at ${percent}%";
    my $body = "Share: $share_name\n";
    $body .= "Usage: ${percent}%\n";
    $body .= "Threshold: ${threshold}%\n";
    $body .= "Used: " . _format_bytes($usage->{used}) . "\n";
    $body .= "Limit: " . _format_bytes($usage->{quota_limit}) . "\n";
    
    # Use system mail command
    open(my $mail, '| mail -s "' . $subject . '" root') or return;
    print $mail $body;
    close $mail;
}

sub _send_system_notification {
    my ($share_name, $threshold, $percent, $usage) = @_;
    
    # Send to syslog
    my $message = "quota_alert share=$share_name threshold=$threshold percent=$percent";
    system("logger -t pve-smbgateway '$message'");
}

# -------- utility functions --------
sub _convert_to_bytes {
    my ($size, $unit) = @_;
    
    if ($unit eq 'K') {
        return $size * 1024;
    } elsif ($unit eq 'M') {
        return $size * 1024**2;
    } elsif ($unit eq 'G') {
        return $size * 1024**3;
    } elsif ($unit eq 'T') {
        return $size * 1024**4;
    }
    
    return $size;
}

sub _parse_size {
    my ($size_str) = @_;
    
    if ($size_str =~ /^(\d+(?:\.\d+)?)([KMGT])?$/) {
        my ($size, $unit) = ($1, $2);
        return _convert_to_bytes($size, $unit || 'B');
    }
    
    return 0;
}

sub _format_bytes {
    my ($bytes) = @_;
    
    if ($bytes >= 1024**4) {
        return sprintf("%.2fT", $bytes / 1024**4);
    } elsif ($bytes >= 1024**3) {
        return sprintf("%.2fG", $bytes / 1024**3);
    } elsif ($bytes >= 1024**2) {
        return sprintf("%.2fM", $bytes / 1024**2);
    } elsif ($bytes >= 1024) {
        return sprintf("%.2fK", $bytes / 1024);
    } else {
        return "${bytes}B";
    }
}

sub _count_files {
    my ($path) = @_;
    return `find "$path" -type f | wc -l` + 0;
}

sub _count_directories {
    my ($path) = @_;
    return `find "$path" -type d | wc -l` + 0;
}

sub _get_largest_file {
    my ($path) = @_;
    my $size = `find "$path" -type f -printf '%s\n' | sort -nr | head -1`;
    chomp $size;
    return $size + 0;
}

sub _add_rollback_step {
    my ($rollback_steps, $action, $description, $target) = @_;
    
    push @$rollback_steps, [$action, $description, $target];
}

# -------- database operations --------
sub _store_quota_config {
    my ($share_name, $path, $quota, $size, $unit, $fs_type) = @_;
    
    my $stmt = $dbh->prepare("
        INSERT OR REPLACE INTO quota_config 
        (share_name, path, quota_limit, quota_unit, filesystem_type, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ");
    
    my $now = time();
    $stmt->execute($share_name, $path, $size, $unit, $fs_type, $now, $now);
}

sub _get_quota_config {
    my ($share_name) = @_;
    
    my $stmt = $dbh->prepare("
        SELECT * FROM quota_config WHERE share_name = ? AND status = 'active'
    ");
    $stmt->execute($share_name);
    
    return $stmt->fetchrow_hashref;
}

sub _store_quota_history {
    my ($share_name, $usage) = @_;
    
    my $stmt = $dbh->prepare("
        INSERT INTO quota_history 
        (share_name, timestamp, quota_limit, quota_used, quota_percent, 
         files_count, directories_count, largest_file_size, filesystem_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    
    $stmt->execute(
        $share_name, time(), $usage->{quota_limit}, $usage->{used}, $usage->{percent},
        $usage->{files_count}, $usage->{directories_count}, $usage->{largest_file_size},
        $usage->{fs_type}
    );
}

sub _get_recent_alert {
    my ($share_name, $threshold) = @_;
    
    my $stmt = $dbh->prepare("
        SELECT * FROM quota_alerts 
        WHERE share_name = ? AND threshold = ? AND timestamp > ?
        ORDER BY timestamp DESC LIMIT 1
    ");
    
    my $recent_time = time() - 3600; # 1 hour ago
    $stmt->execute($share_name, $threshold, $recent_time);
    
    return $stmt->fetchrow_hashref;
}

# -------- cleanup operations --------
sub cleanup_quota_history {
    my ($days) = @_;
    $days ||= $QUOTA_RETENTION_DAYS;
    
    my $cutoff_time = time() - ($days * 24 * 60 * 60);
    
    # Clean up old history
    my $stmt = $dbh->prepare("
        DELETE FROM quota_history WHERE timestamp < ?
    ");
    $stmt->execute($cutoff_time);
    
    # Clean up old alerts
    $stmt = $dbh->prepare("
        DELETE FROM quota_alerts WHERE timestamp < ?
    ");
    $stmt->execute($cutoff_time);
    
    return 1;
}

# -------- reporting --------
sub get_quota_report {
    my ($share_name, $days) = @_;
    $days ||= 30;
    
    my $config = _get_quota_config($share_name);
    my $usage = get_quota_usage($config->{path}, $share_name);
    my $trend = get_quota_trend($share_name, $days);
    
    return {
        share_name => $share_name,
        config => $config,
        current_usage => $usage,
        trend_analysis => $trend,
        alerts => _get_recent_alerts($share_name, $days),
        generated_at => time()
    };
}

sub _get_recent_alerts {
    my ($share_name, $days) = @_;
    
    my $stmt = $dbh->prepare("
        SELECT * FROM quota_alerts 
        WHERE share_name = ? AND timestamp > ?
        ORDER BY timestamp DESC
    ");
    
    my $cutoff_time = time() - ($days * 24 * 60 * 60);
    $stmt->execute($share_name, $cutoff_time);
    
    my @alerts;
    while (my $row = $stmt->fetchrow_hashref) {
        push @alerts, $row;
    }
    
    return \@alerts;
}

# -------- initialization --------
sub new {
    my ($class) = @_;
    
    my $self = bless {}, $class;
    $self->_init_quota_db();
    
    return $self;
}

1; 