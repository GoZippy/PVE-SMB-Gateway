# Developer Guide

## Quick Start

```bash
git clone https://github.com/ZippyNetworks/proxmox-smb-gateway.git
cd proxmox-smb-gateway
./scripts/build_package.sh   # builds .deb
sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb
systemctl restart pveproxy
```

## Coding Standards

- **Perl**: Follow `perltidy -q -i=4`
- **JavaScript**: ESLint (Airbnb) via `npm run lint`
- **Commit prefix**: `[core]`, `[ui]`, `[docs]`, `[ci]`, `[tests]`

## Useful Make Targets

| Target | Action |
|--------|--------|
| `make lint` | Lint Perl & JavaScript |
| `make deb` | Build .deb into `../` |
| `make clean` | Remove `debian/tmp` and build artifacts |

## Release Flow

1. Tag `vX.Y.Z` in Git
2. GitHub Actions builds .deb and attaches to release
3. Publish checksum and changelog in `debian/changelog`
4. Announce on Proxmox forum thread

---

*Add (or modify) any sections as the project evolves—these docs give you a complete baseline for specs, timeline, architecture, testing, and developer onboarding.*