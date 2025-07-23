#!/bin/bash

# PVE SMB Gateway Manual Cleanup Tool
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_DIR="/var/log/pve"
OPERATION_LOG="$LOG_DIR/smbgateway-operations.log"
ERROR_LOG="$LOG_DIR/smbgateway-errors.log"
AUDIT_LOG="$LOG_DIR/smbgateway-audit.log"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status $RED "This script must be run as root"
        exit 1
    fi
}

# Function to display usage
show_usage() {
    cat << EOF
PVE SMB Gateway Manual Cleanup Tool

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    status              Show current system status and cleanup recommendations
    cleanup-containers  Remove all SMB Gateway containers
    cleanup-vms         Remove all SMB Gateway VMs
    cleanup-shares      Remove Samba shares from configuration
    cleanup-ctdb        Remove CTDB configuration
    cleanup-ad          Leave AD domain (interactive)
    cleanup-all         Perform all cleanup operations (interactive)
    report              Generate cleanup report
    logs                Show recent operation logs
    help                Show this help message

Options:
    --force             Skip confirmation prompts
    --dry-run           Show what would be done without executing
    --operation-id ID   Target specific operation ID for cleanup

Examples:
    $0 status                    # Show system status
    $0 cleanup-containers       # Remove SMB Gateway containers
    $0 cleanup-all --dry-run    # Show what cleanup-all would do
    $0 report --operation-id abc123  # Generate report for specific operation

EOF
}

# Function to get system status
get_system_status() {
    print_status $BLUE "Analyzing system status..."
    
    local status=()
    
    # Check for SMB Gateway containers
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$containers" ]]; then
        status+=("containers: $(echo "$containers" | wc -l)")
    else
        status+=("containers: 0")
    fi
    
    # Check for SMB Gateway VMs
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$vms" ]]; then
        status+=("vms: $(echo "$vms" | wc -l)")
    else
        status+=("vms: 0")
    fi
    
    # Check for Samba shares
    if [[ -f /etc/samba/smb.conf ]]; then
        local shares=$(grep -c '^\[' /etc/samba/smb.conf || echo "0")
        status+=("samba_shares: $shares")
    else
        status+=("samba_shares: 0")
    fi
    
    # Check for CTDB configuration
    if [[ -d /etc/ctdb ]]; then
        status+=("ctdb: configured")
    else
        status+=("ctdb: none")
    fi
    
    # Check for AD domain
    local realm_status=$(realm list 2>/dev/null || echo "none")
    if [[ "$realm_status" != "none" ]]; then
        status+=("ad_domain: joined")
    else
        status+=("ad_domain: none")
    fi
    
    echo "System Status: ${status[*]}"
}

# Function to generate cleanup recommendations
generate_recommendations() {
    print_status $BLUE "Generating cleanup recommendations..."
    
    local recommendations=()
    
    # Check for orphaned containers
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$containers" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            recommendations+=("container: $name (ID: $vmid, Status: $status)")
        done <<< "$containers"
    fi
    
    # Check for orphaned VMs
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    if [[ -n "$vms" ]]; then
        while IFS= read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            recommendations+=("vm: $name (ID: $vmid, Status: $status)")
        done <<< "$vms"
    fi
    
    # Check for Samba shares
    if [[ -f /etc/samba/smb.conf ]]; then
        local shares=$(grep '^\[' /etc/samba/smb.conf | grep -v '^\[global\]' | grep -v '^\[homes\]' | grep -v '^\[printers\]' || true)
        if [[ -n "$shares" ]]; then
            while IFS= read -r share; do
                recommendations+=("samba_share: $share")
            done <<< "$shares"
        fi
    fi
    
    # Check for CTDB configuration
    if [[ -d /etc/ctdb ]]; then
        recommendations+=("ctdb: /etc/ctdb directory exists")
    fi
    
    # Check for AD domain
    local realm_status=$(realm list 2>/dev/null || echo "none")
    if [[ "$realm_status" != "none" ]]; then
        recommendations+=("ad_domain: $realm_status")
    fi
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        print_status $GREEN "No cleanup actions recommended"
    else
        print_status $YELLOW "Cleanup recommendations:"
        for rec in "${recommendations[@]}"; do
            echo "  - $rec"
        done
    fi
}

# Function to cleanup containers
cleanup_containers() {
    print_status $BLUE "Cleaning up SMB Gateway containers..."
    
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    if [[ -z "$containers" ]]; then
        print_status $GREEN "No SMB Gateway containers found"
        return 0
    fi
    
    local count=0
    while IFS= read -r line; do
        local vmid=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | awk '{print $3}')
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status $YELLOW "Would stop and destroy container: $name (ID: $vmid)"
        else
            print_status $BLUE "Stopping container: $name (ID: $vmid)"
            pct stop "$vmid" 2>/dev/null || true
            
            print_status $BLUE "Destroying container: $name (ID: $vmid)"
            pct destroy "$vmid" 2>/dev/null || true
            
            print_status $GREEN "Container destroyed: $name (ID: $vmid)"
            ((count++))
        fi
    done <<< "$containers"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_status $GREEN "Cleaned up $count containers"
    fi
}

# Function to cleanup VMs
cleanup_vms() {
    print_status $BLUE "Cleaning up SMB Gateway VMs..."
    
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    if [[ -z "$vms" ]]; then
        print_status $GREEN "No SMB Gateway VMs found"
        return 0
    fi
    
    local count=0
    while IFS= read -r line; do
        local vmid=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | awk '{print $3}')
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status $YELLOW "Would stop and destroy VM: $name (ID: $vmid)"
        else
            print_status $BLUE "Stopping VM: $name (ID: $vmid)"
            qm stop "$vmid" 2>/dev/null || true
            
            print_status $BLUE "Destroying VM: $name (ID: $vmid)"
            qm destroy "$vmid" 2>/dev/null || true
            
            print_status $GREEN "VM destroyed: $name (ID: $vmid)"
            ((count++))
        fi
    done <<< "$vms"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_status $GREEN "Cleaned up $count VMs"
    fi
}

# Function to cleanup Samba shares
cleanup_shares() {
    print_status $BLUE "Cleaning up Samba shares..."
    
    if [[ ! -f /etc/samba/smb.conf ]]; then
        print_status $GREEN "No Samba configuration found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status $YELLOW "Would backup and clean /etc/samba/smb.conf"
    else
        # Backup current configuration
        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # Remove SMB Gateway shares (keep global, homes, printers)
        sed -i '/^\[smb-/d' /etc/samba/smb.conf
        sed -i '/^\[.*\]$/,/^\[/ { /^\[.*\]$/!d; }' /etc/samba/smb.conf
        
        print_status $GREEN "Samba shares cleaned up"
    fi
}

# Function to cleanup CTDB
cleanup_ctdb() {
    print_status $BLUE "Cleaning up CTDB configuration..."
    
    if [[ ! -d /etc/ctdb ]]; then
        print_status $GREEN "No CTDB configuration found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status $YELLOW "Would remove /etc/ctdb directory"
    else
        # Stop CTDB service if running
        systemctl stop ctdb 2>/dev/null || true
        systemctl disable ctdb 2>/dev/null || true
        
        # Remove CTDB configuration
        rm -rf /etc/ctdb
        
        print_status $GREEN "CTDB configuration cleaned up"
    fi
}

# Function to cleanup AD domain
cleanup_ad() {
    print_status $BLUE "Cleaning up AD domain..."
    
    local realm_status=$(realm list 2>/dev/null || echo "none")
    if [[ "$realm_status" == "none" ]]; then
        print_status $GREEN "No AD domain joined"
        return 0
    fi
    
    print_status $YELLOW "Current AD status:"
    echo "$realm_status"
    
    if [[ "$FORCE" != "true" ]]; then
        read -p "Do you want to leave the AD domain? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status $YELLOW "AD domain cleanup skipped"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status $YELLOW "Would leave AD domain"
    else
        # Extract domain name from realm list
        local domain=$(echo "$realm_status" | grep "domain-name:" | awk '{print $2}')
        if [[ -n "$domain" ]]; then
            realm leave "$domain"
            print_status $GREEN "Left AD domain: $domain"
        else
            print_status $RED "Could not determine domain name"
        fi
    fi
}

# Function to cleanup all
cleanup_all() {
    print_status $BLUE "Performing complete cleanup..."
    
    if [[ "$FORCE" != "true" ]]; then
        print_status $YELLOW "This will remove all SMB Gateway resources. Are you sure? (y/N): "
        read -p "" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status $YELLOW "Cleanup cancelled"
            return 0
        fi
    fi
    
    cleanup_containers
    cleanup_vms
    cleanup_shares
    cleanup_ctdb
    cleanup_ad
    
    print_status $GREEN "Complete cleanup finished"
}

# Function to generate report
generate_report() {
    print_status $BLUE "Generating cleanup report..."
    
    local report_file="/tmp/smbgateway-cleanup-report-$(date +%Y%m%d_%H%M%S).json"
    
    # Create report structure
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "system_status": {
EOF
    
    # Add system status
    echo "        \"containers\": \"$(pct list 2>/dev/null | grep -c smbgateway || echo "0")\"," >> "$report_file"
    echo "        \"vms\": \"$(qm list 2>/dev/null | grep -c smbgateway || echo "0")\"," >> "$report_file"
    echo "        \"samba_shares\": \"$(grep -c '^\[' /etc/samba/smb.conf 2>/dev/null || echo "0")\"," >> "$report_file"
    echo "        \"ctdb_configured\": \"$([ -d /etc/ctdb ] && echo "true" || echo "false")\"," >> "$report_file"
    echo "        \"ad_joined\": \"$([ -n "$(realm list 2>/dev/null)" ] && echo "true" || echo "false")\"" >> "$report_file"
    
    cat >> "$report_file" << EOF
    },
    "recommendations": [
EOF
    
    # Add recommendations
    local first=true
    local containers=$(pct list 2>/dev/null | grep smbgateway || true)
    while IFS= read -r line; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        local vmid=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | awk '{print $3}')
        echo "        {\"type\": \"container\", \"id\": \"$vmid\", \"name\": \"$name\"}" >> "$report_file"
    done <<< "$containers"
    
    local vms=$(qm list 2>/dev/null | grep smbgateway || true)
    while IFS= read -r line; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        local vmid=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | awk '{print $3}')
        echo "        {\"type\": \"vm\", \"id\": \"$vmid\", \"name\": \"$name\"}" >> "$report_file"
    done <<< "$vms"
    
    cat >> "$report_file" << EOF
    ]
}
EOF
    
    print_status $GREEN "Report generated: $report_file"
    
    if command -v jq >/dev/null 2>&1; then
        echo "Report contents:"
        jq '.' "$report_file"
    else
        echo "Report contents:"
        cat "$report_file"
    fi
}

# Function to show logs
show_logs() {
    print_status $BLUE "Recent operation logs..."
    
    if [[ -f "$OPERATION_LOG" ]]; then
        echo "=== Operations Log (last 20 lines) ==="
        tail -20 "$OPERATION_LOG" 2>/dev/null || echo "No operations log found"
        echo
    fi
    
    if [[ -f "$ERROR_LOG" ]]; then
        echo "=== Error Log (last 20 lines) ==="
        tail -20 "$ERROR_LOG" 2>/dev/null || echo "No error log found"
        echo
    fi
    
    if [[ -f "$AUDIT_LOG" ]]; then
        echo "=== Audit Log (last 20 lines) ==="
        tail -20 "$AUDIT_LOG" 2>/dev/null || echo "No audit log found"
        echo
    fi
}

# Main script logic
main() {
    check_root
    
    # Parse command line arguments
    FORCE=false
    DRY_RUN=false
    OPERATION_ID=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --operation-id)
                OPERATION_ID="$2"
                shift 2
                ;;
            -h|--help|help)
                show_usage
                exit 0
                ;;
            *)
                COMMAND="$1"
                shift
                ;;
        esac
    done
    
    # Execute command
    case "$COMMAND" in
        status)
            get_system_status
            generate_recommendations
            ;;
        cleanup-containers)
            cleanup_containers
            ;;
        cleanup-vms)
            cleanup_vms
            ;;
        cleanup-shares)
            cleanup_shares
            ;;
        cleanup-ctdb)
            cleanup_ctdb
            ;;
        cleanup-ad)
            cleanup_ad
            ;;
        cleanup-all)
            cleanup_all
            ;;
        report)
            generate_report
            ;;
        logs)
            show_logs
            ;;
        *)
            print_status $RED "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 