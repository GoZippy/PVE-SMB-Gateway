# Roadmap – PVE SMB Gateway

## Current Status (v0.1.0)

| Quarter | Sprint | Deliverables | Status |
|---------|--------|--------------|--------|
| **2025‑Q3** | S‑0 | Repo skeleton, README, deb packaging scaffold | ✅ Completed 22 Jul 2025 |
| | S‑1 | LXC create/delete, basic wizard, PR test harness | ✅ Completed |
| | S‑2 | Quota support, `pve-smbgateway` CLI beta | ✅ Completed |
| **2025‑Q4** | S‑3 | AD join, CTDB VIP, HA tests | 🔄 In Progress |
| | S‑4 | Native host mode, safety rollback | 🔄 In Progress |
| | S‑5 | Documentation polish, screencast, public beta tag (`v0.9.0`) | 📋 Planned |
| **2026‑Q1** | S‑6 | VM mode template builder, VSS snapshot hooks | 📋 Planned |
| | S‑7 | Security review, translation strings, `v1.0.0` GA | 📋 Planned |

## Phase 2: Storage Service Launcher (v1.1+)

### Core Infrastructure Upgrades

| Upgrade | What it unlocks | Why it stays lightweight |
|---------|----------------|--------------------------|
| **1. Generic Service Template Spec** | Any contributor can drop a YAML file that defines service deployment | Templates are pure data; core stays ~150 LoC |
| **2. Pluggable Provisioning Backends** | ZFS, CephFS, Gluster, Longhorn support via small Perl modules | Core only requires modules when templates use them |
| **3. pve-service-store Git Index** | Community PRs add new templates (TrueNAS, MinIO, Nextcloud) | Pure data; wizard fetches from GitHub raw |
| **4. GUI "App Store" Pane** | ExtJS grid shows templates → click Install | Fetches YAML, shows footprint, exposes HA toggle |
| **5. Post-install Helper Scripts** | Each template includes postinstall.sh for setup automation | Executed inside guest via pct/qm exec; sandboxed |
| **6. Rollback Snapshot & Uninstall** | Gateway takes ZFS/Ceph snapshot before provisioning | Eliminates "app graveyard" worry |

### Advanced Features

| Upgrade | What it unlocks | Why it stays lightweight |
|---------|----------------|--------------------------|
| **7. Tag-based HA Profiles** | Template YAML lists `ha: recommended\|optional\|required` | Simple enum; no complex logic |
| **8. Secrets Management** | Integration with PVE's pve-ssl.key store or HashiCorp Vault | No plain-text creds in YAML |
| **9. Pluggable Monitoring** | Auto-register Prometheus exporters with node exporter | Metrics stay external; no bloat |
| **10. Pre-flight Resource Check** | Wizard simulates RAM/CPU/disk impact cluster-wide | One REST call to /cluster/resources |
| **11. CLI Integration** | `pve-svc install truenas --ha=yes --dataset=zfs/share1` | Re-uses YAML + API; no GUI dependency |
| **12. Community CI Badge** | GitHub Action runs templates in nested virtualization nightly | Curated templates remain healthy automatically |

## Implementation Timeline

### Phase 2A: Foundation (2026-Q2)
- [ ] YAML template loader and parser
- [ ] Basic template validation
- [ ] LXC/VM provisioning engine
- [ ] Template cache system

### Phase 2B: App Store (2026-Q3)
- [ ] ExtJS "App Store" GUI pane
- [ ] Template repository integration
- [ ] Post-install script execution
- [ ] Rollback and uninstall functionality

### Phase 2C: Advanced Features (2026-Q4)
- [ ] HA profile system
- [ ] Secrets management integration
- [ ] Resource budget checking
- [ ] Monitoring integration

### Phase 2D: Community (2027-Q1)
- [ ] Community template repository
- [ ] CI/CD for template validation
- [ ] Template submission workflow
- [ ] Documentation and examples

## Folder Structure (Future)

```
pve-smb-gateway/
│
├─ templates/                    # Service templates
│   ├─ truenas-scale.yml
│   ├─ freenas-legacy.yml
│   ├─ minio-objectstore.yml
│   └─ nextcloud-lxc.yml
│
├─ lib/                         # Provisioning backends
│   └─ PVE/SMBgw/Prov/
│        ├─ ZFS.pm
│        ├─ CephFS.pm
│        └─ RBD.pm
│
├─ PVE/Storage/Custom/          # Core plugin (unchanged)
│   └─ SMBGateway.pm
│
└─ www/ext6/pvemanager6/        # Enhanced GUI
    ├─ smb-gateway.js
    └─ service-store.js
```

## Template Example

```yaml
# truenas-scale.yml
name: TrueNAS SCALE
type: vm
source_image: "https://download.truenas.com/..."
cpu: 2
memory: 4096
disks:
  - type: virtio
    size: 40G
  - type: passthrough
    pool: cephssd
postinstall:
  - qm guest exec {{vmid}} -- bash -c "truenas-setup --dataset {{dataset}}"
ha: recommended
ports:
  - {guest: 22, protocol: ssh}
  - {guest: 443, protocol: https, description: "Web UI"}
exporter: node
```

## Community Workflow

1. **Fork** repository
2. **Add** new template YAML file
3. **Open PR** with template
4. **GitHub Action** lints YAML & boots in nested KVM
5. **Merge** → template appears in "App Store" on next refresh

## Why This Approach Works

- **Stays Lightweight**: Core plugin remains Samba-centric; template engine is minimal
- **Full-Featured**: Users can grow from "one SMB share" to "TrueNAS HA gateway" or "MinIO S3 object store"
- **Community-Driven**: Low barrier to contribution (YAML, not Perl/JS)
- **Safe**: Rollback, resource checks, HA defaults, secure secrets handling
