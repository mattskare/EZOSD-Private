<#
.SYNOPSIS
    EZOSD Bootable USB Creation Script
.DESCRIPTION
    Creates a bootable WinPE USB drive with EZOSD deployment tools.
    Requires Windows ADK to be installed on the system.
.PARAMETER USBDrive
    Drive letter of the USB drive (e.g., E:).
.PARAMETER ADKPath
    Path to Windows ADK installation. Auto-detected if not specified.
.PARAMETER WinPEArch
    WinPE architecture (amd64, x86, or arm64).
.PARAMETER IncludeOptionalPackages
    Include additional WinPE packages (PowerShell, DISM, NetFX, etc.).
.EXAMPLE
    .\Create-BootableUSB.ps1 -USBDrive E:
    Create bootable USB on drive E: with default settings.
.NOTES
    Requires: Administrator privileges, Windows ADK
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ADKPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeOptionalPackages,

    [Parameter(Mandatory = $false)]
    [string]$Directory = 'C:\EZOSD',

    # Prefer DiskNumber (passed by GUI). USBDrive (drive letter) kept for backwards-compatible CLI use.
    [Parameter(Mandatory = $false)]
    [int]$DiskNumber = -1,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]:$|^$')]
    [string]$USBDrive = ''
)

$ErrorActionPreference = "Stop"

# Read version from file
$version = (Get-Content -Path (Join-Path "$PSScriptRoot" "USBCREATORVERSION") -Raw).Trim()

# Script variables
$script:WorkingDirectory = Join-Path $Directory "EZOSD_USB_Build"
$script:EZOSDRoot = Split-Path -Parent $PSScriptRoot

<#
.SYNOPSIS
    Writes formatted log message.
#>
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $colors = @{
        "Info" = "White"
        "Success" = "Green"
        "Warning" = "Yellow"
        "Error" = "Red"
    }
    
    $prefix = switch ($Level) {
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error" { "[✗]" }
        default { "[*]" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

<#
.SYNOPSIS
    Detects Windows ADK installation.
#>
function Get-ADKPath {
    Write-Verbose "Detecting Windows ADK installation..."
    
    # Common ADK installation paths
    $adkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit"
    )
    
    foreach ($path in $adkPaths) {
        if (Test-Path $path) {
            Write-Log "Found Windows ADK at: $path" -Level Success
            return $path
        }
    }
    
    Write-Log "Windows ADK not found. Please install Windows ADK from: https://learn.microsoft.com/windows-hardware/get-started/adk-install" -Level Warning
    return $null
}

<#
.SYNOPSIS
    Creates WinPE working environment.
#>
function New-WinPEWorkingDirectory {
    param(
        [string]$ADKPath,
        [string]$Architecture
    )
    
    Write-Log "Creating WinPE working directory..."
    
    # Locate DandISetEnv.bat to set up deployment tools environment
    $envBatPath = "$ADKPath\Deployment Tools\DandISetEnv.bat"
    
    if (-not (Test-Path $envBatPath)) {
        throw "DandISetEnv.bat not found. Ensure Windows ADK is properly installed."
    }
    
    # Run copype to create base WinPE
    Write-Log "Creating base WinPE environment..."
    
    # Use DandISetEnv.bat to set up environment, then run copype
    $cmdLine = "/c `"`"$envBatPath`" && copype $Architecture `"$script:WorkingDirectory\WinPE_$Architecture`""
    Write-Verbose "Running: cmd.exe $cmdLine"
    
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdLine -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        throw "Failed to create WinPE working directory (Exit code: $($process.ExitCode))"
    }
    
    Write-Log "WinPE base created successfully" -Level Success
}

<#
.SYNOPSIS
    Mounts WinPE image for customization.
#>
function Mount-WinPEImage {
    param(
        [string]$Architecture
    )
    
    Write-Log "Mounting WinPE image..."
    
    $wimPath = "$script:WorkingDirectory\WinPE_$Architecture\media\sources\boot.wim"
    
    if (-not (Test-Path $wimPath)) {
        throw "boot.wim not found at: $wimPath"
    }
    
    Mount-WindowsImage -ImagePath $wimPath -Index 1 -Path "$script:WorkingDirectory\WinPE_$Architecture\mount" -ErrorAction Stop
    
    Write-Log "WinPE image mounted" -Level Success
}

<#
.SYNOPSIS
    Adds packages to WinPE.
#>
function Add-WinPEPackages {
    param(
        [string]$ADKPath,
        [string]$Architecture
    )
    
    Write-Log "Adding PowerShell and required packages to WinPE..."
    
    $packagesPath = Join-Path $ADKPath "Windows Preinstallation Environment\$Architecture\WinPE_OCs"
    
    # Required packages for EZOSD
    $requiredPackages = @(
        "WinPE-WMI.cab",
        "WinPE-NetFx.cab",
        "WinPE-Scripting.cab",
        "WinPE-PowerShell.cab",
        "WinPE-StorageWMI.cab",
        "WinPE-DismCmdlets.cab"
    )
    
    # Optional packages
    $optionalPackages = @(
        "WinPE-SecureStartup.cab",
        "WinPE-EnhancedStorage.cab",
        "WinPE-FMAPI.cab"
    )
    
    # Determine which packages to install based on user selection
    $packagesToInstall = $requiredPackages
    if ($IncludeOptionalPackages) {
        $packagesToInstall += $optionalPackages
    }

    # Check for already installed packages to avoid redundant installation
    $packagesAlreadyInstalled = Get-WindowsPackage -Path "$script:WorkingDirectory\WinPE_$Architecture\mount" | Select-Object -ExpandProperty PackageName
    $alreadyInstalled = $packagesToInstall | Where-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        $packagesAlreadyInstalled | Where-Object { $_ -like "$baseName*" }
    }
    if ($alreadyInstalled) {
        Write-Log "Some packages are already installed in the WinPE image. Skipping installation of those packages." -Level Warning
        $packagesToInstall = $packagesToInstall | Where-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not ($packagesAlreadyInstalled | Where-Object { $_ -like "$baseName*" })
        }
    }

    foreach ($package in $packagesToInstall) {
        $packagePath = Join-Path $packagesPath $package
        
        if (Test-Path $packagePath) {
            Write-Verbose "Adding package: $package"
            try {
                Add-WindowsPackage -Path "$script:WorkingDirectory\WinPE_$Architecture\mount" -PackagePath $packagePath -ErrorAction Stop | Out-Null
                
                # Add language pack if available
                $langPackage = $package.Replace(".cab", "_en-us.cab")
                $langPackagePath = Join-Path $packagesPath "en-us\$langPackage"
                
                if (Test-Path $langPackagePath) {
                    Add-WindowsPackage -Path "$script:WorkingDirectory\WinPE_$Architecture\mount" -PackagePath $langPackagePath -ErrorAction Stop | Out-Null
                }
            }
            catch {
                Write-Log "Warning: Failed to add package $package" -Level Warning
            }
        }
        else {
            Write-Log "Warning: Package not found: $package" -Level Warning
        }
    }
    
    Write-Log "Packages added successfully" -Level Success
}

<#
.SYNOPSIS
    Creates startnet.cmd for auto-launching EZOSD.
#>
function New-StartNetCmd {
    param(
        [string]$Architecture
    )

    Write-Log "Creating startnet.cmd..."
    
    $startNetPath = Join-Path "$script:WorkingDirectory\WinPE_$Architecture\mount" "Windows\System32\startnet.cmd"
    
    $startNetContent = Get-Content -Path (Join-Path $PSScriptRoot "startnet_template.cmd") -Raw
    $startNetContent = $startNetContent -replace '__EZOSD_VERSION__', $version
    $startNetContent | Out-File -FilePath $startNetPath -Encoding ASCII -Force
    
    Write-Log "startnet.cmd created" -Level Success
}

<#
.SYNOPSIS
    Unmounts and saves WinPE image.
#>
function Dismount-WinPEImage {
    param(
        [string]$Architecture
    )

    Write-Log "Saving and unmounting WinPE image..."
    
    Dismount-WindowsImage -Path "$script:WorkingDirectory\WinPE_$Architecture\mount" -Save -ErrorAction Stop
    
    Write-Log "WinPE image saved" -Level Success
}

<#
.SYNOPSIS
    Creates bootable USB drive.
#>
function New-BootableUSB {
    param(
        [int]$TargetDiskNumber = -1,
        [string]$Drive = ''
    )
    
    Write-Log "Formatting USB drive..."

    # Resolve disk number — prefer explicit number, fall back to looking up from drive letter
    $diskNumber = $TargetDiskNumber
    if ($diskNumber -lt 0) {
        if (-not $Drive) {
            throw "Either DiskNumber or USBDrive (drive letter) must be supplied."
        }
        $diskNumber = (Get-Partition | Where-Object { $_.DriveLetter -eq $Drive.TrimEnd(':') }).DiskNumber
        if ($null -eq $diskNumber) {
            throw "Could not find disk number for drive letter '$Drive'."
        }
    }

    # Safety check: do not allow formatting the system/boot disk
    $sysDisk = Get-Disk | Where-Object { $_.IsBoot -or $_.IsSystem }
    if ($sysDisk.Number -contains $diskNumber) {
        throw "Disk $diskNumber is a system/boot disk and cannot be formatted."
    }
    
    # Clean and initialize disk
    Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
    
    # Check if disk needs initialization (Clear-Disk may leave it initialized)
    $disk = Get-Disk -Number $diskNumber
    if ($disk.PartitionStyle -eq 'RAW') {
        Write-Verbose "Initializing disk with GPT partition style"
        Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop
    } else {
        Write-Verbose "Disk already initialized with $($disk.PartitionStyle) partition style, skipping initialization"
    }
    
    # Create 2GB partition
    Write-Log "Creating 2GB FAT32 partition..."
    
    # 2GB = 2048 MB = 2147483648 bytes
    $partitionSize = 2GB
    $partition = New-Partition -DiskNumber $diskNumber -Size $partitionSize -ErrorAction Stop
    
    # Format as FAT32
    Write-Verbose "Formatting partition as FAT32..."
    Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel "EZOSD v$version" -Confirm:$false | Out-Null
    
    # Assign drive letter
    $partition | Add-PartitionAccessPath -AssignDriveLetter
    
    # Get the assigned drive letter
    Start-Sleep -Seconds 1  # Give time for drive letter assignment
    $newDriveLetter = (Get-Partition -DiskNumber $diskNumber | Where-Object { $_.DriveLetter }).DriveLetter
    $usbPath = "${newDriveLetter}:"
    
    Write-Log "USB formatted successfully (${usbPath})" -Level Success
    
    return $usbPath
}

function Copy-WinPEFilesToCombinedDirectory {
    Write-Log "Copying WinPE files to combined directory..."
    
    $combinedDir = Join-Path $script:WorkingDirectory "WinPE_Combined"
    
    # Create combined directory
    if (-not (Test-Path $combinedDir)) {
        New-Item -Path $combinedDir -ItemType Directory -Force | Out-Null
    }

    try {
        Copy-Item -Path "$script:WorkingDirectory\WinPE_amd64\media\*" -Destination $combinedDir -Recurse -Force
        Copy-Item -Path "$script:WorkingDirectory\WinPE_arm64\media\EFI\Boot\bootaa64.efi" -Destination "$combinedDir\EFI\boot" -Force
        New-Item -Path "$combinedDir\sources\arm64" -ItemType Directory -Force | Out-Null
        Copy-Item -Path "$script:WorkingDirectory\WinPE_arm64\media\sources\boot.wim" -Destination "$combinedDir\sources\arm64\boot.wim" -Force
    }
    catch {
        throw "Failed to copy WinPE files to combined directory: $_"
    }

    Write-Log "Files copied to combined directory" -Level Success
}

function Update-BootConfiguration {
    param(
        [string]$USBDrive
    )

    Write-Log "Updating boot configuration for multi-architecture support..."
    
    # Set environment variable for bcdedit to use the BCD store in the combined directory
    $env:USBDrive = $USBDrive

    Write-Verbose "Running: cmd.exe /c .\SetBootConfig.cmd"

    & cmd.exe /c ".\SetBootConfig.cmd" 2>&1 | ForEach-Object { $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update boot configuration (Exit code: $LASTEXITCODE)"
    }

    # Clean up
    Remove-Item GUID.txt -ErrorAction SilentlyContinue
    Remove-Item GUID2.txt -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    Downloads and installs Windows ADK and WinPE addon.
.DESCRIPTION
    If Windows ADK is not detected, this function will download and install the latest version of
    Windows ADK and the WinPE addon. This is required for creating the WinPE environment used in the bootable USB.
.PARAMETER DownloadPath
    Path to download the ADK installers. Defaults to a subdirectory in the working directory.
.EXAMPLE
    Install-WindowsADK
    Downloads and installs Windows ADK to the default location.
#>
function Install-WindowsADK {
    param(
        [string]$DownloadPath = (Join-Path $script:WorkingDirectory "ADKSetup")
    )

    Write-Log "Preparing to download Windows ADK..."

    $adkInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2289980" # ADK 10.1.26100.2454
    $adkPEAddonUrl   = "https://go.microsoft.com/fwlink/?linkid=2289981" # WinPE addon 10.1.26100.2454

    $adkInstallerPath  = Join-Path $DownloadPath "adksetup.exe"
    $adkPEAddonPath    = Join-Path $DownloadPath "adkwinpesetup.exe"

    if (-not (Test-Path $DownloadPath)) {
        New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null
    }

    # Download ADK installer
    Write-Log "Downloading Windows ADK installer..."
    try {
        Invoke-WebRequest -Uri $adkInstallerUrl -OutFile $adkInstallerPath -UseBasicParsing
        Write-Log "Windows ADK installer downloaded" -Level Success
    }
    catch {
        throw "Failed to download Windows ADK installer: $_"
    }

    # Download WinPE addon installer
    Write-Log "Downloading Windows ADK WinPE addon installer..."
    try {
        Invoke-WebRequest -Uri $adkPEAddonUrl -OutFile $adkPEAddonPath -UseBasicParsing
        Write-Log "Windows ADK WinPE addon installer downloaded" -Level Success
    }
    catch {
        throw "Failed to download Windows ADK WinPE addon installer: $_"
    }

    # Install ADK
    Write-Log "Installing Windows ADK (this may take several minutes)..."
    $adkArgs = "/quiet /norestart /features OptionId.DeploymentTools"
    $process = Start-Process -FilePath $adkInstallerPath -ArgumentList $adkArgs -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Windows ADK installation failed (Exit code: $($process.ExitCode))"
    }
    Write-Log "Windows ADK installed successfully" -Level Success

    # Install WinPE addon
    Write-Log "Installing Windows ADK WinPE addon (this may take several minutes)..."
    $adkPEArgs = "/quiet /norestart /features OptionId.WindowsPreinstallationEnvironment"
    $process = Start-Process -FilePath $adkPEAddonPath -ArgumentList $adkPEArgs -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Windows ADK WinPE addon installation failed (Exit code: $($process.ExitCode))"
    }
    Write-Log "Windows ADK WinPE addon installed successfully" -Level Success
}

<#
.SYNOPSIS
    Main build process.
#>
function Start-Build {
    try {
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║           EZOSD Bootable USB Creation Tool                    ║" -ForegroundColor Cyan
        Write-Host "║                    Version $version                              ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        # Detect ADK
        if (-not $ADKPath) { # If ADK path not provided as parameter, attempt to detect it
            $ADKPath = Get-ADKPath
            if (-not $ADKPath) { # If ADK still not found, attempt to download and install it
                Write-Log "Windows ADK not found. Attempting to download and install..." -Level Warning
                Install-WindowsADK
                $ADKPath = Get-ADKPath
                if (-not $ADKPath) {
                    throw "Failed to detect Windows ADK after installation."
                }
            }
        }
        
        Write-Host ""
        Write-Host "Build Configuration:" -ForegroundColor Cyan
        Write-Host "  ADK Path: $ADKPath" -ForegroundColor White
        if ($DiskNumber -ge 0) {
            Write-Host "  Target Disk: $DiskNumber" -ForegroundColor White
        } else {
            Write-Host "  USB Drive: $USBDrive" -ForegroundColor White
        }
        Write-Host ""

        $architectures = @('amd64', 'arm64')

        # Create bootable USB
        $finalUSBPath = New-BootableUSB -TargetDiskNumber $DiskNumber -Drive $USBDrive

        # if (-not (Test-Path "$script:WorkingDirectory\WinPE_Combined")) {
            foreach ($architecture in $architectures) {
                # Create WinPE working directory
                if (-not (Test-Path "$script:WorkingDirectory\WinPE_Combined")) {
                    New-WinPEWorkingDirectory -ADKPath $ADKPath -Architecture $architecture
                }
                # Mount WinPE image
                Mount-WinPEImage -Architecture $architecture

                # Add packages
                Add-WinPEPackages -ADKPath $ADKPath -Architecture $architecture

                # Create startnet.cmd
                New-StartNetCmd -Architecture $architecture

                # Unmount image
                Dismount-WinPEImage -Architecture $architecture
            }

            # Create combined EZOSD files in working directory
            Copy-WinPEFilesToCombinedDirectory
        # }

        # Copy files to USB
        Copy-Item -Path "$script:WorkingDirectory\WinPE_Combined\*" -Destination $finalUSBPath -Recurse -Force

        # Update boot configuration for multi-architecture support
        Update-BootConfiguration -USBDrive $finalUSBPath
        
        # Cleanup
        Write-Log "Cleaning up temporary files..."
        
        # Success summary
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║          BOOTABLE USB CREATED SUCCESSFULLY                    ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "USB Drive: $finalUSBPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Boot target device from USB" -ForegroundColor White
        Write-Host "  2. EZOSD will launch automatically" -ForegroundColor White
        Write-Host ""
        
        return $true
    }
    catch {
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                    BUILD FAILED                               ║" -ForegroundColor Red
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Log "Error: $_" -Level Error
        Write-Host ""
        
        return $false
    }
    finally {
        # Dismount any mounted images in case of failure
        foreach ($architecture in @('amd64', 'arm64')) {
            $mountPath = "$script:WorkingDirectory\WinPE_$architecture\mount"
            if (Test-Path "$mountPath\*" -PathType Leaf) {
                try {
                    Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
                    Write-Log "Unmounted $architecture image during cleanup" -Level Warning
                }
                catch {
                    Write-Log "Failed to unmount $architecture image during cleanup: $_" -Level Warning
                }
            }
        }
    }
}

# Execute build
$buildResult = Start-Build

if ($buildResult) {
    exit 0
}
else {
    exit 1
}
