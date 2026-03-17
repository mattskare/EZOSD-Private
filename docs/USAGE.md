# EZOSD Usage Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Creating Bootable USB](#creating-bootable-usb)
4. [Configuring Deployment](#configuring-deployment)
5. [Deploying Windows](#deploying-windows)
6. [Advanced Usage](#advanced-usage)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software

#### For Building Bootable USB
- **Windows 10/11** or **Windows Server 2016+**
- **Windows Assessment and Deployment Kit (ADK)** for Windows 11 v22H2 or later
  - Download: [Microsoft ADK Download](https://learn.microsoft.com/windows-hardware/get-started/adk-install)
  - **Required Components**:
    - Deployment Tools
    - Windows Preinstallation Environment (Windows PE)
- **Administrator Privileges**
- **USB Drive** (8GB+ recommended, 16GB+ for multiple editions)

#### For Deployment
- **Target Device** with UEFI or BIOS support
- **Network Connectivity** (for downloading Windows ESD and drivers)
- **Minimum Target Disk Size**: 64GB recommended (32GB minimum)

### Optional Software

- **Git** (for version control)
- **Visual Studio Code** (for editing configurations and scripts)

## Initial Setup

### 1. Install Windows ADK

```powershell
# Download ADK installer from Microsoft
# Run installer and select:
# - Deployment Tools
# - Windows Preinstallation Environment (Windows PE)

# Verify installation
Test-Path "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
```

### 2. Clone or Download EZOSD

```powershell
# Option 1: Clone with Git
git clone <repository-url> C:\EZOSD

# Option 2: Download and extract ZIP
# Extract to C:\EZOSD
```

### 3. Review Project Structure

```
C:\EZOSD\
├── src\                    # PowerShell modules
├── config\                 # Configuration files
├── build\                  # Build scripts
├── postInstallScripts\     # Post-installation scripts
├── docs\                   # Documentation
├── Deploy-Windows.ps1      # Main deployment script
├── README.md
└── VERSION
```

## Creating Bootable USB

### Basic USB Creation

```powershell
# Open PowerShell as Administrator
cd C:\EZOSD

# Insert USB drive and note drive letter (e.g., E:)

# Create bootable USB
.\build\Create-BootableUSB.ps1 -USBDrive E:
```

**Interactive Process**:
1. Script detects Windows ADK
2. Prompts for confirmation (ALL DATA ON USB WILL BE ERASED)
3. Type `YES` to confirm
4. Wait for build process to complete (5-15 minutes)

### Advanced USB Creation Options

#### Include Optional Packages

Adds additional WinPE packages:

```powershell
.\build\Create-BootableUSB.ps1 -USBDrive E: -IncludeOptionalPackages
```

#### Verbose Output

Enable detailed logging during build:

```powershell
.\build\Create-BootableUSB.ps1 -USBDrive E: -Verbose
```

## Configuring Deployment

### 1. Edit deployment.json

After creating bootable USB, configuration file is located at:
```
E:\EZOSD\config\deployment.json
```

**Basic Configuration**:

```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "ESDDownloadURL": "https://your-server.com/Windows11_Pro_x64.esd"
}
```

### 2. Windows ESD Configuration

**Option A: Download from URL**

```json
{
  "ESDDownloadURL": "https://example.com/Windows11.esd"
}
```

**Option B: Use Local Path**

```json
{
  "ESDPath": "E:\\ISOs\\Windows11.esd"
}
```

**Note**: Copy ESD file to USB drive if using local path approach.

### 3. Driver Configuration

**Add Driver Sources**:

```json
{
  "DriverSources": [
    {
      "Name": "Intel Network Drivers",
      "Type": "URL",
      "URL": "https://downloadcenter.intel.com/drivers/network.zip",
      "Enabled": true
    },
    {
      "Name": "Local Storage Drivers",
      "Type": "Path",
      "Path": "E:\\EZOSD\\drivers\\storage",
      "Enabled": true
    }
  ]
}
```

### 4. Post-Installation Scripts

**Configure Scripts to Run After Installation**:

```json
{
  "PostInstallScripts": [
    "E:\\EZOSD\\scripts\\ConfigureWindows.ps1",
    "E:\\EZOSD\\scripts\\InstallSoftware.cmd"
  ]
}
```

**Note**: Copy custom scripts to USB drive before deployment.

## Deploying Windows

### Standard Deployment Workflow

#### 1. Prepare Target Device

- Boot device from USB
  - **UEFI**: Press F12/F11/ESC (varies by manufacturer) during boot
  - **BIOS**: Configure boot order in BIOS setup
- Ensure Secure Boot is disabled (if troubleshooting boot issues)

#### 2. WinPE Boot

- USB boots into WinPE environment
- startnet.cmd executes automatically
- EZOSD banner displays

#### 3. Start Deployment

Deployment starts automatically after WinPE boots.

**Manual Mode**:
```powershell
# At WinPE command prompt
PowerShell.exe -ExecutionPolicy Bypass -File X:\EZOSD\Deploy-Windows.ps1
```

**Interactive Mode**:
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File X:\EZOSD\Deploy-Windows.ps1 -Interactive
```

#### 4. Deployment Process

Progress indicators show:
```
[Step 1/6] Windows ESD Acquisition
  ✓ ESD located: X:\Windows\install.esd

[Step 2/6] Disk Selection
  ✓ Selected disk 0: 256.00 GB

[Step 3/6] Disk Partitioning
  ✓ Disk partitioned successfully
    System: S:
    Windows: C:

[Step 4/6] Windows Image Deployment
  ✓ Windows image applied successfully

[Step 5/6] Driver Installation
  ✓ Drivers installed successfully

[Step 6/6] Post-Installation Configuration
  ✓ Post-installation configured

Configuring boot loader...
  ✓ Boot configuration completed

╔═══════════════════════════════════════════════════════════════╗
║              DEPLOYMENT COMPLETED SUCCESSFULLY                ║
╚═══════════════════════════════════════════════════════════════╝
```

#### 5. Post-Deployment

1. Remove USB drive
2. Restart computer
3. Windows boots into Autopilot OOBE
4. SetupComplete.cmd executes post-install scripts if configured
5. Device provisioning completed via Azure AD/Intune

### Deployment Time Estimates

| Activity | Typical Time |
|----------|--------------|
| ESD Download (4GB) | 5-15 minutes (depends on network) |
| Disk Partitioning | 30 seconds |
| Image Application | 5-10 minutes |
| Driver Injection | 2-5 minutes |
| Boot Configuration | 30 seconds |
| **Total** | **15-30 minutes** |

## Advanced Usage

### Command-Line Parameters

```powershell
Deploy-Windows.ps1 [parameters]
```

**Available Parameters**:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ConfigPath` | Path to deployment.json | `config\deployment.json` |
| `-LogLevel` | Logging verbosity | `Info` |
| `-Interactive` | Enable user prompts | `$false` |
| `-SkipDrivers` | Skip driver installation | `$false` |
| `-SkipPostInstall` | Skip post-install config | `$false` |

**Examples**:

```powershell
# Debug mode with custom config
.\Deploy-Windows.ps1 -ConfigPath "C:\CustomConfig.json" -LogLevel Debug

# Skip drivers and post-install
.\Deploy-Windows.ps1 -SkipDrivers -SkipPostInstall

# Interactive mode with prompts
.\Deploy-Windows.ps1 -Interactive
```

### Multi-Edition Deployment

**Interactive Edition Selection**:

```powershell
.\Deploy-Windows.ps1 -Interactive
```

User will be prompted to select edition:
```
Available Windows editions:
  [1] Windows 11 Home
  [2] Windows 11 Pro
  [3] Windows 11 Enterprise

Select edition index: 2
```

### Custom Disk Selection

**Specify Target Disk**:

```json
{
  "TargetDisk": "1"
}
```

**Interactive Disk Selection**:

With `-Interactive`, user chooses from available disks:
```
Available disks for deployment:
  [0] 256.00 GB - Samsung SSD 960 EVO
  [1] 1000.00 GB - WDC WD10EZEX

Select disk number: 0
```

### Network Deployment Scenarios

**Using Network Share for ESD**:

```json
{
  "ESDPath": "\\\\server\\share\\ISOs\\Windows11.esd"
}
```

Requires network connectivity in WinPE (inject network drivers).

### Automated Deployment

Complete hands-off deployment:

1. Configure all options in deployment.json
2. Set `TargetDisk` to specific disk number
3. Boot device from USB
4. Deployment proceeds automatically

## Logs and Diagnostics

### Log Locations

**During Deployment (WinPE)**:
```
X:\Windows\Logs\EZOSD\EZOSD_YYYYMMDD_HHMMSS.log
```

**After Deployment**:
```
C:\Windows\Logs\EZOSD\
```

### Log Levels

- **Debug**: Detailed operational information
- **Info**: General progress and status
- **Warning**: Non-critical issues
- **Error**: Failures and exceptions

### Reviewing Logs

```powershell
# In WinPE
notepad X:\Windows\Logs\EZOSD\EZOSD_*.log

# After deployment
notepad C:\Windows\Logs\EZOSD\EZOSD_*.log
notepad C:\Windows\Logs\EZOSD\PostInstall.log
```

## Best Practices

### Configuration Management

1. **Version Control**: Keep deployment.json in version control
2. **Environment-Specific Configs**: Create separate configs for dev/test/prod
3. **Secrets Management**: Don't commit product keys or credentials

### Driver Management

1. **Cache Drivers**: Pre-download drivers to USB to avoid repeated downloads
2. **Vendor-Specific Packages**: Use manufacturer driver packs (Dell, HP, Lenovo)
3. **Test Injection**: Verify drivers work before mass deployment

### Testing

1. **Virtual Machines**: Test deployments in VMs before physical hardware
2. **Hyper-V**: Use Generation 2 VMs for UEFI testing
3. **VMware**: Configure EFI firmware for UEFI testing

### Performance Optimization

1. **USB 3.0**: Use USB 3.0 drive and port for faster performance
2. **Local ESD**: Copy ESD to USB to avoid download on every deployment
3. **SSD Targets**: Deploy to SSD for faster image application

---

**Next Steps**: See [CONFIGURATION.md](CONFIGURATION.md) for detailed configuration reference.
