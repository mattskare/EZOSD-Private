# Enable location services so the time zone will be set automatically (even when skipping the privacy page in OOBE) when an administrator signs in
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type "String" -Value "Allow" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type "DWord" -Value 1 -Force
Start-Service -Name "lfsvc" -ErrorAction SilentlyContinue

# Checks Auto Time Zone service status, and sets it to Manual if needed
#region Settings
$ServiceName = 'tzautoupdate'
$Action = 'Manual'
#endregion
#region Functions
function Set-Services {
    Param
    (
        [string]$ServiceName,
        [ValidateSet("Start", "Stop", "Restart", "Disable", "Auto", "Manual")]
        [string]$Action
    )

    try {
        Start-Transcript -Path "C:\Windows\Temp\$($ServiceName)_Management.Log" -Force -ErrorAction SilentlyContinue
        Get-Date
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $service
        if ($service) {
            Switch ($Action) {
                "Start" { Start-Service -Name $ServiceName; Break; }
                "Stop" { Stop-Service -Name $ServiceName; Break; }
                "Restart" { Restart-Service -Name $ServiceName; Break; }
                "Disable" { Set-Service -Name $ServiceName -StartupType Disabled -Status Stopped; Break; }
                "Auto" { Set-Service -Name $ServiceName -StartupType Automatic -Status Running; Break; }
                "Manual" { Set-Service -Name $ServiceName -StartupType Manual -Status Running; Break; }
            }
            Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        }
        Stop-Transcript -ErrorAction SilentlyContinue
    }
    catch {
        throw $_
    }
}

function Set-SleepSettings {
    Param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("AC", "DC")]
        [string]$PowerMode = "AC",
        
        [Parameter(Mandatory=$false)]
        # The GUID 29f6c1db-86da-48c5-9fdb-f2b67b1f44da represents the "sleep after" setting
        # Details for guids of power setting can be found by running "powercfg /query" in command prompt
        [string]$SettingGuid = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da",
        
        [Parameter(Mandatory=$false)]
        [int]$SettingValue = 0
    )
    
    try {
        Start-Transcript -Path "C:\Windows\Temp\SleepSettings_$PowerMode.Log" -Force -ErrorAction SilentlyContinue
        Write-Host "Setting power configuration for $PowerMode mode..."
        Write-Host "  Setting GUID: $SettingGuid"
        Write-Host "  Target Value: $SettingValue"
        
        # Get power setting data for specified power mode targeting a specific power setting GUID    
        $power = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | 
            Where-Object { $_.InstanceID -like "*$PowerMode*" -and $_.InstanceID -like "*$SettingGuid*" }

        if (-not $power) {
            Write-Warning "No power settings found matching PowerMode: $PowerMode and GUID: $SettingGuid"
            return $false
        }

        $successCount = 0
        $failureCount = 0

        # Loop through each matching power setting
        foreach ($setting in $power) {
            try {
                $originalValue = $setting.SettingIndexValue
                Write-Host "  Processing setting: $($setting.InstanceID)"
                Write-Host "    Original value: $originalValue"
                
                # Set the setting value to specified value
                $setting.SettingIndexValue = $SettingValue
                # Apply the modified setting
                Set-CimInstance -InputObject $setting -ErrorAction Stop
                
                # Verify the change was applied
                $verifyPower = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | 
                    Where-Object { $_.InstanceID -eq $setting.InstanceID }
                
                if ($verifyPower.SettingIndexValue -eq $SettingValue) {
                    Write-Host "    New value: $($verifyPower.SettingIndexValue) - Successfully applied" -ForegroundColor Green
                    $successCount++
                } else {
                    Write-Warning "    Verification failed. Expected: $SettingValue, Got: $($verifyPower.SettingIndexValue)"
                    $failureCount++
                }
            }
            catch {
                Write-Error "    Failed to apply setting: $($_.Exception.Message)"
                $failureCount++
            }
        }

        Write-Host "`nSummary: $successCount succeeded, $failureCount failed"
        Stop-Transcript -ErrorAction SilentlyContinue
        return ($failureCount -eq 0)
    }
    catch {
        Write-Error "Error in Set-SleepSettings: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Process
try {
    Write-Host "Disabling Sleep After settings on AC power..."
    $acResult = Set-SleepSettings -PowerMode "AC" -SettingValue 0

    if ($acResult) {
        Write-Host "Sleep After settings successfully disabled on AC power." -ForegroundColor Green
    } else {
        Write-Warning "One or more Sleep After settings failed to apply."
    }
}
catch {
    Write-Error $_.Exception.Message
}

try {
    Write-Host "Fixing TimeZone service statup type to MANUAL."
    Set-Services -ServiceName $ServiceName -Action $Action
    Exit 0
}
catch {
    Write-Error $_.Exception.Message
}
#endregion