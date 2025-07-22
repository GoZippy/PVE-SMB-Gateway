# Product‑Requirements Document – PVE SMB Gateway

| **Document owner** | Eric Henderson (Zippy Technologies) |
|--------------------|-------------------------------------|
| **Status** | Draft 0.1 – 2025‑07‑22 |
| **Target GA** | 2025‑Q4 (aligned with Proxmox VE 8.x LTS) |

---

## 1. Purpose

Provide a **GUI‑managed, lightweight and HA‑aware way to export SMB/CIFS shares** from existing Proxmox storage back‑ends (ZFS datasets, CephFS subvolumes, or RBD images) without forcing users to maintain a full NAS VM.

---

## 2. Goals & Success Metrics

| Goal | KPI | Target |
|------|-----|--------|
| One‑click share creation | Wizard flow completable < 60 s | 90 % of beta testers |
| Low resource overhead | Idle RAM ≤ 80 MB (LXC mode) | Achieve on 3‑node lab |
| Seamless fail‑over | CT/VM migrates within 30 s; clients reconnect via CTDB VIP | Pass 5 consecutive HA tests |
| Minimal host touch | Native install optional; LXC default | 80 % choose LXC |

---

## 3. Non‑Goals

* NFS, AFP or WebDAV export
* SMB over multi‑protocol security (e.g., DFS namespace)
* Deep NAS features (anti‑virus, cloud‑tiering, etc.)

---

## 4. Personas

| Persona | Needs |
|---------|-------|
| **Sysadmin Sam** (SMB office share) | Quick wizard, AD join, quotas |
| **Homelab Holly** | Zero‑HA, native host install, smallest RAM |
| **Enterprise Eva** | CTDB VIPs, Proxmox HA, audit logs |

---

## 5. Functional Requirements

1. **Wizard (GUI)**
   * Select backing storage: existing dataset/subvolume or create new.
   * Choose mode: *LXC* (default), *Native*, *NAS VM*.
   * AD / Workgroup selection, optional CTDB checkbox.
   * Quota input (GiB/TiB).

2. **Storage plugin**
   * CRUD (`create_share`, `activate_storage`, `status`, `remove_share`).
   * Writes config into `storage.cfg` or dedicated `smbgateway.cfg`.

3. **Provisioners**
   * **LXC Provisioner**  
     * Pull template, set 128 MB RAM, bind‑mount path.  
     * Install `samba` + `winbind`, auto‑join AD if creds supplied.
   * **Native Provisioner**  
     * Install samba, append share stanza, reload `smbd`.
   * **VM Provisioner** (Phase 2)  
     * Clone template (`smb‑gateway.qcow2`), attach virtio‑fs or RBD.

4. **Fail‑over / HA**
   * LXC/VM placed in Proxmox HA group.  
   * Optional CTDB setup script provides floating IP.

5. **CLI Helper**
   * `pve-smbgateway list|create|delete SHAREID [opts]` for automation.

6. **Metrics & Logs**
   * Expose share‑level I/O stats via `/api2/json/nodes/<node>/smbgateway/*`.
   * Log major events to `syslog` with tag `pve-smbgw`.

---

## 6. Non‑Functional Requirements

| Category | Requirement |
|----------|-------------|
| Performance | Sequential throughput within 15 % of host ZFS/CephFS performance. |
| Security | Enforce `min protocol SMB2`; optional signing; Kerberos by default when joined to AD. |
| Compatibility | Proxmox 8.x; Debian 12 PVE hosts; Ceph Quincy‑Reef. |
| Upgradability | Plugin must load cleanly after PVE major upgrades (Perl API version check). |

---

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| API drift in next PVE release | Plugin load failure | CI test against nightly PVE containers |
| CephFS only in mgr‑SMB | RBD users excluded | Offer RBD map path; document performance caveats |
| Quota mis‑configs filling pool | VM I/O stalls | Default per‑share quota + e‑mail alert hook |

---

## 8. Milestones

1. **M0 – Skeleton (DONE)**: Perl stub, ExtJS wizard, packaging.  
2. **M1 – LXC Mode GA**: CRUD, quota, AD join, CI, docs.  
3. **M2 – Native Mode**: Host install path + safety checks.  
4. **M3 – HA & CTDB**: Fail‑over VIP, HA integration tests.  
5. **M4 – VM Mode (optional)**: Template builder, virtio‑fs attach.  
6. **M5 – Beta → Stable**: Community feedback, security audit, v1.0 tag.

---

## 9. Acceptance Criteria

* End‑to‑end wizard demo passes on 3‑node Ceph lab.
* `pve-smbgateway create demo …` works headless.
* `pveceph osd out` simulation triggers CT/VM migration without share outage > 30 s.
* Lintian clean .deb; unit tests ≥ 90 % statements.

