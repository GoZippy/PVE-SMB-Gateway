package PVE::SMBGateway::CLI;

# PVE SMB Gateway Enhanced CLI Module
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# This module provides enhanced CLI functionality with structured output,
# batch operations, and comprehensive command management.

use strict;
use warnings;
use base qw(Exporter);
use PVE::Tools qw(run_command file_read_all file_set_contents);
use PVE::Exception qw(raise_param_exc);
use PVE::JSONSchema qw(get_standard_option);
use Time::HiRes qw(time);
use JSON::PP;
use File::Path qw(make_path);
use Getopt::Long qw(GetOptionsFromArray);
use Pod::Usage qw(pod2usage);

our @EXPORT_OK = qw(
    run_cli_command
    format_output
    parse_config_file
    execute_batch_operations
    validate_command_args
    generate_help_text
);

# -------- configuration --------
my $CLI_CONFIG_DIR = '/etc/pve/smbgateway/cli';
my $CLI_LOG_DIR = '/var/log/pve/smbgateway/cli';
my $CLI_DB_PATH = '/var/lib/pve/smbgateway/cli.db';
my $BATCH_QUEUE_FILE = '/var/lib/pve/smbgateway/batch_queue.json';

# -------- command definitions --------
my $COMMANDS = {
    # Share management
    'list' => {
        description => 'List all SMB Gateway shares',
        usage => 'list [--json] [--filter <filter>] [--sort <field>]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' },
            'filter' => { type => 'string', description => 'Filter shares by criteria' },
            'sort' => { type => 'string', description => 'Sort by field (name, mode, status)' }
        }
    },
    'create' => {
        description => 'Create a new SMB Gateway share',
        usage => 'create <sharename> [options]',
        options => {
            'mode' => { type => 'string', default => 'lxc', description => 'Deployment mode (lxc|native|vm)' },
            'path' => { type => 'string', description => 'Share path' },
            'quota' => { type => 'string', description => 'Quota limit (e.g., 10G, 1T)' },
            'ad-domain' => { type => 'string', description => 'Active Directory domain' },
            'ad-join' => { type => 'flag', description => 'Join AD domain' },
            'ad-username' => { type => 'string', description => 'AD username' },
            'ad-password' => { type => 'string', description => 'AD password' },
            'ctdb-vip' => { type => 'string', description => 'CTDB VIP address' },
            'ha-enabled' => { type => 'flag', description => 'Enable HA' },
            'vm-memory' => { type => 'integer', default => 2048, description => 'VM memory (MB)' },
            'vm-cores' => { type => 'integer', default => 2, description => 'VM CPU cores' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'delete' => {
        description => 'Delete an SMB Gateway share',
        usage => 'delete <share_id> [--force] [--json]',
        options => {
            'force' => { type => 'flag', description => 'Force deletion without confirmation' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'status' => {
        description => 'Get share status and information',
        usage => 'status <share_id> [--json] [--include-metrics] [--include-history]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' },
            'include-metrics' => { type => 'flag', description => 'Include performance metrics' },
            'include-history' => { type => 'flag', description => 'Include historical data' }
        }
    },
    
    # HA management
    'ha-status' => {
        description => 'Get HA status for a share',
        usage => 'ha-status <share_id> [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'ha-test' => {
        description => 'Test HA functionality',
        usage => 'ha-test --vip <vip> --share <share> [--target-node <node>] [--json]',
        options => {
            'vip' => { type => 'string', required => 1, description => 'VIP address' },
            'share' => { type => 'string', required => 1, description => 'Share name' },
            'target-node' => { type => 'string', description => 'Target node for failover test' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'ha-failover' => {
        description => 'Trigger HA failover',
        usage => 'ha-failover <share_id> --target-node <node> [--json]',
        options => {
            'target-node' => { type => 'string', required => 1, description => 'Target node' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # AD management
    'ad-test' => {
        description => 'Test Active Directory connectivity',
        usage => 'ad-test --domain <domain> --username <username> --password <password> [--ou <ou>] [--json]',
        options => {
            'domain' => { type => 'string', required => 1, description => 'AD domain' },
            'username' => { type => 'string', required => 1, description => 'AD username' },
            'password' => { type => 'string', required => 1, description => 'AD password' },
            'ou' => { type => 'string', description => 'Organizational Unit' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'ad-status' => {
        description => 'Get AD status for a share',
        usage => 'ad-status <share_id> [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # Metrics and monitoring
    'metrics' => {
        description => 'Get performance metrics',
        usage => 'metrics <type> <share_id> [options] [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # Backup management
    'backup' => {
        description => 'Manage backups',
        usage => 'backup <type> <share_id> [options] [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # Security management
    'security' => {
        description => 'Security operations',
        usage => 'security <type> <share_id> [options] [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # Batch operations
    'batch' => {
        description => 'Batch operations',
        usage => 'batch <type> [options] [--json]',
        options => {
            'config' => { type => 'string', description => 'Configuration file' },
            'parallel' => { type => 'integer', default => 1, description => 'Parallel execution count' },
            'dry-run' => { type => 'flag', description => 'Show what would be done without executing' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    
    # System operations
    'logs' => {
        description => 'Show operation logs',
        usage => 'logs [--operation-id <id>] [--lines <n>] [--json]',
        options => {
            'operation-id' => { type => 'string', description => 'Show logs for specific operation' },
            'lines' => { type => 'integer', default => 10, description => 'Number of lines to show' },
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    },
    'cleanup' => {
        description => 'System cleanup operations',
        usage => 'cleanup <type> [options] [--json]',
        options => {
            'json' => { type => 'flag', description => 'Output in JSON format' }
        }
    }
};

# -------- constructor --------
sub new {
    my ($class, %param) = @_;
    
    my $self = bless {
        api_client => $param{api_client} // die "missing api_client",
        output_format => $param{output_format} // 'text',
        verbose => $param{verbose} // 0,
        dbh => undef,
    }, $class;
    
    $self->_init_cli_db();
    $self->_ensure_directories();
    
    return $self;
}

# -------- database initialization --------
sub _init_cli_db {
    my ($self) = @_;
    
    # Create database directory
    my $db_dir = dirname($CLI_DB_PATH);
    make_path($db_dir) unless -d $db_dir;
    
    # Connect to SQLite database
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$CLI_DB_PATH", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
    }) or die "Cannot connect to CLI database: " . DBI->errstr;
    
    # Create CLI tables
    my $create_tables_sql = "
        CREATE TABLE IF NOT EXISTS cli_commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            command TEXT NOT NULL,
            args TEXT NOT NULL,
            options TEXT NOT NULL,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            exit_code INTEGER,
            output TEXT,
            error TEXT
        );
        
        CREATE TABLE IF NOT EXISTS batch_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            batch_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            target TEXT NOT NULL,
            status TEXT NOT NULL,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            result TEXT,
            error TEXT
        );
        
        CREATE TABLE IF NOT EXISTS cli_configs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            config_data TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
    ";
    
    $self->{dbh}->do($create_tables_sql);
    
    # Create indexes
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_cli_commands_time ON cli_commands(start_time)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_batch_operations_batch ON batch_operations(batch_id)");
    $self->{dbh}->do("CREATE INDEX IF NOT EXISTS idx_cli_configs_name ON cli_configs(name)");
}

# -------- directory creation --------
sub _ensure_directories {
    my ($self) = @_;
    
    foreach my $dir ($CLI_CONFIG_DIR, $CLI_LOG_DIR) {
        make_path($dir) unless -d $dir;
    }
}

# -------- run CLI command --------
sub run_cli_command {
    my ($self, $command, $args, $options) = @_;
    
    # Validate command
    unless (exists $COMMANDS->{$command}) {
        return {
            success => 0,
            error => "Unknown command: $command",
            exit_code => 1
        };
    }
    
    # Validate arguments
    my $validation_result = $self->validate_command_args($command, $args, $options);
    unless ($validation_result->{valid}) {
        return {
            success => 0,
            error => "Invalid arguments: " . $validation_result->{error},
            exit_code => 1
        };
    }
    
    # Log command execution
    my $command_id = $self->_log_command($command, $args, $options);
    
    # Execute command
    my $start_time = time();
    my $result = $self->_execute_command($command, $args, $options);
    my $end_time = time();
    
    # Update command log
    $self->_update_command_log($command_id, $result, $end_time - $start_time);
    
    # Format output
    my $formatted_result = $self->format_output($result, $options->{json} ? 'json' : 'text');
    
    return $formatted_result;
}

# -------- validate command arguments --------
sub validate_command_args {
    my ($self, $command, $args, $options) = @_;
    
    my $command_def = $COMMANDS->{$command};
    my @errors;
    
    # Check required options
    foreach my $opt_name (keys %{$command_def->{options}}) {
        my $opt_def = $command_def->{options}->{$opt_name};
        
        if ($opt_def->{required} && !exists $options->{$opt_name}) {
            push @errors, "Missing required option: --$opt_name";
        }
        
        # Validate option types
        if (exists $options->{$opt_name}) {
            my $value = $options->{$opt_name};
            
            if ($opt_def->{type} eq 'integer' && $value !~ /^\d+$/) {
                push @errors, "Option --$opt_name must be an integer";
            } elsif ($opt_def->{type} eq 'string' && ref($value) ne '') {
                push @errors, "Option --$opt_name must be a string";
            }
        }
    }
    
    # Check argument count
    my $min_args = $command_def->{min_args} // 0;
    my $max_args = $command_def->{max_args} // 999;
    
    if (@$args < $min_args) {
        push @errors, "Command requires at least $min_args arguments";
    }
    
    if (@$args > $max_args) {
        push @errors, "Command accepts at most $max_args arguments";
    }
    
    return {
        valid => @errors == 0,
        error => join('; ', @errors)
    };
}

# -------- execute command --------
sub _execute_command {
    my ($self, $command, $args, $options) = @_;
    
    # Route to appropriate handler
    my $handler_method = "_handle_$command";
    
    if ($self->can($handler_method)) {
        return $self->$handler_method($args, $options);
    } else {
        return {
            success => 0,
            error => "Command handler not implemented: $command",
            exit_code => 1
        };
    }
}

# -------- command handlers --------
sub _handle_list {
    my ($self, $args, $options) = @_;
    
    my $shares = $self->{api_client}->list_shares();
    
    # Apply filters
    if ($options->{filter}) {
        $shares = $self->_filter_shares($shares, $options->{filter});
    }
    
    # Apply sorting
    if ($options->{sort}) {
        $shares = $self->_sort_shares($shares, $options->{sort});
    }
    
    return {
        success => 1,
        data => $shares,
        exit_code => 0
    };
}

sub _handle_create {
    my ($self, $args, $options) = @_;
    
    my $sharename = $args->[0];
    die "Missing sharename" unless $sharename;
    
    my $response = $self->{api_client}->create_share(
        $sharename,
        $options->{mode} // 'lxc',
        $options->{path},
        $options->{quota},
        $options->{'ad-domain'},
        $options->{'ctdb-vip'},
        $options->{'ad-join'},
        $options->{'ad-username'},
        $options->{'ad-password'},
        $options->{'ad-ou'}
    );
    
    return {
        success => $response->{success},
        data => $response,
        exit_code => $response->{success} ? 0 : 1
    };
}

sub _handle_delete {
    my ($self, $args, $options) = @_;
    
    my $share_id = $args->[0];
    die "Missing share_id" unless $share_id;
    
    # Check for force flag
    unless ($options->{force}) {
        # Interactive confirmation would go here
        # For now, just proceed
    }
    
    my $response = $self->{api_client}->delete_share($share_id);
    
    return {
        success => $response->{success},
        data => $response,
        exit_code => $response->{success} ? 0 : 1
    };
}

sub _handle_status {
    my ($self, $args, $options) = @_;
    
    my $share_id = $args->[0];
    die "Missing share_id" unless $share_id;
    
    my $status = $self->{api_client}->get_share_status($share_id);
    
    # Add additional data if requested
    if ($options->{'include-metrics'}) {
        $status->{metrics} = $self->{api_client}->get_metrics($share_id);
    }
    
    if ($options->{'include-history'}) {
        $status->{history} = $self->{api_client}->get_metrics_history($share_id);
    }
    
    return {
        success => 1,
        data => $status,
        exit_code => 0
    };
}

sub _handle_batch {
    my ($self, $args, $options) = @_;
    
    my $batch_type = $args->[0];
    die "Missing batch type" unless $batch_type;
    
    if ($batch_type eq 'create') {
        return $self->_execute_batch_create($options);
    } elsif ($batch_type eq 'delete') {
        return $self->_execute_batch_delete($options);
    } elsif ($batch_type eq 'status') {
        return $self->_execute_batch_status($options);
    } else {
        return {
            success => 0,
            error => "Unknown batch type: $batch_type",
            exit_code => 1
        };
    }
}

# -------- batch operations --------
sub _execute_batch_create {
    my ($self, $options) = @_;
    
    # Parse configuration file
    my $config = $self->parse_config_file($options->{config});
    unless ($config) {
        return {
            success => 0,
            error => "Failed to parse configuration file",
            exit_code => 1
        };
    }
    
    # Execute batch operations
    my $results = $self->execute_batch_operations(
        'create',
        $config->{shares},
        {
            parallel => $options->{parallel} // 1,
            dry_run => $options->{'dry-run'} // 0
        }
    );
    
    return {
        success => 1,
        data => $results,
        exit_code => 0
    };
}

sub _execute_batch_delete {
    my ($self, $options) = @_;
    
    # Parse configuration file
    my $config = $self->parse_config_file($options->{config});
    unless ($config) {
        return {
            success => 0,
            error => "Failed to parse configuration file",
            exit_code => 1
        };
    }
    
    # Execute batch operations
    my $results = $self->execute_batch_operations(
        'delete',
        $config->{shares},
        {
            parallel => $options->{parallel} // 1,
            dry_run => $options->{'dry-run'} // 0
        }
    );
    
    return {
        success => 1,
        data => $results,
        exit_code => 0
    };
}

sub _execute_batch_status {
    my ($self, $options) = @_;
    
    # Parse configuration file
    my $config = $self->parse_config_file($options->{config});
    unless ($config) {
        return {
            success => 0,
            error => "Failed to parse configuration file",
            exit_code => 1
        };
    }
    
    # Execute batch operations
    my $results = $self->execute_batch_operations(
        'status',
        $config->{shares},
        {
            parallel => $options->{parallel} // 1,
            dry_run => $options->{'dry-run'} // 0
        }
    );
    
    return {
        success => 1,
        data => $results,
        exit_code => 0
    };
}

# -------- parse configuration file --------
sub parse_config_file {
    my ($self, $config_file) = @_;
    
    unless ($config_file && -f $config_file) {
        return undef;
    }
    
    my $config_content = file_read_all($config_file);
    unless ($config_content) {
        return undef;
    }
    
    eval {
        my $config = decode_json($config_content);
        return $config;
    };
    
    return undef;
}

# -------- execute batch operations --------
sub execute_batch_operations {
    my ($self, $operation_type, $targets, $options) = @_;
    
    my $batch_id = "batch_" . time() . "_" . int(rand(10000));
    my $results = [];
    my $parallel_count = $options->{parallel} // 1;
    my $dry_run = $options->{dry_run} // 0;
    
    # Log batch start
    $self->_log_batch_operation($batch_id, $operation_type, 'started', {
        total_targets => scalar(@$targets),
        parallel_count => $parallel_count,
        dry_run => $dry_run
    });
    
    if ($dry_run) {
        # Show what would be done
        foreach my $target (@$targets) {
            push @$results, {
                target => $target,
                status => 'would_execute',
                operation => $operation_type,
                dry_run => 1
            };
        }
    } else {
        # Execute operations
        if ($parallel_count == 1) {
            # Sequential execution
            foreach my $target (@$targets) {
                my $result = $self->_execute_single_operation($operation_type, $target);
                push @$results, $result;
                
                # Log individual operation
                $self->_log_batch_operation($batch_id, $operation_type, $result->{status}, $result);
            }
        } else {
            # Parallel execution (simplified - in real implementation would use threads)
            foreach my $target (@$targets) {
                my $result = $self->_execute_single_operation($operation_type, $target);
                push @$results, $result;
                
                # Log individual operation
                $self->_log_batch_operation($batch_id, $operation_type, $result->{status}, $result);
            }
        }
    }
    
    # Log batch completion
    $self->_log_batch_operation($batch_id, $operation_type, 'completed', {
        total_results => scalar(@$results),
        successful => scalar(grep { $_->{status} eq 'success' } @$results),
        failed => scalar(grep { $_->{status} eq 'error' } @$results)
    });
    
    return {
        batch_id => $batch_id,
        operation_type => $operation_type,
        total_operations => scalar(@$targets),
        results => $results,
        summary => {
            total => scalar(@$results),
            successful => scalar(grep { $_->{status} eq 'success' } @$results),
            failed => scalar(grep { $_->{status} eq 'error' } @$results)
        }
    };
}

# -------- execute single operation --------
sub _execute_single_operation {
    my ($self, $operation_type, $target) = @_;
    
    my $start_time = time();
    
    eval {
        if ($operation_type eq 'create') {
            my $result = $self->{api_client}->create_share(
                $target->{name},
                $target->{mode} // 'lxc',
                $target->{path},
                $target->{quota},
                $target->{ad_domain},
                $target->{ctdb_vip}
            );
            
            return {
                target => $target->{name},
                status => $result->{success} ? 'success' : 'error',
                operation => $operation_type,
                result => $result,
                duration => time() - $start_time
            };
            
        } elsif ($operation_type eq 'delete') {
            my $result = $self->{api_client}->delete_share($target);
            
            return {
                target => $target,
                status => $result->{success} ? 'success' : 'error',
                operation => $operation_type,
                result => $result,
                duration => time() - $start_time
            };
            
        } elsif ($operation_type eq 'status') {
            my $result = $self->{api_client}->get_share_status($target);
            
            return {
                target => $target,
                status => 'success',
                operation => $operation_type,
                result => $result,
                duration => time() - $start_time
            };
        }
    };
    
    return {
        target => ref($target) eq 'HASH' ? $target->{name} : $target,
        status => 'error',
        operation => $operation_type,
        error => $@,
        duration => time() - $start_time
    };
}

# -------- format output --------
sub format_output {
    my ($self, $result, $format) = @_;
    
    if ($format eq 'json') {
        return encode_json($result);
    } else {
        return $self->_format_text_output($result);
    }
}

# -------- format text output --------
sub _format_text_output {
    my ($self, $result) = @_;
    
    my $output = '';
    
    if ($result->{success}) {
        if (ref($result->{data}) eq 'ARRAY') {
            # List output
            if (@{$result->{data}} == 0) {
                $output .= "No items found.\n";
            } else {
                # Determine fields to display
                my $fields = $self->_get_display_fields($result->{data}->[0]);
                
                # Print header
                $output .= sprintf("%-20s %-10s %-30s %-10s\n", @$fields);
                $output .= "-" x 70 . "\n";
                
                # Print data
                foreach my $item (@{$result->{data}}) {
                    $output .= sprintf("%-20s %-10s %-30s %-10s\n",
                        $item->{id} // '',
                        $item->{mode} // '',
                        $item->{path} // '',
                        $item->{status} // ''
                    );
                }
            }
        } elsif (ref($result->{data}) eq 'HASH') {
            # Single item output
            $output .= $self->_format_hash_output($result->{data});
        } else {
            # Simple output
            $output .= $result->{data} . "\n";
        }
    } else {
        $output .= "Error: " . $result->{error} . "\n";
    }
    
    return $output;
}

# -------- format hash output --------
sub _format_hash_output {
    my ($self, $hash) = @_;
    
    my $output = '';
    
    foreach my $key (sort keys %$hash) {
        my $value = $hash->{$key};
        
        if (ref($value) eq 'HASH') {
            $output .= "$key:\n";
            $output .= $self->_format_hash_output($value, '  ');
        } elsif (ref($value) eq 'ARRAY') {
            $output .= "$key:\n";
            foreach my $item (@$value) {
                $output .= "  - $item\n";
            }
        } else {
            $output .= "$key: $value\n";
        }
    }
    
    return $output;
}

# -------- get display fields --------
sub _get_display_fields {
    my ($self, $item) = @_;
    
    if (ref($item) eq 'HASH') {
        if (exists $item->{id}) {
            return ['ID', 'Mode', 'Path', 'Status'];
        } elsif (exists $item->{name}) {
            return ['Name', 'Type', 'Value', 'Status'];
        }
    }
    
    return ['Field1', 'Field2', 'Field3', 'Field4'];
}

# -------- filter shares --------
sub _filter_shares {
    my ($self, $shares, $filter) = @_;
    
    my @filtered;
    
    foreach my $share (@$shares) {
        if ($share->{id} =~ /$filter/i || 
            $share->{mode} =~ /$filter/i || 
            $share->{status} =~ /$filter/i) {
            push @filtered, $share;
        }
    }
    
    return \@filtered;
}

# -------- sort shares --------
sub _sort_shares {
    my ($self, $shares, $sort_field) = @_;
    
    my @sorted = sort {
        my $a_val = $a->{$sort_field} // '';
        my $b_val = $b->{$sort_field} // '';
        $a_val cmp $b_val;
    } @$shares;
    
    return \@sorted;
}

# -------- generate help text --------
sub generate_help_text {
    my ($self, $command) = @_;
    
    if ($command && exists $COMMANDS->{$command}) {
        my $cmd_def = $COMMANDS->{$command};
        my $help = "$command: $cmd_def->{description}\n\n";
        $help .= "Usage: $cmd_def->{usage}\n\n";
        
        if (keys %{$cmd_def->{options}}) {
            $help .= "Options:\n";
            foreach my $opt_name (sort keys %{$cmd_def->{options}}) {
                my $opt_def = $cmd_def->{options}->{$opt_name};
                $help .= "  --$opt_name";
                $help .= " <$opt_def->{type}>" if $opt_def->{type} ne 'flag';
                $help .= " (required)" if $opt_def->{required};
                $help .= " (default: $opt_def->{default})" if exists $opt_def->{default};
                $help .= "\n";
                $help .= "      $opt_def->{description}\n" if $opt_def->{description};
            }
        }
        
        return $help;
    } else {
        my $help = "Available commands:\n\n";
        
        foreach my $cmd_name (sort keys %$COMMANDS) {
            my $cmd_def = $COMMANDS->{$cmd_name};
            $help .= sprintf("%-15s %s\n", $cmd_name, $cmd_def->{description});
        }
        
        $help .= "\nUse 'help <command>' for detailed information about a command.\n";
        return $help;
    }
}

# -------- log command --------
sub _log_command {
    my ($self, $command, $args, $options) = @_;
    
    $self->{dbh}->do(
        "INSERT INTO cli_commands (command, args, options, start_time) VALUES (?, ?, ?, ?)",
        undef, $command, encode_json($args), encode_json($options), time()
    );
    
    return $self->{dbh}->last_insert_id("", "", "", "");
}

# -------- update command log --------
sub _update_command_log {
    my ($self, $command_id, $result, $duration) = @_;
    
    $self->{dbh}->do(
        "UPDATE cli_commands SET end_time = ?, exit_code = ?, output = ?, error = ? WHERE id = ?",
        undef, time(), $result->{exit_code} // 0, 
        $result->{success} ? encode_json($result->{data}) : undef,
        $result->{success} ? undef : $result->{error},
        $command_id
    );
}

# -------- log batch operation --------
sub _log_batch_operation {
    my ($self, $batch_id, $operation_type, $status, $data) = @_;
    
    $self->{dbh}->do(
        "INSERT INTO batch_operations (batch_id, operation_type, target, status, start_time, result) VALUES (?, ?, ?, ?, ?, ?)",
        undef, $batch_id, $operation_type, 'batch', $status, time(), encode_json($data)
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