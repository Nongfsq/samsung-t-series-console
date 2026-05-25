Set-StrictMode -Version Latest

if (-not (Get-Command Write-STCLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Logging.ps1')
}

if (-not (Get-Command Get-STCDriveByLetter -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'DriveDetection.ps1')
}

if (-not (Get-Command Get-STCRelevantProcess -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'RiskAudit.ps1')
}

if (-not (Get-Command Get-STCFormatRecommendation -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'FormatPolicy.ps1')
}

if (-not (Get-Command Invoke-STCShellEject -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'SafeEject.ps1')
}

if (-not (Get-Command Get-STCWindowsSearchSamsungPolicyStatus -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'SearchPolicy.ps1')
}

function ConvertTo-STCUserRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Ready', 'Caution', 'Blocked', 'Unknown')]
        [string] $Status,
        [string[]] $BlockerNames = @(),
        [bool] $HasCriticalDisk153,
        [bool] $HasDrivePnp225,
        [bool] $HasFormatMismatch,
        [bool] $HasGlobalPnp225
    )

    $headline = switch ($Status) {
        'Ready' { '可以安全弹出' }
        'Caution' {
            if ($BlockerNames -contains 'SearchIndexer') { '建议先处理 Windows Search' }
            elseif ($BlockerNames -contains 'SamsungMagician') { '建议先关闭 Samsung Magician' }
            elseif ($HasFormatMismatch) { '格式配置需要复核' }
            else { '有轻微风险，建议确认后弹出' }
        }
        'Blocked' {
            if ($HasDrivePnp225) { '系统记录到本盘弹出被阻止' }
            elseif ($HasCriticalDisk153) { '本盘刚发生 I/O retry，不建议直接拔' }
            else { '当前不建议直接拔盘' }
        }
        default { '无法判断拔插状态' }
    }

    $primaryAction = switch ($Status) {
        'Ready' { 'SafeEject' }
        'Caution' {
            if ($BlockerNames.Count -gt 0) { 'CloseAppsThenRetry' } else { 'SafeEject' }
        }
        'Blocked' { 'ShutdownBeforeUnplug' }
        default { 'RefreshOrDiagnose' }
    }

    $steps = New-Object System.Collections.Generic.List[string]
    switch ($Status) {
        'Ready' {
            $steps.Add('点击“安全弹出选中硬盘”。') | Out-Null
            $steps.Add('看到系统弹出成功或盘符消失后再拔线。') | Out-Null
        }
        'Caution' {
            if ($BlockerNames -contains 'SamsungMagician') {
                $steps.Add('先关闭 Samsung Magician。') | Out-Null
            }
            if ($BlockerNames -contains 'SearchIndexer') {
                $steps.Add('如果弹出失败，勾选“弹出前停止 Windows Search”后重试。') | Out-Null
            }
            if ($BlockerNames -contains 'Explorer') {
                $steps.Add('关闭正在浏览移动盘的资源管理器窗口。') | Out-Null
            }
            if ($steps.Count -eq 0) {
                $steps.Add('先保存并关闭可能正在访问移动盘的应用。') | Out-Null
            }
            $steps.Add('处理后点击“安全弹出选中硬盘”。') | Out-Null
        }
        'Blocked' {
            if ($HasDrivePnp225) {
                $steps.Add('本盘最近弹出被系统阻止，先关闭占用程序。') | Out-Null
            }
            if ($HasCriticalDisk153) {
                $steps.Add('本盘刚出现 I/O retry，先不要硬拔。') | Out-Null
            }
            $steps.Add('若重试仍失败，关机后再拔线。') | Out-Null
        }
        default {
            $steps.Add('点击“刷新拔插状态”。') | Out-Null
            $steps.Add('如果仍无法判断，进入 Diagnostics 查看详细日志。') | Out-Null
        }
    }

    if ($HasGlobalPnp225 -and $Status -ne 'Blocked') {
        $steps.Add('系统有全局弹出阻塞历史；若本盘弹出失败，再进入诊断页查看详情。') | Out-Null
    }

    return [pscustomobject]@{
        Headline      = $headline
        PrimaryAction = $primaryAction
        NextSteps     = @($steps | Select-Object -First 3)
    }
}

function Get-STCDailyEjectReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [int] $DaysBack = 1,
        [int] $CriticalMinutes = 30
    )

    $letter = $DriveLetter.ToUpperInvariant()

    try {
        $drive = Get-STCDriveByLetter -DriveLetter $letter
        if ($null -eq $drive) {
            return [pscustomobject]@{
                Drive         = "$letter`:"
                Model         = $null
                Serial        = $null
                Label         = $null
                Status        = 'Unknown'
                Headline      = '未找到这块 Samsung T 系列硬盘'
                PrimaryAction = 'RefreshOrDiagnose'
                Blockers      = @()
                Evidence      = [pscustomobject]@{ Reason = 'DriveNotFound' }
                NextSteps     = @('重新插入硬盘。', '点击“刷新拔插状态”。', '如果仍不存在，检查线缆和接口。')
            }
        }

        $events = @(Get-STCRecentSystemEvent -Id @(153, 225) -DaysBack $DaysBack)
        $processes = @(Get-STCRelevantProcess)
        $searchPolicy = @(Get-STCWindowsSearchSamsungPolicyStatus | Where-Object { $_.DriveLetter -eq $letter } | Select-Object -First 1)
        $format = Get-STCFormatRecommendation -DriveLetter $letter -ContentProfile $null

        $criticalStart = (Get-Date).AddMinutes(-1 * [math]::Abs($CriticalMinutes))
        $diskPattern = "Disk $($drive.DiskNumber)"
        $disk153All = @($events | Where-Object { $_.Id -eq 153 -and $_.Message -match [regex]::Escape($diskPattern) })
        $disk153Critical = @($disk153All | Where-Object { $_.TimeCreated -ge $criticalStart })

        $serialPattern = [regex]::Escape([string] $drive.Serial)
        $drivePnp225 = @($events | Where-Object {
            $_.Id -eq 225 -and (
                ($drive.Serial -and $_.Message -match $serialPattern) -or
                ($_.Message -match [regex]::Escape($drive.Drive))
            )
        })
        $globalPnp225 = @($events | Where-Object {
            $_.Id -eq 225 -and $_.Message -match '(?i)SearchIndexer|explorer|Samsung'
        })

        $searchIndexerIsUnexcluded = -not ($searchPolicy.Count -gt 0 -and [bool] $searchPolicy[0].Excluded)
        $blockerProcesses = @($processes | Where-Object {
            (($_.ProcessName -eq 'SearchIndexer') -and $searchIndexerIsUnexcluded) -or
            $_.ProcessName -in @('SamsungMagician', 'SamsungPortableSSD') -or
            ($_.ProcessName -eq 'explorer' -and -not [string]::IsNullOrWhiteSpace([string] $_.MainWindowTitle))
        })

        $blockerNames = @($blockerProcesses | Select-Object -ExpandProperty ProcessName -Unique)
        $hasCriticalDisk153 = $disk153Critical.Count -gt 0
        $hasDrivePnp225 = $drivePnp225.Count -gt 0
        $hasFormatMismatch = [bool] $format.RequiresFormatForPolicyMatch
        $hasGlobalPnp225 = $globalPnp225.Count -gt 0

        $status = if ($hasCriticalDisk153 -or $hasDrivePnp225) {
            'Blocked'
        } elseif ($blockerNames.Count -gt 0 -or $hasFormatMismatch -or $hasGlobalPnp225) {
            'Caution'
        } else {
            'Ready'
        }

        $recommendation = ConvertTo-STCUserRecommendation `
            -Status $status `
            -BlockerNames $blockerNames `
            -HasCriticalDisk153:$hasCriticalDisk153 `
            -HasDrivePnp225:$hasDrivePnp225 `
            -HasFormatMismatch:$hasFormatMismatch `
            -HasGlobalPnp225:$hasGlobalPnp225

        $evidence = [pscustomobject]@{
            DiskNumber                 = $drive.DiskNumber
            FileSystem                 = $drive.FileSystem
            AllocationUnitKB           = $drive.AllocationUnitKB
            RecommendedAllocationUnitKB = $format.RecommendedAllocationUnitKB
            FormatPolicyMatch          = -not $format.RequiresFormatForPolicyMatch
            CriticalDisk153Count       = $disk153Critical.Count
            HistoricalDisk153Count     = $disk153All.Count
            DriveKernelPnp225Count     = $drivePnp225.Count
            GlobalKernelPnp225Count    = $globalPnp225.Count
            WindowsSearchExcluded      = if ($searchPolicy.Count -gt 0) { [bool] $searchPolicy[0].Excluded } else { $null }
            WindowsSearchApiError      = if ($searchPolicy.Count -gt 0) { $searchPolicy[0].ApiError } else { $null }
            RelevantProcessNames       = @($processes | Select-Object -ExpandProperty ProcessName -Unique)
            CheckedAt                  = (Get-Date).ToString('o')
        }

        $result = [pscustomobject]@{
            Drive         = $drive.Drive
            Model         = $drive.Model
            Serial        = $drive.Serial
            Label         = $drive.Label
            Status        = $status
            Headline      = $recommendation.Headline
            PrimaryAction = $recommendation.PrimaryAction
            Blockers      = @($blockerProcesses | Select-Object ProcessName, Id, MainWindowTitle, Path)
            Evidence      = $evidence
            NextSteps     = $recommendation.NextSteps
        }

        Write-STCLog -Category 'daily-readiness' -Message "Daily eject readiness checked for $letter`:." -Data $result
        return $result
    } catch {
        $result = [pscustomobject]@{
            Drive         = "$letter`:"
            Model         = $null
            Serial        = $null
            Label         = $null
            Status        = 'Unknown'
            Headline      = '无法判断拔插状态'
            PrimaryAction = 'RefreshOrDiagnose'
            Blockers      = @()
            Evidence      = [pscustomobject]@{ Error = $_.Exception.Message }
            NextSteps     = @('点击“刷新拔插状态”。', '进入 Diagnostics 查看详细信息。', '如果准备拔盘但无法判断，优先关机后拔。')
        }
        Write-STCLog -Category 'daily-readiness-error' -Message $_.Exception.Message -Data $result
        return $result
    }
}

function Get-STCDailyDashboardState {
    [CmdletBinding()]
    param()

    $drives = @(Get-SamsungTDrive)
    $cards = @()
    foreach ($drive in $drives) {
        $cards += Get-STCDailyEjectReadiness -DriveLetter $drive.DriveLetter
    }

    $state = [pscustomobject]@{
        CheckedAt = (Get-Date).ToString('o')
        Count     = $cards.Count
        Drives    = $cards
    }

    Write-STCLog -Category 'daily-dashboard' -Message 'Daily dashboard state refreshed.' -Data $state
    return $state
}

function Invoke-STCDailySafeEjectFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [switch] $StopSearchIndexer
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $before = Get-STCDailyEjectReadiness -DriveLetter $letter
    $searchResult = $null

    if ($StopSearchIndexer) {
        $searchResult = Stop-STCWindowsSearchWithConfirmation -ConfirmationPhrase 'STOP WINDOWS SEARCH'
    }

    $ejectResult = Invoke-STCSafeEject -DriveLetter $letter
    $after = if ($ejectResult.StillPresent) {
        Get-STCDailyEjectReadiness -DriveLetter $letter
    } else {
        [pscustomobject]@{
            Drive         = "$letter`:"
            Status        = 'Ready'
            Headline      = '系统已发送弹出命令，盘符已消失'
            PrimaryAction = 'Unplug'
            Blockers      = @()
            Evidence      = [pscustomobject]@{ StillPresent = $false }
            NextSteps     = @('现在可以拔线。')
        }
    }

    $flow = [pscustomobject]@{
        Drive             = "$letter`:"
        StopSearchIndexer = [bool] $StopSearchIndexer
        SearchResult      = $searchResult
        Before            = $before
        EjectResult       = $ejectResult
        After             = $after
        FinalAdvice       = if ($ejectResult.StillPresent) { '弹出命令已发送但盘符仍存在。请关闭阻塞程序后重试；若仍失败，关机后拔线。' } else { '可以拔线。' }
    }

    Write-STCLog -Category 'daily-safe-eject' -Message "Daily safe eject flow completed for $letter`:." -Data $flow
    return $flow
}
