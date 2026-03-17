# EZOSD Configuration Reference

Complete reference for all EZOSD configuration options.

## Table of Contents

1. [deployment.json Reference](#deploymentjson-reference)
3. [Configuration Examples](#configuration-examples)

## deployment.json Reference

Location: `config\deployment.json` (or USB: `E:\EZOSD\config\deployment.json`)

### Core Settings

#### WindowsVersion
- **Type**: String
- **Required**: Yes
- **Values**: `"11"`
- **Description**: Windows version to deploy
- **Example**:
  ```json
  "WindowsVersion": "11"
  ```

#### Edition
- **Type**: String
- **Required**: Yes
- **Values**: `"Home"`, `"Pro"`, `"Enterprise"`, `"Education"`, etc.
- **Description**: Windows edition to deploy (must match available edition in ESD)
- **Example**:
  ```json
  "Edition": "Pro"
  ```

#### Architecture
- **Type**: String
- **Required**: No
- **Default**: `"x64"`
- **Values**: `"x64"`, `"x86"`, `"arm64"`
- **Description**: System architecture
- **Example**:
  ```json
  "Architecture": "x64"
  ```

### Disk Configuration

#### TargetDisk
- **Type**: String or Integer
- **Required**: Yes
- **Values**: `"auto"`, `"0"`, `"1"`, etc.
- **Description**: Target disk for deployment
  - `"auto"`: Automatically select first suitable disk
  - Number: Specific disk number
- **Example**:
  ```json
  "TargetDisk": "auto"
  ```

#### PartitionScheme
- **Type**: String
- **Required**: Yes
- **Values**: `"UEFI"`, `"BIOS"`
- **Description**: Partition scheme and firmware type
  - `"UEFI"`: GPT partition table (modern systems)
  - `"BIOS"`: MBR partition table (legacy systems)
- **Example**:
  ```json
  "PartitionScheme": "UEFI"
  ```

### Windows Image Source

#### ESDPath
- **Type**: String
- **Required**: No (if `ESDDownloadURL` is provided)
- **Description**: Local or network path to Windows ESD/WIM file
- **Example**:
  ```json
  "ESDPath": "E:\\ISOs\\Windows11_Pro_x64.esd"
  ```
- **Note**: Takes precedence over `ESDDownloadURL`

#### ESDDownloadURL
- **Type**: String
- **Required**: No (if `ESDPath` is provided)
- **Description**: HTTP(S) URL to download Windows ESD
- **Example**:
  ```json
  "ESDDownloadURL": "https://software-server.local/images/Win11Pro.esd"
  ```

#### DownloadPath
- **Type**: String
- **Required**: No
- **Default**: `"C:\\EZOSD\\Downloads"`
- **Description**: Directory path where Windows ESD and other files will be downloaded
- **Important**: Do NOT use `X:\` drive (RAM disk with limited space). Use a physical drive like `C:\`, `D:\`, or a USB drive.
- **Example**:
  ```json
  "DownloadPath": "C:\\EZOSD\\Downloads"
  ```
- **Note**: Windows ESD files are typically 3-5 GB. Ensure the target drive has at least 6 GB of free space.

### Product Key

#### ProductKey
- **Type**: String
- **Required**: No
- **Description**: Windows product key (optional for volume licensing or evaluation)
- **Format**: `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`
- **Example**:
  ```json
  "ProductKey": "VK7JG-NPHTM-C97JM-9MPGT-3V66T"
  ```
- **Security Note**: Do not commit to version control with real keys

### Driver Sources

#### DriverSources
- **Type**: Array of Objects
- **Required**: No
- **Description**: Driver packages to download and inject during deployment

**Driver Source Object Properties**:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `Name` | String | Yes | Friendly name for driver package |
| `Type` | String | Yes | `"URL"`, `"Path"`, or `"Autodetect"` |
| `URL` | String | Conditional | Download URL (required if Type=URL) |
| `Path` | String | Conditional | Local/network path (required if Type=Path) |
| `Enabled` | Boolean | No | Enable this driver source (default: true) |
| `Description` | String | No | Notes about the driver package |

**Example**:
```json
{
  "DriverSources": [
    {
      "Name": "Dell OptiPlex 7090 Drivers",
      "Type": "URL",
      "URL": "https://downloads.dell.com/FOLDER12345/OptiPlex_7090_Drivers.zip",
      "Enabled": true,
      "Description": "Complete driver pack for Dell OptiPlex 7090"
    },
    {
      "Name": "Network Drivers",
      "Type": "Path",
      "Path": "E:\\EZOSD\\drivers\\network",
      "Enabled": true,
      "Description": "Intel and Realtek network drivers"
    }
  ]
}
```

### Post-Installation Script

#### PostInstallScript
- **Type**: String
- **Required**: No
- **Description**: URL of a script to download and execute after Windows installation completes

**Example**:
```json
{
  "PostInstallScript": "https://github.com/your-org/scripts/releases/latest/download/SetupComplete.ps1"
}
```

**Execution**: The script is downloaded and executed during the Windows first-boot Setup phase via SetupComplete.cmd.

### Advanced Settings

The `Advanced` configuration section has been removed. ESD caching and image verification are handled automatically.

## Configuration Examples

### Example 1: Basic Workstation Deployment

```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "ESDDownloadURL": "https://server.local/Win11Pro.esd",
  "DriverSources": [
    {
      "Name": "Intel Drivers",
      "Type": "URL",
      "URL": "https://server.local/drivers/intel-bundle.zip",
      "Enabled": true
    }
  ],
  "PostInstallScripts": []
}
```

### Example 2: Enterprise Domain-Joined Deployment

```json
{
  "WindowsVersion": "11",
  "Edition": "Enterprise",
  "TargetDisk": "0",
  "PartitionScheme": "UEFI",
  "ESDPath": "E:\\ISOs\\Win11Enterprise.esd",
  "ProductKey": "NPPR9-FWDCX-D2C8J-H872K-2YT43",
  "DriverSources": [
    {
      "Name": "Dell Enterprise Drivers",
      "Type": "Path",
      "Path": "\\\\fileserver\\drivers\\Dell_CAB",
      "Enabled": true
    }
  ],
  "PostInstallScripts": [
    "E:\\EZOSD\\scripts\\JoinDomain.ps1",
    "E:\\EZOSD\\scripts\\InstallCorporateApps.ps1"
  ]
}
```

### Example 3: Multi-Site Deployment

Create separate configs:

**Site-Seattle.json**:
```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "ESDPath": "\\\\sea-fileserver\\images\\Win11.esd",
  "Network": {
    "JoinDomain": true,
    "DomainName": "corp.contoso.com",
    "DomainOU": "OU=Seattle,OU=Workstations,DC=corp,DC=contoso,DC=com"
  }
}
```

**Site-NewYork.json**:
```json
{
  "WindowsVersion": "11",
  "Edition": "Pro",
  "TargetDisk": "auto",
  "PartitionScheme": "UEFI",
  "ESDPath": "\\\\nyc-fileserver\\images\\Win11.esd",
  "Network": {
    "JoinDomain": true,
    "DomainName": "corp.contoso.com",
    "DomainOU": "OU=NewYork,OU=Workstations,DC=corp,DC=contoso,DC=com"
  }
}
```

Deploy with:
```powershell
.\Deploy-Windows.ps1 -ConfigPath "E:\EZOSD\config\Site-Seattle.json"
```

---

**See Also**: 
- [USAGE.md](USAGE.md) - Deployment procedures
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
