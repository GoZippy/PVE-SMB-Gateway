# Product Overview

PVE SMB Gateway Plugin is a Proxmox Virtual Environment (PVE) storage plugin that provides GUI-managed SMB/CIFS shares from existing Proxmox storage backends (ZFS datasets, CephFS subvolumes, or RBD images) without requiring a full NAS VM.

## Key Features
- One-click share creation via Proxmox web interface
- Multiple deployment modes: LXC (default), Native, VM (planned)
- High Availability with CTDB support for floating IPs
- Active Directory integration for enterprise environments
- Quota management and resource efficiency (≤80MB RAM in LXC mode)
- CLI tools for automation

## Architecture
Control Plane: ExtJS Wizard → REST API → Perl Storage Plugin
Data Plane: ZFS/Ceph → mount/bind → Samba → network clients

## Licensing
Dual-licensed under AGPL-3.0 (community) and commercial license for OEM/commercial distribution.

## Target Users
- Proxmox administrators needing lightweight SMB shares
- Homelabs and educational institutions (AGPL)
- Commercial deployments (commercial license)