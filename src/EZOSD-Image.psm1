<#
.SYNOPSIS
    EZOSD Image Deployment Module
.DESCRIPTION
    Handles applying Windows ESD/WIM images to target disks using DISM.
#>

using module .\EZOSD-Logger.psm1

<#
.SYNOPSIS
    Applies Windows image to target partition.
.PARAMETER ImagePath
    Path to ESD or WIM file.
.PARAMETER Index
    Image index to apply.
.PARAMETER TargetDrive
    Drive letter where Windows will be installed.
#>
function Install-WindowsImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        
        [Parameter(Mandatory = $false)]
        [int]$Index = 1,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive
    )
    
    Write-EZOSDLogSection -Title "Windows Image Deployment"
    
    try {
        # Validate image path
        if (-not (Test-Path $ImagePath)) {
            throw "Image file not found: $ImagePath"
        }
        
        # Ensure target drive is formatted
        $targetPath = "${TargetDrive}:\"
        if (-not (Test-Path $targetPath)) {
            throw "Target drive not accessible: $targetPath"
        }
        
        Write-EZOSDLog -Message "Image: $ImagePath" -Level Info
        Write-EZOSDLog -Message "Index: $Index" -Level Info
        Write-EZOSDLog -Message "Target: $targetPath" -Level Info
        
        # Get image information
        $imageInfo = Get-WindowsImage -ImagePath $ImagePath -Index $Index
        Write-EZOSDLog -Message "Deploying: $($imageInfo.ImageName)" -Level Info
        Write-EZOSDLog -Message "Version: $($imageInfo.Version)" -Level Info
        Write-EZOSDLog -Message "Size: $([math]::Round($imageInfo.ImageSize / 1GB, 2)) GB" -Level Info
        
        # Apply image
        Write-EZOSDLog -Message "Applying Windows image (this may take several minutes)..." -Level Info
        $startTime = Get-Date
        
        Expand-WindowsImage -ImagePath $ImagePath -Index $Index -ApplyPath $targetPath -Verify -ErrorAction Stop
        
        $duration = (Get-Date) - $startTime
        Write-EZOSDLog -Message "Image applied in $([math]::Round($duration.TotalMinutes, 2)) minutes" -Level Info
        
        return $true
    }
    catch {
        Write-EZOSDError -Message "Failed to apply Windows image" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Configures boot files for the deployed Windows installation.
.PARAMETER WindowsDrive
    Drive letter where Windows is installed.
.PARAMETER SystemPartition
    System/boot partition object.
.PARAMETER PartitionScheme
    Partition scheme (UEFI or BIOS).
#>
function Set-WindowsBootConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory = $true)]
        [object]$SystemPartition,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("UEFI", "BIOS")]
        [string]$PartitionScheme
    )
    
    Write-EZOSDLogSection -Title "Boot Configuration"
    
    try {
        $windowsPath = "${WindowsDrive}:\Windows"
        
        Write-EZOSDLog -Message "Configuring boot for $PartitionScheme..." -Level Info
        Write-EZOSDLog -Message "Windows path: $windowsPath" -Level Debug
        
        # Temporarily assign a drive letter to the system partition for bcdboot
        Write-EZOSDLog -Message "Temporarily assigning drive letter to system partition..." -Level Debug
        $SystemPartition | Add-PartitionAccessPath -AssignDriveLetter
        
        # Refresh partition to get the assigned drive letter
        $systemPartitionRefreshed = Get-Partition -DiskNumber $SystemPartition.DiskNumber -PartitionNumber $SystemPartition.PartitionNumber
        $systemDrive = $systemPartitionRefreshed.DriveLetter
        $systemPath = "${systemDrive}:"
        
        Write-EZOSDLog -Message "System path: $systemPath" -Level Debug
        
        # Run BCDBoot
        if ($PartitionScheme -eq "UEFI") {
            Write-EZOSDLog -Message "Configuring UEFI boot..." -Level Info
            $bcdbootArgs = "$windowsPath /s $systemPath /f UEFI"
        }
        else {
            Write-EZOSDLog -Message "Configuring BIOS boot..." -Level Info
            $bcdbootArgs = "$windowsPath /s $systemPath /f BIOS"
        }
        
        Write-EZOSDLog -Message "Running: bcdboot $bcdbootArgs" -Level Debug
        $result = Start-Process -FilePath "bcdboot.exe" -ArgumentList $bcdbootArgs -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -ne 0) {
            throw "BCDBoot failed with exit code $($result.ExitCode)"
        }
        
        # Remove the drive letter from the system partition
        Write-EZOSDLog -Message "Removing drive letter from system partition..." -Level Debug
        Remove-PartitionAccessPath -DiskNumber $SystemPartition.DiskNumber -PartitionNumber $SystemPartition.PartitionNumber -AccessPath "${systemDrive}:"
        
        Write-EZOSDLog -Message "Boot configuration completed" -Level Info
        return $true
    }
    catch {
        Write-EZOSDError -Message "Failed to configure boot" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Selects Windows edition from ESD image.
.PARAMETER ImagePath
    Path to ESD/WIM file.
.PARAMETER EditionName
    Desired edition name (e.g., "Pro", "Enterprise").
.PARAMETER Interactive
    Whether to prompt user for selection.
#>
function Select-WindowsEdition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        
        [Parameter(Mandatory = $false)]
        [string]$EditionName,
        
        [Parameter(Mandatory = $false)]
        [bool]$Interactive = $false
    )
    
    try {
        Write-EZOSDLog -Message "Retrieving available editions..." -Level Info
        
        $images = Get-WindowsImage -ImagePath $ImagePath
        
        Write-EZOSDLog -Message "Found $($images.Count) edition(s)" -Level Info
        
        # If specific edition requested, find it
        if ($EditionName) {
            $selectedImage = $images | Where-Object { $_.ImageName -like "*$EditionName*" } | Select-Object -First 1
            
            if ($selectedImage) {
                Write-EZOSDLog -Message "Selected edition: $($selectedImage.ImageName) (Index $($selectedImage.ImageIndex))" -Level Info
                return $selectedImage.ImageIndex
            }
            else {
                Write-EZOSDLog -Message "Edition '$EditionName' not found" -Level Warning
            }
        }
        
        # Interactive selection
        if ($Interactive -and $images.Count -gt 1) {
            Write-Host "`nAvailable Windows editions:" -ForegroundColor Cyan
            foreach ($image in $images) {
                Write-Host "  [$($image.ImageIndex)] $($image.ImageName)" -ForegroundColor White
            }
            
            do {
                $editionSelection = Read-Host "`nSelect edition index"
                $selectedImage = $images | Where-Object { $_.ImageIndex -eq [int]$editionSelection }
            } while (-not $selectedImage)
            
            Write-EZOSDLog -Message "User selected: $($selectedImage.ImageName)" -Level Info
            return $selectedImage.ImageIndex
        }
        
        # Default to first image
        Write-EZOSDLog -Message "Using default edition: $($images[0].ImageName) (Index $($images[0].ImageIndex))" -Level Info
        return $images[0].ImageIndex
    }
    catch {
        Write-EZOSDError -Message "Failed to select Windows edition" -Exception $_.Exception
        throw
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Install-WindowsImage',
    'Set-WindowsBootConfiguration',
    'Select-WindowsEdition'
)
