# Project Name Change Summary

## From: "Proxmox SMB Gateway" → To: "PVE SMB Gateway"

### Why the Change?

We proactively renamed the project to avoid potential trademark issues with Proxmox GmbH. While "Proxmox" is a registered trademark, "PVE" (Proxmox Virtual Environment) is the generic term for the platform.

### What Changed

#### Repository Name
- **Old**: `proxmox-smb-gateway`
- **New**: `pve-smb-gateway`

#### GitHub URLs
- **Old**: `https://github.com/ZippyNetworks/proxmox-smb-gateway`
- **New**: `https://github.com/ZippyNetworks/pve-smb-gateway`

#### Documentation Updates
- All README files updated
- GitHub setup guide updated
- Commercial license updated
- Contributor agreement updated
- Release notes updated

#### Source Code
- File headers updated
- Package descriptions updated
- Comments and documentation strings updated

### What Stays the Same

- **Functionality**: 100% identical - no code changes
- **Package Name**: Still `pve-plugin-smbgateway` (this is appropriate)
- **CLI Tool**: Still `pve-smbgateway` (this is appropriate)
- **Plugin Class**: Still `PVE::Storage::Custom::SMBGateway` (this is appropriate)

### Legal Benefits

1. **Trademark Compliance**: Avoids potential trademark infringement
2. **Clear Distinction**: Makes it clear this is a third-party plugin
3. **Professional Approach**: Shows respect for Proxmox GmbH's intellectual property
4. **Future-Proof**: Reduces risk of legal issues as the project grows

### Community Impact

- **Zero Functional Impact**: Users won't notice any difference
- **Clear Branding**: "PVE SMB Gateway" is still descriptive and recognizable
- **Professional Image**: Shows we take legal compliance seriously
- **Proxmox-Friendly**: Demonstrates respect for the platform and its creators

### Next Steps

1. **Create GitHub Repository**: Use the new name `pve-smb-gateway`
2. **Update Documentation**: All references now point to the new repository
3. **Community Announcement**: Explain the change in the initial release
4. **Monitor Feedback**: Ensure the community understands the reasoning

### Example Community Message

```
Hi Proxmox Community!

I'm excited to announce the initial release of the PVE SMB Gateway plugin - a GUI-managed way to export SMB/CIFS shares from your Proxmox storage backends without needing a full NAS VM.

Note: We chose "PVE SMB Gateway" as the name to avoid any potential trademark issues with Proxmox GmbH, while still being clear about what the plugin does.

[rest of announcement...]
```

---

*This name change demonstrates our commitment to building a professional, legally compliant project that respects the Proxmox ecosystem.* 