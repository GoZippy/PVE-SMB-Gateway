package PVE::SMBGateway::Security;

# PVE SMB Gateway Security Module
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# This module provides security hardening for SMB protocol,
# container/VM security profiles, and security validation.

use strict;
use warnings;
use base qw(Exporter);
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::Exception qw(raise_param_exc);
use PVE::JSONSchema qw(get_standard_option);
use Time::HiRes qw(time);
use JSON::PP;
use File::Path qw(make_path);

our @EXPORT_OK = qw(
    harden_smb_protocol
    create_security_profile
    validate_security_config
    setup_service_user
    run_security_scan
    generate_security_report
    enforce_security_policies
    monitor_security_events
);

# -------- configuration --------
my $SECURITY_CONFIG_DIR = '/etc/pve/smbgateway/security';
my $SECURITY_LOG_DIR = '/var/log/pve/smbgateway/security';
my $SECURITY_DB_PATH = '/var/lib/pve/smbgateway/security.db';
my $SECURITY_SCAN_INTERVAL = 3600; # 1 hour

# -------- security policies --------
my $SECURITY_POLICIES = {
    smb_protocol => {
        min_protocol => 'SMB2',
        max_protocol => 'SMB3',
        signing => 'mandatory',
        encryption => 'required',
        guest_access => 'disabled',
        anonymous_access => 'disabled',
        lanman_auth => 'disabled',
        ntlm_auth => 'disabled',
        smb1_support => 'disabled'
    },
    authentication => {
        kerberos_required => 1,
        strong_passwords => 1,
        password_history => 5,
        account_lockout => 1,
        lockout_threshold => 5,
        lockout_duration => 900, # 15 minutes
        session_timeout => 3600  # 1 hour
    },
    network => {
        bind_interfaces => 1,
        allowed_hosts => [],
        denied_hosts => [],
        port_scanning => 'detect',
        ddos_protection => 1
    },
    filesystem => {
        symlink_following => 'disabled',
        wide_links => 'disabled',
        unix_extensions => 'enabled',
        acl_support => 'enabled',
        case_sensitive => 'auto'
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
    
    $self->_init_security_db();
    $self->_ensure_directories();
    
    return $self;
}

# -------- database initialization --------
sub _init_security_db {
    my ($self) = @_;
    
    # Create database directory
    my $db_dir = dirname($SECURITY_DB_PATH);
    make_path($db_dir) unless -d $db_dir;
    
    # Connect to SQLite database
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$SECURITY_DB_PATH", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
    }) or die "Cannot connect to security database: " . DBI->errstr;
    
    # Create security tables
    my $create_tables_sql = "
        CREATE TABLE IF NOT EXISTS security_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            severity TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            metadata TEXT
        );
        
        CREATE TABLE IF NOT EXISTS security_scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            scan_type TEXT NOT NULL,
            status TEXT NOT NULL,
            findings_count INTEGER DEFAULT 0,
            critical_count INTEGER DEFAULT 0,
            high_count INTEGER DEFAULT 0,
            medium_count INTEGER DEFAULT 0,
            low_count INTEGER DEFAULT 0,
            scan_start INTEGER NOT NULL,
            scan_end INTEGER,
            report_path TEXT
        );
        
        CREATE TABLE IF NOT EXISTS security_policies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            policy_type TEXT NOT NULL,
            policy_name TEXT NOT NULL,
            policy_config TEXT NOT NULL,
            enabled INTEGER DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS service_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            share_id TEXT NOT NULL,
            username TEXT NOT NULL,
            uid INTEGER NOT NULL,
            gid INTEGER NOT NULL,
            home_dir TEXT NOT NULL,
            shell TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            last_login INTEGER,
            status TEXT DEFAULT 'active'
        );
    ";
    
    $self->{dbh}->do($create_tables_sql);
    
    # Create indexes
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_security_events_share_time ON security_events(share_id, timestamp)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events(event_type, severity)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_security_scans_share_time ON security_scans(share_id, scan_start)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_security_policies_share_type ON security_policies(share_id, policy_type)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_service_users_share ON service_users(share_id, username)");
}

# -------- directory creation --------
sub _ensure_directories {
    my ($self) = @_;
    
    foreach my $dir ($SECURITY_CONFIG_DIR, $SECURITY_LOG_DIR) {
        make_path($dir) unless -d $dir;
    }
}

# -------- SMB protocol hardening --------
sub harden_smb_protocol {
    my ($self, %param) = @_;
    
    my $smb_conf_path = $param{smb_conf_path} // "/etc/samba/smb.conf";
    my $policies = $param{policies} // $SECURITY_POLICIES->{smb_protocol};
    
    # Read existing Samba configuration
    my $smb_conf = file_read_all($smb_conf_path) or die "Cannot read Samba config: $!";
    
    # Apply security policies
    my $hardened_conf = $self->_apply_smb_security_policies($smb_conf, $policies);
    
    # Write hardened configuration
    file_set_contents($smb_conf_path, $hardened_conf);
    
    # Validate configuration
    my $validation_result = $self->_validate_smb_config($smb_conf_path);
    
    if ($validation_result->{valid}) {
        # Reload Samba configuration
        run_command(['systemctl', 'reload', 'smbd']);
        run_command(['systemctl', 'reload', 'nmbd']);
        
        $self->_log_security_event('smb_hardening', 'info', 
            "SMB protocol hardened successfully for share $self->{share_name}");
        
        return {
            status => 'success',
            message => 'SMB protocol hardened successfully',
            changes => $validation_result->{changes}
        };
    } else {
        $self->_log_security_event('smb_hardening', 'error', 
            "SMB hardening failed: " . $validation_result->{error});
        
        return {
            status => 'error',
            message => 'SMB hardening failed',
            error => $validation_result->{error}
        };
    }
}

# -------- apply SMB security policies --------
sub _apply_smb_security_policies {
    my ($self, $smb_conf, $policies) = @_;
    
    my $lines = [split(/\n/, $smb_conf)];
    my $global_section = 0;
    my $changes = [];
    
    for (my $i = 0; $i < @$lines; $i++) {
        my $line = $lines->[$i];
        
        if ($line =~ /^\[global\]/) {
            $global_section = 1;
            next;
        }
        
        if ($global_section && $line =~ /^\[/) {
            $global_section = 0;
            next;
        }
        
        if ($global_section) {
            # Apply security policies
            foreach my $policy (keys %$policies) {
                my $value = $policies->{$policy};
                my $pattern = qr/^\s*$policy\s*=/i;
                
                if ($line =~ $pattern) {
                    # Update existing setting
                    $lines->[$i] = "    $policy = $value";
                    push @$changes, "Updated $policy = $value";
                    last;
                } elsif ($line =~ /^\s*$/ && $i > 0) {
                    # Add new setting after empty line
                    splice(@$lines, $i, 0, "    $policy = $value");
                    push @$changes, "Added $policy = $value";
                    $i++;
                    last;
                }
            }
        }
    }
    
    # Add any missing policies
    foreach my $policy (keys %$policies) {
        my $value = $policies->{$policy};
        my $found = 0;
        
        foreach my $line (@$lines) {
            if ($line =~ /^\s*$policy\s*=/i) {
                $found = 1;
                last;
            }
        }
        
        if (!$found) {
            push @$lines, "    $policy = $value";
            push @$changes, "Added $policy = $value";
        }
    }
    
    return join("\n", @$lines);
}

# -------- validate SMB configuration --------
sub _validate_smb_config {
    my ($self, $smb_conf_path) = @_;
    
    eval {
        # Test Samba configuration
        my $test_result = run_command(['testparm', '-s', $smb_conf_path]);
        
        if ($test_result->{exitcode} == 0) {
            return {
                valid => 1,
                changes => $test_result->{stdout}
            };
        } else {
            return {
                valid => 0,
                error => $test_result->{stderr}
            };
        }
    };
    
    return {
        valid => 0,
        error => "Configuration validation failed: $@"
    };
}

# -------- create security profile --------
sub create_security_profile {
    my ($self, %param) = @_;
    
    my $profile_type = $param{profile_type} // 'standard';
    my $mode = $param{mode} // $self->{mode};
    
    my $profile = {
        name => "security_profile_$self->{share_name}",
        type => $profile_type,
        mode => $mode,
        created_at => time(),
        policies => {}
    };
    
    # Apply mode-specific security policies
    if ($mode eq 'lxc') {
        $profile->{policies} = $self->_create_lxc_security_profile($profile_type);
    } elsif ($mode eq 'vm') {
        $profile->{policies} = $self->_create_vm_security_profile($profile_type);
    } else {
        $profile->{policies} = $self->_create_native_security_profile($profile_type);
    }
    
    # Store profile in database
    $self->{dbh}->do(
        "INSERT INTO security_policies (share_id, policy_type, policy_name, policy_config, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        undef, $self->{share_id}, 'profile', $profile->{name}, encode_json($profile), time(), time()
    );
    
    $self->_log_security_event('profile_created', 'info', 
        "Security profile created for share $self->{share_name}");
    
    return $profile;
}

# -------- create LXC security profile --------
sub _create_lxc_security_profile {
    my ($self, $profile_type) = @_;
    
    my $profile = {
        apparmor => {
            enabled => 1,
            profile => "pve-smbgateway-$self->{share_name}",
            rules => [
                "deny /proc/sys/kernel/random/uuid r",
                "deny /proc/sys/kernel/random/entropy_avail r",
                "deny /proc/sys/kernel/random/poolsize r",
                "deny /proc/sys/kernel/random/read_wakeup_threshold r",
                "deny /proc/sys/kernel/random/write_wakeup_threshold r",
                "deny /proc/sys/kernel/random/urandom_min_reseed_secs r",
                "deny /proc/sys/kernel/random/reseed_uuid r",
                "deny /proc/sys/kernel/random/boot_id r",
                "deny /proc/sys/kernel/random/cpu_entropy_bits r",
                "deny /proc/sys/kernel/random/entropy_avail r",
                "deny /proc/sys/kernel/random/poolsize r",
                "deny /proc/sys/kernel/random/read_wakeup_threshold r",
                "deny /proc/sys/kernel/random/write_wakeup_threshold r",
                "deny /proc/sys/kernel/random/urandom_min_reseed_secs r",
                "deny /proc/sys/kernel/random/reseed_uuid r",
                "deny /proc/sys/kernel/random/boot_id r",
                "deny /proc/sys/kernel/random/cpu_entropy_bits r"
            ]
        },
        resource_limits => {
            memory_limit => "128M",
            cpu_limit => "1",
            disk_limit => "1G",
            network_limit => "100M"
        },
        isolation => {
            unprivileged => 1,
            seccomp => 1,
            capabilities => ['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'],
            namespaces => ['ipc', 'net', 'pid', 'uts']
        }
    };
    
    return $profile;
}

# -------- create VM security profile --------
sub _create_vm_security_profile {
    my ($self, $profile_type) = @_;
    
    my $profile = {
        virtualization => {
            type => 'kvm',
            security_features => ['secure-boot', 'tpm', 'encryption'],
            isolation => 'full'
        },
        network => {
            isolation => 'vlan',
            firewall => 'enabled',
            intrusion_detection => 'enabled'
        },
        storage => {
            encryption => 'enabled',
            integrity_checking => 'enabled',
            access_control => 'strict'
        }
    };
    
    return $profile;
}

# -------- create native security profile --------
sub _create_native_security_profile {
    my ($self, $profile_type) = @_;
    
    my $profile = {
        service_isolation => {
            dedicated_user => 1,
            dedicated_group => 1,
            chroot => 0,
            systemd_scope => 1
        },
        file_permissions => {
            strict_umask => '0027',
            ownership => 'smbgateway:smbgateway',
            acl_enforcement => 1
        },
        network => {
            bind_interfaces => 1,
            firewall_rules => 'enabled',
            rate_limiting => 'enabled'
        }
    };
    
    return $profile;
}

# -------- setup service user --------
sub setup_service_user {
    my ($self, %param) = @_;
    
    my $username = $param{username} // "smbgateway_$self->{share_name}";
    my $uid = $param{uid} // (10000 + int(rand(10000)));
    my $gid = $param{gid} // $uid;
    my $home_dir = $param{home_dir} // "/var/lib/pve/smbgateway/$self->{share_name}";
    my $shell = $param{shell} // "/bin/false";
    
    # Create user and group
    eval {
        # Create group
        run_command(['groupadd', '-g', $gid, $username]);
        
        # Create user
        run_command(['useradd', '-u', $uid, '-g', $gid, '-d', $home_dir, '-s', $shell, '-r', $username]);
        
        # Create home directory
        make_path($home_dir) unless -d $home_dir;
        run_command(['chown', "$username:$username", $home_dir]);
        run_command(['chmod', '750', $home_dir]);
        
        # Store user info in database
        $self->{dbh}->do(
            "INSERT INTO service_users (share_id, username, uid, gid, home_dir, shell, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            undef, $self->{share_id}, $username, $uid, $gid, $home_dir, $shell, time()
        );
        
        $self->_log_security_event('service_user_created', 'info', 
            "Service user $username created for share $self->{share_name}");
        
        return {
            status => 'success',
            username => $username,
            uid => $uid,
            gid => $gid,
            home_dir => $home_dir
        };
    };
    
    if ($@) {
        $self->_log_security_event('service_user_creation_failed', 'error', 
            "Failed to create service user: $@");
        
        return {
            status => 'error',
            error => "Failed to create service user: $@"
        };
    }
}

# -------- run security scan --------
sub run_security_scan {
    my ($self, %param) = @_;
    
    my $scan_type = $param{scan_type} // 'comprehensive';
    my $scan_start = time();
    
    # Log scan start
    $self->_log_security_event('security_scan_started', 'info', 
        "Security scan started for share $self->{share_name}");
    
    my $findings = [];
    my $critical_count = 0;
    my $high_count = 0;
    my $medium_count = 0;
    my $low_count = 0;
    
    # Run different types of scans
    if ($scan_type eq 'comprehensive' || $scan_type eq 'smb') {
        my $smb_findings = $self->_scan_smb_security();
        push @$findings, @$smb_findings;
    }
    
    if ($scan_type eq 'comprehensive' || $scan_type eq 'filesystem') {
        my $fs_findings = $self->_scan_filesystem_security();
        push @$findings, @$fs_findings;
    }
    
    if ($scan_type eq 'comprehensive' || $scan_type eq 'network') {
        my $net_findings = $self->_scan_network_security();
        push @$findings, @$net_findings;
    }
    
    # Count findings by severity
    foreach my $finding (@$findings) {
        if ($finding->{severity} eq 'critical') { $critical_count++; }
        elsif ($finding->{severity} eq 'high') { $high_count++; }
        elsif ($finding->{severity} eq 'medium') { $medium_count++; }
        elsif ($finding->{severity} eq 'low') { $low_count++; }
    }
    
    my $scan_end = time();
    my $report_path = "$SECURITY_LOG_DIR/scan_$self->{share_name}_" . time() . ".json";
    
    # Store scan results
    $self->{dbh}->do(
        "INSERT INTO security_scans (share_id, scan_type, status, findings_count, critical_count, high_count, medium_count, low_count, scan_start, scan_end, report_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        undef, $self->{share_id}, $scan_type, 'completed', scalar(@$findings), $critical_count, $high_count, $medium_count, $low_count, $scan_start, $scan_end, $report_path
    );
    
    # Save detailed report
    my $report = {
        scan_info => {
            share_id => $self->{share_id},
            share_name => $self->{share_name},
            scan_type => $scan_type,
            scan_start => $scan_start,
            scan_end => $scan_end,
            duration => $scan_end - $scan_start
        },
        summary => {
            total_findings => scalar(@$findings),
            critical_count => $critical_count,
            high_count => $high_count,
            medium_count => $medium_count,
            low_count => $low_count
        },
        findings => $findings
    };
    
    file_set_contents($report_path, encode_json($report));
    
    $self->_log_security_event('security_scan_completed', 'info', 
        "Security scan completed for share $self->{share_name}: " . scalar(@$findings) . " findings");
    
    return {
        status => 'completed',
        findings_count => scalar(@$findings),
        critical_count => $critical_count,
        high_count => $high_count,
        medium_count => $medium_count,
        low_count => $low_count,
        report_path => $report_path,
        duration => $scan_end - $scan_start
    };
}

# -------- scan SMB security --------
sub _scan_smb_security {
    my ($self) = @_;
    
    my $findings = [];
    
    # Check Samba configuration
    eval {
        my $test_result = run_command(['testparm', '-s']);
        
        if ($test_result->{exitcode} != 0) {
            push @$findings, {
                severity => 'critical',
                category => 'smb_config',
                title => 'Invalid Samba Configuration',
                description => 'Samba configuration contains errors',
                recommendation => 'Fix configuration errors before proceeding'
            };
        }
    };
    
    # Check for weak protocols
    my $smb_conf = file_read_all('/etc/samba/smb.conf');
    if ($smb_conf && $smb_conf =~ /min protocol\s*=\s*NT1/i) {
        push @$findings, {
            severity => 'critical',
            category => 'smb_protocol',
            title => 'Weak SMB Protocol',
            description => 'SMB1 protocol is enabled',
            recommendation => 'Set min protocol = SMB2 or higher'
        };
    }
    
    # Check for guest access
    if ($smb_conf && $smb_conf =~ /map to guest\s*=\s*bad user/i) {
        push @$findings, {
            severity => 'high',
            category => 'smb_auth',
            title => 'Guest Access Enabled',
            description => 'Guest access is enabled in Samba',
            recommendation => 'Disable guest access for security'
        };
    }
    
    return $findings;
}

# -------- scan filesystem security --------
sub _scan_filesystem_security {
    my ($self) = @_;
    
    my $findings = [];
    
    # Check file permissions
    my $path = $self->{path};
    if (-d $path) {
        my @stat = stat($path);
        my $mode = $stat[2] & 07777;
        
        if (($mode & 0002) != 0) {
            push @$findings, {
                severity => 'high',
                category => 'filesystem',
                title => 'World Writable Directory',
                description => "Directory $path is world writable",
                recommendation => 'Set appropriate permissions (750 or 755)'
            };
        }
    }
    
    return $findings;
}

# -------- scan network security --------
sub _scan_network_security {
    my ($self) = @_;
    
    my $findings = [];
    
    # Check for open SMB ports
    eval {
        my $netstat_result = run_command(['netstat', '-tlnp']);
        
        if ($netstat_result->{stdout} =~ /:445\s+.*LISTEN/) {
            push @$findings, {
                severity => 'medium',
                category => 'network',
                title => 'SMB Port Open',
                description => 'SMB port 445 is listening',
                recommendation => 'Ensure firewall rules are properly configured'
            };
        }
    };
    
    return $findings;
}

# -------- generate security report --------
sub generate_security_report {
    my ($self, %param) = @_;
    
    my $report_type = $param{report_type} // 'comprehensive';
    my $timeframe = $param{timeframe} // 30; # days
    
    my $report = {
        share_info => {
            share_id => $self->{share_id},
            share_name => $self->{share_name},
            mode => $self->{mode},
            path => $self->{path}
        },
        report_info => {
            generated_at => time(),
            report_type => $report_type,
            timeframe => $timeframe
        },
        security_summary => {},
        recent_events => [],
        scan_results => [],
        recommendations => []
    };
    
    # Get recent security events
    my $events = $self->{dbh}->selectall_arrayref(
        "SELECT event_type, severity, message, timestamp FROM security_events WHERE share_id = ? AND timestamp > ? ORDER BY timestamp DESC LIMIT 100",
        {Slice => {}}, $self->{share_id}, time() - ($timeframe * 24 * 3600)
    );
    
    $report->{recent_events} = $events;
    
    # Get recent scan results
    my $scans = $self->{dbh}->selectall_arrayref(
        "SELECT scan_type, status, findings_count, critical_count, high_count, medium_count, low_count, scan_start FROM security_scans WHERE share_id = ? AND scan_start > ? ORDER BY scan_start DESC LIMIT 10",
        {Slice => {}}, $self->{share_id}, time() - ($timeframe * 24 * 3600)
    );
    
    $report->{scan_results} = $scans;
    
    # Generate recommendations
    $report->{recommendations} = $self->_generate_security_recommendations($events, $scans);
    
    return $report;
}

# -------- generate security recommendations --------
sub _generate_security_recommendations {
    my ($self, $events, $scans) = @_;
    
    my $recommendations = [];
    
    # Analyze events and scans to generate recommendations
    my $critical_events = grep { $_->{severity} eq 'critical' } @$events;
    my $high_events = grep { $_->{severity} eq 'high' } @$events;
    
    if ($critical_events > 0) {
        push @$recommendations, {
            priority => 'critical',
            title => 'Address Critical Security Events',
            description => "Found $critical_events critical security events in the last period",
            action => 'Review and address all critical security events immediately'
        };
    }
    
    if ($high_events > 0) {
        push @$recommendations, {
            priority => 'high',
            title => 'Review High Priority Security Events',
            description => "Found $high_events high priority security events",
            action => 'Review and address high priority security events'
        };
    }
    
    # Check for recent scans with findings
    foreach my $scan (@$scans) {
        if ($scan->{critical_count} > 0) {
            push @$recommendations, {
                priority => 'critical',
                title => 'Address Critical Security Findings',
                description => "Security scan found $scan->{critical_count} critical issues",
                action => 'Review security scan report and address critical findings'
            };
        }
    }
    
    return $recommendations;
}

# -------- log security event --------
sub _log_security_event {
    my ($self, $event_type, $severity, $message, $metadata) = @_;
    
    $self->{dbh}->do(
        "INSERT INTO security_events (share_id, event_type, severity, message, timestamp, metadata) VALUES (?, ?, ?, ?, ?, ?)",
        undef, $self->{share_id}, $event_type, $severity, $message, time(), $metadata ? encode_json($metadata) : undef
    );
}

# -------- destructor --------
sub DESTROY {
    my ($self) = @_;
    
    if ($self->{dbh}) {
        $self->{dbh}->disconnect();
    }
}

1; 