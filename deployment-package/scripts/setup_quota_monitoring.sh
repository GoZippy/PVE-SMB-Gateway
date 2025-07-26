#!/bin/bash
# Setup Quota Monitoring Cron Job
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License

set -e

# Default configuration
CRON_SCHEDULE="0 * * * *"  # Default: Run hourly
WARN_THRESHOLD=80
CRITICAL_THRESHOLD=90
NOTICE_THRESHOLD=75
NOTIFY_EMAIL=""
NOTIFY_WEBHOOK=""
ENFORCE_QUOTAS=0
ENFORCE_THRESHOLD=95
PROMETHEUS_OUTPUT=0
PROMETHEUS_FILE="/var/lib/prometheus/node_exporter/smb_gateway_quotas.prom"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --schedule <cron>     Cron schedule (default: '0 * * * *' - hourly)"
    echo "  -w, --warn <percent>      Warning threshold percentage (default: 80)"
    echo "  -c, --critical <percent>  Critical threshold percentage (default: 90)"
    echo "  -n, --notice <percent>    Notice threshold percentage (default: 75)"
    echo "  -e, --email <address>     Email address for notifications"
    echo "  -u, --webhook <url>       Webhook URL for notifications"
    echo "  -f, --enforce             Enforce quotas by blocking writes when threshold is exceeded"
    echo "  -t, --enforce-threshold <percent> Threshold for enforcing quotas (default: 95)"
    echo "  -p, --prometheus          Enable Prometheus metrics output"
    echo "  -o, --output-file <path>  Path to write Prometheus metrics (default: $PROMETHEUS_FILE)"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--schedule)
            CRON_SCHEDULE="$2"
            shift
            shift
            ;;
        -w|--warn)
            WARN_THRESHOLD="$2"
            shift
            shift
            ;;
        -c|--critical)
            CRITICAL_THRESHOLD="$2"
            shift
            shift
            ;;
        -n|--notice)
            NOTICE_THRESHOLD="$2"
            shift
            shift
            ;;
        -e|--email)
            NOTIFY_EMAIL="$2"
            shift
            shift
            ;;
        -u|--webhook)
            NOTIFY_WEBHOOK="$2"
            shift
            shift
            ;;
        -f|--enforce)
            ENFORCE_QUOTAS=1
            shift
            ;;
        -t|--enforce-threshold)
            ENFORCE_THRESHOLD="$2"
            shift
            shift
            ;;
        -p|--prometheus)
            PROMETHEUS_OUTPUT=1
            shift
            ;;
        -o|--output-file)
            PROMETHEUS_FILE="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if monitor_quotas.sh exists
MONITOR_SCRIPT="/usr/share/pve-smbgateway/scripts/monitor_quotas.sh"
if [ ! -f "$MONITOR_SCRIPT" ]; then
    # Try to find it in the development environment
    if [ -f "scripts/monitor_quotas.sh" ]; then
        MONITOR_SCRIPT="$(pwd)/scripts/monitor_quotas.sh"
    else
        echo "Error: monitor_quotas.sh script not found"
        exit 1
    fi
fi

# Make sure the script is executable
chmod +x "$MONITOR_SCRIPT"

# Build the command
COMMAND="$MONITOR_SCRIPT"
COMMAND="$COMMAND --warn $WARN_THRESHOLD"
COMMAND="$COMMAND --critical $CRITICAL_THRESHOLD"
COMMAND="$COMMAND --notice $NOTICE_THRESHOLD"

if [ -n "$NOTIFY_EMAIL" ]; then
    COMMAND="$COMMAND --email '$NOTIFY_EMAIL'"
fi

if [ -n "$NOTIFY_WEBHOOK" ]; then
    COMMAND="$COMMAND --webhook '$NOTIFY_WEBHOOK'"
fi

if [ $ENFORCE_QUOTAS -eq 1 ]; then
    COMMAND="$COMMAND --enforce --enforce-threshold $ENFORCE_THRESHOLD"
fi

if [ $PROMETHEUS_OUTPUT -eq 1 ]; then
    # Create directory for Prometheus metrics if it doesn't exist
    PROMETHEUS_DIR=$(dirname "$PROMETHEUS_FILE")
    mkdir -p "$PROMETHEUS_DIR"
    
    COMMAND="$COMMAND --prometheus > $PROMETHEUS_FILE"
fi

# Create cron job
CRON_JOB="$CRON_SCHEDULE $COMMAND"

# Check if cron job already exists
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" || true)

if [ -n "$EXISTING_CRON" ]; then
    # Update existing cron job
    (crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "$CRON_JOB") | crontab -
    echo "Updated existing cron job for quota monitoring"
else
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Added new cron job for quota monitoring"
fi

echo "Quota monitoring configured with the following settings:"
echo "  Schedule: $CRON_SCHEDULE"
echo "  Notice threshold: $NOTICE_THRESHOLD%"
echo "  Warning threshold: $WARN_THRESHOLD%"
echo "  Critical threshold: $CRITICAL_THRESHOLD%"
if [ -n "$NOTIFY_EMAIL" ]; then
    echo "  Email notifications: $NOTIFY_EMAIL"
fi
if [ -n "$NOTIFY_WEBHOOK" ]; then
    echo "  Webhook notifications: $NOTIFY_WEBHOOK"
fi
if [ $ENFORCE_QUOTAS -eq 1 ]; then
    echo "  Quota enforcement: Enabled (threshold: $ENFORCE_THRESHOLD%)"
fi
if [ $PROMETHEUS_OUTPUT -eq 1 ]; then
    echo "  Prometheus metrics: Enabled (output file: $PROMETHEUS_FILE)"
fi

# Run the script once to verify it works
echo "Running quota monitoring script to verify configuration..."
eval "$COMMAND"
echo "Quota monitoring setup complete"