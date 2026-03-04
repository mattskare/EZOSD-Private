<#
.SYNOPSIS
    EZOSD Core Module
.DESCRIPTION
    Core orchestration and initialization functions for EZOSD.
    Handles configuration loading, environment validation, and workflow coordination.
#>

using module .\EZOSD-Logger.psm1

# Module variables
$Script:Config = $null
$Script:EZOSDVersion = $null
$Script:DeploymentStartTime = $null

<#
.SYNOPSIS
    Initializes the EZOSD environment.
.PARAMETER ConfigPath
    Path to deployment configuration file.
.PARAMETER LogLevel
    Logging level (Debug, Info, Warning, Error).
#>
function Initialize-EZOSD {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "config\deployment.json",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$LogLevel = "Info"
    )
    
    $Script:DeploymentStartTime = Get-Date
    
    try {
        # Initialize logger
        Initialize-EZOSDLogger -Level $LogLevel
        
        Write-EZOSDLogSection -Title "EZOSD Initialization"
        
        # Load version
        $versionFile = Join-Path $PSScriptRoot "..\VERSION"
        if (Test-Path $versionFile) {
            $Script:EZOSDVersion = (Get-Content $versionFile -Raw).Trim()
            Write-EZOSDLog -Message "EZOSD Version: $Script:EZOSDVersion" -Level Info
        }
        
        # Validate WinPE environment
        Write-EZOSDLog -Message "Validating WinPE environment..." -Level Info
        if (-not (Test-WinPEEnvironment)) {
            throw "Not running in a valid WinPE environment"
        }
        
        # Load configuration
        Write-EZOSDLog -Message "Loading configuration from: $ConfigPath" -Level Info
        $Script:Config = Get-EZOSDConfiguration -ConfigPath $ConfigPath
        
        Write-EZOSDLog -Message "EZOSD initialized successfully" -Level Info
        return $true
    }
    catch {
        Write-EZOSDError -Message "Failed to initialize EZOSD" -Exception $_.Exception
        return $false
    }
}

<#
.SYNOPSIS
    Loads and validates the deployment configuration.
.PARAMETER ConfigPath
    Path to configuration file.
#>
function Get-EZOSDConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    try {
        # Resolve relative paths
        if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
            $scriptRoot = Split-Path -Parent $PSScriptRoot
            $ConfigPath = Join-Path $scriptRoot $ConfigPath
        }
        
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }
        
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        # Validate required fields
        $requiredFields = @('WindowsVersion', 'Edition', 'TargetDisk', 'PartitionScheme')
        foreach ($field in $requiredFields) {
            if (-not $config.PSObject.Properties[$field]) {
                throw "Missing required configuration field: $field"
            }
        }
        
        Write-EZOSDLog -Message "Configuration loaded successfully" -Level Info
        Write-EZOSDLog -Message "Windows Version: $($config.WindowsVersion)" -Level Info
        Write-EZOSDLog -Message "Edition: $($config.Edition)" -Level Info
        Write-EZOSDLog -Message "Partition Scheme: $($config.PartitionScheme)" -Level Info
        
        return $config
    }
    catch {
        Write-EZOSDError -Message "Failed to load configuration" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Validates the WinPE environment.
#>
function Test-WinPEEnvironment {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        # Check if running in WinPE
        $isWinPE = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT"
        
        if (-not $isWinPE) {
            Write-EZOSDLog -Message "Warning: Not running in WinPE environment" -Level Warning
            # Don't fail - allow testing in full Windows
        }
        
        # Check for required PowerShell modules
        Write-EZOSDLog -Message "Checking for required PowerShell modules..." -Level Info
        
        $requiredModules = @('Storage', 'DISM')
        foreach ($moduleName in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $moduleName)) {
                Write-EZOSDLog -Message "Required module not found: $moduleName" -Level Warning
            }
            else {
                Write-EZOSDLog -Message "Module available: $moduleName" -Level Debug
            }
        }
        
        # Check for DISM.exe
        $dismPath = (Get-Command dism.exe -ErrorAction SilentlyContinue).Source
        if ($dismPath) {
            Write-EZOSDLog -Message "DISM found at: $dismPath" -Level Debug
        }
        else {
            Write-EZOSDLog -Message "DISM.exe not found in PATH" -Level Warning
        }
        
        # Check network connectivity
        Write-EZOSDLog -Message "Checking network connectivity..." -Level Info
        $networkAvailable = Test-NetworkConnectivity
        
        if ($networkAvailable) {
            Write-EZOSDLog -Message "Network connectivity: Available" -Level Info
        }
        else {
            Write-EZOSDLog -Message "Network connectivity: Not available" -Level Warning
        }
        
        return $true
    }
    catch {
        Write-EZOSDError -Message "Environment validation failed" -Exception $_.Exception
        return $false
    }
}

<#
.SYNOPSIS
    Tests network connectivity.
#>
function Test-NetworkConnectivity {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        # Try to ping a reliable host
        $testHosts = @('8.8.8.8', '1.1.1.1')
        foreach ($testHost in $testHosts) {
            $pingResult = Test-Connection -ComputerName $testHost -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($pingResult) {
                Write-EZOSDLog -Message "Successfully pinged $testHost" -Level Debug
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Gets the current deployment configuration.
#>
function Get-CurrentConfiguration {
    return $Script:Config
}

<#
.SYNOPSIS
    Gets deployment statistics.
#>
function Get-DeploymentStatistics {
    [CmdletBinding()]
    param()
    
    $stats = @{
        StartTime = $Script:DeploymentStartTime
        ElapsedTime = $null
        Version = $Script:EZOSDVersion
    }
    
    if ($Script:DeploymentStartTime) {
        $stats.ElapsedTime = (Get-Date) - $Script:DeploymentStartTime
    }
    
    return $stats
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-EZOSD',
    'Get-EZOSDConfiguration',
    'Test-WinPEEnvironment',
    'Test-NetworkConnectivity',
    'Get-CurrentConfiguration',
    'Get-DeploymentStatistics'
)
