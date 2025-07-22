# Architecture Overview

```mermaid
flowchart LR
    A[ExtJS Wizard] -->|REST| B(API2 :: SMBGateway)
    B -->|Perl call| C[Storage Plugin :: SMBGateway.pm]
    C -- mode=lxc --> D[LXC Provisioner]
    C -- mode=native --> E[Host Provisioner]
    C -- mode=vm --> F[VM Provisioner]
    D & E & F --> G[Backing Storage]
    G -->|ZFS dataset<br/>CephFS subvolume<br/>RBD map| H(Samba Service)
    H --> I[CTDB VIP (optional)]
    I --> J[Windows / macOS Clients]
```

Control Plane: wizard → REST → plugin

Data Plane: ZFS/Ceph → mount/bind → Samba → network

Key directories inside the .deb:

/usr/share/perl5/PVE/Storage/Custom/SMBGateway.pm
/usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js
/usr/share/pve-smbgateway/lxc_setup.sh