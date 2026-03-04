<#
.SYNOPSIS
    Build script for creating standalone EZOSD deployment script.
.DESCRIPTION
    Combines all EZOSD modules and the Deploy-Windows.ps1 script into a single
    standalone PowerShell script that can be distributed and run without dependencies.
.PARAMETER OutputPath
    Path where the standalone script will be saved.
.PARAMETER IncludeDebugInfo
    Include build metadata and source file markers in the output.
.EXAMPLE
    .\Build-Standalone.ps1
    Build with default settings.
.EXAMPLE
    .\Build-Standalone.ps1 -OutputPath "C:\Output\Deploy-Windows-Standalone.ps1" -IncludeDebugInfo
    Build with custom output path and debug markers.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "..\EZOSD.ps1",
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDebugInfo
)

$ErrorActionPreference = "Stop"

# Resolve paths
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$srcPath = Join-Path $repoRoot "src"
$deployScript = Join-Path $repoRoot "Deploy-Windows.ps1"
$versionFile = Join-Path $repoRoot "VERSION"
$outputFile = Join-Path $scriptRoot $OutputPath

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         EZOSD Standalone Build Script                        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Validate source files exist
Write-Host "[1/5] Validating source files..." -ForegroundColor Yellow

$requiredFiles = @(
    $deployScript,
    $versionFile,
    (Join-Path $srcPath "EZOSD-Logger.psm1"),
    (Join-Path $srcPath "EZOSD-Core.psm1"),
    (Join-Path $srcPath "EZOSD-Download.psm1"),
    (Join-Path $srcPath "EZOSD-Disk.psm1"),
    (Join-Path $srcPath "EZOSD-Image.psm1"),
    (Join-Path $srcPath "EZOSD-Driver.psm1"),
    (Join-Path $srcPath "EZOSD-Updates.psm1"),
    (Join-Path $srcPath "EZOSD-PostInstall.psm1")
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        throw "Required file not found: $file"
    }
}

Write-Host "  ✓ All source files found" -ForegroundColor Green

# Read version
$version = (Get-Content $versionFile -Raw).Trim()
Write-Host "  ✓ Version: $version" -ForegroundColor Green

# Define module order (Logger must be first as others depend on it)
$moduleOrder = @(
    "EZOSD-Logger.psm1",
    "EZOSD-Core.psm1",
    "EZOSD-Disk.psm1",
    "EZOSD-Download.psm1",
    "EZOSD-Image.psm1",
    "EZOSD-Driver.psm1",
    "EZOSD-Updates.psm1",
    "EZOSD-PostInstall.psm1"
)

Write-Host "`n[2/5] Processing modules..." -ForegroundColor Yellow

# Start building the combined script
$combinedScript = @"
<#
.SYNOPSIS
    EZOSD - Enterprise Zero-Touch Operating System Deployment
    Standalone Deployment Script
.DESCRIPTION
    Combined standalone version of EZOSD. All modules are embedded.
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
    .\Deploy-Windows-Standalone.ps1
    Run with default settings and configuration.
.EXAMPLE
    .\Deploy-Windows-Standalone.ps1 -ConfigPath "C:\CustomConfig\deployment.json" -LogLevel Debug
    Run with custom configuration and debug logging.
.NOTES
    Version: $version
    Build Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Requires: WinPE environment, PowerShell 5.1+, DISM module
    
    This is a standalone build that includes all EZOSD modules:
$($moduleOrder | ForEach-Object { "    - $_" })
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = `$false)]
    [string]`$ConfigPath = "config\deployment.json",
    
    [Parameter(Mandatory = `$false)]
    [ValidateSet("Debug", "Info", "Warning", "Error")]
    [string]`$LogLevel = "Info",
    
    [Parameter(Mandatory = `$false)]
    [switch]`$Interactive,
    
    [Parameter(Mandatory = `$false)]
    [switch]`$SkipDrivers,
    
    [Parameter(Mandatory = `$false)]
    [switch]`$SkipPostInstall
)

# Set error action preference
`$ErrorActionPreference = "Stop"

#region Embedded Modules

"@

# Process each module
foreach ($moduleName in $moduleOrder) {
    $modulePath = Join-Path $srcPath $moduleName
    Write-Host "  Processing $moduleName..." -ForegroundColor White
    
    # Read module content
    $moduleContent = Get-Content $modulePath -Raw
    
    # Strip the header comment block (first occurrence of <# ... #>)
    $moduleContent = $moduleContent -replace '(?s)^<#.*?#>\s*', ''
    
    # Strip "using module" statements
    $moduleContent = $moduleContent -replace '(?m)^using\s+module\s+.*$\s*', ''
    
    # Strip Export-ModuleMember statements (including multi-line)
    $moduleContent = $moduleContent -replace '(?s)Export-ModuleMember\s+-Function\s+@\([^)]*\)\s*', ''
    
    # Add module section marker if debug info enabled
    if ($IncludeDebugInfo) {
        $combinedScript += @"

#region $moduleName
# Source: src/$moduleName

"@
    } else {
        $combinedScript += "`n#region $moduleName`n"
    }
    
    # Add the processed module content
    $combinedScript += $moduleContent.TrimEnd()
    
    # Close region
    $combinedScript += "`n#endregion $moduleName`n"
    
    Write-Host "    ✓ Added ($([math]::Round((Get-Content $modulePath).Length / 1KB, 1)) KB)" -ForegroundColor Green
}

$combinedScript += @"

#endregion Embedded Modules

"@

Write-Host "`n[3/5] Processing main deployment script..." -ForegroundColor Yellow

# Read the main deployment script
$deployContent = Get-Content $deployScript -Raw

# Find where the actual script logic starts (after the Import-Module statements)
# We'll split on the line that marks the end of imports
$lines = Get-Content $deployScript

$scriptStartIndex = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*Import-Module.*EZOSD-PostInstall') {
        # Found the last import, start after the next blank line
        $scriptStartIndex = $i + 1
        while ($scriptStartIndex -lt $lines.Count -and $lines[$scriptStartIndex].Trim() -eq '') {
            $scriptStartIndex++
        }
        break
    }
}

# Also remove the param block and initial comments from Deploy-Windows.ps1
# since we already have them at the top
$deployLogic = -join ($lines[$scriptStartIndex..($lines.Count - 1)] | ForEach-Object { "$_`n" })

if ($IncludeDebugInfo) {
    $combinedScript += @"

#region Main Deployment Logic
# Source: Deploy-Windows.ps1

"@
} else {
    $combinedScript += "`n#region Main Deployment Logic`n"
}

$combinedScript += $deployLogic.TrimEnd()
$combinedScript += "`n#endregion Main Deployment Logic`n"

Write-Host "  ✓ Main logic added" -ForegroundColor Green

Write-Host "`n[4/5] Writing output file..." -ForegroundColor Yellow

# Ensure output directory exists
$outputDir = Split-Path -Parent $outputFile
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# Write the combined script
$combinedScript | Out-File -FilePath $outputFile -Encoding UTF8 -Force

$outputSize = [math]::Round((Get-Item $outputFile).Length / 1KB, 1)
Write-Host "  ✓ Written to: $outputFile" -ForegroundColor Green
Write-Host "  ✓ Size: $outputSize KB" -ForegroundColor Green

Write-Host "`n[5/5] Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Standalone script created successfully!                     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output: $outputFile" -ForegroundColor White
Write-Host "Size: $outputSize KB" -ForegroundColor White
Write-Host ""
Write-Host "You can now run the standalone script with:" -ForegroundColor Yellow
Write-Host "  .\Deploy-Windows-Standalone.ps1" -ForegroundColor White
Write-Host ""
