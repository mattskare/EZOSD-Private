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
.PARAMETER AutoStart
    Automatically start deployment on boot without user interaction.
.PARAMETER KeepBuildFiles
    Keep the WinPE working directory after build for faster rebuilds.
.PARAMETER RebuildOnly
    Skip WinPE creation and only update EZOSD files on USB (requires existing build files).
.EXAMPLE
    .\Create-BootableUSB.ps1 -USBDrive E:
    Create bootable USB on drive E: with default settings.
.EXAMPLE
    .\Create-BootableUSB.ps1 -USBDrive F: -AutoStart -Verbose
    Create auto-starting bootable USB with verbose output.
.EXAMPLE
    .\Create-BootableUSB.ps1 -USBDrive E: -KeepBuildFiles
    Create USB and keep build files for faster subsequent rebuilds.
.EXAMPLE
    .\Create-BootableUSB.ps1 -USBDrive E: -RebuildOnly
    Quickly rebuild USB using existing WinPE files (after modifying EZOSD source).
.NOTES
    Version: 0.1.0-alpha
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
    [switch]$AutoStart,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepBuildFiles,
    
    [Parameter(Mandatory = $false)]
    [switch]$RebuildOnly,

    [Parameter(Mandatory = $false)]
    [string]$Directory = 'C:\EZOSD',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Z]:$')]
    [string]$USBDrive
)

$ErrorActionPreference = "Stop"

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
    
    throw "Windows ADK not found. Please install Windows ADK from: https://learn.microsoft.com/windows-hardware/get-started/adk-install"
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
    
    $packagesToInstall = $requiredPackages
    if ($IncludeOptionalPackages) {
        $packagesToInstall += $optionalPackages
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
    Write-Log "Creating startnet.cmd..."
    
    $startNetPath = Join-Path "$script:WorkingDirectory\WinPE_$Architecture\mount" "Windows\System32\startnet.cmd"
    
    $startNetContent = Get-Content -Path (Join-Path $script:EZOSDRoot "build\startnet_template.cmd") -Raw
    
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
    param([string]$Drive)
    
    Write-Log "Formatting USB drive..."
    
    $diskNumber = (Get-Partition | Where-Object { $_.DriveLetter -eq $Drive.TrimEnd(':') }).DiskNumber
    
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
    Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel "EZOSD" -Confirm:$false | Out-Null
    
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
    
    # Set path to BCD store in the combined WinPE directory
    $bcdPath = Join-Path $script:WorkingDirectory "WinPE_Combined\EFI\Microsoft\Boot\BCD"
    # Set environment variable for bcdedit to use the BCD store in the combined directory
    $env:CombinedBCDStore = $bcdPath
    $env:USBDrive = $USBDrive

    $cmdLine = "/c .\build\SetBootConfig.cmd"
    Write-Verbose "Running: cmd.exe $cmdLine"

    $process = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdLine -Wait -PassThru -NoNewWindow

    # Clean up
    Remove-Item GUID.txt -ErrorAction SilentlyContinue
    Remove-Item GUID2.txt -ErrorAction SilentlyContinue
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
        Write-Host "║                    Version 0.1.0-alpha                        ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        # Detect ADK
        if (-not $ADKPath) {
            $ADKPath = Get-ADKPath
        }
        
        Write-Host ""
        Write-Host "Build Configuration:" -ForegroundColor Cyan
        Write-Host "  ADK Path: $ADKPath" -ForegroundColor White
        Write-Host "  USB Drive: $USBDrive" -ForegroundColor White
        Write-Host "  Auto-Start: $AutoStart" -ForegroundColor White
        Write-Host "  Keep Build Files: $KeepBuildFiles" -ForegroundColor White
        Write-Host "  Rebuild Only: $RebuildOnly" -ForegroundColor White
        Write-Host ""

        $architectures = @('amd64', 'arm64')

        # Create bootable USB
        $finalUSBPath = New-BootableUSB -Drive $USBDrive

        if (-not (Test-Path "$script:WorkingDirectory\WinPE_Combined")) {
            foreach ($architecture in $architectures) {
                # Create WinPE working directory
                New-WinPEWorkingDirectory -ADKPath $ADKPath -Architecture $architecture

                # Mount WinPE image
                Mount-WinPEImage -Architecture $architecture

                # Add packages
                Add-WinPEPackages -ADKPath $ADKPath -Architecture $architecture

                # Create startnet.cmd
                New-StartNetCmd

                # Unmount image
                Dismount-WinPEImage -Architecture $architecture
            }

            # Create combined EZOSD files in working directory
            Copy-WinPEFilesToCombinedDirectory
        }

        # Copy files to USB
        Copy-Item -Path "$script:WorkingDirectory\WinPE_Combined\*" -Destination $finalUSBPath -Recurse -Force

        # Update boot configuration for multi-architecture support
        Update-BootConfiguration -USBDrive $USBDrive
        
        # Cleanup
        Write-Log "Cleaning up temporary files..."
        #Remove-Item -Path $script:WorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        
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
        
        # Attempt cleanup
        if (Test-Path $script:MountDirectory) {
            Write-Log "Attempting to unmount WinPE image..." -Level Warning
            try {
                Dismount-WindowsImage -Path $script:MountDirectory -Discard -ErrorAction SilentlyContinue
            }
            catch {
                Write-Log "Manual cleanup may be required: $script:MountDirectory" -Level Warning
            }
        }
        
        # if (Test-Path $script:WorkingDirectory) {
        #     Write-Log "Cleaning up working directory..." -Level Warning
        #     try {
        #         Remove-Item -Path $script:WorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        #     }
        #     catch {
        #         Write-Log "Manual cleanup may be required: $script:WorkingDirectory" -Level Warning
        #     }
        # }
        
        return $false
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
