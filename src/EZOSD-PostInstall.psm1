<#
.SYNOPSIS
    EZOSD Post-Installation Module
.DESCRIPTION
    Handles post-installation automation including SetupComplete.cmd creation
    and script deployment. Device provisioning is handled by Windows Autopilot
    (Azure AD/Intune).
#>

using module .\EZOSD-Logger.psm1

function New-SetupCompleteScript {
    <#
    .SYNOPSIS
        Creates SetupComplete.cmd for post-installation tasks.
    .PARAMETER TargetDrive
        Drive letter where Windows is installed.
    .PARAMETER Scripts
        Array of scripts to execute.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive,
        
        [Parameter(Mandatory = $false)]
        [array]$Scripts = @()
    )
    
    Write-EZOSDLog -Message "Creating SetupComplete.cmd..." -Level Info
    
    try {
        $setupScriptsPath = "${TargetDrive}:\Windows\Setup\Scripts"
        $setupCompletePath = Join-Path $setupScriptsPath "SetupComplete.cmd"
        
        # Create Scripts directory
        if (-not (Test-Path $setupScriptsPath)) {
            New-Item -Path $setupScriptsPath -ItemType Directory -Force | Out-Null
        }
        
        # Generate SetupComplete.cmd content
        $setupCompleteContent = @"
@echo off
REM EZOSD Post-Installation Script
REM Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

echo EZOSD Post-Installation Starting...

REM Create log directory
if not exist "C:\Windows\Logs\EZOSD" mkdir "C:\Windows\Logs\EZOSD"

REM Log start time
echo Post-Installation Started: %date% %time% >> C:\Windows\Logs\EZOSD\PostInstall.log

"@
        
        # Add configured scripts
        if ($Scripts -and $Scripts.Count -gt 0) {
            $setupCompleteContent += "`r`nREM Execute configured post-installation scripts`r`n"
            
            foreach ($script in $Scripts) {
                $setupCompleteContent += "echo Executing: $script >> C:\Windows\Logs\EZOSD\PostInstall.log`r`n"
                
                if ($script -like "*.ps1") {
                    $setupCompleteContent += "PowerShell.exe -ExecutionPolicy Bypass -File `"$script`" >> C:\Windows\Logs\EZOSD\PostInstall.log 2>&1`r`n"
                }
                elseif ($script -like "*.cmd" -or $script -like "*.bat") {
                    $setupCompleteContent += "call `"$script`" >> C:\Windows\Logs\EZOSD\PostInstall.log 2>&1`r`n"
                }
                else {
                    $setupCompleteContent += "call `"$script`" >> C:\Windows\Logs\EZOSD\PostInstall.log 2>&1`r`n"
                }
            }
        }
        
        # Add completion logging
        $setupCompleteContent += @"

REM Log completion
echo Post-Installation Completed: %date% %time% >> C:\Windows\Logs\EZOSD\PostInstall.log

echo EZOSD Post-Installation Complete!

REM Exit
exit /b 0
"@
        
        # Write SetupComplete.cmd
        $setupCompleteContent | Out-File -FilePath $setupCompletePath -Encoding ASCII -Force
        
        Write-EZOSDLog -Message "SetupComplete.cmd created at: $setupCompletePath" -Level Info
        return $setupCompletePath
    }
    catch {
        Write-EZOSDError -Message "Failed to create SetupComplete.cmd" -Exception $_.Exception
        throw
    }
}

function Add-PostInstallScriptFromGitHub {
    <#
    .SYNOPSIS
        Adds a script from GitHub to the post-installation configuration.
    .PARAMETER PostInstallScriptUrl
        URL of the raw script on GitHub.
    .PARAMETER SetupCompletePath
        Path to the SetupComplete.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PostInstallScriptUrl,
        [Parameter(Mandatory = $false)]
        [string]$SetupCompletePath = "C:\Windows\Setup\Scripts\SetupComplete.ps1"
    )

    if (-not (Test-Path $SetupCompletePath)) {
        New-Item -Path $SetupCompletePath -ItemType File -Force
    }
    
    $contentToAdd = @"
 Start-Transcript -Path 'C:\EZOSD\Logs\SetupComplete.log' -ErrorAction Ignore
 `$url = '$PostInstallScriptUrl'; `$scriptContent = (Invoke-RestMethod -Uri `$url); Invoke-Expression `$scriptContent
 Stop-Transcript
"@

    Add-Content -Path $SetupCompletePath -Value $contentToAdd

    return $SetupCompletePath
}

function Set-PostInstallConfiguration {
    <#
    .SYNOPSIS
        Configures post-installation automation.
    .PARAMETER TargetDrive
        Drive letter where Windows is installed.
    .PARAMETER Configuration
        Configuration object with post-install settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive,
        
        [Parameter(Mandatory = $false)]
        [object]$Configuration
    )
    
    Write-EZOSDLogSection -Title "Post-Installation Configuration"
    
    try {
        Write-EZOSDLog -Message "Device will be provisioned via Windows Autopilot (Azure AD/Intune)" -Level Info
        
        # Copy post-install scripts if configured
        if ($Configuration -and $Configuration.PostInstallScript) {
            Write-EZOSDLog -Message "Processing post-install script..." -Level Info
            $copiedScript = Add-PostInstallScriptFromGitHub -PostInstallScriptUrl $Configuration.PostInstallScript

            $setupCompletePath = New-SetupCompleteScript -TargetDrive $TargetDrive -Scripts $copiedScript
        } else {
            Write-EZOSDLog -Message "No post-install script configured. Device will be fully provisioned by Autopilot." -Level Info
        }
        
        Write-EZOSDLog -Message "Post-installation configuration completed" -Level Info
        return $true
    }
    catch {
        Write-EZOSDError -Message "Failed to configure post-installation" -Exception $_.Exception
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'New-SetupCompleteScript',
    'Set-PostInstallConfiguration',
    'Add-PostInstallScriptFromGitHub'
)
