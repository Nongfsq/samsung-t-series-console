Set-StrictMode -Version Latest

function Get-STCRelevantProcess {
    [CmdletBinding()]
    param()

    $names = @('SearchIndexer', 'SamsungMagician', 'SamsungPortableSSD', 'explorer')
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $names } | Select-Object ProcessName, Id, MainWindowTitle, Path)
}

function Get-STCRecentSystemEvent {
    [CmdletBinding()]
    param(
        [int[]] $Id = @(153, 225),
        [int] $DaysBack = 7
    )

    $start = (Get-Date).AddDays(-1 * [math]::Abs($DaysBack))
    return @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = $Id; StartTime = $start } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, ProviderName, Message)
}

function Get-STCRiskAudit {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [int] $DaysBack = 7
    )

    $drives = if ($DriveLetter) {
        @(Get-STCDriveByLetter -DriveLetter $DriveLetter)
    } else {
        @(Get-SamsungTDrive)
    }

    $events = Get-STCRecentSystemEvent -DaysBack $DaysBack
    $processes = Get-STCRelevantProcess
    $searchService = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    $searchPolicy = if (Get-Command Get-STCWindowsSearchSamsungPolicyStatus -ErrorAction SilentlyContinue) {
        @(Get-STCWindowsSearchSamsungPolicyStatus)
    } else {
        @()
    }

    $audits = @()
    foreach ($drive in $drives) {
        if ($null -eq $drive) {
            continue
        }

        $diskPattern = "Disk $($drive.DiskNumber)"
        $disk153 = @($events | Where-Object { $_.Id -eq 153 -and $_.Message -match [regex]::Escape($diskPattern) })
        $serial = [regex]::Escape([string] $drive.Serial)
        $pnp225 = @($events | Where-Object {
            $_.Id -eq 225 -and (
                ($drive.Serial -and $_.Message -match $serial) -or
                ($_.Message -match [regex]::Escape($drive.Drive))
            )
        })
        $globalPnp225 = @($events | Where-Object {
            $_.Id -eq 225 -and $_.Message -match '(?i)SearchIndexer|explorer|Samsung'
        })

        $findings = New-Object System.Collections.Generic.List[string]
        if ($disk153.Count -gt 0) {
            $findings.Add("Disk 153 retries found for Disk $($drive.DiskNumber): $($disk153.Count)") | Out-Null
        }
        if ($pnp225.Count -gt 0) {
            $findings.Add("Kernel-PnP 225 eject/blocker events found: $($pnp225.Count)") | Out-Null
        }
        if ($pnp225.Count -eq 0 -and $globalPnp225.Count -gt 0) {
            $findings.Add("Global Kernel-PnP 225 blocker events found recently: $($globalPnp225.Count). They may not belong to this drive.") | Out-Null
        }
        if ($processes.ProcessName -contains 'SearchIndexer') {
            $policyForDrive = @($searchPolicy | Where-Object { $_.Drive -eq $drive.Drive } | Select-Object -First 1)
            if ($policyForDrive.Count -gt 0 -and [bool] $policyForDrive[0].Excluded) {
                $findings.Add('SearchIndexer is running, but Windows Search is configured to exclude this drive root.') | Out-Null
            } else {
                $findings.Add('SearchIndexer is running and this drive root is not confirmed excluded from Windows Search.') | Out-Null
            }
        }
        if ($processes.ProcessName -contains 'SamsungMagician') {
            $findings.Add('Samsung Magician is running; treat it as a monitoring risk and close it before safe eject or benchmarking.') | Out-Null
        }
        if ($processes.ProcessName -contains 'explorer') {
            $findings.Add('Explorer is running; open folder windows/thumbnails can keep handles open.') | Out-Null
        }
        if ($drive.FileSystem -ne 'exFAT') {
            $findings.Add("Filesystem is $($drive.FileSystem), expected exFAT for Windows/macOS sharing.") | Out-Null
        }

        $riskLevel = if ($disk153.Count -gt 0) {
            'High'
        } elseif ($pnp225.Count -gt 0 -or ($processes.ProcessName -contains 'SearchIndexer')) {
            'Medium'
        } else {
            'Low'
        }

        $windowsSearchStatus = if ($null -ne $searchService) { [string] $searchService.Status } else { 'NotFound' }
        $windowsSearchExcluded = @($searchPolicy | Where-Object { $_.Drive -eq $drive.Drive } | Select-Object -First 1)
        $relevantProcesses = @($processes)
        $latestDisk153 = @($disk153 | Sort-Object TimeCreated -Descending | Select-Object -First 10)
        $latestKernelPnp225 = @($pnp225 | Sort-Object TimeCreated -Descending | Select-Object -First 10)
        $latestGlobalKernelPnp225 = @($globalPnp225 | Sort-Object TimeCreated -Descending | Select-Object -First 10)

        $audits += [pscustomobject]@{
            Drive                    = $drive.Drive
            Model                    = $drive.Model
            Serial                   = $drive.Serial
            DiskNumber               = $drive.DiskNumber
            DaysBack                 = $DaysBack
            RiskLevel                = $riskLevel
            Disk153RetryCount        = $disk153.Count
            KernelPnp225Count        = $pnp225.Count
            GlobalKernelPnp225Count  = $globalPnp225.Count
            WindowsSearchStatus      = $windowsSearchStatus
            WindowsSearchExcluded    = if ($windowsSearchExcluded.Count -gt 0) { [bool] $windowsSearchExcluded[0].Excluded } else { $null }
            RelevantProcesses        = $relevantProcesses
            Findings                 = @($findings)
            LatestDisk153            = $latestDisk153
            LatestKernelPnp225       = $latestKernelPnp225
            LatestGlobalKernelPnp225 = $latestGlobalKernelPnp225
        }
    }

    $items = @($audits)
    Write-STCLog -Category 'risk-audit' -Message 'Risk audit completed.' -Data $items
    return $items
}
