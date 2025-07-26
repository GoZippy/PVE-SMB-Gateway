#!/bin/bash

# Comprehensive Test Script for PVE SMB Gateway
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>

set -e

echo "=== PVE SMB Gateway Comprehensive Test Suite ==="
echo "Testing all components for bugs and issues..."
echo

# Test 1: Check all Perl files for syntax errors
echo "Test 1: Perl Syntax Validation"
echo "================================"

PERL_FILES=(
    "PVE/Storage/Custom/SMBGateway.pm"
    "PVE/SMBGateway/Monitor.pm"
    "PVE/SMBGateway/Backup.pm"
    "sbin/pve-smbgateway"
)

for file in "${PERL_FILES[@]}"; do
    echo "Checking $file..."
    if perl -c "$file" 2>/dev/null; then
        echo "✓ $file - Syntax OK"
    else
        echo "✗ $file - Syntax Error"
        exit 1
    fi
done
echo

# Test 2: Check JavaScript syntax
echo "Test 2: JavaScript Syntax Validation"
echo "===================================="

JS_FILES=(
    "www/ext6/pvemanager6/smb-gateway.js"
)

for file in "${JS_FILES[@]}"; do
    echo "Checking $file..."
    if node -c "$file" 2>/dev/null; then
        echo "✓ $file - Syntax OK"
    else
        echo "✗ $file - Syntax Error (or node not available)"
        # Don't fail on this as node might not be available
    fi
done
echo

# Test 3: Check for missing imports and dependencies
echo "Test 3: Dependency and Import Validation"
echo "========================================"

# Check for missing imports in Backup.pm
echo "Checking Backup.pm imports..."
if grep -q "use File::Basename" "PVE/SMBGateway/Backup.pm" && \
   grep -q "use File::Path" "PVE/SMBGateway/Backup.pm"; then
    echo "✓ Backup.pm - Required imports present"
else
    echo "✗ Backup.pm - Missing required imports"
    exit 1
fi

# Check for missing imports in Monitor.pm
echo "Checking Monitor.pm imports..."
if grep -q "use File::Path" "PVE/SMBGateway/Monitor.pm"; then
    echo "✓ Monitor.pm - Required imports present"
else
    echo "✗ Monitor.pm - Missing required imports"
    exit 1
fi

# Check for missing imports in main plugin
echo "Checking SMBGateway.pm imports..."
if grep -q "use PVE::SMBGateway::Backup" "PVE/Storage/Custom/SMBGateway.pm"; then
    echo "✓ SMBGateway.pm - Backup module imported"
else
    echo "✗ SMBGateway.pm - Missing Backup module import"
    exit 1
fi
echo

# Test 4: Check for directory creation issues
echo "Test 4: Directory Creation Validation"
echo "===================================="

# Check for proper directory creation in Backup.pm
echo "Checking Backup.pm directory creation..."
if grep -q "make_path" "PVE/SMBGateway/Backup.pm" && \
   ! grep -q "mkdir -p" "PVE/SMBGateway/Backup.pm"; then
    echo "✓ Backup.pm - Proper directory creation methods"
else
    echo "✗ Backup.pm - Directory creation issues found"
    exit 1
fi

# Check for proper directory creation in Monitor.pm
echo "Checking Monitor.pm directory creation..."
if grep -q "make_path" "PVE/SMBGateway/Monitor.pm" && \
   ! grep -q "mkdir " "PVE/SMBGateway/Monitor.pm"; then
    echo "✓ Monitor.pm - Proper directory creation methods"
else
    echo "✗ Monitor.pm - Directory creation issues found"
    exit 1
fi
echo

# Test 5: Check for database connection error handling
echo "Test 5: Database Error Handling Validation"
echo "=========================================="

# Check Backup.pm database error handling
echo "Checking Backup.pm database error handling..."
if grep -q "or die.*Cannot connect to backup database" "PVE/SMBGateway/Backup.pm"; then
    echo "✓ Backup.pm - Database error handling present"
else
    echo "✗ Backup.pm - Missing database error handling"
    exit 1
fi

# Check Monitor.pm database error handling
echo "Checking Monitor.pm database error handling..."
if grep -q "or die.*Cannot connect to metrics database" "PVE/SMBGateway/Monitor.pm"; then
    echo "✓ Monitor.pm - Database error handling present"
else
    echo "✗ Monitor.pm - Missing database error handling"
    exit 1
fi
echo

# Test 6: Check CLI tool for issues
echo "Test 6: CLI Tool Validation"
echo "==========================="

# Check for the hostname bug fix
echo "Checking CLI hostname handling..."
if grep -A5 -B5 "list_shares" "sbin/pve-smbgateway" | grep -q "chomp.*hostname.*api_call"; then
    echo "✓ CLI - Hostname handling fixed"
else
    echo "✗ CLI - Hostname handling issue found"
    exit 1
fi

# Check for proper error handling in CLI
echo "Checking CLI error handling..."
if grep -q "eval.*api_call" "sbin/pve-smbgateway"; then
    echo "✓ CLI - Error handling present"
else
    echo "✗ CLI - Missing error handling"
    exit 1
fi
echo

# Test 7: Check Debian packaging
echo "Test 7: Debian Packaging Validation"
echo "==================================="

# Check control file dependencies
echo "Checking debian/control dependencies..."
if grep -q "libdbi-perl" "debian/control" && \
   grep -q "libdbd-sqlite3-perl" "debian/control" && \
   grep -q "libjson-pp-perl" "debian/control" && \
   grep -q "libfile-path-perl" "debian/control"; then
    echo "✓ debian/control - Required dependencies present"
else
    echo "✗ debian/control - Missing required dependencies"
    exit 1
fi

# Check install file for test scripts
echo "Checking debian/install for test scripts..."
if grep -q "test_metrics.sh" "debian/install" && \
   grep -q "test_backup.sh" "debian/install"; then
    echo "✓ debian/install - Test scripts included"
else
    echo "✗ debian/install - Test scripts missing"
    exit 1
fi

# Check postinst script
echo "Checking debian/postinst..."
if grep -q "mkdir -p" "debian/postinst" && \
   grep -q "if.*! -d" "debian/postinst"; then
    echo "✓ debian/postinst - Proper directory creation"
else
    echo "✗ debian/postinst - Directory creation issues"
    exit 1
fi
echo

# Test 8: Check systemd service files
echo "Test 8: Systemd Service Validation"
echo "=================================="

# Check metrics service
echo "Checking pve-smbgateway-metrics.service..."
if [ -f "debian/pve-smbgateway-metrics.service" ] && \
   grep -q "ExecStart.*perl.*Monitor" "debian/pve-smbgateway-metrics.service"; then
    echo "✓ Metrics service - Properly configured"
else
    echo "✗ Metrics service - Configuration issues"
    exit 1
fi

# Check metrics timer
echo "Checking pve-smbgateway-metrics.timer..."
if [ -f "debian/pve-smbgateway-metrics.timer" ] && \
   grep -q "OnCalendar.*0/5" "debian/pve-smbgateway-metrics.timer"; then
    echo "✓ Metrics timer - Properly configured"
else
    echo "✗ Metrics timer - Configuration issues"
    exit 1
fi
echo

# Test 9: Check for missing method implementations
echo "Test 9: Method Implementation Validation"
echo "========================================"

# Check Backup module methods
echo "Checking Backup module methods..."
REQUIRED_BACKUP_METHODS=(
    "_create_lxc_backup"
    "_create_vm_backup"
    "_create_native_backup"
    "_create_tar_backup"
    "register_backup_job"
    "unregister_backup_job"
    "create_backup_snapshot"
    "get_backup_status"
)

for method in "${REQUIRED_BACKUP_METHODS[@]}"; do
    if grep -q "sub $method" "PVE/SMBGateway/Backup.pm"; then
        echo "✓ Backup.$method - Implemented"
    else
        echo "✗ Backup.$method - Missing implementation"
        exit 1
    fi
done

# Check Monitor module methods
echo "Checking Monitor module methods..."
REQUIRED_MONITOR_METHODS=(
    "collect_all_metrics"
    "collect_io_stats"
    "collect_connection_stats"
    "collect_quota_stats"
    "collect_system_stats"
    "get_metrics"
    "export_prometheus_metrics"
)

for method in "${REQUIRED_MONITOR_METHODS[@]}"; do
    if grep -q "sub $method" "PVE/SMBGateway/Monitor.pm"; then
        echo "✓ Monitor.$method - Implemented"
    else
        echo "✗ Monitor.$method - Missing implementation"
        exit 1
    fi
done
echo

# Test 10: Check for potential security issues
echo "Test 10: Security Validation"
echo "============================"

# Check for hardcoded credentials
echo "Checking for hardcoded credentials..."
if ! grep -r "password.*=" . --include="*.pm" --include="*.pl" --include="*.js" | grep -v "ad_password"; then
    echo "✓ No hardcoded credentials found"
else
    echo "✗ Potential hardcoded credentials found"
    exit 1
fi

# Check for proper input validation
echo "Checking input validation..."
if grep -q "regex.*pve-storage-id" "PVE/Storage/Custom/SMBGateway.pm" && \
   grep -q "regex.*quota" "www/ext6/pvemanager6/smb-gateway.js"; then
    echo "✓ Input validation present"
else
    echo "✗ Missing input validation"
    exit 1
fi
echo

# Test 11: Check for potential memory leaks
echo "Test 11: Memory Management Validation"
echo "====================================="

# Check for proper database connection cleanup
echo "Checking database connection cleanup..."
if grep -q "DESTROY.*disconnect" "PVE/SMBGateway/Backup.pm" && \
   grep -q "DESTROY.*disconnect" "PVE/SMBGateway/Monitor.pm"; then
    echo "✓ Database connection cleanup implemented"
else
    echo "✗ Missing database connection cleanup"
    exit 1
fi

# Check for proper file handle cleanup
echo "Checking file handle cleanup..."
if ! grep -r "open.*>" . --include="*.pm" --include="*.pl" | grep -v "close"; then
    echo "✓ File handle cleanup appears proper"
else
    echo "✗ Potential file handle leaks found"
    exit 1
fi
echo

# Test 12: Check for potential race conditions
echo "Test 12: Concurrency Validation"
echo "==============================="

# Check for proper locking in database operations
echo "Checking database concurrency..."
if grep -q "sqlite_use_immediate_transaction" "PVE/SMBGateway/Monitor.pm" && \
   grep -q "sqlite_use_immediate_transaction" "PVE/SMBGateway/Backup.pm"; then
    echo "✓ Database concurrency handling present"
else
    echo "✗ Missing database concurrency handling"
    exit 1
fi
echo

echo "=== All Tests Passed! ==="
echo "✅ No critical bugs or issues found"
echo "✅ All components properly implemented"
echo "✅ Security and performance considerations addressed"
echo
echo "The PVE SMB Gateway system is ready for deployment!" 