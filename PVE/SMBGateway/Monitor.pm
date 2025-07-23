package PVE::SMBGateway::Monitor;

# PVE SMB Gateway Performance Monitoring Module
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

use strict;
use warnings;
use base qw(Exporter);
use PVE::Tools qw(run_command);
use PVE::Exception qw(raise_param_exc);

our @EXPORT_OK = qw(
    collect_io_stats
    collect_connection_stats
    collect_quota_stats
    collect_performance_metrics
    store_metrics
    get_metrics
    cleanup_old_metrics
);

# -------- configuration --------
my $METRICS_DB = "/etc/pve/smbgateway/metrics.db";
my $METRICS_RETENTION_DAYS = 30;
my $METRICS_COLLECTION_INTERVAL = 60; # seconds

# -------- database initialization --------
sub _init_metrics_db {
    my ($self) = @_;
    
    # Create metrics directory
    my $metrics_dir = "/etc/pve/smbgateway";
    mkdir $metrics_dir unless -d $metrics_dir;
    
    # Initialize SQLite database
    my $db_init_sql = "
        CREATE TABLE IF NOT EXISTS io_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            bytes_read BIGINT DEFAULT 0,
            bytes_written BIGINT DEFAULT 0,
            operations_read INTEGER DEFAULT 0,
            operations_written INTEGER DEFAULT 0,
            latency_avg_ms REAL DEFAULT 0,
            latency_max_ms REAL DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS connection_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            active_connections INTEGER DEFAULT 0,
            total_connections INTEGER DEFAULT 0,
            failed_connections INTEGER DEFAULT 0,
            auth_failures INTEGER DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS quota_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            quota_limit BIGINT DEFAULT 0,
            quota_used BIGINT DEFAULT 0,
            quota_percent REAL DEFAULT 0,
            files_count INTEGER DEFAULT 0
        );
        
        CREATE INDEX IF NOT EXISTS idx_io_stats_share_time ON io_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_connection_stats_share_time ON connection_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_quota_stats_share_time ON quota_stats(share_name, timestamp);
    ";
    
    # Execute SQL (simplified - in production would use DBI)
    my $temp_file = "/tmp/smbgateway_metrics_init.sql";
    open(my $fh, '>', $temp_file) or die "Cannot create temp file: $!";
    print $fh $db_init_sql;
    close $fh;
    
    # Note: In production, would use proper SQLite DBI module
    # For now, we'll use file-based storage for simplicity
}

# -------- I/O statistics collection --------
sub collect_io_stats {
    my ($share_name, $path) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        bytes_read => 0,
        bytes_written => 0,
        operations_read => 0,
        operations_written => 0,
        latency_avg_ms => 0,
        latency_max_ms => 0
    };
    
    # Collect I/O statistics from Samba
    eval {
        # Get Samba process stats
        my $smbd_pid = `pgrep smbd`;
        chomp $smbd_pid;
        
        if ($smbd_pid) {
            # Get I/O stats from /proc
            my $io_stats = `cat /proc/$smbd_pid/io 2>/dev/null`;
            if ($io_stats =~ /rchar:\s*(\d+)/) {
                $stats->{bytes_read} = $1;
            }
            if ($io_stats =~ /wchar:\s*(\d+)/) {
                $stats->{bytes_written} = $1;
            }
        }
        
        # Get filesystem I/O stats for the specific path
        my $iostat = `iostat -x 1 1 2>/dev/null`;
        if ($iostat =~ /(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)/) {
            $stats->{latency_avg_ms} = $1;
            $stats->{latency_max_ms} = $2;
        }
        
        # Get operation counts from Samba logs
        my $log_stats = `tail -100 /var/log/samba/log.smbd 2>/dev/null | grep -c "read\|write"`;
        chomp $log_stats;
        $stats->{operations_read} = int($log_stats / 2);
        $stats->{operations_written} = int($log_stats / 2);
    };
    
    return $stats;
}

# -------- connection statistics collection --------
sub collect_connection_stats {
    my ($share_name) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        active_connections => 0,
        total_connections => 0,
        failed_connections => 0,
        auth_failures => 0
    };
    
    eval {
        # Count active SMB connections
        my $active_conns = `smbstatus --brief 2>/dev/null | grep -c "Connected"`;
        chomp $active_conns;
        $stats->{active_connections} = int($active_conns);
        
        # Count total connections from logs
        my $total_conns = `tail -1000 /var/log/samba/log.smbd 2>/dev/null | grep -c "session setup"`;
        chomp $total_conns;
        $stats->{total_connections} = int($total_conns);
        
        # Count failed connections
        my $failed_conns = `tail -1000 /var/log/samba/log.smbd 2>/dev/null | grep -c "session setup failed"`;
        chomp $failed_conns;
        $stats->{failed_connections} = int($failed_conns);
        
        # Count authentication failures
        my $auth_failures = `tail -1000 /var/log/samba/log.smbd 2>/dev/null | grep -c "authentication failure"`;
        chomp $auth_failures;
        $stats->{auth_failures} = int($auth_failures);
    };
    
    return $stats;
}

# -------- quota statistics collection --------
sub collect_quota_stats {
    my ($share_name, $path, $quota) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        quota_limit => 0,
        quota_used => 0,
        quota_percent => 0,
        files_count => 0
    };
    
    eval {
        # Parse quota limit
        if ($quota =~ /(\d+)([GT])/) {
            my $size = $1;
            my $unit = $2;
            $stats->{quota_limit} = $size * ($unit eq 'G' ? 1024*1024*1024 : 1024*1024*1024*1024);
        }
        
        # Get current usage
        my $usage = `du -sb "$path" 2>/dev/null`;
        if ($usage =~ /^(\d+)/) {
            $stats->{quota_used} = $1;
        }
        
        # Calculate percentage
        if ($stats->{quota_limit} > 0) {
            $stats->{quota_percent} = ($stats->{quota_used} / $stats->{quota_limit}) * 100;
        }
        
        # Count files
        my $file_count = `find "$path" -type f 2>/dev/null | wc -l`;
        chomp $file_count;
        $stats->{files_count} = int($file_count);
    };
    
    return $stats;
}

# -------- comprehensive performance metrics --------
sub collect_performance_metrics {
    my ($share_name, $path, $quota) = @_;
    
    my $metrics = {
        timestamp => time(),
        share_name => $share_name,
        io_stats => collect_io_stats($share_name, $path),
        connection_stats => collect_connection_stats($share_name),
        quota_stats => collect_quota_stats($share_name, $path, $quota),
        system_stats => {
            cpu_usage => 0,
            memory_usage => 0,
            disk_usage => 0
        }
    };
    
    # Collect system-level statistics
    eval {
        # CPU usage
        my $cpu_usage = `top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1`;
        chomp $cpu_usage;
        $metrics->{system_stats}->{cpu_usage} = $cpu_usage || 0;
        
        # Memory usage
        my $mem_info = `free | grep Mem`;
        if ($mem_info =~ /(\d+)\s+(\d+)/) {
            my $total = $1;
            my $used = $2;
            $metrics->{system_stats}->{memory_usage} = ($used / $total) * 100;
        }
        
        # Disk usage for the share path
        my $disk_usage = `df "$path" | tail -1 | awk '{print \$5}' | cut -d'%' -f1`;
        chomp $disk_usage;
        $metrics->{system_stats}->{disk_usage} = $disk_usage || 0;
    };
    
    return $metrics;
}

# -------- metrics storage --------
sub store_metrics {
    my ($metrics) = @_;
    
    # Store metrics in JSON format for simplicity
    # In production, would use proper SQLite database
    my $metrics_dir = "/etc/pve/smbgateway/metrics";
    mkdir $metrics_dir unless -d $metrics_dir;
    
    my $share_name = $metrics->{share_name};
    my $timestamp = $metrics->{timestamp};
    my $metrics_file = "$metrics_dir/${share_name}_${timestamp}.json";
    
    # Convert to JSON (simplified)
    my $json_data = _hash_to_json($metrics);
    
    open(my $fh, '>', $metrics_file) or die "Cannot write metrics file: $!";
    print $fh $json_data;
    close $fh;
    
    return 1;
}

# -------- metrics retrieval --------
sub get_metrics {
    my ($share_name, $start_time, $end_time) = @_;
    
    $start_time //= time() - (24 * 60 * 60); # Default to last 24 hours
    $end_time //= time();
    
    my $metrics_dir = "/etc/pve/smbgateway/metrics";
    my @metrics = ();
    
    # Read all metrics files for the share
    opendir(my $dh, $metrics_dir) or return \@metrics;
    
    while (my $file = readdir($dh)) {
        next unless $file =~ /^${share_name}_(\d+)\.json$/;
        my $file_timestamp = $1;
        
        if ($file_timestamp >= $start_time && $file_timestamp <= $end_time) {
            my $metrics_file = "$metrics_dir/$file";
            if (open(my $fh, '<', $metrics_file)) {
                local $/;
                my $json_data = <$fh>;
                close $fh;
                
                my $metrics = _json_to_hash($json_data);
                push @metrics, $metrics if $metrics;
            }
        }
    }
    
    closedir($dh);
    
    # Sort by timestamp
    @metrics = sort { $a->{timestamp} <=> $b->{timestamp} } @metrics;
    
    return \@metrics;
}

# -------- cleanup old metrics --------
sub cleanup_old_metrics {
    my ($retention_days) = @_;
    
    $retention_days //= $METRICS_RETENTION_DAYS;
    my $cutoff_time = time() - ($retention_days * 24 * 60 * 60);
    
    my $metrics_dir = "/etc/pve/smbgateway/metrics";
    return unless -d $metrics_dir;
    
    my $deleted_count = 0;
    
    opendir(my $dh, $metrics_dir) or return;
    
    while (my $file = readdir($dh)) {
        next unless $file =~ /_(\d+)\.json$/;
        my $file_timestamp = $1;
        
        if ($file_timestamp < $cutoff_time) {
            my $file_path = "$metrics_dir/$file";
            if (unlink($file_path)) {
                $deleted_count++;
            }
        }
    }
    
    closedir($dh);
    
    return $deleted_count;
}

# -------- helper functions --------
sub _hash_to_json {
    my ($hash) = @_;
    
    # Simple JSON conversion (in production, use JSON::PP)
    my $json = "{";
    my @pairs = ();
    
    foreach my $key (keys %$hash) {
        my $value = $hash->{$key};
        if (ref($value) eq 'HASH') {
            push @pairs, "\"$key\": " . _hash_to_json($value);
        } elsif (ref($value) eq 'ARRAY') {
            push @pairs, "\"$key\": [" . join(',', @$value) . "]";
        } else {
            push @pairs, "\"$key\": \"$value\"";
        }
    }
    
    $json .= join(',', @pairs) . "}";
    return $json;
}

sub _json_to_hash {
    my ($json) = @_;
    
    # Simple JSON parsing (in production, use JSON::PP)
    # This is a simplified version - would need proper JSON parsing
    my $hash = {};
    
    # Remove outer braces
    $json =~ s/^\{//;
    $json =~ s/\}$//;
    
    # Parse key-value pairs
    while ($json =~ /"([^"]+)":\s*"([^"]+)"/g) {
        $hash->{$1} = $2;
    }
    
    return $hash;
}

# -------- initialization --------
sub new {
    my ($class) = @_;
    
    my $self = bless {}, $class;
    $self->_init_metrics_db();
    
    return $self;
}

1; 