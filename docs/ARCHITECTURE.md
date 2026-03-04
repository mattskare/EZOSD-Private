# EZOSD Architecture

## Overview

EZOSD (Enterprise Zero-Touch Operating System Deployment) is a modular PowerShell-based Windows deployment solution designed for enterprise IT environments. It operates within WinPE and automates the complete deployment workflow from image acquisition to post-installation configuration.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     WinPE Boot Environment                  │
├─────────────────────────────────────────────────────────────┤
│  startnet.cmd → PowerShell → Deploy-Windows.ps1            │
└────────────────────┬────────────────────────────────────────┘
                     │
          ┌──────────▼─────────────┐
          │   EZOSD-Core Module    │  ← Configuration & Orchestration
          └──────────┬─────────────┘
                     │
       ┌─────────────┼─────────────┬─────────────┬─────────────┐
       │             │             │             │             │
  ┌────▼───┐  ┌─────▼────┐  ┌────▼────┐  ┌─────▼────┐  ┌────▼────┐
  │Download│  │   Disk   │  │  Image  │  │  Driver  │  │PostInst │
  │ Module │  │  Module  │  │ Module  │  │  Module  │  │ Module  │
  └────┬───┘  └─────┬────┘  └────┬────┘  └─────┬────┘  └────┬────┘
       │            │            │             │             │
  [ESD Files]  [Partitions]  [Windows]    [Drivers]   [Scripts]
                     │            │             │             │
                     └────────────┼─────────────┴─────────────┘
                                  │
                          ┌───────▼────────┐
                          │  Target Disk   │
                          │  (C:\Windows)  │
                          └────────────────┘
```

## Core Components

### 1. Deploy-Windows.ps1 (Main Entry Point)

**Responsibility**: Orchestrates the entire deployment workflow.

**Key Functions**:
- Parameter parsing and validation
- Module loading and initialization
- Workflow execution
- Error handling and reporting
- User interaction and progress display

**Workflow**:
1. Initialize logging and configuration
2. Validate WinPE environment
3. Download/locate Windows ESD
4. Select and prepare target disk
5. Apply Windows image
6. Inject drivers
7. Configure post-installation
8. Set boot configuration
9. Report completion

### 2. EZOSD-Core Module

**Responsibility**: Core initialization, configuration management, and environment validation.

**Key Functions**:
- `Initialize-EZOSD`: Initialize logging, load configuration
- `Get-EZOSDConfiguration`: Load and validate deployment.json
- `Test-WinPEEnvironment`: Validate WinPE prerequisites
- `Test-NetworkConnectivity`: Check network availability
- `Get-DeploymentStatistics`: Track deployment metrics

**Data Flow**:
```
deployment.json → Get-EZOSDConfiguration → Validation → Global Config Object
```

### 3. EZOSD-Logger Module

**Responsibility**: Centralized logging infrastructure.

**Features**:
- Multi-level logging (Debug, Info, Warning, Error)
- Console and file output
- Timestamped entries
- Exception tracking

**Log Locations**:
- WinPE: `X:\Windows\Logs\EZOSD\`
- Deployed System: `C:\Windows\Logs\EZOSD\`

### 4. EZOSD-Download Module

**Responsibility**: Windows ESD acquisition and validation.

**Key Functions**:
- `Get-WindowsESD`: Download Windows ESD from configured sources
- `Invoke-EZOSDDownload`: HTTP download with progress tracking
- `Test-ESDFile`: Validate ESD integrity using DISM
- `Get-ESDImageInfo`: Extract image metadata

**Download Methods**:
1. **Local Path**: Use pre-downloaded ESD from configuration
2. **Direct URL**: Download from configured URL
3. **BITS Transfer**: Resumable downloads when available
4. **WebClient Fallback**: Standard HTTP download

### 5. EZOSD-Disk Module

**Responsibility**: Disk detection, partitioning, and formatting.

**Partition Schemes**:

**UEFI (GPT)**:
- EFI System Partition (ESP): 512 MB, FAT32
- Microsoft Reserved (MSR): 128 MB
- Windows Partition: Remaining space, NTFS

**BIOS (MBR)**:
- System Reserved: 500 MB, NTFS, Active
- Windows Partition: Remaining space, NTFS

**Key Functions**:
- `Get-EZOSDTargetDisk`: Enumerate suitable disks
- `Select-EZOSDTargetDisk`: Interactive/automatic disk selection
- `Initialize-EZOSDDisk`: Clean, partition, and format disk
- `New-EZOSDUEFIPartitions`: Create GPT partition layout
- `New-EZOSDBIOSPartitions`: Create MBR partition layout

### 6. EZOSD-Image Module

**Responsibility**: Windows image deployment and boot configuration.

**Key Functions**:
- `Install-WindowsImage`: Apply ESD/WIM using DISM
- `Set-WindowsBootConfiguration`: Configure boot loader (UEFI/BIOS)
- `Select-WindowsEdition`: Choose Windows edition from multi-edition ESD
- `Optimize-WindowsImage`: DISM cleanup and optimization

**Image Deployment Process**:
```
ESD File → Select Edition → Expand-WindowsImage → Target Partition
                                    │
                                    ▼
                            BCDBoot (Boot Config)
```

### 7. EZOSD-Driver Module

**Responsibility**: Driver download, extraction, and injection.

**Key Functions**:
- `Get-DriverPackage`: Download driver packages
- `Expand-DriverPackage`: Extract ZIP/CAB/EXE packages
- `Add-DriversToImage`: Inject drivers into offline Windows image
- `Get-SystemHardwareInfo`: Detect hardware for driver matching
- `Install-ConfiguredDrivers`: Process driver configuration

**Supported Package Formats**:
- ZIP archives
- CAB files
- Self-extracting EXE (best-effort)

### 8. EZOSD-PostInstall Module

**Responsibility**: Post-installation automation setup.

**Key Functions**:
- `New-SetupCompleteScript`: Create SetupComplete.cmd
- `Copy-PostInstallScripts`: Deploy custom scripts
- `Set-PostInstallConfiguration`: Orchestrate post-install setup

**Post-Install Execution Flow**:
```
Windows First Boot → OOBE → Autopilot Enrollment → Azure AD/Intune Provisioning → Custom Scripts (optional)
```

**Script Locations in Deployed Image**:
- `C:\Windows\Setup\Scripts\SetupComplete.cmd`: Main post-install script (optional)
- `C:\Windows\Setup\Scripts\PostInstall\`: Custom scripts (if configured)

## Configuration System

### deployment.json Structure

```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "ESDPath": "",
  "ESDDownloadURL": "",
  "DriverSources": [],
  "PostInstallScripts": [],
  "Customization": {},
  "Network": {},
  "Advanced": {}
}
```

**Configuration Loading**:
1. Parse JSON file
2. Validate required fields
3. Apply defaults for optional fields
4. Make available globally via `Get-CurrentConfiguration`

## Boot Media Creation

### Create-BootableUSB.ps1 Workflow

```
Windows + ADK
    │
    ├─► copype.cmd → Base WinPE
    │
    ├─► Mount boot.wim
    │
    ├─► Add Packages (PowerShell, DISM, NetFX)
    │
    ├─► Copy EZOSD Files
    │
    ├─► Create startnet.cmd
    │
    ├─► Dismount and Save
    │
    └─► MakeWinPEMedia → Bootable USB
```

## Data Flow

### Complete Deployment Data Flow

```
User Boots from USB
        │
        ▼
startnet.cmd executes
        │
        ▼
Deploy-Windows.ps1 launched
        │
        ├─► Load Modules
        ├─► Initialize Logger
        ├─► Load deployment.json
        │
        ▼
Download/Locate ESD
        │
        ▼
Select Target Disk
        │
        ▼
Partition & Format Disk
        │
        ▼
Apply Windows Image (DISM)
        │
        ▼
Download & Inject Drivers (DISM)
        │
        ▼
Copy Post-Install Scripts
        │
        ├─► Create SetupComplete.cmd (if scripts configured)
        │
        ▼
Configure Boot (BCDBoot)
        │
        ▼
User Reboots
        │
        ▼
┌───────────────────────────────────┐
│  Windows Autopilot:               │
│  Windows OOBE                     │
│  (Interactive Autopilot flow)     │
│         ▼                         │
│  Autopilot Enrollment             │
│         ▼                         │
│  Azure AD/Intune Provisioning     │
│         ▼                         │
│  SetupComplete.cmd (optional)     │
│         ▼                         │
│  Deployment Complete              │
└───────────────────────────────────┘
```

## Error Handling Strategy

### Error Handling Hierarchy

1. **Module Level**: Try/catch with logging via `Write-EZOSDError`
2. **Workflow Level**: Validate prerequisites before operations
3. **User Level**: Clear error messages with log file references

### Recovery Mechanisms

- **Image Mount Failures**: Auto-dismount on script exit
- **Download Failures**: Cached ESD reuse
- **Driver Injection Warnings**: Non-fatal, continue deployment
- **Network Unavailable**: Skip online components

## Security Considerations

### Credential Handling

- Product keys stored in plain text configuration (avoid in VCS)
- Domain credentials optionally encrypted in configuration
- Network credentials passed to post-install scripts securely

### Image Integrity

- DISM validation of ESD/WIM files before deployment
- Optional integrity checks via `Test-ESDFile`

## Performance Optimization

### Image Deployment

- **DISM Expand-WindowsImage**: Native, efficient expansion
- **Multi-threaded**: DISM handles parallel decompression

### Driver Injection

- **Offline Injection**: Faster than online injection
- **Recursive INF Search**: Batch driver addition

### Network Operations

- **BITS Transfer**: Resumable, background downloads
- **Cached ESDs**: Avoid repeated downloads

## Extensibility Points

### Custom Modules

Add custom modules by:
1. Creating `.psm1` file in `src/`
2. Importing in `Deploy-Windows.ps1`
3. Calling functions in workflow

### Custom Post-Install Scripts

Add scripts in `PostInstallScripts` array:
- PowerShell (.ps1)
- Batch files (.cmd, .bat)
- Executables (.exe)

### PXE/HTTPS Expansion

Future support for:
- **PXE**: Network boot using WDS/SCCM integration
- **HTTPS**: iPXE boot with HTTP(S) image sources

## Technology Stack

- **Language**: PowerShell 5.1+ (WinPE compatible)
- **Image Management**: DISM PowerShell module
- **Disk Management**: Storage PowerShell module
- **Configuration**: JSON
- **Boot Environment**: Windows PE (ADK)
- **Deployment Tools**: BCDBoot, DISM.exe, diskpart

## Standards and Conventions

### Coding Standards

- **Naming**: `Verb-EZOSDNoun` for exported functions
- **Parameters**: CmdletBinding with validation
- **Comments**: Synopsis, description, examples
- **Error Handling**: Try/catch with logging

### File Organization

- **Modules**: `src/*.psm1`
- **Configuration**: `config/*.json`, `config/*.xml`
- **Scripts**: `scripts/*.ps1`
- **Documentation**: `docs/*.md`
- **Build**: `build/*.ps1`

---

**Version**: 0.1.0-alpha  
**Last Updated**: February 2026
