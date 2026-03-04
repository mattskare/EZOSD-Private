<#
.SYNOPSIS
    EZOSD - Enterprise Zero-Touch Operating System Deployment
    Main Deployment Script
.DESCRIPTION
    Orchestrates the complete Windows deployment workflow from WinPE.
    Downloads Windows ESD, partitions disk, applies image, injects drivers,
    and configures post-installation automation.
.PARAMETER ConfigPath
    Path to deployment configuration file.
.PARAMETER LogLevel
    Logging level (Debug, Info, Warning, Error).
.PARAMETER Interactive
    Enable interactive prompts for disk/edition selection.
.PARAMETER SkipDrivers
    Skip driver download and injection.
.PARAMETER SkipPostInstall
    Skip post-installation configuration.
.EXAMPLE
    .\Deploy-Windows.ps1
    Run with default settings and configuration.
.EXAMPLE
    .\Deploy-Windows.ps1 -ConfigPath "C:\CustomConfig\deployment.json" -LogLevel Debug
    Run with custom configuration and debug logging.
.NOTES
    Version: 0.1.0-alpha
    Requires: WinPE environment, PowerShell 5.1+, DISM module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config\deployment.json",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Info", "Warning", "Error")]
    [string]$LogLevel = "Info",
    
    [Parameter(Mandatory = $false)]
    [switch]$Interactive,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipDrivers,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipPostInstall
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Import modules
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $scriptRoot "src"

Import-Module (Join-Path $modulePath "EZOSD-Logger.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-Core.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-Download.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-Disk.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-Image.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-Driver.psm1") -Force
Import-Module (Join-Path $modulePath "EZOSD-PostInstall.psm1") -Force

<#
.SYNOPSIS
    Main deployment workflow.
#>
function Start-Deployment {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host " ███████╗███████╗ ██████╗ ███████╗██████╗ " -ForegroundColor Cyan
        Write-Host " ██╔════╝╚══███╔╝██╔═══██╗██╔════╝██╔══██╗" -ForegroundColor Cyan
        Write-Host " █████╗    ███╔╝ ██║   ██║███████╗██║  ██║" -ForegroundColor Cyan
        Write-Host " ██╔══╝   ███╔╝  ██║   ██║╚════██║██║  ██║" -ForegroundColor Cyan
        Write-Host " ███████╗███████╗╚██████╔╝███████║██████╔╝" -ForegroundColor Cyan
        Write-Host " ╚══════╝╚══════╝ ╚═════╝ ╚══════╝╚═════╝ " -ForegroundColor Cyan

        # Banner
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║         EZOSD - Enterprise Windows Deployment Tool            ║" -ForegroundColor Cyan
        Write-Host "║                    Version 0.1.0-alpha                        ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        # Initialize EZOSD
        Write-Host "Initializing EZOSD..." -ForegroundColor Yellow
        $initResult = Initialize-EZOSD -ConfigPath $ConfigPath -LogLevel $LogLevel
        
        if (-not $initResult) {
            throw "EZOSD initialization failed"
        }
        
        # Get configuration
        $config = Get-CurrentConfiguration
        
        # Display configuration summary
        Write-Host "`nDeployment Configuration:" -ForegroundColor Cyan
        Write-Host "  Windows Version: $($config.WindowsVersion)" -ForegroundColor White
        Write-Host "  Edition: $($config.Edition)" -ForegroundColor White
        Write-Host "  Partition Scheme: $($config.PartitionScheme)" -ForegroundColor White
        Write-Host ""
        
        # Confirm deployment
        if ($Interactive) {
            $confirm = Read-Host "Proceed with deployment? (Y/N)"
            if ($confirm -ne "Y" -and $confirm -ne "y") {
                Write-EZOSDLog -Message "Deployment cancelled by user" -Level Info
                return $false
            }
        }
        
        # Step 1: Select target disk
        Write-Host "`n[Step 1/6] Disk Selection" -ForegroundColor Yellow
        
        $targetDisk = Select-EZOSDTargetDisk -DiskNumber $config.TargetDisk -Interactive:$Interactive
        
        Write-Host "  ✓ Selected disk $($targetDisk.Number): $([math]::Round($targetDisk.Size / 1GB, 2)) GB" -ForegroundColor Green

        # Step 2: Partition disk
        
        # Confirm disk partitioning
        if ($Interactive) {
            $confirmPartition = Read-Host "This will partition and format disk $($targetDisk.Number). All data on this disk will be lost. Proceed? (Y/N)"
            if ($confirmPartition -ne "Y" -and $confirmPartition -ne "y") {
                Write-EZOSDLog -Message "Disk partitioning cancelled by user" -Level Info
                return $false
            }
        }
        
        Write-Host "`n[Step 2/6] Disk Partitioning" -ForegroundColor Yellow
        
        $partitions = Initialize-EZOSDDisk -Disk $targetDisk -PartitionScheme $config.PartitionScheme
        
        $systemPartition = $partitions.System
        $windowsDrive = $partitions.Windows.DriveLetter
        
        Write-Host "  ✓ Disk partitioned successfully" -ForegroundColor Green
        Write-Host "    System: No drive letter" -ForegroundColor White
        Write-Host "    Windows: ${windowsDrive}:" -ForegroundColor White
        
        # Step 3: Download or locate Windows ESD
        Write-Host "`n[Step 3/6] Windows ESD Acquisition" -ForegroundColor Yellow
        
        $esdPath = $null
        if ($config.ESDPath -and (Test-Path $config.ESDPath)) {
            Write-EZOSDLog -Message "Using ESD from configuration: $($config.ESDPath)" -Level Info
            $esdPath = $config.ESDPath
        }
        elseif ($config.ESDDownloadURL) {
            Write-EZOSDLog -Message "Downloading ESD from configured URL..." -Level Info
            # Use configured download path or default
            $downloadPath = if ($config.DownloadPath) { $config.DownloadPath } else { "C:\EZOSD\Downloads" }
            $esdDestination = Join-Path $downloadPath "install.esd"
            $esdPath = Invoke-EZOSDDownload -Url $config.ESDDownloadURL -DestinationPath $esdDestination
        }
        else {
            Write-EZOSDLog -Message "Attempting to download Windows ESD..." -Level Info
            # Use configured download path if available
            $downloadParams = @{
                Version = $config.WindowsVersion
                Edition = $config.Edition
                Release = $config.WindowsRelease
                Architecture = $config.Architecture
            }
            if ($config.DownloadPath) {
                $downloadParams['DestinationPath'] = $config.DownloadPath
            }
            $esdPath = Get-WindowsESD @downloadParams
        }
        
        if (-not $esdPath -or -not (Test-Path $esdPath)) {
            throw "Failed to acquire Windows ESD. Please configure ESDPath or ESDDownloadURL in deployment.json"
        }
        
        Write-Host "  ✓ ESD located: $esdPath" -ForegroundColor Green
        
        # Step 4: Select and apply Windows image
        Write-Host "`n[Step 4/6] Windows Image Deployment" -ForegroundColor Yellow
        
        $imageIndex = Select-WindowsEdition -ImagePath $esdPath -EditionName $config.Edition -Interactive:$Interactive
        
        $imageInstalled = Install-WindowsImage -ImagePath $esdPath -Index $imageIndex -TargetDrive $windowsDrive
        
        if (-not $imageInstalled) {
            throw "Failed to install Windows image"
        }
        
        Write-Host "  ✓ Windows image applied successfully" -ForegroundColor Green
        
        # Step 5: Install drivers
        if (-not $SkipDrivers -and $config.DriverSources) {
            Write-Host "`n[Step 5/6] Driver Installation" -ForegroundColor Yellow
            
            $driversInstalled = Install-ConfiguredDrivers -DriverConfig $config.DriverSources -TargetDrive $windowsDrive
            
            if ($driversInstalled) {
                Write-Host "  ✓ Drivers installed successfully" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ Driver installation completed with warnings" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n[Step 5/6] Driver Installation - SKIPPED" -ForegroundColor Gray
        }
        
        # Step 6: Configure post-installation
        if (-not $SkipPostInstall) {
            Write-Host "`n[Step 6/6] Post-Installation Configuration" -ForegroundColor Yellow
            
            $postInstallConfigured = Set-PostInstallConfiguration -TargetDrive $windowsDrive -Configuration $config
            
            if ($postInstallConfigured) {
                Write-Host "  ✓ Post-installation configured" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ Post-installation configuration completed with warnings" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n[Step 6/6] Post-Installation Configuration - SKIPPED" -ForegroundColor Gray
        }
        
        # Configure boot
        Write-Host "`nConfiguring boot loader..." -ForegroundColor Yellow
        
        $bootConfigured = Set-WindowsBootConfiguration -WindowsDrive $windowsDrive -SystemPartition $systemPartition -PartitionScheme $config.PartitionScheme
        
        if ($bootConfigured) {
            Write-Host "  ✓ Boot configuration completed" -ForegroundColor Green
        }
        
        # Display completion summary
        $stats = Get-DeploymentStatistics

        # Copy log file to Windows partition for post-deployment access
        if (Get-EZOSDLogPath) {
            $logDestination = Join-Path ${windowsDrive}":" "EZOSD\EZOSD-Deployment.log"
            try {
                Copy-Item -Path (Get-EZOSDLogPath) -Destination $logDestination -ErrorAction Stop
                Write-Host "  ✓ Log file copied to Windows partition: $logDestination" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to copy log file to Windows partition: $_"
            }
        }

        #region Temp
        # Temporarily copy module files to Windows partition for post-install script access
        $postInstallModulePath = Join-Path ${windowsDrive}":" "EZOSD\Modules"
        try {
            if (-not (Test-Path $postInstallModulePath)) {
                New-Item -Path $postInstallModulePath -ItemType Directory -ErrorAction Stop | Out-Null
            }
            Get-ChildItem -Path $modulePath\*.psm1 -ErrorAction Stop | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $postInstallModulePath -ErrorAction Stop
            }
            Write-Host "  ✓ Module files copied to Windows partition for post-install script access" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to copy module files to Windows partition: $_"
        }
        #endregion Temp
        
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║              DEPLOYMENT COMPLETED SUCCESSFULLY                ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "Deployment Summary:" -ForegroundColor Cyan
        Write-Host "  Start Time: $($stats.StartTime)" -ForegroundColor White
        Write-Host "  Duration: $([math]::Round($stats.ElapsedTime.TotalMinutes, 2)) minutes" -ForegroundColor White
        Write-Host "  Windows Drive: ${windowsDrive}:" -ForegroundColor White
        Write-Host "  Log File: $(Get-EZOSDLogPath)" -ForegroundColor White
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Remove installation media" -ForegroundColor White
        Write-Host "  2. Restart the computer" -ForegroundColor White
        Write-Host "  3. Windows will complete setup automatically" -ForegroundColor White
        Write-Host ""
        
        if ($Interactive) {
            Read-Host "Press Enter to exit"
        }
        
        return $true
    }
    catch {
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                  DEPLOYMENT FAILED                            ║" -ForegroundColor Red
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-EZOSDError -Message "Deployment failed" -Exception $_.Exception
        Write-Host ""
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "Check log file: $(Get-EZOSDLogPath)" -ForegroundColor Yellow
        Write-Host ""
        
        if ($Interactive) {
            Read-Host "Press Enter to exit"
        }
        
        return $false
    }
}

# Execute deployment
$deploymentResult = Start-Deployment

# Exit with appropriate code
if ($deploymentResult) {
    exit 0
}
else {
    exit 1
}
