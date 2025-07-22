# GitHub Repository Setup Guide

## Initial Repository Setup

### 1. Create GitHub Repository

1. Go to [GitHub](https://github.com) and sign in
2. Click "New repository"
3. Repository name: `pve-smb-gateway`
4. Description: `Proxmox VE plugin for GUI-managed SMB/CIFS gateway with dual licensing`
5. Make it **Public**
6. **Don't** initialize with README (we already have one)
7. Click "Create repository"

### 2. Push Local Repository

```bash
# Add the remote origin
git remote add origin https://github.com/ZippyNetworks/pve-smb-gateway.git

# Push the main branch
git push -u origin master

# Push the tag
git push origin v0.1.0
```

### 3. Repository Settings

#### Enable GitHub Actions
- Go to Settings → Actions → General
- Enable "Allow all actions and reusable workflows"

#### Enable DCO (Developer Certificate of Origin)
- Go to Settings → General → Developer Certificate of Origin
- Check "Require a signed commit"

#### Set up Branch Protection
- Go to Settings → Branches
- Add rule for `master` branch:
  - Require pull request reviews
  - Require status checks to pass
  - Require signed commits
  - Include administrators

### 4. Create Release

1. Go to Releases → "Create a new release"
2. Tag: `v0.1.0`
3. Title: `PVE SMB Gateway v0.1.0 - Initial Release`
4. Description:

```markdown
## 🎉 Initial Release - PVE SMB Gateway v0.1.0

### Features
- ✅ **Complete SMB Gateway Plugin**: LXC and Native deployment modes
- ✅ **ExtJS Wizard**: Professional web interface with validation
- ✅ **CLI Management**: `pve-smbgateway` command-line tools
- ✅ **Error Handling**: Comprehensive rollback and recovery
- ✅ **Dual Licensing**: AGPL-3.0 (Community) + Commercial License
- ✅ **Build System**: Automated packaging and CI/CD
- ✅ **Documentation**: Complete guides and examples

### Installation
```bash
# Download and install
wget https://github.com/ZippyNetworks/pve-smb-gateway/releases/download/v0.1.0/pve-plugin-smbgateway_0.1.0-1_all.deb
sudo dpkg -i pve-plugin-smbgateway_0.1.0-1_all.deb
sudo systemctl restart pveproxy
```

### Usage
1. Navigate to Datacenter → Storage → Add → SMB Gateway
2. Configure your share settings
3. Click Create

### CLI Usage
```bash
# List shares
pve-smbgateway list

# Create share
pve-smbgateway create myshare --mode lxc --quota 10G

# Check status
pve-smbgateway status myshare
```

### License
- **Community Edition**: AGPL-3.0 (free for personal/educational use)
- **Commercial Edition**: Commercial license for enterprise use
- See [docs/COMMERCIAL_LICENSE.md](docs/COMMERCIAL_LICENSE.md) for details

### Support
- **Maintainer**: Eric Henderson <eric@gozippy.com>
- **Issues**: [GitHub Issues](https://github.com/ZippyNetworks/pve-smb-gateway/issues)
- **Documentation**: [docs/](docs/)

### Roadmap
- Phase 1: SMB Gateway (v0.1.0 - v1.0.0) - Current
- Phase 2: Storage Service Launcher (v1.1.0+) - TrueNAS, MinIO, Nextcloud deployment

### Contributing
We welcome contributions! See [CONTRIBUTOR_LICENSE_AGREEMENT.md](CONTRIBUTOR_LICENSE_AGREEMENT.md) for details.

---

**Thank you for using Proxmox SMB Gateway!** 🚀
```

5. Upload the `.deb` package (build it first if needed)
6. Mark as "Latest release"
7. Publish release

### 5. Configure Issue Templates

Create `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Create a report to help us improve
title: ''
labels: 'bug'
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Environment:**
 - Proxmox VE Version: [e.g. 8.0]
 - Plugin Version: [e.g. 0.1.0]
 - Browser: [e.g. chrome, safari]
 - OS: [e.g. Debian 12]

**Additional context**
Add any other context about the problem here.
```

### 6. Configure Pull Request Template

Create `.github/pull_request_template.md`:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Manual testing completed
- [ ] No breaking changes

## Checklist
- [ ] My code follows the style guidelines of this project
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
```

### 7. Set up GitHub Pages (Optional)

1. Go to Settings → Pages
2. Source: "Deploy from a branch"
3. Branch: `gh-pages` (create this branch)
4. Folder: `/ (root)`
5. Save

### 8. Community Outreach

#### Proxmox Forum Post
Post in the [Proxmox Community Forum](https://forum.proxmox.com/):

**Subject**: `[ANNOUNCEMENT] PVE SMB Gateway Plugin v0.1.0 - GUI-managed SMB shares`

**Content**:
```
Hello Proxmox Community!

I'm excited to announce the initial release of the PVE SMB Gateway plugin - a GUI-managed way to export SMB/CIFS shares from your Proxmox storage backends without needing a full NAS VM.

**Key Features:**
- One-click share creation via web interface
- LXC and Native deployment modes
- CLI management tools
- Quota and AD integration support
- Comprehensive error handling
- Dual licensing (AGPL-3.0 + Commercial)

**Quick Start:**
```bash
wget https://github.com/ZippyNetworks/pve-smb-gateway/releases/download/v0.1.0/pve-plugin-smbgateway_0.1.0-1_all.deb
sudo dpkg -i pve-plugin-smbgateway_0.1.0-1_all.deb
sudo systemctl restart pveproxy
```

**Repository:** https://github.com/ZippyNetworks/pve-smb-gateway
**Documentation:** https://github.com/ZippyNetworks/pve-smb-gateway/tree/main/docs

The plugin is dual-licensed - free for community use under AGPL-3.0, with commercial licensing available for enterprise deployments.

I'd love to get feedback from the community and welcome contributions!

Best regards,
Eric Henderson
eric@gozippy.com
```

#### Reddit Posts
- r/Proxmox
- r/homelab
- r/selfhosted

#### Social Media
- Twitter/X: Announce with screenshots
- LinkedIn: Professional announcement
- Mastodon: Open source community

### 9. Monitor and Respond

1. **Watch Issues**: Respond to bug reports and feature requests
2. **Review PRs**: Merge community contributions
3. **Update Documentation**: Keep docs current
4. **Plan Next Release**: Based on community feedback

---

*This guide ensures a professional, community-friendly repository setup.* 