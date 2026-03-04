<#
.SYNOPSIS
    EZOSD Download Module
.DESCRIPTION
    Handles downloading Windows ESD images from Microsoft sources.
    Supports both direct downloads and Media Creation Tool integration.
#>

using module .\EZOSD-Logger.psm1

<#
.SYNOPSIS
    Downloads Windows ESD image.
.PARAMETER Version
    Windows version (10, 11).
.PARAMETER Edition
    Windows edition (Pro, Home, Enterprise).
.PARAMETER Architecture
    System architecture (x64, x86, arm64).
.PARAMETER DestinationPath
    Where to save the downloaded ESD file.
.PARAMETER UseCache
    Whether to use cached ESD if available.
#>
function Get-WindowsESD {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("10", "11")]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$Edition,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("x64", "x86", "arm64")]
        [string]$Architecture = "x64",

        [Parameter(Mandatory = $false)]
        [string]$Release,
        
        [Parameter(Mandatory = $false)]
        [string]$DestinationPath = "C:\EZOSD\Downloads",
        
        [Parameter(Mandatory = $false)]
        [bool]$UseCache = $true
    )
    
    Write-EZOSDLogSection -Title "Windows ESD Download"
    
    try {
        # Create destination directory
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        
        # Check available disk space (ESD files are typically 3-5 GB)
        $drive = (Split-Path -Qualifier $DestinationPath)
        try {
            $diskSpace = Get-PSDrive -Name ($drive -replace ':', '') -ErrorAction SilentlyContinue
            if ($diskSpace -and $diskSpace.Free -lt 6GB) {
                $freeGB = [math]::Round($diskSpace.Free / 1GB, 2)
                throw "Insufficient disk space on ${drive} (${freeGB}GB free, need at least 6GB). Consider changing DownloadPath in deployment.json to a drive with more space."
            }
        } catch {
            Write-EZOSDLog -Message "Warning: Could not verify disk space: $($_.Exception.Message)" -Level Warning
        }
        
        $esdFileName = "Windows_${Version}_${Edition}_${Architecture}_${Release}.esd"
        $esdPath = Join-Path $DestinationPath $esdFileName
        
        # Check cache
        if ($UseCache -and (Test-Path $esdPath)) {
            Write-EZOSDLog -Message "Using cached ESD: $esdPath" -Level Info
            
            # Validate cached file
            if (Test-ESDFile -Path $esdPath) {
                return $esdPath
            }
            else {
                Write-EZOSDLog -Message "Cached ESD is invalid, re-downloading..." -Level Warning
                Remove-Item -Path $esdPath -Force
            }
        }
        
        # Download ESD
        Write-EZOSDLog -Message "Downloading Windows $Version $Edition ($Architecture)..." -Level Info
        Write-EZOSDLog -Message "Destination: $esdPath" -Level Info
        
        # Get download URL
        $downloadUrl = Get-WindowsDownloadURL -Version $Version -Edition $Edition -Architecture $Architecture -Release $Release
        
        if (-not $downloadUrl) {
            throw "Failed to retrieve download URL for Windows $Version $Edition"
        }
        
        Write-EZOSDLog -Message "Download URL: $downloadUrl" -Level Debug
        
        # Download file with progress
        $downloadResult = Invoke-EZOSDDownload -Url $downloadUrl -DestinationPath $esdPath
        
        if (-not $downloadResult) {
            throw "Failed to download Windows ESD"
        }
        
        # Validate downloaded file
        Write-EZOSDLog -Message "Validating downloaded ESD..." -Level Info
        if (-not (Test-ESDFile -Path $esdPath)) {
            throw "Downloaded ESD file is invalid"
        }
        
        Write-EZOSDLog -Message "Windows ESD downloaded successfully" -Level Info
        return $esdPath
    }
    catch {
        Write-EZOSDError -Message "Failed to download Windows ESD" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Gets the download URL for Windows ESD.
.PARAMETER Version
    Windows version.
.PARAMETER Edition
    Windows edition.
.PARAMETER Architecture
    System architecture.
.PARAMETER Release
    Windows release (e.g., 22H2, 23H2, 24H2, 25H2).
.PARAMETER Language
    Windows language (default: en-US).
#>
function Get-WindowsDownloadURL {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('10', '11')]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'ARM64')]
        [string]$Architecture,

        [Parameter(Mandatory = $false)]
        [string]$Language = 'en-US',

        [Parameter(Mandatory = $false)]
        [string]$Release,

        [Parameter(Mandatory = $false)]
        [string]$Edition,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = "C:\EZOSD\Temp"
    )

    if ($Edition -eq 'Pro') {
        $Edition = 'Professional'
    }

    Write-EZOSDLog "Checking Windows $Version $Release ESD file"
    Write-EZOSDLog "Windows Architecture: $Architecture"
    Write-EZOSDLog "Windows Language: $Language"
    Write-EZOSDLog "Windows Edition: $Edition"

    $cabFilePath = Join-Path $OutputDirectory "tempCabFile.cab"

    try {
        if ($Version -eq '11') {
            Write-EZOSDLog "Downloading Cab file"
            $buildReleaseMap = @{
                '24H2' = '26100.0.0.0'
                '25H2' = '26200.0.0.0'
            }
            $normalizedRelease = $Release.ToUpper()
            if ($buildReleaseMap.ContainsKey($normalizedRelease)) {
                $buildRelease = $buildReleaseMap[$normalizedRelease]
            }
            else {
                Write-EZOSDLog "No explicit build mapping found for Windows 11 version '$Release'. Defaulting products.cab build token to 26200.0.0.0."
                $buildRelease = '26200.0.0.0'
            }

            Get-WindowsProductsCab -OutFile $cabFilePath -BuildVersion $buildRelease | Out-Null
        }
        else {
            throw "Downloading Windows $Version is not supported. Please use the -ISOPath parameter to specify the path to the Windows $Version ISO file."
        }
        Write-EZOSDLog "Download succeeded"
    }
    catch {
        Write-EZOSDLog "Failed to download products.cab: $($_.Exception.Message)"
        throw
    }

    Write-EZOSDLog "Extracting Products XML from cab"
    $xmlFilePath = Join-Path $OutputDirectory "products.xml"
    EXPAND $cabFilePath $xmlFilePath | Out-Null
    Write-EZOSDLog "Products XML extracted"

    # Load XML content
    [xml]$xmlContent = Get-Content -Path $xmlFilePath

    # Find the FilePath value based on Architecture, Language, and Edition
    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $Architecture -and $file.LanguageCode -eq $Language -and $file.Edition -eq $Edition) {
            try {
                return $file.FilePath
            }
            catch {
                Write-EZOSDLog "Failed to retrieve FilePath from XML: $($_.Exception.Message)"
                throw
            }
            finally {
                Write-EZOSDLog "Cleaning up cab and xml files"
                if (Test-Path $cabFilePath) { Remove-Item -Path $cabFilePath -Force }
                if (Test-Path $xmlFilePath) { Remove-Item -Path $xmlFilePath -Force }
                Write-EZOSDLog "Cleanup done"
            }
        }
    }
}

<#
.SYNOPSIS
    Downloads a file with progress tracking.
.PARAMETER Url
    URL to download from.
.PARAMETER DestinationPath
    Where to save the file.
#>
function Invoke-EZOSDDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )
    
    try {
        Write-EZOSDLog -Message "Starting download: $Url" -Level Info
        Write-EZOSDLog -Message "Using WebRequest for download..." -Level Debug
        
        # Use Invoke-WebRequest (compatible with WinPE)
        $ProgressPreference = 'SilentlyContinue'  # Speeds up Invoke-WebRequest
        Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
        
        Write-EZOSDLog -Message "Download completed" -Level Info
        return $true
    }
    catch {
        Write-EZOSDError -Message "Download failed" -Exception $_.Exception
        return $false
    }
}

<#
.SYNOPSIS
    Validates an ESD file.
.PARAMETER Path
    Path to ESD file.
#>
function Test-ESDFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path $Path)) {
            return $false
        }
        
        # Try to get image info using DISM
        Write-EZOSDLog -Message "Validating ESD with DISM..." -Level Debug
        $dismInfo = Get-WindowsImage -ImagePath $Path -ErrorAction SilentlyContinue
        
        if ($dismInfo) {
            Write-EZOSDLog -Message "ESD contains $($dismInfo.Count) image(s)" -Level Debug
            return $true
        }
        
        return $false
    }
    catch {
        Write-EZOSDLog -Message "ESD validation failed: $_" -Level Warning
        return $false
    }
}

<#
.SYNOPSIS
    Gets information about images in an ESD file.
.PARAMETER ESDPath
    Path to ESD file.
#>
function Get-ESDImageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ESDPath
    )
    
    try {
        Write-EZOSDLog -Message "Getting image information from ESD..." -Level Info
        
        $images = Get-WindowsImage -ImagePath $ESDPath
        
        foreach ($image in $images) {
            Write-EZOSDLog -Message "Index $($image.ImageIndex): $($image.ImageName)" -Level Info
            Write-EZOSDLog -Message "  Size: $([math]::Round($image.ImageSize / 1GB, 2)) GB" -Level Debug
        }
        
        return $images
    }
    catch {
        Write-EZOSDError -Message "Failed to get ESD image info" -Exception $_.Exception
        throw
    }
}

function Get-WindowsProductsCab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        # [Parameter(Mandatory = $true)]
        # [ValidateSet('x64', 'arm64')]
        # [string]$Architecture,

        [Parameter(Mandatory = $true)]
        [string]$BuildVersion
    )

    if ( $BuildVersion -eq '26100.0.0.0' ) {
        Write-EZOSDLog "Using legacy build version token for products.cab: $BuildVersion"
        # If downloading 24H2, download cab using this link: https://go.microsoft.com/fwlink/?LinkId=2156292
        $legacyCabUrl = 'https://go.microsoft.com/fwlink/?LinkId=2156292'
        Write-EZOSDLog "Downloading legacy products.cab from $legacyCabUrl"

        $destDir = Split-Path -Path $OutFile -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            [void](New-Item -ItemType Directory -Path $destDir)
        }

        Invoke-WebRequest -Uri $legacyCabUrl -OutFile $OutFile -UseBasicParsing
        Write-EZOSDLog "Legacy products.cab downloaded successfully."
        return $OutFile

    }
    elseif ( $BuildVersion -eq '26200.0.0.0' ) {
        Write-EZOSDLog "Using build version token for products.cab: $BuildVersion"

        # This is broken. Must search by amd64
        # $productsArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
        $productsArchitecture = 'amd64'

        $productsParam = "PN=Windows.Products.Cab.$productsArchitecture&V=$BuildVersion"
        $deviceAttributes = "DUScan=1;OSVersion=10.0.26100.1"

        $bodyObj = [ordered]@{
            Products         = $productsParam
            DeviceAttributes = $deviceAttributes
        }
        $bodyJson = $bodyObj | ConvertTo-Json -Compress

        $searchUri = 'https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo'

        Write-EZOSDLog "Requesting products.cab location from Windows Update service..."
        try {
            $searchResponse = Invoke-RestMethod -Uri $searchUri -Method Post -ContentType 'application/json' -Headers @{ Accept = '*/*' } -Body $bodyJson -UseBasicParsing
        }
        catch {
            Write-EZOSDLog "Failed to retrieve products.cab metadata: $($_.Exception.Message)"
            throw
        }

        if ($searchResponse -is [System.Array]) { $searchResponse = $searchResponse[0] }
        if (-not $searchResponse.FileLocations) { throw "Search response did not include FileLocations." }

        $fileRec = $searchResponse.FileLocations | Where-Object { $_.FileName -eq 'products.cab' } | Select-Object -First 1
        if (-not $fileRec) { throw "products.cab entry not found in FileLocations." }

        $downloadUrl = $fileRec.Url
        $serverDigestB64 = $fileRec.Digest
        $serverSize = [int64]$fileRec.Size
        $updateId = $searchResponse.UpdateIds[0]

        try {
            $metaUri = "https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/v1/$updateId"
            $meta = Invoke-RestMethod -Uri $metaUri -Method Get -Headers @{ Accept = '*/*' } -UseBasicParsing
            if ($meta.LocalizedProperties.Count -gt 0) {
                $title = $meta.LocalizedProperties[0].Title
                Write-EZOSDLog "Resolved update: $title"
            }
            else {
                Write-EZOSDLog "Resolved update id: $updateId"
            }
        }
        catch {
            Write-EZOSDLog "Resolved update id: $updateId"
        }

        $destDir = Split-Path -Path $OutFile -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            [void](New-Item -ItemType Directory -Path $destDir)
        }

        Write-EZOSDLog "Downloading products.cab to $OutFile ..."
        $downloadHeaders = @{ Accept = '*/*' }
        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -Headers $downloadHeaders -UseBasicParsing

        $actualSize = (Get-Item $OutFile).Length
        if ($actualSize -ne $serverSize) {
            throw "Size check failed. Expected $serverSize bytes. Got $actualSize bytes."
        }

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($OutFile)
        try {
            $hashBytes = $sha256.ComputeHash($fs)
        }
        finally {
            $fs.Dispose()
        }
        $actualDigestB64 = [Convert]::ToBase64String($hashBytes)

        if ($actualDigestB64 -ne $serverDigestB64) {
            throw "Digest check failed. Expected $serverDigestB64. Got $actualDigestB64."
        }

        Write-EZOSDLog "products.cab downloaded and verified successfully."
        return $OutFile

    }

}

# Export module members
Export-ModuleMember -Function @(
    'Get-WindowsESD',
    'Test-ESDFile',
    'Get-ESDImageInfo',
    'Invoke-EZOSDDownload',
    'Get-WindowsProductsCab',
    'Get-WindowsDownloadURL'
)
