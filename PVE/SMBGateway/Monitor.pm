package PVE::SMBGateway::Monitor;

# PVE SMB Gateway Performance Monitoring Module
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

our @EXPORT_OK = qw(
    collect_io_stats
    collect_connection_stats
    collect_quota_stats
    collect_system_stats
    collect_performance_metrics
    store_metrics
    get_metrics
    cleanup_old_metrics
    get_metrics_summary
    export_prometheus_metrics
);

# -------- configuration --------
my $METRICS_DB = "/etc/pve/smbgateway/metrics.db";
my $METRICS_RETENTION_DAYS = 30;
my $METRICS_COLLECTION_INTERVAL = 60; # seconds
my $METRICS_BATCH_SIZE = 1000;

# -------- database connection --------
my $dbh = undef;

# -------- database initialization --------
sub _init_metrics_db {
    my ($self) = @_;
    
    # Create metrics directory
    my $metrics_dir = "/etc/pve/smbgateway";
    make_path($metrics_dir) unless -d $metrics_dir;
    
    # Connect to SQLite database
    $dbh = DBI->connect("dbi:SQLite:dbname=$METRICS_DB", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        sqlite_use_immediate_transaction => 1
    }) or die "Cannot connect to metrics database: " . DBI->errstr;
    
    # Create tables if they don't exist
    my $create_tables_sql = "
        CREATE TABLE IF NOT EXISTS io_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            bytes_read BIGINT DEFAULT 0,
            bytes_written BIGINT DEFAULT 0,
            operations_read INTEGER DEFAULT 0,
            operations_written INTEGER DEFAULT 0,
            latency_avg_ms REAL DEFAULT 0,
            latency_max_ms REAL DEFAULT 0,
            iops_total INTEGER DEFAULT 0,
            throughput_mbps REAL DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS connection_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            active_connections INTEGER DEFAULT 0,
            total_connections INTEGER DEFAULT 0,
            failed_connections INTEGER DEFAULT 0,
            auth_failures INTEGER DEFAULT 0,
            concurrent_users INTEGER DEFAULT 0,
            session_count INTEGER DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS quota_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            quota_limit BIGINT DEFAULT 0,
            quota_used BIGINT DEFAULT 0,
            quota_percent REAL DEFAULT 0,
            files_count INTEGER DEFAULT 0,
            directories_count INTEGER DEFAULT 0,
            largest_file_size BIGINT DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS system_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            cpu_usage_percent REAL DEFAULT 0,
            memory_usage_percent REAL DEFAULT 0,
            disk_usage_percent REAL DEFAULT 0,
            network_rx_bytes BIGINT DEFAULT 0,
            network_tx_bytes BIGINT DEFAULT 0,
            load_average_1min REAL DEFAULT 0,
            load_average_5min REAL DEFAULT 0,
            load_average_15min REAL DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS performance_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_name TEXT NOT NULL,
            alert_type TEXT NOT NULL,
            alert_level TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            acknowledged INTEGER DEFAULT 0,
            acknowledged_by TEXT,
            acknowledged_at INTEGER
        );
        
        CREATE INDEX IF NOT EXISTS idx_io_stats_share_time ON io_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_connection_stats_share_time ON connection_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_quota_stats_share_time ON quota_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_system_stats_share_time ON system_stats(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_performance_alerts_share_time ON performance_alerts(share_name, timestamp);
        CREATE INDEX IF NOT EXISTS idx_performance_alerts_type ON performance_alerts(alert_type, alert_level);
    ";
    
    # Execute table creation
    $dbh->do($create_tables_sql) or die "Cannot create tables: " . $dbh->errstr;
    
    # Create views for easier querying
    my $create_views_sql = "
        CREATE VIEW IF NOT EXISTS metrics_summary AS
        SELECT 
            s.share_name,
            s.timestamp,
            i.bytes_read,
            i.bytes_written,
            i.operations_read,
            i.operations_written,
            i.latency_avg_ms,
            c.active_connections,
            c.total_connections,
            c.failed_connections,
            q.quota_used,
            q.quota_percent,
            q.files_count,
            sys.cpu_usage_percent,
            sys.memory_usage_percent,
            sys.disk_usage_percent
        FROM system_stats s
        LEFT JOIN io_stats i ON s.share_name = i.share_name AND s.timestamp = i.timestamp
        LEFT JOIN connection_stats c ON s.share_name = c.share_name AND s.timestamp = c.timestamp
        LEFT JOIN quota_stats q ON s.share_name = q.share_name AND s.timestamp = q.timestamp
        WHERE s.share_name = i.share_name AND s.timestamp = i.timestamp;
    ";
    
    eval {
        $dbh->do($create_views_sql);
    };
    
    return 1;
}

# -------- enhanced I/O statistics collection --------
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
        latency_max_ms => 0,
        iops_total => 0,
        throughput_mbps => 0
    };
    
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
            if ($io_stats =~ /syscr:\s*(\d+)/) {
                $stats->{operations_read} = $1;
            }
            if ($io_stats =~ /syscw:\s*(\d+)/) {
                $stats->{operations_written} = $1;
            }
        }
        
        # Get filesystem I/O stats for the specific path
        my $iostat = `iostat -x 1 1 2>/dev/null`;
        if ($iostat =~ /(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)/) {
            $stats->{latency_avg_ms} = $1;
            $stats->{latency_max_ms} = $2;
        }
        
        # Calculate IOPS and throughput
        $stats->{iops_total} = $stats->{operations_read} + $stats->{operations_written};
        my $total_bytes = $stats->{bytes_read} + $stats->{bytes_written};
        $stats->{throughput_mbps} = ($total_bytes * 8) / (1024 * 1024); # Convert to Mbps
        
        # Get operation counts from Samba logs with better parsing
        my $log_stats = `tail -1000 /var/log/samba/log.smbd 2>/dev/null | grep -E "(read|write)" | wc -l`;
        chomp $log_stats;
        my $total_ops = int($log_stats);
        $stats->{operations_read} = int($total_ops * 0.6);  # Estimate 60% reads
        $stats->{operations_written} = int($total_ops * 0.4);  # Estimate 40% writes
    };
    
    if ($@) {
        warn "Error collecting I/O stats for $share_name: $@";
    }
    
    return $stats;
}

# -------- enhanced connection statistics collection --------
sub collect_connection_stats {
    my ($share_name) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        active_connections => 0,
        total_connections => 0,
        failed_connections => 0,
        auth_failures => 0,
        concurrent_users => 0,
        session_count => 0
    };
    
    eval {
        # Get detailed SMB status
        my $smbstatus = `smbstatus --brief 2>/dev/null`;
        
        # Count active connections
        my $active_conns = 0;
        my $unique_users = 0;
        my %users = ();
        
        foreach my $line (split /\n/, $smbstatus) {
            if ($line =~ /Connected/) {
                $active_conns++;
                if ($line =~ /(\S+)\s+\d+\.\d+\.\d+\.\d+/) {
                    $users{$1} = 1;
                }
            }
        }
        
        $stats->{active_connections} = $active_conns;
        $stats->{concurrent_users} = scalar keys %users;
        
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
        
        # Count sessions
        my $sessions = `smbstatus --brief 2>/dev/null | grep -c "Locked files"`;
        chomp $sessions;
        $stats->{session_count} = int($sessions);
    };
    
    if ($@) {
        warn "Error collecting connection stats for $share_name: $@";
    }
    
    return $stats;
}

# -------- enhanced quota statistics collection --------
sub collect_quota_stats {
    my ($share_name, $path, $quota) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        quota_limit => 0,
        quota_used => 0,
        quota_percent => 0,
        files_count => 0,
        directories_count => 0,
        largest_file_size => 0
    };
    
    eval {
        # Parse quota limit
        if ($quota =~ /(\d+)([KMGTP])/) {
            my $size = $1;
            my $unit = $2;
            my $multiplier = {
                'K' => 1024,
                'M' => 1024*1024,
                'G' => 1024*1024*1024,
                'T' => 1024*1024*1024*1024,
                'P' => 1024*1024*1024*1024*1024
            }->{$unit} || 1;
            $stats->{quota_limit} = $size * $multiplier;
        }
        
        # Get current usage with better accuracy
        my $usage = `du -sb "$path" 2>/dev/null`;
        if ($usage =~ /^(\d+)/) {
            $stats->{quota_used} = $1;
        }
        
        # Calculate percentage
        if ($stats->{quota_limit} > 0) {
            $stats->{quota_percent} = ($stats->{quota_used} / $stats->{quota_limit}) * 100;
        }
        
        # Count files and directories
        my $file_count = `find "$path" -type f 2>/dev/null | wc -l`;
        chomp $file_count;
        $stats->{files_count} = int($file_count);
        
        my $dir_count = `find "$path" -type d 2>/dev/null | wc -l`;
        chomp $dir_count;
        $stats->{directories_count} = int($dir_count);
        
        # Find largest file
        my $largest_file = `find "$path" -type f -printf '%s\n' 2>/dev/null | sort -nr | head -1`;
        chomp $largest_file;
        $stats->{largest_file_size} = int($largest_file || 0);
    };
    
    if ($@) {
        warn "Error collecting quota stats for $share_name: $@";
    }
    
    return $stats;
}

# -------- system statistics collection --------
sub collect_system_stats {
    my ($share_name) = @_;
    
    my $stats = {
        share_name => $share_name,
        timestamp => time(),
        cpu_usage_percent => 0,
        memory_usage_percent => 0,
        disk_usage_percent => 0,
        network_rx_bytes => 0,
        network_tx_bytes => 0,
        load_average_1min => 0,
        load_average_5min => 0,
        load_average_15min => 0
    };
    
    eval {
        # CPU usage
        my $cpu_usage = `top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1`;
        chomp $cpu_usage;
        $stats->{cpu_usage_percent} = $cpu_usage || 0;
        
        # Memory usage
        my $mem_info = `free | grep Mem`;
        if ($mem_info =~ /(\d+)\s+(\d+)/) {
            my $total = $1;
            my $used = $2;
            $stats->{memory_usage_percent} = ($used / $total) * 100;
        }
        
        # Load average
        my $loadavg = `cat /proc/loadavg`;
        if ($loadavg =~ /(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)/) {
            $stats->{load_average_1min} = $1;
            $stats->{load_average_5min} = $2;
            $stats->{load_average_15min} = $3;
        }
        
        # Network statistics
        my $net_stats = `cat /proc/net/dev | grep -E "(eth0|ens|enp)" | head -1`;
        if ($net_stats =~ /\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/) {
            $stats->{network_rx_bytes} = $1;
            $stats->{network_tx_bytes} = $2;
        }
        
        # Disk usage for the share path (if available)
        if (defined $share_name) {
            my $disk_usage = `df /srv/smb/$share_name 2>/dev/null | tail -1 | awk '{print \$5}' | cut -d'%' -f1`;
            chomp $disk_usage;
            $stats->{disk_usage_percent} = $disk_usage || 0;
        }
    };
    
    if ($@) {
        warn "Error collecting system stats for $share_name: $@";
    }
    
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
        system_stats => collect_system_stats($share_name)
    };
    
    return $metrics;
}

# -------- enhanced metrics storage with SQLite --------
sub store_metrics {
    my ($metrics) = @_;
    
    return unless $dbh;
    
    eval {
        # Store I/O stats
        my $io_sql = "INSERT INTO io_stats (share_name, timestamp, bytes_read, bytes_written, operations_read, operations_written, latency_avg_ms, latency_max_ms, iops_total, throughput_mbps) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        my $io_sth = $dbh->prepare($io_sql);
        $io_sth->execute(
            $metrics->{share_name},
            $metrics->{timestamp},
            $metrics->{io_stats}->{bytes_read},
            $metrics->{io_stats}->{bytes_written},
            $metrics->{io_stats}->{operations_read},
            $metrics->{io_stats}->{operations_written},
            $metrics->{io_stats}->{latency_avg_ms},
            $metrics->{io_stats}->{latency_max_ms},
            $metrics->{io_stats}->{iops_total},
            $metrics->{io_stats}->{throughput_mbps}
        );
        
        # Store connection stats
        my $conn_sql = "INSERT INTO connection_stats (share_name, timestamp, active_connections, total_connections, failed_connections, auth_failures, concurrent_users, session_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
        my $conn_sth = $dbh->prepare($conn_sql);
        $conn_sth->execute(
            $metrics->{share_name},
            $metrics->{timestamp},
            $metrics->{connection_stats}->{active_connections},
            $metrics->{connection_stats}->{total_connections},
            $metrics->{connection_stats}->{failed_connections},
            $metrics->{connection_stats}->{auth_failures},
            $metrics->{connection_stats}->{concurrent_users},
            $metrics->{connection_stats}->{session_count}
        );
        
        # Store quota stats
        my $quota_sql = "INSERT INTO quota_stats (share_name, timestamp, quota_limit, quota_used, quota_percent, files_count, directories_count, largest_file_size) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
        my $quota_sth = $dbh->prepare($quota_sql);
        $quota_sth->execute(
            $metrics->{share_name},
            $metrics->{timestamp},
            $metrics->{quota_stats}->{quota_limit},
            $metrics->{quota_stats}->{quota_used},
            $metrics->{quota_stats}->{quota_percent},
            $metrics->{quota_stats}->{files_count},
            $metrics->{quota_stats}->{directories_count},
            $metrics->{quota_stats}->{largest_file_size}
        );
        
        # Store system stats
        my $sys_sql = "INSERT INTO system_stats (share_name, timestamp, cpu_usage_percent, memory_usage_percent, disk_usage_percent, network_rx_bytes, network_tx_bytes, load_average_1min, load_average_5min, load_average_15min) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        my $sys_sth = $dbh->prepare($sys_sql);
        $sys_sth->execute(
            $metrics->{share_name},
            $metrics->{timestamp},
            $metrics->{system_stats}->{cpu_usage_percent},
            $metrics->{system_stats}->{memory_usage_percent},
            $metrics->{system_stats}->{disk_usage_percent},
            $metrics->{system_stats}->{network_rx_bytes},
            $metrics->{system_stats}->{network_tx_bytes},
            $metrics->{system_stats}->{load_average_1min},
            $metrics->{system_stats}->{load_average_5min},
            $metrics->{system_stats}->{load_average_15min}
        );
        
        # Check for performance alerts
        _check_performance_alerts($metrics);
        
    };
    
    if ($@) {
        warn "Error storing metrics for $metrics->{share_name}: $@";
        return 0;
    }
    
    return 1;
}

# -------- enhanced metrics retrieval with SQLite --------
sub get_metrics {
    my ($share_name, $start_time, $end_time, $limit) = @_;
    
    return [] unless $dbh;
    
    $start_time //= time() - (24 * 60 * 60); # Default to last 24 hours
    $end_time //= time();
    $limit //= 1000;
    
    my @metrics = ();
    
    eval {
        # Get comprehensive metrics
        my $sql = "
            SELECT 
                s.timestamp,
                s.share_name,
                i.bytes_read,
                i.bytes_written,
                i.operations_read,
                i.operations_written,
                i.latency_avg_ms,
                i.iops_total,
                i.throughput_mbps,
                c.active_connections,
                c.total_connections,
                c.failed_connections,
                c.concurrent_users,
                q.quota_used,
                q.quota_percent,
                q.files_count,
                sys.cpu_usage_percent,
                sys.memory_usage_percent,
                sys.disk_usage_percent,
                sys.load_average_1min
            FROM system_stats s
            LEFT JOIN io_stats i ON s.share_name = i.share_name AND s.timestamp = i.timestamp
            LEFT JOIN connection_stats c ON s.share_name = c.share_name AND s.timestamp = c.timestamp
            LEFT JOIN quota_stats q ON s.share_name = q.share_name AND s.timestamp = q.timestamp
            WHERE s.share_name = ? AND s.timestamp BETWEEN ? AND ?
            ORDER BY s.timestamp DESC
            LIMIT ?
        ";
        
        my $sth = $dbh->prepare($sql);
        $sth->execute($share_name, $start_time, $end_time, $limit);
        
        while (my $row = $sth->fetchrow_hashref) {
            push @metrics, $row;
        }
    };
    
    if ($@) {
        warn "Error retrieving metrics for $share_name: $@";
    }
    
    return \@metrics;
}

# -------- metrics summary for dashboard --------
sub get_metrics_summary {
    my ($share_name, $hours) = @_;
    
    return {} unless $dbh;
    
    $hours //= 24;
    my $start_time = time() - ($hours * 60 * 60);
    
    my $summary = {
        share_name => $share_name,
        period_hours => $hours,
        timestamp => time()
    };
    
    eval {
        # Get latest metrics
        my $latest_sql = "
            SELECT 
                i.bytes_read, i.bytes_written, i.operations_read, i.operations_written,
                i.latency_avg_ms, i.iops_total, i.throughput_mbps,
                c.active_connections, c.concurrent_users,
                q.quota_used, q.quota_percent, q.files_count,
                sys.cpu_usage_percent, sys.memory_usage_percent, sys.disk_usage_percent
            FROM system_stats sys
            LEFT JOIN io_stats i ON sys.share_name = i.share_name AND sys.timestamp = i.timestamp
            LEFT JOIN connection_stats c ON sys.share_name = c.share_name AND sys.timestamp = c.timestamp
            LEFT JOIN quota_stats q ON sys.share_name = q.share_name AND sys.timestamp = q.timestamp
            WHERE sys.share_name = ? AND sys.timestamp >= ?
            ORDER BY sys.timestamp DESC
            LIMIT 1
        ";
        
        my $sth = $dbh->prepare($latest_sql);
        $sth->execute($share_name, $start_time);
        my $latest = $sth->fetchrow_hashref;
        
        if ($latest) {
            $summary->{current} = $latest;
        }
        
        # Get averages for the period
        my $avg_sql = "
            SELECT 
                AVG(i.bytes_read) as avg_bytes_read,
                AVG(i.bytes_written) as avg_bytes_written,
                AVG(i.operations_read) as avg_operations_read,
                AVG(i.operations_written) as avg_operations_written,
                AVG(i.latency_avg_ms) as avg_latency_ms,
                AVG(i.iops_total) as avg_iops,
                AVG(i.throughput_mbps) as avg_throughput_mbps,
                AVG(c.active_connections) as avg_active_connections,
                AVG(c.concurrent_users) as avg_concurrent_users,
                AVG(q.quota_percent) as avg_quota_percent,
                AVG(sys.cpu_usage_percent) as avg_cpu_usage,
                AVG(sys.memory_usage_percent) as avg_memory_usage,
                AVG(sys.disk_usage_percent) as avg_disk_usage
            FROM system_stats sys
            LEFT JOIN io_stats i ON sys.share_name = i.share_name AND sys.timestamp = i.timestamp
            LEFT JOIN connection_stats c ON sys.share_name = c.share_name AND sys.timestamp = c.timestamp
            LEFT JOIN quota_stats q ON sys.share_name = q.share_name AND sys.timestamp = q.timestamp
            WHERE sys.share_name = ? AND sys.timestamp >= ?
        ";
        
        $sth = $dbh->prepare($avg_sql);
        $sth->execute($share_name, $start_time);
        my $averages = $sth->fetchrow_hashref;
        
        if ($averages) {
            $summary->{averages} = $averages;
        }
        
        # Get peak values
        my $peak_sql = "
            SELECT 
                MAX(i.bytes_read) as peak_bytes_read,
                MAX(i.bytes_written) as peak_bytes_written,
                MAX(i.operations_read) as peak_operations_read,
                MAX(i.operations_written) as peak_operations_written,
                MAX(i.latency_avg_ms) as peak_latency_ms,
                MAX(i.iops_total) as peak_iops,
                MAX(i.throughput_mbps) as peak_throughput_mbps,
                MAX(c.active_connections) as peak_active_connections,
                MAX(c.concurrent_users) as peak_concurrent_users,
                MAX(q.quota_percent) as peak_quota_percent,
                MAX(sys.cpu_usage_percent) as peak_cpu_usage,
                MAX(sys.memory_usage_percent) as peak_memory_usage,
                MAX(sys.disk_usage_percent) as peak_disk_usage
            FROM system_stats sys
            LEFT JOIN io_stats i ON sys.share_name = i.share_name AND sys.timestamp = i.timestamp
            LEFT JOIN connection_stats c ON sys.share_name = c.share_name AND sys.timestamp = c.timestamp
            LEFT JOIN quota_stats q ON sys.share_name = q.share_name AND sys.timestamp = q.timestamp
            WHERE sys.share_name = ? AND sys.timestamp >= ?
        ";
        
        $sth = $dbh->prepare($peak_sql);
        $sth->execute($share_name, $start_time);
        my $peaks = $sth->fetchrow_hashref;
        
        if ($peaks) {
            $summary->{peaks} = $peaks;
        }
        
    };
    
    if ($@) {
        warn "Error getting metrics summary for $share_name: $@";
    }
    
    return $summary;
}

# -------- Prometheus metrics export --------
sub export_prometheus_metrics {
    my ($share_name) = @_;
    
    return "" unless $dbh;
    
    my $prometheus_output = "";
    my $timestamp = time() * 1000; # Prometheus uses milliseconds
    
    eval {
        # Get latest metrics
        my $sql = "
            SELECT 
                i.bytes_read, i.bytes_written, i.operations_read, i.operations_written,
                i.latency_avg_ms, i.iops_total, i.throughput_mbps,
                c.active_connections, c.total_connections, c.failed_connections,
                q.quota_used, q.quota_percent, q.files_count,
                sys.cpu_usage_percent, sys.memory_usage_percent, sys.disk_usage_percent
            FROM system_stats sys
            LEFT JOIN io_stats i ON sys.share_name = i.share_name AND sys.timestamp = i.timestamp
            LEFT JOIN connection_stats c ON sys.share_name = c.share_name AND sys.timestamp = c.timestamp
            LEFT JOIN quota_stats q ON sys.share_name = q.share_name AND sys.timestamp = q.timestamp
            WHERE sys.share_name = ? 
            ORDER BY sys.timestamp DESC
            LIMIT 1
        ";
        
        my $sth = $dbh->prepare($sql);
        $sth->execute($share_name);
        my $metrics = $sth->fetchrow_hashref;
        
        if ($metrics) {
            $prometheus_output .= "# HELP smbgateway_bytes_read Total bytes read\n";
            $prometheus_output .= "# TYPE smbgateway_bytes_read counter\n";
            $prometheus_output .= "smbgateway_bytes_read{share=\"$share_name\"} $metrics->{bytes_read} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_bytes_written Total bytes written\n";
            $prometheus_output .= "# TYPE smbgateway_bytes_written counter\n";
            $prometheus_output .= "smbgateway_bytes_written{share=\"$share_name\"} $metrics->{bytes_written} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_operations_total Total I/O operations\n";
            $prometheus_output .= "# TYPE smbgateway_operations_total counter\n";
            $prometheus_output .= "smbgateway_operations_total{share=\"$share_name\"} $metrics->{iops_total} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_latency_ms Average latency in milliseconds\n";
            $prometheus_output .= "# TYPE smbgateway_latency_ms gauge\n";
            $prometheus_output .= "smbgateway_latency_ms{share=\"$share_name\"} $metrics->{latency_avg_ms} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_throughput_mbps Throughput in Mbps\n";
            $prometheus_output .= "# TYPE smbgateway_throughput_mbps gauge\n";
            $prometheus_output .= "smbgateway_throughput_mbps{share=\"$share_name\"} $metrics->{throughput_mbps} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_active_connections Active SMB connections\n";
            $prometheus_output .= "# TYPE smbgateway_active_connections gauge\n";
            $prometheus_output .= "smbgateway_active_connections{share=\"$share_name\"} $metrics->{active_connections} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_quota_percent Quota usage percentage\n";
            $prometheus_output .= "# TYPE smbgateway_quota_percent gauge\n";
            $prometheus_output .= "smbgateway_quota_percent{share=\"$share_name\"} $metrics->{quota_percent} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_cpu_usage_percent CPU usage percentage\n";
            $prometheus_output .= "# TYPE smbgateway_cpu_usage_percent gauge\n";
            $prometheus_output .= "smbgateway_cpu_usage_percent{share=\"$share_name\"} $metrics->{cpu_usage_percent} $timestamp\n";
            
            $prometheus_output .= "# HELP smbgateway_memory_usage_percent Memory usage percentage\n";
            $prometheus_output .= "# TYPE smbgateway_memory_usage_percent gauge\n";
            $prometheus_output .= "smbgateway_memory_usage_percent{share=\"$share_name\"} $metrics->{memory_usage_percent} $timestamp\n";
        }
    };
    
    if ($@) {
        warn "Error exporting Prometheus metrics for $share_name: $@";
    }
    
    return $prometheus_output;
}

# -------- performance alert checking --------
sub _check_performance_alerts {
    my ($metrics) = @_;
    
    return unless $dbh;
    
    my $share_name = $metrics->{share_name};
    my $timestamp = $metrics->{timestamp};
    
    # Check quota alerts
    my $quota_percent = $metrics->{quota_stats}->{quota_percent};
    if ($quota_percent >= 95) {
        _create_alert($share_name, 'quota', 'critical', "Quota usage at ${quota_percent}%", $timestamp);
    } elsif ($quota_percent >= 85) {
        _create_alert($share_name, 'quota', 'warning', "Quota usage at ${quota_percent}%", $timestamp);
    }
    
    # Check performance alerts
    my $latency = $metrics->{io_stats}->{latency_avg_ms};
    if ($latency >= 100) {
        _create_alert($share_name, 'performance', 'critical', "High latency: ${latency}ms", $timestamp);
    } elsif ($latency >= 50) {
        _create_alert($share_name, 'performance', 'warning', "Elevated latency: ${latency}ms", $timestamp);
    }
    
    # Check connection alerts
    my $failed_connections = $metrics->{connection_stats}->{failed_connections};
    if ($failed_connections >= 10) {
        _create_alert($share_name, 'connection', 'warning', "High connection failures: $failed_connections", $timestamp);
    }
    
    # Check system alerts
    my $cpu_usage = $metrics->{system_stats}->{cpu_usage_percent};
    if ($cpu_usage >= 90) {
        _create_alert($share_name, 'system', 'critical', "High CPU usage: ${cpu_usage}%", $timestamp);
    } elsif ($cpu_usage >= 80) {
        _create_alert($share_name, 'system', 'warning', "Elevated CPU usage: ${cpu_usage}%", $timestamp);
    }
}

# -------- create performance alert --------
sub _create_alert {
    my ($share_name, $alert_type, $alert_level, $message, $timestamp) = @_;
    
    return unless $dbh;
    
    eval {
        my $sql = "INSERT INTO performance_alerts (share_name, alert_type, alert_level, message, timestamp) VALUES (?, ?, ?, ?, ?)";
        my $sth = $dbh->prepare($sql);
        $sth->execute($share_name, $alert_type, $alert_level, $message, $timestamp);
    };
    
    if ($@) {
        warn "Error creating alert for $share_name: $@";
    }
}

# -------- enhanced cleanup with SQLite --------
sub cleanup_old_metrics {
    my ($retention_days) = @_;
    
    return 0 unless $dbh;
    
    $retention_days //= $METRICS_RETENTION_DAYS;
    my $cutoff_time = time() - ($retention_days * 24 * 60 * 60);
    
    my $deleted_count = 0;
    
    eval {
        # Clean up old metrics from all tables
        my @tables = qw(io_stats connection_stats quota_stats system_stats);
        
        foreach my $table (@tables) {
            my $sql = "DELETE FROM $table WHERE timestamp < ?";
            my $sth = $dbh->prepare($sql);
            my $rows = $sth->execute($cutoff_time);
            $deleted_count += $rows;
        }
        
        # Clean up old alerts (keep for 7 days)
        my $alert_cutoff = time() - (7 * 24 * 60 * 60);
        my $sql = "DELETE FROM performance_alerts WHERE timestamp < ?";
        my $sth = $dbh->prepare($sql);
        my $rows = $sth->execute($alert_cutoff);
        $deleted_count += $rows;
        
        # Optimize database
        $dbh->do("VACUUM");
        
    };
    
    if ($@) {
        warn "Error cleaning up old metrics: $@";
    }
    
    return $deleted_count;
}

# -------- initialization --------
sub new {
    my ($class) = @_;
    
    my $self = bless {}, $class;
    $self->_init_metrics_db();
    
    return $self;
}

# -------- cleanup on destruction --------
sub DESTROY {
    if ($dbh) {
        $dbh->disconnect();
    }
}

# -------- class method for collecting all shares metrics --------
sub collect_all_metrics {
    my ($class) = @_;
    
    # Get all SMB Gateway shares from PVE storage configuration
    my $pve_config_dir = '/etc/pve/storage.cfg';
    return unless -f $pve_config_dir;
    
    my @shares = ();
    open(my $fh, '<', $pve_config_dir) or return;
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ /^smbgateway:\s*(\S+)/) {
            my $share_id = $1;
            push @shares, $share_id;
        }
    }
    close($fh);
    
    # Collect metrics for each share
    foreach my $share_id (@shares) {
        eval {
            # Get share configuration
            my $share_config = _get_share_config($share_id);
            next unless $share_config;
            
            my $sharename = $share_config->{sharename};
            my $path = $share_config->{path} // "/srv/smb/$sharename";
            
            # Create monitor instance for this share
            my $monitor = $class->new(
                share_name => $sharename,
                share_path => $path,
                db_path => "/var/lib/pve/smbgateway/metrics.db"
            );
            
            # Collect and store metrics
            $monitor->collect_and_store_metrics();
            
            # Check for alerts
            $monitor->check_performance_alerts();
            
            print "Collected metrics for share: $sharename\n";
            
        };
        
        if ($@) {
            warn "Error collecting metrics for share $share_id: $@";
        }
    }
    
    # Cleanup old metrics
    my $monitor = $class->new();
    $monitor->cleanup_old_data();
    
    print "Metrics collection completed for " . scalar(@shares) . " shares\n";
}

# -------- helper method to get share configuration --------
sub _get_share_config {
    my ($share_id) = @_;
    
    my $pve_config_dir = '/etc/pve/storage.cfg';
    return unless -f $pve_config_dir;
    
    my $current_section = '';
    my $share_config = {};
    
    open(my $fh, '<', $pve_config_dir) or return;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/;  # Skip comments
        
        if ($line =~ /^(\w+):\s*(\S+)/) {
            $current_section = $1;
            my $section_id = $2;
            
            if ($current_section eq 'smbgateway' && $section_id eq $share_id) {
                $share_config->{sharename} = $section_id;
            } else {
                $share_config = {};  # Reset for other sections
            }
        } elsif ($line =~ /^\s*(\w+)\s+(.+)$/ && $share_config->{sharename}) {
            my $key = $1;
            my $value = $2;
            $share_config->{$key} = $value;
        }
    }
    close($fh);
    
    return $share_config->{sharename} ? $share_config : undef;
}

1; 