<#
.SYNOPSIS
    EZOSD Disk Management Module
.DESCRIPTION
    Handles disk detection, partitioning, and formatting for Windows deployment.
    Supports both UEFI (GPT) and BIOS (MBR) partition schemes.
#>

using module .\EZOSD-Logger.psm1

<#
.SYNOPSIS
    Gets available disks for deployment.
.PARAMETER MinimumSizeGB
    Minimum disk size in GB.
#>
function Get-EZOSDTargetDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MinimumSizeGB = 32
    )
    
    try {
        Write-EZOSDLog -Message "Scanning for available disks..." -Level Info
        
        $disks = Get-Disk | Where-Object {
            $_.BusType -ne 'USB' -and  # Exclude USB (likely our boot drive)
            ($_.Size / 1GB) -ge $MinimumSizeGB -and
            -not $_.IsBoot
        }
        
        if ($disks.Count -eq 0) {
            Write-EZOSDLog -Message "No suitable disks found" -Level Warning
            return $null
        }
        
        foreach ($disk in $disks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            Write-EZOSDLog -Message "Disk $($disk.Number): $sizeGB GB ($($disk.FriendlyName))" -Level Info
        }
        
        return $disks
    }
    catch {
        Write-EZOSDError -Message "Failed to get target disks" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Selects target disk for deployment.
.PARAMETER DiskNumber
    Specific disk number, or 'auto' for automatic selection.
.PARAMETER Interactive
    Whether to prompt user for disk selection.
#>
function Select-EZOSDTargetDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DiskNumber = "auto",
        
        [Parameter(Mandatory = $false)]
        [bool]$Interactive = $true
    )
    
    try {
        $availableDisks = Get-EZOSDTargetDisk
        
        if (-not $availableDisks) {
            throw "No suitable disks available for deployment"
        }
        
        # Auto-select if only one disk
        if ($DiskNumber -eq "auto" -and $availableDisks.Count -eq 1) {
            $selectedDisk = $availableDisks[0]
            Write-EZOSDLog -Message "Auto-selected disk $($selectedDisk.Number)" -Level Info
            return $selectedDisk
        }
        
        # Use specified disk number
        if ($DiskNumber -ne "auto") {
            $selectedDisk = $availableDisks | Where-Object { $_.Number -eq [int]$DiskNumber }
            if ($selectedDisk) {
                Write-EZOSDLog -Message "Selected disk $DiskNumber" -Level Info
                return $selectedDisk
            }
            else {
                throw "Disk $DiskNumber not found or not suitable"
            }
        }
        
        # Interactive selection
        if ($Interactive) {
            Write-Host "`nAvailable disks for deployment:" -ForegroundColor Cyan
            foreach ($disk in $availableDisks) {
                $sizeGB = [math]::Round($disk.Size / 1GB, 2)
                Write-Host "  [$($disk.Number)] $sizeGB GB - $($disk.FriendlyName)" -ForegroundColor White
            }
            
            do {
                $diskSelection = Read-Host "`nSelect disk number"
                $selectedDisk = $availableDisks | Where-Object { $_.Number -eq [int]$diskSelection }
            } while (-not $selectedDisk)
            
            Write-EZOSDLog -Message "User selected disk $($selectedDisk.Number)" -Level Info
            return $selectedDisk
        }
        
        # Default to first disk
        $selectedDisk = $availableDisks[0]
        Write-EZOSDLog -Message "Defaulting to disk $($selectedDisk.Number)" -Level Info
        return $selectedDisk
    }
    catch {
        Write-EZOSDError -Message "Failed to select target disk" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Prepares disk for Windows installation.
.PARAMETER Disk
    Disk object to prepare.
.PARAMETER PartitionScheme
    Partition scheme (UEFI or BIOS).
#>
function Initialize-EZOSDDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Disk,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("UEFI", "BIOS")]
        [string]$PartitionScheme
    )
    
    Write-EZOSDLogSection -Title "Disk Initialization"
    
    try {
        $diskNumber = $Disk.Number
        Write-EZOSDLog -Message "Initializing disk $diskNumber for $PartitionScheme" -Level Info
        
        # WARNING: This will erase all data
        Write-EZOSDLog -Message "WARNING: All data on disk $diskNumber will be erased" -Level Warning
        
        # Clean the disk
        Write-EZOSDLog -Message "Cleaning disk..." -Level Info
        Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        
        # Initialize disk with appropriate partition style
        if ($PartitionScheme -eq "UEFI") {
            Write-EZOSDLog -Message "Initializing as GPT (UEFI)..." -Level Info
            Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop
            
            # Create UEFI partitions
            $partitions = New-EZOSDUEFIPartitions -DiskNumber $diskNumber
        }
        else {
            Write-EZOSDLog -Message "Initializing as MBR (BIOS)..." -Level Info
            Initialize-Disk -Number $diskNumber -PartitionStyle MBR -ErrorAction Stop
            
            # Create BIOS partitions
            $partitions = New-EZOSDBIOSPartitions -DiskNumber $diskNumber
        }
        
        Write-EZOSDLog -Message "Disk initialization completed" -Level Info
        return $partitions
    }
    catch {
        Write-EZOSDError -Message "Failed to initialize disk" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Creates UEFI (GPT) partitions.
.PARAMETER DiskNumber
    Disk number.
#>
function New-EZOSDUEFIPartitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )
    
    try {
        Write-EZOSDLog -Message "Creating UEFI partition layout..." -Level Info
        
        # Create EFI System Partition (ESP) - 512MB
        Write-EZOSDLog -Message "Creating EFI System Partition (512MB)..." -Level Info
        $espPartition = New-Partition -DiskNumber $DiskNumber -Size 512MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
        Format-Volume -Partition $espPartition -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false | Out-Null
        # ESP does not need a drive letter
        
        # Create Microsoft Reserved Partition (MSR) - 128MB
        Write-EZOSDLog -Message "Creating MSR Partition (128MB)..." -Level Info
        $msrPartition = New-Partition -DiskNumber $DiskNumber -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
        
        # Create Windows partition (remaining space)
        Write-EZOSDLog -Message "Creating Windows Partition (remaining space)..." -Level Info
        $windowsPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
        Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
        # Explicitly assign C: to Windows partition
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $windowsPartition.PartitionNumber -NewDriveLetter C
        
        # Refresh partition info
        $espPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $espPartition.PartitionNumber
        $windowsPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $windowsPartition.PartitionNumber
        
        Write-EZOSDLog -Message "ESP: No drive letter (as expected)" -Level Info
        Write-EZOSDLog -Message "Windows: $($windowsPartition.DriveLetter):" -Level Info
        
        return @{
            System = $espPartition
            Windows = $windowsPartition
        }
    }
    catch {
        Write-EZOSDError -Message "Failed to create UEFI partitions" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Creates BIOS (MBR) partitions.
.PARAMETER DiskNumber
    Disk number.
#>
function New-EZOSDBIOSPartitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )
    
    try {
        Write-EZOSDLog -Message "Creating BIOS partition layout..." -Level Info
        
        # Create System Reserved partition - 500MB
        Write-EZOSDLog -Message "Creating System Reserved Partition (500MB)..." -Level Info
        $systemPartition = New-Partition -DiskNumber $DiskNumber -Size 500MB -IsActive
        Format-Volume -Partition $systemPartition -FileSystem NTFS -NewFileSystemLabel "System Reserved" -Confirm:$false | Out-Null
        # System Reserved does not need a drive letter
        
        # Create Windows partition (remaining space)
        Write-EZOSDLog -Message "Creating Windows Partition (remaining space)..." -Level Info
        $windowsPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize
        Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
        # Explicitly assign C: to Windows partition
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $windowsPartition.PartitionNumber -NewDriveLetter C
        
        # Refresh partition info
        $systemPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $systemPartition.PartitionNumber
        $windowsPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $windowsPartition.PartitionNumber
        
        Write-EZOSDLog -Message "System Reserved: No drive letter (as expected)" -Level Info
        Write-EZOSDLog -Message "Windows: $($windowsPartition.DriveLetter):" -Level Info
        
        return @{
            System = $systemPartition
            Windows = $windowsPartition
        }
    }
    catch {
        Write-EZOSDError -Message "Failed to create BIOS partitions" -Exception $_.Exception
        throw
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-EZOSDTargetDisk',
    'Select-EZOSDTargetDisk',
    'Initialize-EZOSDDisk'
)
