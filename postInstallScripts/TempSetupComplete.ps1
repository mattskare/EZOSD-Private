<#
.SYNOPSIS
    Custom Setup Complete Script - Windows Updates
.DESCRIPTION
    This script runs after Windows installation to automatically search, 
    download and install Windows updates using the EZOSD-Updates module.
.NOTES
    This script is designed to run as a Windows SetupComplete.cmd companion script.
    Place in C:\Windows\Setup\Scripts\ along with SetupComplete.cmd
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDrivers,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipReboot,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxUpdateIterations = 3
)

# Determine script and module paths
$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptRoot)) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$ModulePath = "C:\EZOSD\Modules\EZOSD-Updates.psm1"
$LogPath = Join-Path $env:SystemDrive "EZOSD\Logs"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Create transcript log
$TranscriptFile = Join-Path $LogPath "CustomSetupComplete_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $TranscriptFile -Force

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " EZOSD Custom Setup Complete - Windows Updates" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Import EZOSD-Updates module
    Write-Host "[INFO] Importing EZOSD-Updates module..." -ForegroundColor Green
    if (-not (Test-Path $ModulePath)) {
        Write-Host "[ERROR] EZOSD-Updates module not found at: $ModulePath" -ForegroundColor Red
        throw "Module not found"
    }
    
    Import-Module $ModulePath -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Module imported successfully" -ForegroundColor Green
    Write-Host ""
    
    # Test WUA availability
    Write-Host "[INFO] Testing Windows Update Agent availability..." -ForegroundColor Green
    if (-not (Test-WuaComAvailable)) {
        Write-Host "[ERROR] Windows Update Agent COM API is not available" -ForegroundColor Red
        throw "WUA COM API not available"
    }
    Write-Host "[SUCCESS] WUA is available" -ForegroundColor Green
    Write-Host ""
    
    # Ensure Windows Update service is running
    Write-Host "[INFO] Checking Windows Update service..." -ForegroundColor Green
    if (-not (Test-WuaServiceRunning)) {
        Write-Host "[ERROR] Windows Update service could not be started" -ForegroundColor Red
        throw "Windows Update service not running"
    }
    Write-Host "[SUCCESS] Windows Update service is running" -ForegroundColor Green
    Write-Host ""
    
    # Main update loop
    $iteration = 0
    $totalUpdatesInstalled = 0
    $rebootRequired = $false
    
    do {
        $iteration++
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " Update Iteration $iteration of $MaxUpdateIterations" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Search for updates
        Write-Host "[INFO] Searching for available updates..." -ForegroundColor Green
        $updates = Get-WindowsUpdates -IncludeDrivers $IncludeDrivers.IsPresent -IncludeHidden $false
        
        if (-not $updates -or $updates.Count -eq 0) {
            Write-Host "[INFO] No updates available" -ForegroundColor Green
            break
        }
        
        Write-Host "[INFO] Found $($updates.Count) update(s)" -ForegroundColor Green
        Write-Host ""
        
        # Display updates
        Write-Host "Updates to be installed:" -ForegroundColor Yellow
        foreach ($update in $updates) {
            $sizeInMB = [math]::Round($update.SizeBytes / 1MB, 2)
            Write-Host "  - $($update.Title)" -ForegroundColor White
            Write-Host "    KBs: $($update.KBs)" -ForegroundColor Gray
            Write-Host "    Size: $sizeInMB MB" -ForegroundColor Gray
            Write-Host "    Categories: $($update.Categories)" -ForegroundColor Gray
        }
        Write-Host ""
        
        # Extract WUA update objects
        $wuaUpdates = $updates | ForEach-Object { $_.WuaUpdate }
        
        # Download updates
        Write-Host "[INFO] Downloading updates..." -ForegroundColor Green
        $downloadSuccess = Save-WindowsUpdates -Updates $wuaUpdates
        
        if (-not $downloadSuccess) {
            Write-Host "[WARNING] Failed to download some or all updates" -ForegroundColor Yellow
            break
        }
        Write-Host "[SUCCESS] Updates downloaded successfully" -ForegroundColor Green
        Write-Host ""
        
        # Install updates
        Write-Host "[INFO] Installing updates..." -ForegroundColor Green
        $installSuccess = Install-WindowsUpdates -Updates $wuaUpdates
        
        if (-not $installSuccess) {
            Write-Host "[WARNING] Failed to install some or all updates" -ForegroundColor Yellow
            break
        }
        Write-Host "[SUCCESS] Updates installed successfully" -ForegroundColor Green
        Write-Host ""
        
        $totalUpdatesInstalled += $updates.Count
        
        # Check if reboot is required
        foreach ($update in $wuaUpdates) {
            if ($update.RebootRequired) {
                $rebootRequired = $true
                break
            }
        }
        
        if ($rebootRequired) {
            Write-Host "[INFO] Reboot is required to complete installation" -ForegroundColor Yellow
            break
        }
        
        # Brief pause between iterations
        if ($iteration -lt $MaxUpdateIterations) {
            Write-Host "[INFO] Waiting 5 seconds before next check..." -ForegroundColor Green
            Start-Sleep -Seconds 5
        }
        
    } while ($iteration -lt $MaxUpdateIterations)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Update Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total updates installed: $totalUpdatesInstalled" -ForegroundColor White
    Write-Host "Iterations completed: $iteration" -ForegroundColor White
    Write-Host "Reboot required: $rebootRequired" -ForegroundColor White
    Write-Host ""
    
    # Handle reboot
    if ($rebootRequired -and -not $SkipReboot) {
        Write-Host "[INFO] System will reboot in 60 seconds..." -ForegroundColor Yellow
        Write-Host "[INFO] Press Ctrl+C to cancel reboot" -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        
        Write-Host "[INFO] Initiating system restart..." -ForegroundColor Yellow
        Restart-Computer -Force
    }
    elseif ($rebootRequired -and $SkipReboot) {
        Write-Host "[WARNING] Reboot required but -SkipReboot was specified" -ForegroundColor Yellow
        Write-Host "[INFO] Please reboot the system manually to complete installation" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[SUCCESS] Custom Setup Complete script finished" -ForegroundColor Green
    
    # Get update history
    Write-Host ""
    Write-Host "[INFO] Recent update history:" -ForegroundColor Green
    $history = Get-WindowsUpdateHistory -MaxEntries 10
    if ($history) {
        foreach ($entry in $history) {
            Write-Host "  [$($entry.Date)] $($entry.Result) - $($entry.Title)" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] An error occurred during setup:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    exit 1
}
finally {
    Stop-Transcript
    Write-Host ""
    Write-Host "Transcript saved to: $TranscriptFile" -ForegroundColor Cyan
}

exit 0
