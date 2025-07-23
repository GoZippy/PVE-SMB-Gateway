# PVE SMB Gateway - User Process Flow

## Overview

This document provides a comprehensive flow diagram of the user process flow for the PVE SMB Gateway plugin, covering all deployment modes, configuration options, and user interactions from initial setup to ongoing management.

## High-Level User Journey

```mermaid
flowchart TD
    A[User Access Proxmox Web Interface] --> B[Navigate to Datacenter → Storage]
    B --> C[Click Add Storage]
    C --> D[Select SMB Gateway from Storage Types]
    D --> E[ExtJS Wizard Opens]
    E --> F[Configure Basic Settings]
    F --> G{Choose Deployment Mode}
    
    G -->|LXC Mode| H[LXC Configuration]
    G -->|Native Mode| I[Native Configuration]
    G -->|VM Mode| J[VM Configuration]
    
    H --> K{Enable Advanced Features?}
    I --> K
    J --> K
    
    K -->|Yes| L[Configure AD Integration]
    K -->|Yes| M[Configure HA/CTDB]
    K -->|Yes| N[Configure Quotas]
    K -->|No| O[Review Configuration]
    
    L --> O
    M --> O
    N --> O
    
    O --> P[Click Create]
    P --> Q[Backend Processing]
    Q --> R{Success?}
    
    R -->|Yes| S[Share Created Successfully]
    R -->|No| T[Error Handling & Rollback]
    
    S --> U[Ongoing Management]
    T --> V[Manual Cleanup if Needed]
    
    U --> W[Monitor Performance]
    U --> X[Manage Backups]
    U --> Y[Handle Failover]
    U --> Z[Update Configuration]
```

## Detailed Process Flows

### 1. Initial Setup and Configuration

```mermaid
flowchart TD
    A[User Starts] --> B[Access Proxmox Web Interface]
    B --> C[Navigate to Datacenter → Storage]
    C --> D[Click Add Storage Button]
    D --> E[Storage Type Selection Dialog]
    E --> F[Select SMB Gateway]
    F --> G[ExtJS Wizard Opens]
    
    G --> H[Basic Configuration Panel]
    H --> I[Enter Share Name]
    I --> J[Select Deployment Mode]
    
    J --> K{Mode Selection}
    K -->|LXC| L[LXC Mode Configuration]
    K -->|Native| M[Native Mode Configuration]
    K -->|VM| N[VM Mode Configuration]
    
    L --> O[Configure Path]
    M --> O
    N --> O
    
    O --> P[Set Quota (Optional)]
    P --> Q[Advanced Features Panel]
    
    Q --> R{Enable AD Integration?}
    R -->|Yes| S[AD Configuration]
    R -->|No| T[Skip AD Setup]
    
    S --> U[Enter Domain Name]
    U --> V[Enter AD Credentials]
    V --> W[Configure OU (Optional)]
    W --> X[Set Fallback Authentication]
    
    T --> Y{Enable HA/CTDB?}
    X --> Y
    
    Y -->|Yes| Z[HA Configuration]
    Y -->|No| AA[Skip HA Setup]
    
    Z --> BB[Enter VIP Address]
    BB --> CC[Select Cluster Nodes]
    CC --> DD[Configure Failover Settings]
    
    AA --> EE[Review Configuration]
    DD --> EE
    
    EE --> FF[Validation Check]
    FF --> GG{Validation Pass?}
    
    GG -->|Yes| HH[Create Share]
    GG -->|No| II[Show Error Messages]
    
    II --> JJ[User Fixes Issues]
    JJ --> FF
```

### 2. Deployment Mode-Specific Flows

#### LXC Mode Flow

```mermaid
flowchart TD
    A[LXC Mode Selected] --> B[Template Discovery]
    B --> C{Template Found?}
    
    C -->|Yes| D[Use Existing Template]
    C -->|No| E[Download Debian Template]
    
    D --> F[Create LXC Container]
    E --> F
    
    F --> G[Configure Container Resources]
    G --> H[Set Memory Limit (128MB)]
    H --> I[Configure Network]
    I --> J[Create Bind Mount]
    J --> K[Start Container]
    
    K --> L[Install Samba in Container]
    L --> M[Configure Samba]
    M --> N{AD Integration?}
    
    N -->|Yes| O[Join AD Domain]
    N -->|No| P[Configure Local Auth]
    
    O --> Q[Configure Kerberos]
    P --> R[Set Up Local Users]
    
    Q --> S{HA Enabled?}
    R --> S
    
    S -->|Yes| T[Install CTDB]
    S -->|No| U[Start Samba Services]
    
    T --> V[Configure CTDB Cluster]
    V --> W[Set Up VIP]
    W --> U
    
    U --> X[Apply Quotas]
    X --> Y[Share Ready]
```

#### Native Mode Flow

```mermaid
flowchart TD
    A[Native Mode Selected] --> B[Check Host Samba Installation]
    B --> C{Samba Installed?}
    
    C -->|Yes| D[Use Existing Installation]
    C -->|No| E[Install Samba Packages]
    
    D --> F[Create Share Directory]
    E --> F
    
    F --> G[Configure Samba Share]
    G --> H{AD Integration?}
    
    H -->|Yes| I[Join AD Domain]
    H -->|No| J[Configure Local Auth]
    
    I --> K[Configure Kerberos]
    J --> L[Set Up Local Users]
    
    K --> M{HA Enabled?}
    L --> M
    
    M -->|Yes| N[Install CTDB]
    M -->|No| O[Reload Samba Configuration]
    
    N --> P[Configure CTDB Cluster]
    P --> Q[Set Up VIP]
    Q --> O
    
    O --> R[Apply Quotas]
    R --> S[Share Ready]
```

#### VM Mode Flow

```mermaid
flowchart TD
    A[VM Mode Selected] --> B[VM Template Discovery]
    B --> C{Template Found?}
    
    C -->|Yes| D[Use Existing Template]
    C -->|No| E[Create VM Template]
    
    D --> F[Clone VM Template]
    E --> F
    
    F --> G[Configure VM Resources]
    G --> H[Set Memory Allocation]
    H --> I[Set CPU Cores]
    I --> J[Configure Network]
    J --> K[Add Cloud-init Configuration]
    
    K --> L[Start VM]
    L --> M[Wait for VM Boot]
    M --> N[Get VM IP Address]
    N --> O[SSH to VM]
    
    O --> P[Install Samba in VM]
    P --> Q[Configure Samba]
    Q --> R{AD Integration?}
    
    R -->|Yes| S[Join AD Domain]
    R -->|No| T[Configure Local Auth]
    
    S --> U[Configure Kerberos]
    T --> V[Set Up Local Users]
    
    U --> W{HA Enabled?}
    V --> W
    
    W -->|Yes| X[Install CTDB]
    W -->|No| Y[Start Samba Services]
    
    X --> Z[Configure CTDB Cluster]
    Z --> AA[Set Up VIP]
    AA --> Y
    
    Y --> BB[Apply Quotas]
    BB --> CC[Share Ready]
```

### 3. Active Directory Integration Flow

```mermaid
flowchart TD
    A[AD Integration Enabled] --> B[Domain Controller Discovery]
    B --> C[Test DNS Resolution]
    C --> D{DC Found?}
    
    D -->|Yes| E[Test Connectivity]
    D -->|No| F[Show Error: DC Not Found]
    
    E --> G{Connectivity OK?}
    G -->|Yes| H[Validate Credentials]
    G -->|No| I[Show Error: Cannot Connect]
    
    H --> J{Credentials Valid?}
    J -->|Yes| K[Join Domain]
    J -->|No| L[Show Error: Invalid Credentials]
    
    K --> M{Domain Join Success?}
    M -->|Yes| N[Configure Kerberos]
    M -->|No| O{Enable Fallback?}
    
    O -->|Yes| P[Configure Fallback Auth]
    O -->|No| Q[Show Error: Join Failed]
    
    N --> R[Configure Samba for AD]
    P --> R
    
    R --> S[Test Authentication]
    S --> T{Auth Working?}
    
    T -->|Yes| U[AD Integration Complete]
    T -->|No| V[Show Warning: Auth Issues]
    
    U --> W[Continue with Share Creation]
    V --> W
```

### 4. High Availability (CTDB) Flow

```mermaid
flowchart TD
    A[HA/CTDB Enabled] --> B[Validate VIP Address]
    B --> C{VIP Available?}
    
    C -->|Yes| D[Get Cluster Nodes]
    C -->|No| E[Show Error: VIP in Use]
    
    D --> F[Validate Node Connectivity]
    F --> G{All Nodes Reachable?}
    G -->|Yes| H[Install CTDB Packages]
    G -->|No| I[Show Error: Node Unreachable]
    
    H --> J[Configure CTDB]
    J --> K[Create Nodes File]
    K --> L[Create Public Addresses File]
    L --> M[Configure Samba for CTDB]
    
    M --> N[Start CTDB Service]
    N --> O[Wait for CTDB Ready]
    O --> P{CTDB Healthy?}
    
    P -->|Yes| Q[Configure VIP]
    P -->|No| R[Show Error: CTDB Failed]
    
    Q --> S[Test VIP Connectivity]
    S --> T{VIP Working?}
    
    T -->|Yes| U[HA Setup Complete]
    T -->|No| V[Show Error: VIP Issues]
    
    U --> W[Continue with Share Creation]
    V --> W
```

### 5. Quota Management Flow

```mermaid
flowchart TD
    A[Quota Configuration] --> B[Validate Quota Format]
    B --> C{Format Valid?}
    
    C -->|Yes| D[Detect Filesystem Type]
    C -->|No| E[Show Error: Invalid Format]
    
    D --> F{Filesystem Type}
    F -->|ZFS| G[Apply ZFS Quota]
    F -->|XFS| H[Apply XFS Project Quota]
    F -->|Other| I[Apply User Quota]
    
    G --> J{Quota Applied?}
    H --> J
    I --> J
    
    J -->|Yes| K[Store Quota Info]
    J -->|No| L[Show Error: Quota Failed]
    
    K --> M[Set Up Monitoring]
    M --> N[Configure History Tracking]
    N --> O[Quota Setup Complete]
    
    O --> P[Continue with Share Creation]
    L --> Q[Continue Without Quota]
```

### 6. Error Handling and Rollback Flow

```mermaid
flowchart TD
    A[Error Occurs] --> B[Log Error Details]
    B --> C[Identify Error Type]
    C --> D{Error Category}
    
    D -->|Validation Error| E[Show User-Friendly Message]
    D -->|System Error| F[Attempt Automatic Recovery]
    D -->|Critical Error| G[Initiate Rollback]
    
    E --> H[User Fixes Issue]
    H --> I[Retry Operation]
    
    F --> J{Recovery Success?}
    J -->|Yes| K[Continue Operation]
    J -->|No| G
    
    G --> L[Stop Current Operation]
    L --> M[Execute Rollback Steps]
    M --> N[Clean Up Resources]
    N --> O[Generate Cleanup Report]
    
    O --> P[Show Error to User]
    P --> Q[Provide Manual Cleanup Instructions]
    Q --> R[Log Rollback Results]
    
    R --> S[User Reviews Cleanup Report]
    S --> T[User Performs Manual Cleanup if Needed]
    T --> U[User Retries Operation]
```

### 7. Ongoing Management Flow

```mermaid
flowchart TD
    A[Share Management] --> B{Management Action}
    
    B -->|Monitor Status| C[Check Share Status]
    B -->|View Metrics| D[Access Performance Metrics]
    B -->|Manage Backups| E[Backup Operations]
    B -->|HA Management| F[HA Operations]
    B -->|Update Config| G[Configuration Changes]
    B -->|Delete Share| H[Share Deletion]
    
    C --> I[Display Status Information]
    I --> J[Show Quota Usage]
    J --> K[Show HA Status]
    K --> L[Show AD Status]
    
    D --> M[Display I/O Statistics]
    M --> N[Show Connection Stats]
    N --> O[Show System Stats]
    O --> P[Show Historical Data]
    
    E --> Q{Backup Action}
    Q -->|Create Backup| R[Create Snapshot]
    Q -->|Restore Backup| S[Restore from Snapshot]
    Q -->|List Backups| T[Show Backup History]
    Q -->|Test Backup| U[Test Restoration]
    
    F --> V{HA Action}
    V -->|Check Status| W[Show Cluster Health]
    V -->|Trigger Failover| X[Initiate Failover]
    V -->|Test HA| Y[Run HA Tests]
    
    G --> Z{Config Change}
    Z -->|Update Quota| AA[Modify Quota Settings]
    Z -->|Update AD| BB[Modify AD Settings]
    Z -->|Update HA| CC[Modify HA Settings]
    
    H --> DD[Stop Services]
    DD --> EE[Remove Configuration]
    EE --> FF[Clean Up Resources]
    FF --> GG[Delete Share]
```

### 8. CLI Management Flow

```mermaid
flowchart TD
    A[CLI Command] --> B{Command Type}
    
    B -->|List Shares| C[Query API for Shares]
    B -->|Create Share| D[Share Creation Process]
    B -->|Delete Share| E[Share Deletion Process]
    B -->|Status Check| F[Status Query Process]
    B -->|HA Management| G[HA Command Process]
    B -->|AD Management| H[AD Command Process]
    B -->|Metrics| I[Metrics Query Process]
    B -->|Backup| J[Backup Command Process]
    
    C --> K[Display Share List]
    D --> L[Execute Creation Workflow]
    E --> M[Execute Deletion Workflow]
    F --> N[Display Status Information]
    G --> O[Execute HA Operations]
    H --> P[Execute AD Operations]
    I --> Q[Display Metrics Data]
    J --> R[Execute Backup Operations]
    
    K --> S[Format Output]
    L --> S
    M --> S
    N --> S
    O --> S
    P --> S
    Q --> S
    R --> S
    
    S --> T{Output Format}
    T -->|JSON| U[Return JSON Data]
    T -->|Human| V[Format for Human Reading]
    T -->|Table| W[Format as Table]
    
    U --> X[Exit with Status Code]
    V --> X
    W --> X
```

## User Decision Points

### Mode Selection Decision Tree

```mermaid
flowchart TD
    A[Choose Deployment Mode] --> B{Resource Constraints?}
    
    B -->|Minimal Resources| C[LXC Mode]
    B -->|Moderate Resources| D{Isolation Requirements?}
    B -->|High Resources| E{Full Isolation Needed?}
    
    D -->|Low Isolation OK| F[Native Mode]
    D -->|High Isolation| G[VM Mode]
    
    E -->|Yes| G
    E -->|No| H{Performance Critical?}
    
    H -->|Yes| F
    H -->|No| C
    
    C --> I[Lightweight Containers]
    F --> J[Host Installation]
    G --> K[Dedicated VMs]
```

### Feature Selection Decision Tree

```mermaid
flowchart TD
    A[Configure Advanced Features] --> B{Enterprise Environment?}
    
    B -->|Yes| C[Enable AD Integration]
    B -->|No| D[Skip AD Integration]
    
    C --> E{High Availability Needed?}
    D --> E
    
    E -->|Yes| F[Enable CTDB HA]
    E -->|No| G[Skip HA Configuration]
    
    F --> H{Storage Quotas Needed?}
    G --> H
    
    H -->|Yes| I[Configure Quotas]
    H -->|No| J[Skip Quota Configuration]
    
    I --> K[Review Configuration]
    J --> K
    
    K --> L[Create Share]
```

## Error Recovery Paths

### Common Error Scenarios

1. **Template Not Found**
   - Automatic template download
   - Manual template creation option
   - Fallback to generic templates

2. **AD Domain Join Failure**
   - Fallback to local authentication
   - Retry with different credentials
   - Manual domain join option

3. **CTDB Cluster Issues**
   - Automatic cluster reconfiguration
   - Manual cluster setup option
   - Fallback to single-node mode

4. **Quota Application Failure**
   - Fallback to different quota method
   - Continue without quotas
   - Manual quota setup option

5. **Resource Allocation Failure**
   - Automatic resource adjustment
   - Suggest alternative configurations
   - Manual resource allocation

## Success Metrics

### User Experience Metrics

- **Time to First Share**: < 5 minutes for basic setup
- **Success Rate**: > 95% for standard configurations
- **Error Recovery**: < 2 minutes for common errors
- **Feature Adoption**: > 80% for enterprise features

### Technical Metrics

- **Resource Usage**: < 80MB RAM for LXC mode
- **Provisioning Time**: < 30 seconds for LXC, < 2 minutes for VM
- **Failover Time**: < 30 seconds for HA failover
- **Backup Performance**: < 5% performance impact during backup

## Conclusion

The PVE SMB Gateway user process flow is designed to be:

1. **Intuitive**: Clear progression from basic to advanced features
2. **Flexible**: Multiple deployment modes and configuration options
3. **Robust**: Comprehensive error handling and recovery
4. **Efficient**: Optimized for common use cases
5. **Enterprise-Ready**: Full support for enterprise features
6. **User-Friendly**: Helpful guidance and validation throughout

The flow diagrams provide a complete picture of the user journey, from initial setup through ongoing management, ensuring users can successfully deploy and manage SMB shares in their Proxmox environment. 