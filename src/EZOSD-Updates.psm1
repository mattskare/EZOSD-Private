<#
.SYNOPSIS
	EZOSD Windows Update Module
.DESCRIPTION
	Uses the Windows Update Agent (WUA) COM API to search, download, and install updates.
#>

using module .\EZOSD-Logger.psm1

$Script:DefaultClientAppId = "EZOSD"

function Test-WuaComAvailable {
	<#
	.SYNOPSIS
		Tests if the WUA COM API is available.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param()

	try {
		$null = New-Object -ComObject "Microsoft.Update.Session"
		return $true
	}
	catch {
		Write-EZOSDLog -Message "WUA COM API not available: $($_.Exception.Message)" -Level Warning
		return $false
	}
}

function Initialize-WuaSession {
	<#
	.SYNOPSIS
		Creates and returns a WUA session.
	.PARAMETER ClientApplicationID
		The client application ID used by WUA.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$ClientApplicationID = $Script:DefaultClientAppId
	)

	try {
		if (-not (Test-WuaComAvailable)) {
			throw "WUA COM API is not available on this system."
		}

		$session = New-Object -ComObject "Microsoft.Update.Session"
		$session.ClientApplicationID = $ClientApplicationID
		return $session
	}
	catch {
		Write-EZOSDError -Message "Failed to initialize WUA session" -Exception $_.Exception
		throw
	}
}

function Test-WuaServiceRunning {
	<#
	.SYNOPSIS
		Tests if the Windows Update service is running.
	#>
	[CmdletBinding()]
	param()

	try {
		$service = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
		if (-not $service) {
			Write-EZOSDLog -Message "Windows Update service (wuauserv) not found" -Level Warning
			return $false
		}

		if ($service.Status -ne "Running") {
			Write-EZOSDLog -Message "Starting Windows Update service..." -Level Info
			Start-Service -Name "wuauserv" -ErrorAction Stop
		}

		return $true
	}
	catch {
		Write-EZOSDLog -Message "Failed to start Windows Update service: $($_.Exception.Message)" -Level Warning
		return $false
	}
}

function Get-WindowsUpdates {
	<#
	.SYNOPSIS
		Searches for available Windows updates using WUA.
	.PARAMETER Criteria
		WUA search criteria string.
	.PARAMETER IncludeDrivers
		Include driver updates in search results.
	.PARAMETER IncludeHidden
		Include hidden updates.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$Criteria,

		[Parameter(Mandatory = $false)]
		[bool]$IncludeDrivers = $false,

		[Parameter(Mandatory = $false)]
		[bool]$IncludeHidden = $false
	)

	Write-EZOSDLogSection -Title "Windows Update Search"

	try {
		Test-WuaServiceRunning | Out-Null

		$session = Initialize-WuaSession
		$searcher = $session.CreateUpdateSearcher()

		if (-not $Criteria) {
			$typeClause = if ($IncludeDrivers) { "(Type='Software' or Type='Driver')" } else { "Type='Software'" }
			$hiddenClause = if ($IncludeHidden) { "" } else { " and IsHidden=0" }
			$Criteria = "IsInstalled=0 and $typeClause$hiddenClause"
		}

		Write-EZOSDLog -Message "Search criteria: $Criteria" -Level Info
		$searchResult = $searcher.Search($Criteria)

		Write-EZOSDLog -Message "Updates found: $($searchResult.Updates.Count)" -Level Info

		$results = @()
		foreach ($update in $searchResult.Updates) {
			$kbIds = if ($update.KBArticleIDs) { ($update.KBArticleIDs -join ", ") } else { "" }
			$categories = @()
			foreach ($cat in $update.Categories) { $categories += $cat.Name }

			$results += [pscustomobject]@{
				Title = $update.Title
				KBs = $kbIds
				Categories = ($categories -join ", ")
				IsDownloaded = $update.IsDownloaded
				IsInstalled = $update.IsInstalled
				RequiresReboot = $update.RebootRequired
				SizeBytes = $update.MaxDownloadSize
				WuaUpdate = $update
			}
		}

		return $results
	}
	catch {
		Write-EZOSDError -Message "Failed to search for updates" -Exception $_.Exception
		throw
	}
}

function Save-WindowsUpdates {
	<#
	.SYNOPSIS
		Downloads the specified updates.
	.PARAMETER Updates
		Array of WUA update COM objects.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[array]$Updates
	)

	Write-EZOSDLogSection -Title "Windows Update Download"

	try {
		if (-not $Updates -or $Updates.Count -eq 0) {
			Write-EZOSDLog -Message "No updates specified for download" -Level Warning
			return $false
		}

		Write-EZOSDLog -Message "Downloading $($Updates.Count) update(s)..." -Level Info #Debug

		Test-WuaServiceRunning | Out-Null

		Write-EZOSDLog -Message "Ensuring EULA acceptance for updates..." -Level Info #Debug

		foreach ($update in $Updates) {
			if (-not $update.EulaAccepted) {
				$update.AcceptEula()
			}
		}

		Write-EZOSDLog -Message "Initializing WUA session for download..." -Level Info #Debug

		$session = Initialize-WuaSession
		$downloader = $session.CreateUpdateDownloader()

		Write-EZOSDLog -Message "Creating update collection for download..." -Level Info #Debug

		$coll = New-Object -ComObject "Microsoft.Update.UpdateColl"
		foreach ($update in $Updates) {
			$coll.Add($update) | Out-Null
		}

		$downloader.Updates = $coll

		Write-EZOSDLog -Message "Starting download..." -Level Info #Debug

		Write-EZOSDLog -Message "Downloading $($downloader.Updates.Count) update(s)..." -Level Info
		$result = $downloader.Download()

		Write-EZOSDLog -Message "Download result code: $($result.ResultCode)" -Level Info #Debug

		$resultText = Convert-WuaResultCode -ResultCode $result.ResultCode
		Write-EZOSDLog -Message "Download result: $resultText" -Level Info
 #Debug

		return ($result.ResultCode -eq 2)
	}
	catch {	
		Write-EZOSDError -Message "Failed to download updates" -Exception $_.Exception
		return $false
	}
}

function Install-WindowsUpdates {
	<#
	.SYNOPSIS
		Installs the specified updates.
	.PARAMETER Updates
		Array of WUA update COM objects.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[array]$Updates
	)

	Write-EZOSDLogSection -Title "Windows Update Install"

	try {
		if (-not $Updates -or $Updates.Count -eq 0) {
			Write-EZOSDLog -Message "No updates specified for installation" -Level Warning
			return $false
		}

		Test-WuaServiceRunning | Out-Null

		foreach ($update in $Updates) {
			if (-not $update.EulaAccepted) {
				$update.AcceptEula()
			}
		}

		$session = Initialize-WuaSession
		$installer = $session.CreateUpdateInstaller()

		$coll = New-Object -ComObject "Microsoft.Update.UpdateColl"
		foreach ($update in $Updates) {
			$coll.Add($update) | Out-Null
		}
		$installer.Updates = $coll
		
		$installer.ForceQuiet = $true
		$installer.AllowSourcePrompts = $false
		$installer.IsForced = $false

		Write-EZOSDLog -Message "Installing $($installer.Updates.Count) update(s)..." -Level Info
		$result = $installer.Install()

		$resultText = Convert-WuaResultCode -ResultCode $result.ResultCode
		Write-EZOSDLog -Message "Install result: $resultText" -Level Info
		Write-EZOSDLog -Message "Reboot required: $($result.RebootRequired)" -Level Info

		return ($result.ResultCode -eq 2)
	}
	catch {
		Write-EZOSDError -Message "Failed to install updates" -Exception $_.Exception
		return $false
	}
}

function Convert-WuaResultCode {
	<#
	.SYNOPSIS
		Converts a WUA operation result code to a readable string.
	.PARAMETER ResultCode
		WUA result code integer.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[int]$ResultCode
	)

	switch ($ResultCode) {
		0 { return "NotStarted" }
		1 { return "InProgress" }
		2 { return "Succeeded" }
		3 { return "SucceededWithErrors" }
		4 { return "Failed" }
		5 { return "Aborted" }
		default { return "Unknown($ResultCode)" }
	}
}

function Get-WindowsUpdateHistory {
	<#
	.SYNOPSIS
		Retrieves the Windows Update history.
	.PARAMETER MaxEntries
		Maximum number of entries to return.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[int]$MaxEntries = 50
	)

	Write-EZOSDLogSection -Title "Windows Update History"

	try {
		$session = Initialize-WuaSession
		$searcher = $session.CreateUpdateSearcher()

		$total = $searcher.GetTotalHistoryCount()
		if ($total -le 0) {
			Write-EZOSDLog -Message "No update history found" -Level Info
			return @()
		}

		$count = [math]::Min($MaxEntries, $total)
		$history = $searcher.QueryHistory(0, $count)

		$results = @()
		foreach ($entry in $history) {
			$results += [pscustomobject]@{
				Title = $entry.Title
				Date = $entry.Date
				Result = Convert-WuaResultCode -ResultCode $entry.ResultCode
				Description = $entry.Description
				HResult = $entry.HResult
			}
		}

		return $results
	}
	catch {
		Write-EZOSDError -Message "Failed to read update history" -Exception $_.Exception
		return @()
	}
}

# Export module members
Export-ModuleMember -Function @(
	'Test-WuaComAvailable',
	'Initialize-WuaSession',
	'Test-WuaServiceRunning',
	'Get-WindowsUpdates',
	'Save-WindowsUpdates',
	'Install-WindowsUpdates',
	'Get-WindowsUpdateHistory'
)
