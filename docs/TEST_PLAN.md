# Test Plan

## 1. Unit Tests (Perl)

* `t/00-load.t` – module compiles
* `t/10-create-native.t` – mock `run_command`, assert config lines
* `t/20-create-lxc.t` – patch `%PVE::Tools::run_command`, verify `pct` args

## 2. Integration (GitHub Actions)

| Stage | Image | Steps |
|-------|-------|-------|
| Lint  | `debian:12` | `perlcritic -1 *.pm` |
| Build | `ghcr.io/proxmox/pve-test-env:8` | `dpkg-buildpackage -us -uc -b` |
| Smoke | Same container | *Install plugin* → call wizard via `pvesh` → assert share exists |

## 3. Manual HA Fail‑over

1. Create share in LXC mode on node A.  
2. Put node A into `pvecm nodequorum 0` or power‑cycle.  
3. Validate CT migrates to node B, VIP fails over, client copy resumes < 30 s.

## 4. Security Tests

* `smbclient` auth brute‑force blocked by fail2ban (if enabled).  
* Verify `min protocol SMB2` via `smbclient --option='client min protocol=NT1' …` fails.

## 5. Performance Baseline

Measure `fio --direct=1 --rw=read …` on:
* host ZFS dataset,
* LXC bind‑mount,
* VM virtio‑fs.

Accept ≤ 15 % regression LXC vs. host.