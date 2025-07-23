# Quota Management

The PVE SMB Gateway Plugin includes comprehensive quota management with real-time monitoring, usage tracking, and trend analysis across multiple filesystem types.

## Supported Filesystem Types

### ZFS Quotas
- **Native support**: Uses ZFS built-in quota system
- **Commands used**: `zfs get quota,used`, `zfs set quota=<size>`
- **Features**: Precise quota enforcement, instant usage reporting
- **Requirements**: ZFS filesystem with quota property set

```bash
# Example ZFS quota setup
zfs create tank/myshare
zfs set quota=10G tank/myshare
```

### XFS Project Quotas
- **Project-based**: Uses XFS project quota system for directory-level quotas
- **Commands used**: `xfs_quota -x -c "report -p"`, `xfs_quota -x -c "limit -p"`
- **Configuration files**: `/etc/projects`, `/etc/projid`
- **Requirements**: XFS filesystem mounted with `prjquota` option

```bash
# Example XFS project quota setup
mount -o prjquota /dev/sdb1 /mnt/xfs
# Plugin automatically manages project IDs and configuration
```

### User Quotas (Fallback)
- **Standard quotas**: Uses traditional user quota system
- **Commands used**: `quota -u`, `setquota -u`
- **Limitations**: Per-user rather than per-directory quotas
- **Requirements**: Filesystem with user quotas enabled

## Quota Monitoring Features

### Real-time Usage Tracking
- Automatic usage calculation with percentage of quota used
- Support for different size units (B, K, M, G, T)
- Warning levels at 75% (notice), 85% (warning), and 95% (critical)

### Historical Data Storage
- Usage history stored in `/etc/pve/smbgateway/history/`
- Automatic cleanup (keeps last 100 data points per share)
- CSV format: `timestamp,used_bytes,percent`

### Trend Analysis
- 24-hour trend calculation showing usage patterns
- Direction indicators: increasing, decreasing, or stable
- Rate calculations: percent per hour and bytes per hour
- Minimum 2 data points required for trend analysis

## Configuration

### Setting Quotas
Quotas can be set during share creation or added later:

```bash
# During creation
pve-smbgateway create myshare --quota 10G

# Via storage.cfg
storage: myshare
    type smbgateway
    sharename myshare
    quota 10G
```

### Quota Format
- Supported units: K (kilobytes), M (megabytes), G (gigabytes), T (terabytes)
- Examples: `1G`, `500M`, `2T`, `10240K`

## Status Information

The `status` command provides comprehensive quota information:

```bash
pve-smbgateway status myshare
```

### Status Output Fields
- **limit**: Configured quota limit
- **used**: Current usage
- **percent**: Percentage of quota used
- **filesystem_type**: Detected filesystem type (zfs, xfs, ext4, etc.)
- **status**: ok, notice, warning, or critical
- **trend**: Usage trend over last 24 hours (if available)
- **last_checked**: Timestamp of last quota check

### Example Status Output
```json
{
  "quota": {
    "limit": "10G",
    "used": "2.5G",
    "percent": 25,
    "filesystem_type": "zfs",
    "status": "ok",
    "trend": {
      "percent_per_hour": "0.15",
      "bytes_per_hour": 15728640,
      "direction": "increasing",
      "data_points": 24,
      "time_span_hours": "23.8"
    },
    "last_checked": 1642781234
  }
}
```

## Troubleshooting

### Common Issues

#### Quota Not Applied
- **ZFS**: Ensure dataset exists and quota property is supported
- **XFS**: Verify filesystem is mounted with `prjquota` option
- **Other**: Check if quota tools are installed and quotas are enabled

#### Quota Tools Missing
```bash
# Install required tools
apt-get install quota          # For user quotas
apt-get install xfsprogs       # For XFS quotas
# ZFS tools are included with ZFS installation
```

#### Permission Errors
- Ensure the plugin runs with sufficient privileges to access quota commands
- Check that quota files (`/etc/projects`, `/etc/projid`) are writable

#### Inaccurate Usage Reporting
- **ZFS**: Usage should be accurate and real-time
- **XFS**: May have slight delays in project quota updates
- **User quotas**: Limited to user-level rather than directory-level tracking

### Debugging Commands

```bash
# Check ZFS quota status
zfs get quota,used tank/myshare

# Check XFS project quotas
xfs_quota -x -c "report -p" /mnt/xfs

# Check user quotas
quota -u root

# Verify quota history files
ls -la /etc/pve/smbgateway/history/
cat /etc/pve/smbgateway/history/myshare.history
```

## Performance Considerations

### Monitoring Overhead
- Quota checks are performed during status requests, not continuously
- Historical data is updated only when status is checked
- Minimal performance impact on normal SMB operations

### Storage Requirements
- History files are small (typically <10KB per share)
- Automatic cleanup prevents unbounded growth
- Quota metadata files are minimal (<1KB per share)

### Filesystem Performance
- **ZFS**: Quota enforcement has minimal performance impact
- **XFS**: Project quotas may have slight overhead during writes
- **User quotas**: Traditional quota overhead applies

## Best Practices

### Quota Sizing
- Set quotas with reasonable headroom for growth
- Monitor trends to predict when quotas may be exceeded
- Consider filesystem overhead when setting limits

### Monitoring
- Check quota status regularly, especially for critical shares
- Set up external monitoring to alert on high usage
- Review trend data to plan capacity upgrades

### Filesystem Selection
- **ZFS**: Best choice for accurate quotas and performance
- **XFS**: Good alternative with project quota support
- **ext4**: Functional but limited to user-level quotas

## API Integration

### REST API Endpoints
Quota information is available through the standard storage status API:

```bash
# Get quota status via API
pvesh get /nodes/{node}/storage/{storage}/status
```

### CLI Integration
All quota functionality is accessible through the CLI:

```bash
# Status with quota information
pve-smbgateway status myshare --json

# List all shares with quota usage
pve-smbgateway list --show-quotas
```