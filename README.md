# EZOSD - Enterprise Zero-Touch Operating System Deployment

**EZOSD** is a PowerShell-based Windows deployment tool designed for enterprise IT environments. It automates the deployment of Windows from bootable USB, PXE, or HTTPS sources using WinPE environments.

## Features

- **Automated Windows Deployment**: Download and deploy Windows ESD images directly from Microsoft
- **Intelligent Disk Partitioning**: Automatic UEFI (GPT) and BIOS (MBR) partitioning
- **Driver Management**: Download and inject drivers during deployment
- **Post-Installation Automation**: Execute custom scripts after Windows installation
- **Windows Autopilot Support**: Cloud-based provisioning via Azure AD/Intune
- **Enterprise-Ready**: Configuration-driven, modular architecture with comprehensive logging
- **Multi-Edition Support**: Deploy Windows Pro, Enterprise, or other editions

## Prerequisites

### For Building Bootable USB
- Windows 10/11 or Windows Server 2016+
- Windows Assessment and Deployment Kit (ADK) installed
- Administrator privileges
- USB drive (16GB+ recommended)

### For Deployment
- WinPE environment (created by build script)
- Target device with UEFI or BIOS support
- Network connectivity (for ESD download and driver retrieval)

## Quick Start

### 1. Prepare Your Environment
```powershell
# Install Windows ADK from Microsoft
# Download from: https://learn.microsoft.com/windows-hardware/get-started/adk-install
```

### 2. Configure Deployment
Edit `config\deployment.json` to specify:
- Windows version and edition
- ESD download source
- Disk configuration
- Driver sources
- Post-installation scripts

### 3. Build Bootable USB
```powershell
# Run as Administrator
.\build\Create-BootableUSB.ps1 -USBDrive E: -Verbose
```

### 4. Deploy Windows
1. Boot target device from USB
2. WinPE will automatically launch EZOSD
3. Follow on-screen prompts or let automated deployment proceed
4. Monitor deployment progress and logs

## Project Structure

```
EZOSD/
├── src/                    # PowerShell modules
│   ├── EZOSD-Core.psm1    # Core orchestration and initialization
│   ├── EZOSD-Download.psm1 # ESD download functionality
│   ├── EZOSD-Disk.psm1    # Disk partitioning and formatting
│   ├── EZOSD-Image.psm1   # Windows image deployment
│   ├── EZOSD-Driver.psm1  # Driver management
│   ├── EZOSD-PostInstall.psm1 # Post-installation automation
│   └── EZOSD-Logger.psm1  # Logging infrastructure
├── config/                # Configuration files
│   └── deployment.json    # Main deployment configuration
├── build/                 # Build scripts
│   └── Create-BootableUSB.ps1 # USB creation script
├── scripts/               # Helper scripts
├── drivers/               # Driver package storage
├── docs/                  # Documentation
└── Deploy-Windows.ps1     # Main deployment entry point
```

## Configuration

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for detailed configuration options.

Example minimal configuration:
```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "DriverSources": [],
  "PostInstallScripts": []
}
```

## Deployment Scenarios

### USB Boot (Current)
Boot from USB drive with WinPE environment containing EZOSD.

### Windows Autopilot Integration
EZOSD supports Windows Autopilot deployments for cloud-based device provisioning:

1. EZOSD will:
   - Deploy the base Windows image
   - Inject critical drivers (e.g., network drivers)
   - Allow Autopilot to handle OOBE and provisioning

2. After deployment, the device boots into Autopilot OOBE where:
   - User signs in with Azure AD/Entra ID credentials
   - Device automatically enrolls in Intune
   - Policies and applications are deployed from the cloud

**Requirements**: Device must be registered in Autopilot, and Autopilot profile must be assigned in Intune.

### PXE Boot (Planned)
Network boot for enterprise environments with PXE infrastructure.

### HTTPS Boot (Planned)
Cloud-based deployment over HTTPS for modern UEFI systems.

## Logging

Deployment logs are stored in:
- **WinPE**: `X:\Windows\Logs\EZOSD\`
- **Deployed System**: `C:\Windows\Logs\EZOSD\`

Log files include timestamps, severity levels, and detailed operation information.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

## Contributing

Contributions are welcome! Please ensure:
- PowerShell code follows best practices
- Functions include comment-based help
- Changes are tested in WinPE environment
- Documentation is updated accordingly

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or feature requests, please create an issue on the project repository.

## Version

Current version: See [VERSION](VERSION) file.

---

**EZOSD** - Simplifying enterprise Windows deployment.
