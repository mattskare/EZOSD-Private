<#
.SYNOPSIS
    EZOSD Logging Module
.DESCRIPTION
    Provides centralized logging functionality for EZOSD deployment operations.
    Supports console and file output with severity levels and timestamps.
#>

# Module variables
$Script:LogPath = $null
$Script:LogLevel = "Info"
$Script:LogToConsole = $true
$Script:LogToFile = $true
$Script:LogLevels = @{
    "Debug" = 0
    "Info" = 1
    "Warning" = 2
    "Error" = 3
}

<#
.SYNOPSIS
    Initializes the logging system.
.PARAMETER LogDirectory
    Directory where log files will be stored.
.PARAMETER Level
    Minimum log level to record (Debug, Info, Warning, Error).
.PARAMETER Console
    Whether to output logs to console.
#>
function Initialize-EZOSDLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = "X:\Windows\Logs\EZOSD",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [bool]$Console = $true
    )
    
    try {
        # Create log directory if it doesn't exist
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        
        # Set log file path with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Script:LogPath = Join-Path $LogDirectory "EZOSD_$timestamp.log"
        $Script:LogLevel = $Level
        $Script:LogToConsole = $Console
        
        # Write initial log entry
        Write-EZOSDLog -Message "EZOSD Logging initialized" -Level Info
        Write-EZOSDLog -Message "Log file: $Script:LogPath" -Level Info
        Write-EZOSDLog -Message "Log level: $Level" -Level Info
        
        return $true
    }
    catch {
        Write-Warning "Failed to initialize logger: $_"
        $Script:LogToFile = $false
        return $false
    }
}

<#
.SYNOPSIS
    Writes a log message.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    Severity level of the message.
.PARAMETER NoConsole
    Suppress console output for this message.
#>
function Write-EZOSDLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )
    
    # Check if message should be logged based on level
    if ($Script:LogLevels[$Level] -lt $Script:LogLevels[$Script:LogLevel]) {
        return
    }
    
    # Format log entry
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    if ($Script:LogToConsole -and -not $NoConsole) {
        switch ($Level) {
            "Debug"   { Write-Host $logEntry -ForegroundColor Gray }
            "Info"    { Write-Host $logEntry -ForegroundColor White }
            "Warning" { Write-Host $logEntry -ForegroundColor Yellow }
            "Error"   { Write-Host $logEntry -ForegroundColor Red }
        }
    }
    
    # Write to file
    if ($Script:LogToFile -and $Script:LogPath) {
        try {
            Add-Content -Path $Script:LogPath -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}

<#
.SYNOPSIS
    Writes an error log with exception details.
.PARAMETER Message
    Error message.
.PARAMETER Exception
    Exception object to log.
#>
function Write-EZOSDError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception
    )
    
    Write-EZOSDLog -Message $Message -Level Error
    
    if ($Exception) {
        Write-EZOSDLog -Message "Exception: $($Exception.Message)" -Level Error
        Write-EZOSDLog -Message "Stack Trace: $($Exception.StackTrace)" -Level Debug
    }
}

<#
.SYNOPSIS
    Gets the current log file path.
#>
function Get-EZOSDLogPath {
    return $Script:LogPath
}

<#
.SYNOPSIS
    Writes a section header to the log.
.PARAMETER Title
    Section title.
#>
function Write-EZOSDLogSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    
    $separator = "=" * 80
    Write-EZOSDLog -Message $separator -Level Info
    Write-EZOSDLog -Message $Title -Level Info
    Write-EZOSDLog -Message $separator -Level Info
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-EZOSDLogger',
    'Write-EZOSDLog',
    'Write-EZOSDError',
    'Get-EZOSDLogPath',
    'Write-EZOSDLogSection'
)
