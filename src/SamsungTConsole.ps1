Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

$libRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libRoot 'Logging.ps1')
. (Join-Path $libRoot 'DriveDetection.ps1')
. (Join-Path $libRoot 'RiskAudit.ps1')
. (Join-Path $libRoot 'ContentProfile.ps1')
. (Join-Path $libRoot 'PerformanceTest.ps1')
. (Join-Path $libRoot 'FormatPolicy.ps1')
. (Join-Path $libRoot 'SafeEject.ps1')
. (Join-Path $libRoot 'DailyEject.ps1')
. (Join-Path $libRoot 'SearchPolicy.ps1')
. (Join-Path $libRoot 'MagicianPolicy.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Samsung T-Series Console'
$form.Size = New-Object System.Drawing.Size(1240, 800)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1040, 680)

$font = New-Object System.Drawing.Font('Segoe UI', 10)
$titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$cardTitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$statusFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$monoFont = New-Object System.Drawing.Font('Consolas', 10)
$form.Font = $font

$script:DashboardState = $null
$script:CurrentDrives = @()
$script:LastContentProfile = $null
$script:SelectedDailyDrive = $null

function Get-STCStatusColor {
    param([string] $Status)

    switch ($Status) {
        'Ready' { return [System.Drawing.Color]::FromArgb(26, 127, 55) }
        'Caution' { return [System.Drawing.Color]::FromArgb(176, 111, 0) }
        'Blocked' { return [System.Drawing.Color]::FromArgb(189, 38, 30) }
        default { return [System.Drawing.Color]::FromArgb(84, 93, 104) }
    }
}

function ConvertTo-STCStatusChinese {
    param([string] $Status)

    switch ($Status) {
        'Ready' { '可以弹出' }
        'Caution' { '有风险' }
        'Blocked' { '不要直接拔' }
        default { '无法判断' }
    }
}

function Set-STCStatus {
    param([string] $Text)
    $statusLabel.Text = "$Text | Logs: $(Get-STCLogRoot)"
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-STCTextBox {
    param(
        [System.Windows.Forms.TextBox] $TextBox,
        [object] $Value
    )
    $TextBox.Text = $Value | ConvertTo-STCReadableText
    $TextBox.SelectionStart = 0
    $TextBox.SelectionLength = 0
}

function Invoke-STCGuardedAction {
    param(
        [string] $Name,
        [scriptblock] $Action
    )

    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        Set-STCStatus "Running: $Name"
        & $Action
        Set-STCStatus "Done: $Name"
    } catch {
        $message = $_.Exception.Message
        Write-STCLog -Category 'ui-error' -Message $message -Data $_
        [System.Windows.Forms.MessageBox]::Show($message, 'Samsung T-Series Console Error', 'OK', 'Error') | Out-Null
        Set-STCStatus "Error: $message"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Get-STCSelectedDiagnosticsDriveLetter {
    if ($diagDriveCombo.SelectedItem -and $diagDriveCombo.SelectedItem.PSObject.Properties.Name -contains 'DriveLetter') {
        return [string] $diagDriveCombo.SelectedItem.DriveLetter
    }

    throw 'No Samsung T-series drive selected. Run refresh first.'
}

function Refresh-STCDiagnosticsDriveCombo {
    $script:CurrentDrives = @(Get-SamsungTDrive)
    $diagDriveCombo.Items.Clear()
    foreach ($drive in $script:CurrentDrives) {
        $diagDriveCombo.Items.Add($drive) | Out-Null
    }

    $diagDriveCombo.DisplayMember = 'DisplayName'
    if ($diagDriveCombo.Items.Count -gt 0) {
        $diagDriveCombo.SelectedIndex = 0
    }
}

function New-STCDailyDriveCard {
    param([object] $DriveState)

    $card = New-Object System.Windows.Forms.Panel
    $card.Width = 552
    $card.Height = 230
    $card.Margin = New-Object System.Windows.Forms.Padding(10)
    $card.Padding = New-Object System.Windows.Forms.Padding(14)
    $card.BorderStyle = 'FixedSingle'
    $card.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $card.Tag = $DriveState

    $statusColor = Get-STCStatusColor -Status $DriveState.Status

    $driveTitle = New-Object System.Windows.Forms.Label
    $driveTitle.Text = "$($DriveState.Drive)  $($DriveState.Model)"
    $driveTitle.Font = $cardTitleFont
    $driveTitle.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $driveTitle.AutoSize = $true
    $driveTitle.Location = New-Object System.Drawing.Point(14, 14)
    $card.Controls.Add($driveTitle)

    $statusLabelCard = New-Object System.Windows.Forms.Label
    $statusLabelCard.Text = ConvertTo-STCStatusChinese -Status $DriveState.Status
    $statusLabelCard.Font = $statusFont
    $statusLabelCard.ForeColor = $statusColor
    $statusLabelCard.AutoSize = $true
    $statusLabelCard.Location = New-Object System.Drawing.Point(14, 50)
    $card.Controls.Add($statusLabelCard)

    $headline = New-Object System.Windows.Forms.Label
    $headline.Text = $DriveState.Headline
    $headline.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $headline.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $headline.AutoSize = $false
    $headline.Width = 500
    $headline.Height = 28
    $headline.Location = New-Object System.Drawing.Point(16, 88)
    $card.Controls.Add($headline)

    $baseline = New-Object System.Windows.Forms.Label
    $baseline.Text = "格式：$($DriveState.Evidence.FileSystem) + $($DriveState.Evidence.AllocationUnitKB)KB  推荐：$($DriveState.Evidence.RecommendedAllocationUnitKB)KB"
    $baseline.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $baseline.AutoSize = $true
    $baseline.Location = New-Object System.Drawing.Point(16, 118)
    $card.Controls.Add($baseline)

    $blockerText = if ($DriveState.Blockers.Count -gt 0) {
        '阻塞源：' + (($DriveState.Blockers | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')
    } elseif ($DriveState.Evidence.GlobalKernelPnp225Count -gt 0) {
        '阻塞源：系统有历史弹出阻塞记录，但未确认属于本盘'
    } else {
        '阻塞源：未发现明显阻塞'
    }
    $blockers = New-Object System.Windows.Forms.Label
    $blockers.Text = $blockerText
    $blockers.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $blockers.AutoSize = $false
    $blockers.Width = 510
    $blockers.Height = 24
    $blockers.Location = New-Object System.Drawing.Point(16, 144)
    $card.Controls.Add($blockers)

    $steps = New-Object System.Windows.Forms.Label
    $steps.Text = '下一步：' + (($DriveState.NextSteps | Select-Object -First 2) -join ' ')
    $steps.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $steps.AutoSize = $false
    $steps.Width = 510
    $steps.Height = 42
    $steps.Location = New-Object System.Drawing.Point(16, 172)
    $card.Controls.Add($steps)

    $card.Add_Click({
        $script:SelectedDailyDrive = $this.Tag
        Update-STCDailySelection
    })
    foreach ($control in $card.Controls) {
        $control.Add_Click({
            $script:SelectedDailyDrive = $this.Parent.Tag
            Update-STCDailySelection
        })
    }

    return $card
}

function Update-STCDailySelection {
    if ($null -eq $script:SelectedDailyDrive) {
        $dailySelectionLabel.Text = '未选择硬盘'
        $dailyPrimaryButton.Enabled = $false
        $dailyDetails.Text = '点击上方硬盘卡片，或点击“刷新拔插状态”。'
        return
    }

    $drive = $script:SelectedDailyDrive
    $dailySelectionLabel.Text = "当前选择：$($drive.Drive) $($drive.Model) - $($drive.Headline)"
    $dailyPrimaryButton.Enabled = $true
    $dailyPrimaryButton.Text = switch ($drive.PrimaryAction) {
        'ShutdownBeforeUnplug' { '查看阻塞原因' }
        'CloseAppsThenRetry' { '处理后安全弹出选中硬盘' }
        default { '安全弹出选中硬盘' }
    }

    $dailyStopSearchCheck.Enabled = ($drive.Blockers.ProcessName -contains 'SearchIndexer')

    $detail = [ordered]@{
        Drive = $drive.Drive
        Status = ConvertTo-STCStatusChinese -Status $drive.Status
        Headline = $drive.Headline
        NextSteps = $drive.NextSteps
        Evidence = $drive.Evidence
    }
    Set-STCTextBox -TextBox $dailyDetails -Value ([pscustomobject]$detail)
}

function Refresh-STCDailyDashboard {
    $script:DashboardState = Get-STCDailyDashboardState
    $dailyCardsPanel.Controls.Clear()

    foreach ($driveState in $script:DashboardState.Drives) {
        $dailyCardsPanel.Controls.Add((New-STCDailyDriveCard -DriveState $driveState)) | Out-Null
    }

    if ($script:DashboardState.Drives.Count -gt 0) {
        $script:SelectedDailyDrive = $script:DashboardState.Drives[0]
    } else {
        $script:SelectedDailyDrive = $null
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = '未检测到 Samsung T7/T7 Shield/T9。请插入硬盘后点击刷新。'
        $empty.AutoSize = $true
        $empty.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $empty.Margin = New-Object System.Windows.Forms.Padding(16)
        $dailyCardsPanel.Controls.Add($empty) | Out-Null
    }

    Update-STCDailySelection
    Refresh-STCDiagnosticsDriveCombo
    Refresh-STCLogList
}

function Refresh-STCLogList {
    $logList.Items.Clear()
    $logs = @(Get-ChildItem -LiteralPath (Get-STCLogRoot) -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($log in $logs) {
        $logList.Items.Add($log) | Out-Null
    }
    $logList.DisplayMember = 'Name'
}

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = 'Top'
$topPanel.Height = 82
$topPanel.Padding = New-Object System.Windows.Forms.Padding(14)
$form.Controls.Add($topPanel)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Samsung T-Series Console'
$title.Font = $titleFont
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(14, 10)
$topPanel.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Daily safe-eject dashboard first. Deep diagnostics and repair tools stay in advanced tabs.'
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(17, 48)
$topPanel.Controls.Add($subtitle)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

$dailyTab = New-Object System.Windows.Forms.TabPage
$dailyTab.Text = 'Daily Eject'
$tabs.TabPages.Add($dailyTab) | Out-Null

$diagTab = New-Object System.Windows.Forms.TabPage
$diagTab.Text = 'Diagnostics & Repair'
$tabs.TabPages.Add($diagTab) | Out-Null

$logsTab = New-Object System.Windows.Forms.TabPage
$logsTab.Text = 'Logs'
$tabs.TabPages.Add($logsTab) | Out-Null

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Ready | Logs: $(Get-STCLogRoot)"
$status.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($status)

$dailyActions = New-Object System.Windows.Forms.Panel
$dailyActions.Dock = 'Top'
$dailyActions.Height = 106
$dailyActions.Padding = New-Object System.Windows.Forms.Padding(14)
$dailyTab.Controls.Add($dailyActions)

$dailyHeader = New-Object System.Windows.Forms.Label
$dailyHeader.Text = '拔盘前先看这里'
$dailyHeader.Font = $cardTitleFont
$dailyHeader.AutoSize = $true
$dailyHeader.Location = New-Object System.Drawing.Point(14, 12)
$dailyActions.Controls.Add($dailyHeader)

$dailyRefreshButton = New-Object System.Windows.Forms.Button
$dailyRefreshButton.Text = '刷新拔插状态'
$dailyRefreshButton.Width = 140
$dailyRefreshButton.Height = 34
$dailyRefreshButton.Location = New-Object System.Drawing.Point(16, 54)
$dailyRefreshButton.Add_Click({ Invoke-STCGuardedAction -Name 'Refresh Daily Eject' -Action { Refresh-STCDailyDashboard } })
$dailyActions.Controls.Add($dailyRefreshButton)

$dailyPrimaryButton = New-Object System.Windows.Forms.Button
$dailyPrimaryButton.Text = '安全弹出选中硬盘'
$dailyPrimaryButton.Width = 190
$dailyPrimaryButton.Height = 34
$dailyPrimaryButton.Location = New-Object System.Drawing.Point(168, 54)
$dailyPrimaryButton.Enabled = $false
$dailyPrimaryButton.Add_Click({
    Invoke-STCGuardedAction -Name 'Daily Safe Eject' -Action {
        if ($null -eq $script:SelectedDailyDrive) {
            throw 'No drive selected.'
        }

        if ($script:SelectedDailyDrive.Status -eq 'Blocked') {
            [System.Windows.Forms.MessageBox]::Show(($script:SelectedDailyDrive.NextSteps -join "`r`n"), '当前不建议直接拔盘', 'OK', 'Warning') | Out-Null
            return
        }

        $confirmMessage = "准备安全弹出 $($script:SelectedDailyDrive.Drive)。`r`n`r`n$($script:SelectedDailyDrive.Headline)`r`n`r`n继续？"
        $confirm = [System.Windows.Forms.MessageBox]::Show($confirmMessage, '安全弹出确认', 'YesNo', 'Warning')
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        $flow = Invoke-STCDailySafeEjectFlow -DriveLetter $script:SelectedDailyDrive.Drive.Substring(0, 1) -StopSearchIndexer:$dailyStopSearchCheck.Checked
        Set-STCTextBox -TextBox $dailyDetails -Value ([pscustomobject]@{
            Result = $flow.FinalAdvice
            Before = $flow.Before.Headline
            Eject = $flow.EjectResult.Message
            After = $flow.After.Headline
        })
        Refresh-STCDailyDashboard
    }
})
$dailyActions.Controls.Add($dailyPrimaryButton)

$dailyStopSearchCheck = New-Object System.Windows.Forms.CheckBox
$dailyStopSearchCheck.Text = '弹出前停止 Windows Search'
$dailyStopSearchCheck.AutoSize = $true
$dailyStopSearchCheck.Location = New-Object System.Drawing.Point(376, 61)
$dailyStopSearchCheck.Enabled = $false
$dailyActions.Controls.Add($dailyStopSearchCheck)

$dailySelectionLabel = New-Object System.Windows.Forms.Label
$dailySelectionLabel.Text = '未选择硬盘'
$dailySelectionLabel.AutoSize = $true
$dailySelectionLabel.Location = New-Object System.Drawing.Point(610, 62)
$dailyActions.Controls.Add($dailySelectionLabel)

$dailySplit = New-Object System.Windows.Forms.SplitContainer
$dailySplit.Dock = 'Fill'
$dailySplit.Orientation = 'Horizontal'
$dailySplit.SplitterDistance = 300
$dailyTab.Controls.Add($dailySplit)

$dailyCardsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$dailyCardsPanel.Dock = 'Fill'
$dailyCardsPanel.AutoScroll = $true
$dailyCardsPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$dailyCardsPanel.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
$dailySplit.Panel1.Controls.Add($dailyCardsPanel)

$dailyDetails = New-Object System.Windows.Forms.TextBox
$dailyDetails.Multiline = $true
$dailyDetails.ScrollBars = 'Both'
$dailyDetails.WordWrap = $true
$dailyDetails.Dock = 'Fill'
$dailyDetails.Font = $monoFont
$dailyDetails.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 26)
$dailyDetails.ForeColor = [System.Drawing.Color]::FromArgb(220, 236, 235)
$dailySplit.Panel2.Controls.Add($dailyDetails)

$diagTop = New-Object System.Windows.Forms.Panel
$diagTop.Dock = 'Top'
$diagTop.Height = 104
$diagTop.Padding = New-Object System.Windows.Forms.Padding(12)
$diagTab.Controls.Add($diagTop)

$diagLabel = New-Object System.Windows.Forms.Label
$diagLabel.Text = '高级诊断与修复。日常拔盘不要从这里开始。'
$diagLabel.AutoSize = $true
$diagLabel.Location = New-Object System.Drawing.Point(14, 12)
$diagTop.Controls.Add($diagLabel)

$diagDriveCombo = New-Object System.Windows.Forms.ComboBox
$diagDriveCombo.DropDownStyle = 'DropDownList'
$diagDriveCombo.Width = 420
$diagDriveCombo.Location = New-Object System.Drawing.Point(16, 42)
$diagTop.Controls.Add($diagDriveCombo)

$diagButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$diagButtonPanel.Width = 720
$diagButtonPanel.Height = 44
$diagButtonPanel.Location = New-Object System.Drawing.Point(450, 36)
$diagTop.Controls.Add($diagButtonPanel)

$diagOutput = New-Object System.Windows.Forms.TextBox
$diagOutput.Multiline = $true
$diagOutput.ScrollBars = 'Both'
$diagOutput.WordWrap = $false
$diagOutput.Dock = 'Fill'
$diagOutput.Font = $monoFont
$diagOutput.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 26)
$diagOutput.ForeColor = [System.Drawing.Color]::FromArgb(220, 236, 235)
$diagTab.Controls.Add($diagOutput)

function Add-STCDiagButton {
    param(
        [string] $Text,
        [scriptblock] $OnClick,
        [int] $Width = 104
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 34
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    $button.Add_Click({ Invoke-STCGuardedAction -Name $Text -Action $OnClick })
    $diagButtonPanel.Controls.Add($button)
}

Add-STCDiagButton -Text 'Detect' -OnClick {
    Refresh-STCDiagnosticsDriveCombo
    $path = Export-STCJson -Name 'drive-inventory' -Data $script:CurrentDrives
    Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{ Summary = "Detected $($script:CurrentDrives.Count) drive(s)."; Export = $path; Drives = $script:CurrentDrives })
}

Add-STCDiagButton -Text 'Risk Audit' -Width 112 -OnClick {
    $letter = Get-STCSelectedDiagnosticsDriveLetter
    $audit = Get-STCRiskAudit -DriveLetter $letter -DaysBack 7
    $path = Export-STCJson -Name "risk-audit-$letter" -Data $audit
    Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{ Summary = "Risk audit completed for $letter`:."; Export = $path; Audit = $audit })
}

Add-STCDiagButton -Text 'Apply Policies' -Width 132 -OnClick {
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will exclude currently connected Samsung T-series drive roots from Windows Search, set SamsungMagicianSVC startup to Manual, and stop the current service instance if it is running. Continue?",
        'Apply Samsung Drive Policies',
        'OKCancel',
        'Warning'
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $search = Set-STCWindowsSearchSamsungExclusion
    $magician = Set-STCSamsungMagicianManualStartup
    $path = Export-STCJson -Name 'system-policy' -Data ([pscustomobject]@{ WindowsSearch = $search; SamsungMagician = $magician })
    Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{
        Summary = 'Samsung drive policies applied.'
        Export = $path
        WindowsSearch = $search
        SamsungMagician = $magician
    })
    Refresh-STCDailyDashboard
}

Add-STCDiagButton -Text 'Profile' -OnClick {
    $letter = Get-STCSelectedDiagnosticsDriveLetter
    $confirm = [System.Windows.Forms.MessageBox]::Show("Content Profile recursively scans $letter`: and may take time. Continue?", 'Content Profile', 'OKCancel', 'Information')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $script:LastContentProfile = Get-STCContentProfile -DriveLetter $letter
    $path = Export-STCJson -Name "content-profile-$letter" -Data $script:LastContentProfile
    Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{ Summary = "Content profile completed for $letter`:."; Export = $path; Profile = $script:LastContentProfile })
}

Add-STCDiagButton -Text 'Benchmark' -Width 112 -OnClick {
    $letter = Get-STCSelectedDiagnosticsDriveLetter
    $sizeText = [Microsoft.VisualBasic.Interaction]::InputBox("Benchmark size in GiB. Default 8. Use 1 or 4 for a faster smoke test.", 'Performance Test', '8')
    if ([string]::IsNullOrWhiteSpace($sizeText)) { return }
    $sizeGiB = [int] $sizeText
    $confirm = [System.Windows.Forms.MessageBox]::Show("This will write and delete a temporary $sizeGiB GiB test file on $letter`:. Continue?", 'Performance Test', 'OKCancel', 'Warning')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $result = Invoke-STCPerformanceTest -DriveLetter $letter -SizeGiB $sizeGiB
    $path = Export-STCJson -Name "performance-$letter" -Data $result
    Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{ Summary = "Performance test completed for $letter`:."; Export = $path; Result = $result })
}

Add-STCDiagButton -Text 'Danger Format' -Width 132 -OnClick {
    $letter = Get-STCSelectedDiagnosticsDriveLetter
    $recommendation = Get-STCFormatRecommendation -DriveLetter $letter -ContentProfile $script:LastContentProfile
    $backupText = 'Before formatting, verify your backup outside this tool.'
    $message = ($recommendation | ConvertTo-STCReadableText) + "`r`n$backupText`r`n`r`nFormatting destroys all data. Type exactly:`r`n$($recommendation.ConfirmationPhrase)"
    $phrase = [Microsoft.VisualBasic.Interaction]::InputBox($message, 'Advanced Dangerous Format', '')
    if ([string]::IsNullOrWhiteSpace($phrase)) {
        Set-STCTextBox -TextBox $diagOutput -Value ([pscustomobject]@{ Summary = 'Format not executed.'; BackupEvidence = $backupText; Recommendation = $recommendation })
        return
    }
    if ($phrase -ne $recommendation.ConfirmationPhrase) {
        throw "Confirmation phrase mismatch. Required: $($recommendation.ConfirmationPhrase)"
    }
    $final = [System.Windows.Forms.MessageBox]::Show("LAST WARNING: Format $letter`: as exFAT $($recommendation.RecommendedAllocationUnitKB)KB? This deletes all data.", 'Destructive Format Confirmation', 'YesNo', 'Stop')
    if ($final -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $label = [Microsoft.VisualBasic.Interaction]::InputBox('New volume label:', 'Format Label', "SamsungT$letter")
    if ([string]::IsNullOrWhiteSpace($label)) { throw 'Volume label is required for format.' }
    Invoke-STCFormatProfile -DriveLetter $letter -AllocationUnitKB $recommendation.RecommendedAllocationUnitKB -Label $label -ConfirmationPhrase $phrase
    Refresh-STCDailyDashboard
    Set-STCTextBox -TextBox $diagOutput -Value "Format completed for $letter`:."
}

$logsTop = New-Object System.Windows.Forms.Panel
$logsTop.Dock = 'Top'
$logsTop.Height = 56
$logsTop.Padding = New-Object System.Windows.Forms.Padding(12)
$logsTab.Controls.Add($logsTop)

$logRefreshButton = New-Object System.Windows.Forms.Button
$logRefreshButton.Text = 'Refresh Logs'
$logRefreshButton.Width = 120
$logRefreshButton.Height = 32
$logRefreshButton.Location = New-Object System.Drawing.Point(14, 12)
$logRefreshButton.Add_Click({ Invoke-STCGuardedAction -Name 'Refresh Logs' -Action { Refresh-STCLogList } })
$logsTop.Controls.Add($logRefreshButton)

$logsSplit = New-Object System.Windows.Forms.SplitContainer
$logsSplit.Dock = 'Fill'
$logsSplit.SplitterDistance = 260
$logsTab.Controls.Add($logsSplit)

$logList = New-Object System.Windows.Forms.ListBox
$logList.Dock = 'Fill'
$logList.Font = $font
$logList.Add_SelectedIndexChanged({
    if ($logList.SelectedItem) {
        $content = Get-Content -LiteralPath $logList.SelectedItem.FullName -Tail 200 -ErrorAction SilentlyContinue
        $logText.Text = ($content -join "`r`n")
    }
})
$logsSplit.Panel1.Controls.Add($logList)

$logText = New-Object System.Windows.Forms.TextBox
$logText.Multiline = $true
$logText.ScrollBars = 'Both'
$logText.WordWrap = $false
$logText.Dock = 'Fill'
$logText.Font = $monoFont
$logText.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 26)
$logText.ForeColor = [System.Drawing.Color]::FromArgb(220, 236, 235)
$logsSplit.Panel2.Controls.Add($logText)

try {
    Refresh-STCDailyDashboard
    Set-STCStatus 'Ready'
} catch {
    Set-STCTextBox -TextBox $dailyDetails -Value "Startup detection failed: $($_.Exception.Message)"
}

[System.Windows.Forms.Application]::Run($form)
