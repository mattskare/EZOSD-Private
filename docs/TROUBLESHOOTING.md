# EZOSD Troubleshooting Guide

Common issues, solutions, and debugging procedures for EZOSD deployments.

## Table of Contents

1. [USB Boot Issues](#usb-boot-issues)
2. [WinPE Environment Issues](#winpe-environment-issues)
3. [Download and Network Issues](#download-and-network-issues)
4. [Disk and Partition Issues](#disk-and-partition-issues)
5. [Image Deployment Issues](#image-deployment-issues)
6. [Driver Issues](#driver-issues)
7. [Post-Installation Issues](#post-installation-issues)
8. [Error Messages](#common-error-messages)
9. [Diagnostic Tools](#diagnostic-tools)

## USB Boot Issues

### USB Drive Not Booting

**Symptoms**: Computer doesn't boot from USB, shows errors, or boots to existing OS.

**Solutions**:

1. **Verify Boot Order**
   - Enter BIOS/UEFI setup (F2, F12, DEL, or ESC during boot)
   - Set USB as first boot device
   - Save and exit

2. **Disable Secure Boot**
   - For UEFI systems, disable Secure Boot in BIOS
   - Location varies: Security tab, Boot tab, or Advanced settings
   - Required for unsigned WinPE images

3. **Check USB Format**
   - USB must be FAT32 for UEFI boot
   - Verify with: `Get-Volume | Where-Object {$_.DriveLetter -eq 'E'}`
   - Expected: `FileSystemType: FAT32`

4. **Recreate USB**
   ```powershell
   .\build\Create-BootableUSB.ps1 -USBDrive E: -Verbose
   ```

5. **Try Different USB Port**
   - Use USB 2.0 port instead of USB 3.0
   - Try front panel vs. rear ports
   - Avoid USB hubs

### USB Created but Files Missing

**Symptoms**: USB boots but EZOSD files not found.

**Verification**:
```
E:\
├── Boot\
├── EFI\
├── sources\
└── EZOSD\          ← Should exist
    ├── src\
    ├── config\
    └── Deploy-Windows.ps1
```

**Solutions**:

1. **Check EZOSD Directory**
   ```powershell
   # Verify structure
   Get-ChildItem E:\EZOSD -Recurse
   ```

2. **Recreate with Verbose Logging**
   ```powershell
   .\build\Create-BootableUSB.ps1 -USBDrive E: -Verbose
   # Review output for errors
   ```

## WinPE Environment Issues

### PowerShell Not Available

**Symptoms**: `PowerShell.exe` command not found in WinPE.

**Solutions**:

1. **Verify PowerShell Package**
   - PowerShell is added via WinPE-PowerShell.cab during USB creation
   - Must be included in ADK WinPE add-on

2. **Recreate USB with Optional Packages**
   ```powershell
   .\build\Create-BootableUSB.ps1 -USBDrive E: -IncludeOptionalPackages
   ```

3. **Manual Verification**
   - In WinPE command prompt:
   ```cmd
   dir X:\Windows\System32\WindowsPowerShell
   ```
   - Should show PowerShell directory

### DISM Module Not Available

**Symptoms**: `Import-Module DISM` fails or DISM cmdlets unavailable.

**Solutions**:

1. **Check DISM Package**
   ```powershell
   # In WinPE
   Get-WindowsPackage -Path X:\ -Online
   # Look for: Microsoft-Windows-Dism-Cmdlets
   ```

2. **Use DISM.exe Instead**
   - If PowerShell DISM unavailable, DISM.exe is always present
   - Edit modules to use `dism.exe` commands directly

3. **Recreate USB**
   - WinPE-DismCmdlets.cab should be added automatically
   - Verify ADK installation includes DISM tools

### startnet.cmd Not Executing

**Symptoms**: WinPE boots but EZOSD doesn't start automatically.

**Solutions**:

1. **Manual Launch**
   ```cmd
   cd X:\EZOSD
   PowerShell.exe -ExecutionPolicy Bypass -File Deploy-Windows.ps1
   ```

2. **Check startnet.cmd**
   ```cmd
   type X:\Windows\System32\startnet.cmd
   ```
   - Should contain EZOSD launch commands

3. **Verify File Encoding**
   - startnet.cmd must be ASCII encoded
   - No UTF-8 BOM or Unicode

## Download and Network Issues

### Network Not Available in WinPE

**Symptoms**: Cannot ping external hosts, download fails.

**Diagnosis**:
```powershell
# Test connectivity
Test-Connection 8.8.8.8 -Count 4

# Check network adapters
Get-NetAdapter
```

**Solutions**:

1. **Inject Network Drivers**
   - Add network drivers to WinPE during USB creation
   - Or manually inject into boot.wim

2. **Load Network Drivers Manually**
   ```powershell
   # In WinPE
   dism /Image:X:\ /Add-Driver /Driver:E:\Drivers\Network /Recurse
   wpeinit
   ```

3. **Use Local ESD**
   - Copy ESD to USB to avoid network dependency
   - Update deployment.json:
   ```json
   {
     "ESDPath": "E:\\ISOs\\Windows11.esd"
   }
   ```

### ESD Download Fails

**Symptoms**: Download times out, fails, or incomplete. Error message: "Insufficient disk space" or "Not enough space on X: drive".

**Solutions**:

1. **Fix Disk Space Issues (Most Common)**
   
   **Problem**: X: drive is a RAM disk with limited space (typically 512MB-2GB). Windows ESD files are 3-5 GB and won't fit.
   
   **Solution**: Configure download path to use a physical drive in `config\deployment.json`:
   ```json
   {
     "DownloadPath": "C:\\EZOSD\\Downloads"
   }
   ```
   
   **Note**: C: drive becomes available after disk partitioning. Alternatively, use USB drive path like `E:\\EZOSD\\Downloads`.
   
   **Verification**:
   ```powershell
   # Check available space on all drives
   Get-Volume | Select-Object DriveLetter, FileSystemLabel, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}
   ```

2. **Use Pre-Downloaded ESD**
   
   Copy the Windows ESD file to USB before deployment:
   ```json
   {
     "ESDPath": "E:\\ISOs\\Windows11.esd"
   }
   ```
   This avoids downloading entirely.

3. **Verify URL**
   ```powershell
   # Test URL accessibility
   Invoke-WebRequest -Uri "https://your-url/file.esd" -Method Head
   ```
   - ESD files are 3-5 GB
   - WinPE RAM disk must be large enough

3. **Pre-Download ESD**
   ```powershell
   # From full Windows
   Invoke-WebRequest -Uri "URL" -OutFile "E:\Windows11.esd"
   ```

### SSL/TLS Errors

**Symptoms**: `The request was aborted: Could not create SSL/TLS secure channel`

**Solutions**:

```powershell
# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Then retry download
```

## Disk and Partition Issues

### No Suitable Disks Found

**Symptoms**: "No suitable disks available for deployment"

**Diagnosis**:
```powershell
# Check all disks
Get-Disk

# Check disk properties
Get-Disk | Select-Object Number, FriendlyName, Size, BusType, IsBoot
```

**Solutions**:

1. **Disk Too Small**
   - Minimum 32 GB required
   - Increase MinimumSizeGB in configuration

2. **All Disks are USB**
   - Script excludes USB drives (assumes boot drive)
   - Override in `EZOSD-Disk.psm1` if needed

3. **No Online Disks**
   ```powershell
   # Bring disk online
   Get-Disk | Where-Object {$_.OperationalStatus -eq 'Offline'} | Set-Disk -IsOffline $false
   ```

### Disk Partitioning Fails

**Symptoms**: Errors during `Initialize-EZOSDDisk`

**Solutions**:

1. **Disk Not Clean**
   ```powershell
   # Manually clean disk
   Clear-Disk -Number 0 -RemoveData -RemoveOEM -Confirm:$false
   ```

2. **Protected Partitions**
   ```powershell
   # List partitions
   Get-Partition -DiskNumber 0
   
   # Remove all partitions
   Get-Partition -DiskNumber 0 | Remove-Partition -Confirm:$false
   ```

3. **GPT/MBR Mismatch**
   - UEFI requires GPT (PartitionScheme: "UEFI")
   - BIOS requires MBR (PartitionScheme: "BIOS")
   - Verify in deployment.json

### Cannot Format Partition

**Symptoms**: Format-Volume fails

**Solutions**:

1. **Use Quick Format**
   ```powershell
   Format-Volume -Partition $partition -FileSystem NTFS -QuickFormat
   ```

2. **Check for Bad Sectors**
   - Disk may be failing
   - Try different disk

## Image Deployment Issues

### ESD File Invalid

**Symptoms**: "ESD validation failed", "Cannot get image info"

**Diagnosis**:
```powershell
# Verify ESD integrity
Get-WindowsImage -ImagePath "X:\Windows\install.esd"
```

**Solutions**:

1. **Re-download ESD**
   - File may be corrupted during download
   - Verify file size matches expected

2. **Check File Format**
   - Must be ESD or WIM format
   - ISO files must be extracted first

3. **Use WIM Instead of ESD**
   - Convert ESD to WIM if issues persist
   ```powershell
   # From full Windows with DISM
   dism /Export-Image /SourceImageFile:install.esd /SourceIndex:1 /DestinationImageFile:install.wim /Compress:max
   ```

### Image Application Takes Too Long

**Symptoms**: Deployment stuck at "Applying Windows image"

**Solutions**:

1. **Check Progress**
   - Large images (15+ GB) take 10-20 minutes
   - Monitor DISM progress in logs

2. **Disk Performance**
   - Slow USB drives impact speed
   - Target disk speed matters (HDD vs SSD)

3. **Normal Duration**:
   - SSD: 5-10 minutes
   - HDD: 10-20 minutes
   - USB 2.0: 20-40 minutes

### Wrong Edition Deployed

**Symptoms**: Installed edition doesn't match configuration

**Solutions**:

1. **Verify Available Editions**
   ```powershell
   Get-WindowsImage -ImagePath "install.esd"
   # Lists all available editions
   ```

2. **Explicit Index Selection**
   ```powershell
   # Use -Interactive to select edition
   .\Deploy-Windows.ps1 -Interactive
   ```

3. **Check Edition Name Matching**
   - Edition name must match exactly
   - "Professional" vs "Pro"
   - Case-insensitive but spelling matters

## Driver Issues

### Drivers Not Injected

**Symptoms**: Drivers missing after deployment, hardware not working

**Diagnosis**:
```powershell
# Check driver injection logs
Get-Content X:\Windows\Logs\EZOSD\*.log | Select-String "driver"
```

**Solutions**:

1. **Verify Driver Path**
   ```powershell
   # Check driver source exists
   Test-Path "E:\EZOSD\drivers\network"
   
   # Check for INF files
   Get-ChildItem "E:\EZOSD\drivers" -Filter *.inf -Recurse
   ```

2. **Enable Driver Sources**
   - In deployment.json, set `"Enabled": true`

3. **Manual Driver Injection**
   ```powershell
   # After image deployment, before reboot
   Add-WindowsDriver -Path "C:\" -Driver "E:\Drivers" -Recurse
   ```

### Driver Download Fails

**Symptoms**: Cannot download driver packages

**Solutions**:

1. **Check URLs**
   - Verify driver package URLs are accessible
   ```powershell
   Invoke-WebRequest -Uri "driver-url" -Method Head
   ```

2. **Use Local Drivers**
   - Copy drivers to USB
   - Update configuration to use local path

3. **Network Connectivity**
   - Ensure network drivers injected in WinPE
   - Test connectivity before driver download phase

### Unsigned Driver Errors

**Symptoms**: "Driver signature verification failed"

**Solutions**:

1. **Force Unsigned Drivers**
   - Add-WindowsDriver uses `-ForceUnsigned` by default in EZOSD

2. **Disable Driver Signature Enforcement** (Post-Install)
   ```cmd
   bcdedit /set nointegritychecks on
   bcdedit /set testsigning on
   ```

## Post-Installation Issues

### SetupComplete.cmd Not Executing

**Symptoms**: Post-install scripts didn't run

**Diagnosis**:
```powershell
# Check execution log
Get-Content "C:\Windows\Logs\EZOSD\PostInstall.log"

# Verify SetupComplete.cmd exists
Test-Path "C:\Windows\Setup\Scripts\SetupComplete.cmd"
```

**Solutions**:

1. **Check File Location**
   - Must be: `C:\Windows\Setup\Scripts\SetupComplete.cmd`
   - Created by EZOSD during deployment

2. **Manual Execution**
   ```cmd
   C:\Windows\Setup\Scripts\SetupComplete.cmd
   ```

3. **Check Script Syntax**
   - Review SetupComplete.cmd for errors
   - Test scripts individually

### Scripts Fail with Execution Policy

**Symptoms**: PowerShell scripts blocked by execution policy

**Solutions**:

```powershell
# In SetupComplete.cmd, scripts should use:
PowerShell.exe -ExecutionPolicy Bypass -File "script.ps1"

# Or set globally (not recommended)
Set-ExecutionPolicy Unrestricted -Force
```

## Common Error Messages

### "Not running in a valid WinPE environment"

**Cause**: Script detected it's not in WinPE

**Solution**:
- For testing in full Windows, ignore warning
- For production, always run from WinPE USB

### "Configuration file not found"

**Cause**: deployment.json missing or wrong path

**Solution**:
```powershell
# Verify path
Test-Path "X:\EZOSD\config\deployment.json"

# Specify custom path
.\Deploy-Windows.ps1 -ConfigPath "E:\custom-config.json"
```

### "Failed to initialize disk"

**Cause**: Disk locked, in use, or hardware issue

**Solution**:
```powershell
# Clear all locks
Get-Disk -Number 0 | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false

# Check disk health
Get-Disk -Number 0 | Get-PhysicalDisk | Select-Object HealthStatus
```

### "BCDBoot failed with exit code X"

**Cause**: Boot configuration failed

**Solutions**:

1. **Check Partition Scheme Match**
   - UEFI system + BIOS deployment = failure
   - BIOS system + UEFI deployment = failure

2. **Manual BCDBoot**
   ```cmd
   rem For UEFI
   bcdboot C:\Windows /s S: /f UEFI
   
   rem For BIOS
   bcdboot C:\Windows /s S: /f BIOS
   ```

## Diagnostic Tools

### Log Analysis

**Primary Log Location**:
```powershell
# During deployment
X:\Windows\Logs\EZOSD\EZOSD_TIMESTAMP.log

# After deployment
C:\Windows\Logs\EZOSD\EZOSD_TIMESTAMP.log
C:\Windows\Logs\EZOSD\PostInstall.log
```

**Review Logs**:
```powershell
# Search for errors
Get-Content EZOSD_*.log | Select-String -Pattern "ERROR|FAILED|Exception"

# View recent entries
Get-Content EZOSD_*.log -Tail 100

# Filter by level
Get-Content EZOSD_*.log | Select-String "Error"
```

### System Information

**Gather Hardware Info**:
```powershell
# Computer info
Get-WmiObject Win32_ComputerSystem

# Disk info
Get-Disk | Format-Table

# Network adapters
Get-NetAdapter

# Firmware type
$env:firmware_type  # UEFI or Legacy
```

### Network Diagnostics

```powershell
# Test connectivity
Test-Connection 8.8.8.8 -Count 4
Test-Connection google.com

# DNS resolution
Resolve-DnsName microsoft.com

# Network configuration
Get-NetIPConfiguration
```

### DISM Diagnostics

```powershell
# Check image health
Dism /Image:C:\ /Cleanup-Image /CheckHealth

# Scan image
Dism /Image:C:\ /Cleanup-Image /ScanHealth

# List drivers in image
Dism /Image:C:\ /Get-Drivers

# Get image info
Dism /Get-ImageInfo /ImageFile:install.esd
```

## Getting Help

### Collect Diagnostic Information

Before requesting support, collect:

1. **Logs**
   - All files from `X:\Windows\Logs\EZOSD\`
   - Windows Setup logs: `C:\Windows\Panther\setupact.log`

2. **Configuration**
   - deployment.json (redact sensitive info)

3. **System Info**
   ```powershell
   # Export system info
   Get-ComputerInfo | Out-File SystemInfo.txt
   Get-Disk | Out-File DiskInfo.txt
   ```

4. **Error Screenshots**
   - Capture error messages
   - Include full context

### Enable Debug Logging

```powershell
# Run with debug logging
.\Deploy-Windows.ps1 -LogLevel Debug

# More verbose output
.\Deploy-Windows.ps1 -LogLevel Debug -Verbose
```

### Reset and Retry

**Complete Reset**:
```powershell
# 1. Clean target disk
Get-Disk -Number 0 | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false

# 2. Unmount any mounted images (if stuck)
Get-WindowsImage -Mounted | Dismount-WindowsImage -Discard

# 3. Retry deployment
.\Deploy-Windows.ps1 -Interactive -LogLevel Debug
```

---

**Additional Resources**:
- [Microsoft DISM Documentation](https://learn.microsoft.com/windows-hardware/manufacture/desktop/dism)
- [WinPE Documentation](https://learn.microsoft.com/windows-hardware/manufacture/desktop/winpe-intro)
- [Windows ADK Download](https://learn.microsoft.com/windows-hardware/get-started/adk-install)
