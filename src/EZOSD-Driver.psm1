<#
.SYNOPSIS
    EZOSD Driver Management Module
.DESCRIPTION
    Handles driver download, extraction, and injection during deployment.
#>

using module .\EZOSD-Logger.psm1

function Get-DriverPackage {
    <#
    .SYNOPSIS
        Downloads driver package from URL.
    .PARAMETER Url
        URL to download driver from.
    .PARAMETER DestinationPath
        Where to save the driver package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $false)]
        [string]$DestinationPath = "C:\EZOSD\Downloads\Drivers"
    )
    
    try {
        Write-EZOSDLog -Message "Downloading driver package from: $Url" -Level Info
        
        # Create destination directory
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        
        # Determine filename from URL
        $fileName = Split-Path $Url -Leaf
        $destinationFile = Join-Path $DestinationPath $fileName
        
        # Download using Invoke-WebRequest
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $destinationFile
        
        Write-EZOSDLog -Message "Driver package downloaded: $destinationFile" -Level Info
        return $destinationFile
    }
    catch {
        Write-EZOSDError -Message "Failed to download driver package" -Exception $_.Exception
        throw
    }
}

function Expand-DriverPackage {
    <#
    .SYNOPSIS
        Extracts driver package.
    .PARAMETER PackagePath
        Path to driver package (ZIP, CAB, EXE).
    .PARAMETER DestinationPath
        Where to extract drivers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        
        [Parameter(Mandatory = $false)]
        [string]$DestinationPath = "C:\EZOSD\Downloads\Drivers\Extracted"
    )
    
    try {
        Write-EZOSDLog -Message "Extracting driver package: $PackagePath" -Level Info
        
        # Create destination directory
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        
        $extension = [System.IO.Path]::GetExtension($PackagePath).ToLower()
        
        switch ($extension) {
            ".zip" {
                Expand-Archive -Path $PackagePath -DestinationPath $DestinationPath -Force
            }
            ".cab" {
                $expandArgs = "-F:* `"$PackagePath`" `"$DestinationPath`""
                Start-Process -FilePath "expand.exe" -ArgumentList $expandArgs -Wait -NoNewWindow
            }
            ".exe" {
                # Attempt silent extraction
                $ArgumentList = "/s /e=`"$DestinationPath`" /l=`"$DestinationPath\extract.log`""
                $extracted = $false
                try {
                    Start-Process -FilePath $PackagePath -ArgumentList $ArgumentList -Wait -NoNewWindow -ErrorAction Stop
                    if ((Get-ChildItem $DestinationPath -Recurse -File).Count -gt 0) {
                        $extracted = $true
                    }
                }
                catch {
                    Write-EZOSDLog -Message "Silent extraction failed, may require manual extraction: $($Error[0].Exception.Message)" -Level Warning
                }
                
                if (-not $extracted) {
                    Write-EZOSDLog -Message "Could not auto-extract EXE, requires manual extraction" -Level Warning
                    return $null
                }
            }
            default {
                Write-EZOSDLog -Message "Unsupported package format: $extension" -Level Warning
                return $null
            }
        }
        
        Write-EZOSDLog -Message "Driver package extracted to: $DestinationPath" -Level Info
        return $DestinationPath
    }
    catch {
        Write-EZOSDError -Message "Failed to extract driver package" -Exception $_.Exception
        return $null
    }
}

function Add-DriversToImage {
    <#
    .SYNOPSIS
        Injects drivers into offline Windows image.
    .PARAMETER DriverPath
        Path to folder containing drivers.
    .PARAMETER TargetDrive
        Drive letter where Windows is installed.
    .PARAMETER Recurse
        Whether to search for drivers recursively.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriverPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive,
        
        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $true
    )
    
    Write-EZOSDLogSection -Title "Driver Injection"
    
    try {
        $windowsPath = "${TargetDrive}:\"
        
        Write-EZOSDLog -Message "Injecting drivers from: $DriverPath" -Level Info
        Write-EZOSDLog -Message "Target Windows: $windowsPath" -Level Info
        
        # Validate paths
        if (-not (Test-Path $DriverPath)) {
            throw "Driver path not found: $DriverPath"
        }
        
        if (-not (Test-Path $windowsPath)) {
            throw "Target Windows path not found: $windowsPath"
        }
        
        # Count driver INF files
        $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse:$Recurse
        Write-EZOSDLog -Message "Found $($infFiles.Count) driver INF file(s)" -Level Info
        
        if ($infFiles.Count -eq 0) {
            Write-EZOSDLog -Message "No driver INF files found" -Level Warning
            return $false
        }
        
        # Add drivers using DISM
        Write-EZOSDLog -Message "Adding drivers to offline image..." -Level Info
        
        Add-WindowsDriver -Path $windowsPath -Driver $DriverPath -Recurse:$Recurse -ForceUnsigned -ErrorAction Stop
        
        Write-EZOSDLog -Message "Drivers injected successfully" -Level Info
        return $true
    }
    catch {
        Write-EZOSDError -Message "Failed to inject drivers" -Exception $_.Exception
        return $false
    }
}

function Get-SystemHardwareInfo {
    <#
    .SYNOPSIS
        Gets system hardware information for driver matching.
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-EZOSDLog -Message "Detecting system hardware..." -Level Info

        $arch = (Get-CimInstance -ClassName Win32_Processor).Architecture
        switch ($arch) {
            0 { $arch = "x86" }
            9 { $arch = "x64" }
            12 { $arch = "arm64" }
            default { throw "Unknown architecture code: $arch" }
        }
        
        $hardwareInfo = @{
            Manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
            Model = (Get-WmiObject -Class Win32_ComputerSystem).Model
            SystemID = (Get-CimInstance -ClassName CIM_ComputerSystem).SystemSKUNumber
            Architecture = $arch
            NetworkAdapters = @()
            StorageControllers = @()
            VideoControllers = @()
        }
        
        # Network adapters
        $netAdapters = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.PNPDeviceID }
        foreach ($adapter in $netAdapters) {
            $hardwareInfo.NetworkAdapters += @{
                Name = $adapter.Name
                DeviceID = $adapter.PNPDeviceID
            }
        }
        
        # Storage controllers
        $storageControllers = Get-WmiObject -Class Win32_SCSIController
        foreach ($controller in $storageControllers) {
            $hardwareInfo.StorageControllers += @{
                Name = $controller.Name
                DeviceID = $controller.PNPDeviceID
            }
        }
        
        # Video controllers
        $videoControllers = Get-WmiObject -Class Win32_VideoController
        foreach ($controller in $videoControllers) {
            $hardwareInfo.VideoControllers += @{
                Name = $controller.Name
                DeviceID = $controller.PNPDeviceID
            }
        }
        
        Write-EZOSDLog -Message "Manufacturer: $($hardwareInfo.Manufacturer)" -Level Info
        Write-EZOSDLog -Message "Model: $($hardwareInfo.Model)" -Level Info
        Write-EZOSDLog -Message "Network Adapters: $($hardwareInfo.NetworkAdapters.Count)" -Level Debug
        Write-EZOSDLog -Message "Storage Controllers: $($hardwareInfo.StorageControllers.Count)" -Level Debug
        Write-EZOSDLog -Message "Video Controllers: $($hardwareInfo.VideoControllers.Count)" -Level Debug
        
        return $hardwareInfo
    }
    catch {
        Write-EZOSDError -Message "Failed to get hardware info" -Exception $_.Exception
        return $null
    }
}

function Install-ConfiguredDrivers {
    <#
    .SYNOPSIS
        Processes driver configuration and downloads/injects drivers.
    .PARAMETER DriverConfig
        Driver configuration from deployment.json.
    .PARAMETER TargetDrive
        Drive letter where Windows is installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$DriverConfig,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive
    )
    
    try {
        Write-EZOSDLogSection -Title "Configured Driver Installation"
        
        if (-not $DriverConfig -or $DriverConfig.Count -eq 0) {
            Write-EZOSDLog -Message "No driver sources configured" -Level Info
            return $true
        }
        
        $driverBasePath = "C:\EZOSD\Downloads\Drivers"
        if (-not (Test-Path $driverBasePath)) {
            New-Item -Path $driverBasePath -ItemType Directory -Force | Out-Null
        }
        $allDriversInjected = $true
        
        foreach ($driverSource in $DriverConfig) {
            Write-EZOSDLog -Message "Processing driver source: $($driverSource.Name)" -Level Info
            
            if ($driverSource.Type -eq "Autodetect") {
                $HardwareInfo = Get-SystemHardwareInfo
                if ($HardwareInfo.SystemID) {
                    $downloadLink = Get-DellDriverPackDownloadLink -SystemID $HardwareInfo.SystemID -Architecture $HardwareInfo.Architecture
                    if ($downloadLink) {
                        $downloadedPackage = Get-DriverPackage -Url $downloadLink -DestinationPath $driverBasePath
                        if ($downloadedPackage) {
                            $extractedPath = Expand-DriverPackage -PackagePath $downloadedPackage -DestinationPath (Join-Path $driverBasePath $driverSource.Name)
                            if ($extractedPath) {
                                $injected = Add-DriversToImage -DriverPath $extractedPath -TargetDrive $TargetDrive
                                if (-not $injected) {
                                    $allDriversInjected = $false
                                }
                            }
                        }
                    }
                }
            }    
            elseif ($driverSource.Type -eq "URL") {
                # Download driver package
                $downloadedPackage = Get-DriverPackage -Url $driverSource.URL -DestinationPath $driverBasePath
                
                if ($downloadedPackage) {
                    # Extract package
                    $extractedPath = Expand-DriverPackage -PackagePath $downloadedPackage -DestinationPath (Join-Path $driverBasePath $driverSource.Name)
                    
                    if ($extractedPath) {
                        # Inject drivers
                        $injected = Add-DriversToImage -DriverPath $extractedPath -TargetDrive $TargetDrive
                        if (-not $injected) {
                            $allDriversInjected = $false
                        }
                    }
                }
            }
            elseif ($driverSource.Type -eq "Path") {
                # Use local driver path
                if (Test-Path $driverSource.Path) {
                    $injected = Add-DriversToImage -DriverPath $driverSource.Path -TargetDrive $TargetDrive
                    if (-not $injected) {
                        $allDriversInjected = $false
                    }
                }
                else {
                    Write-EZOSDLog -Message "Driver path not found: $($driverSource.Path)" -Level Warning
                    $allDriversInjected = $false
                }
            }
        }
        
        return $allDriversInjected
    }
    catch {
        Write-EZOSDError -Message "Driver installation failed" -Exception $_.Exception
        return $false
    }
}

function Get-DellDriverPackDownloadLink {
    <#
    .SYNOPSIS
        Retrieves the appropriate Dell DriverPack download link for the current system.
    .PARAMETER SystemID
        System ID (SKU) used to find matching driver pack.
    .PARAMETER Architecture
        System architecture (x86, x64, arm64) to find correct driver pack.
    .PARAMETER DestinationPath
        Where to save the downloaded driver pack.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$SystemID,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x86", "x64", "arm64")]
        [string]$Architecture,

        [Parameter(Mandatory = $false)]
        [string]$DestinationPath = "C:\EZOSD\Downloads\Drivers"
    )

    Write-EZOSDLog "Getting Dell DriverPack for System ID: $SystemID, Architecture: $Architecture"

    if (-not (Test-Path $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    $catalogCABFile = Join-Path $DestinationPath "DriverPackCatalog.cab"
    $catalogXMLFile = Join-Path $DestinationPath "DriverPackCatalog.xml"

    try {
        # Download the latest Dell DriverPackCatalog.cab file to the current directory
        Write-EZOSDLog "Downloading Dell DriverPackCatalog.cab..."
        $source = "http://downloads.dell.com/catalog/DriverPackCatalog.cab"

        Invoke-WebRequest -Uri $source -OutFile $catalogCABFile
        Write-EZOSDLog "DriverPackCatalog.cab downloaded successfully."

        # Extract the contents of the downloaded .cab file to XML
        Write-EZOSDLog "Extracting catalog XML from cab file..."
        EXPAND $catalogCABFile $catalogXMLFile | Out-Null
        Write-EZOSDLog "Catalog XML extracted successfully."

        # Find models
        Write-EZOSDLog "Searching for driver pack matching System ID: $SystemID"
        [xml]$catalogXMLDoc = Get-Content $catalogXMLFile

        $cabSelected = $catalogXMLDoc.DriverPackManifest.DriverPackage | Where-Object { ($_.SupportedSystems.Brand.Model.systemID -eq $SystemID ) }

        #parse the path property of $cabSelected to check for win11
        foreach ($driverPack in $cabSelected) {
            if ($driverPack.path -match "win11") {
                $driverPackForWin11 = $driverPack
                break
            }
        }

        if (-not $driverPackForWin11) {
            Write-EZOSDLog "No driver pack found for Windows 11 for System ID: $SystemID"
            throw "No driver pack found for Windows 11 for System ID: $SystemID"
        }

        $cabDownloadLink = "http://" + $catalogXMLDoc.DriverPackManifest.baseLocation + "/" + $driverPackForWin11.path

        return $cabDownloadLink
    }
    catch {
        Write-EZOSDLog "Failed to get Dell DriverPack: $($_.Exception.Message)"
        throw
    }
    finally {
        # Cleanup temporary files
        Write-EZOSDLog "Cleaning up temporary catalog files..."
        if (Test-Path $catalogCABFile) { 
            Remove-Item -Path $catalogCABFile -Force 
            Write-EZOSDLog "Removed $catalogCABFile"
        }
        if (Test-Path $catalogXMLFile) { 
            Remove-Item -Path $catalogXMLFile -Force 
            Write-EZOSDLog "Removed $catalogXMLFile"
        }
        Write-EZOSDLog "Cleanup complete."
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-DriverPackage',
    'Expand-DriverPackage',
    'Add-DriversToImage',
    'Get-SystemHardwareInfo',
    'Install-ConfiguredDrivers',
    'Get-DellDriverPackDownloadLink'
)
