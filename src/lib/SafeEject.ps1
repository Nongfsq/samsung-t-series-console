Set-StrictMode -Version Latest

if (-not (Get-Command Write-STCLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Logging.ps1')
}

if (-not (Get-Command Get-STCRelevantProcess -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'RiskAudit.ps1')
}

function Invoke-STCFlush {
    [CmdletBinding()]
    param()

    $sync = Get-Command sync.exe -ErrorAction SilentlyContinue
    if ($sync) {
        & $sync.Source 2>$null
        Write-STCLog -Category 'safe-eject' -Message 'sync.exe invoked.' -Data @{ Path = $sync.Source }
        return "sync.exe invoked: $($sync.Source)"
    }

    Write-STCLog -Category 'safe-eject' -Message 'sync.exe not found; relying on Windows cache policy and FileStream flushes.' -Data $null
    return 'sync.exe not found; relying on Windows cache policy and FileStream flushes.'
}

function Get-STCEjectBlockerSummary {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $processes = Get-STCRelevantProcess
    $events = Get-STCRecentSystemEvent -Id @(225) -DaysBack 3

    return [pscustomobject]@{
        Drive             = if ($DriveLetter) { "$($DriveLetter.ToUpperInvariant()):" } else { $null }
        RelevantProcesses = @($processes)
        RecentEjectEvents = @($events | Sort-Object TimeCreated -Descending | Select-Object -First 10)
        Notes             = @(
            'Close Explorer windows that display the drive.',
            'Close Samsung Magician before ejecting.',
            'If SearchIndexer is listed and eject still fails, temporarily stop Windows Search after confirmation.'
        )
    }
}

function Stop-STCWindowsSearchWithConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConfirmationPhrase
    )

    if ($ConfirmationPhrase -ne 'STOP WINDOWS SEARCH') {
        throw 'Confirmation phrase mismatch. Expected: STOP WINDOWS SEARCH'
    }

    $service = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return 'Windows Search service not found.'
    }

    if ($service.Status -eq 'Running') {
        Stop-Service -Name WSearch -Force -ErrorAction Stop
        Write-STCLog -Category 'safe-eject' -Message 'Windows Search service stopped by user request.' -Data $null
        return 'Windows Search stopped. It will normally restart later or after reboot.'
    }

    return "Windows Search status is $($service.Status); no stop needed."
}

function Get-STCRustCliPath {
    [CmdletBinding()]
    param()

    $projectRoot = Get-STCProjectRoot
    $candidates = @(
        (Join-Path $projectRoot 'target\release\stc.exe'),
        (Join-Path $projectRoot 'target\debug\stc.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command stc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Invoke-STCRustEject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $cliPath = Get-STCRustCliPath
    if ([string]::IsNullOrWhiteSpace($cliPath)) {
        throw 'Rust CLI stc.exe was not found. Build it with: cargo build -p stc-cli'
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $cliPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.ArgumentList.Add('eject') | Out-Null
    $psi.ArgumentList.Add("$letter`:") | Out-Null
    $psi.ArgumentList.Add('--yes') | Out-Null

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $envelope = $null
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        try {
            $envelope = $stdout | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Rust CLI returned non-JSON output: $stdout"
        }
    }

    $payload = if ($null -ne $envelope) { $envelope.payload } else { $null }
    $result = if ($null -ne $payload -and $payload.PSObject.Properties.Name -contains 'result') { [string] $payload.result } else { 'error' }
    $stillPresent = if ($null -ne $payload -and $payload.PSObject.Properties.Name -contains 'still_present') {
        [bool] $payload.still_present
    } else {
        Test-Path -LiteralPath "$letter`:\"
    }

    $message = switch ($result) {
        'ok' {
            if ($stillPresent) {
                'Rust eject accepted the request, but the drive is still visible. Wait briefly, then refresh.'
            } else {
                'Rust eject accepted the request and the drive path is no longer visible.'
            }
        }
        'vetoed' {
            $vetoName = if ($payload.veto_name) { " by $($payload.veto_name)" } else { '' }
            "Windows vetoed eject$vetoName ($($payload.veto_type))."
        }
        'not-ejectable' {
            "Rust eject could not eject this drive: $($payload.reason_key)."
        }
        default {
            if ([string]::IsNullOrWhiteSpace($stderr)) {
                "Rust eject failed with exit code $($process.ExitCode)."
            } else {
                "Rust eject failed with exit code $($process.ExitCode): $stderr"
            }
        }
    }

    $resultObject = [pscustomobject]@{
        Drive        = "$letter`:"
        Method       = 'RustCfgMgr32'
        CliPath      = $cliPath
        ExitCode     = [int] $process.ExitCode
        Result       = $result
        VetoType     = if ($null -ne $payload -and $payload.PSObject.Properties.Name -contains 'veto_type') { $payload.veto_type } else { $null }
        VetoName     = if ($null -ne $payload -and $payload.PSObject.Properties.Name -contains 'veto_name') { $payload.veto_name } else { $null }
        StillPresent = $stillPresent
        Message      = $message
        StdErr       = $stderr.Trim()
        Payload      = $payload
    }

    Write-STCLog -Category 'safe-eject' -Message "Rust eject attempted for $letter`:." -Data $resultObject
    return $resultObject
}

function Invoke-STCSafeEject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    try {
        $rustResult = Invoke-STCRustEject -DriveLetter $DriveLetter
        if ($rustResult.ExitCode -in @(0, 10, 11, 12, 13)) {
            return $rustResult
        }

        Write-STCLog -Category 'safe-eject' -Message 'Rust eject returned an internal error; falling back to Shell COM.' -Data $rustResult
    } catch {
        Write-STCLog -Category 'safe-eject' -Message 'Rust eject unavailable; falling back to Shell COM.' -Data @{ Error = $_.Exception.Message }
    }

    $shellResult = Invoke-STCShellEject -DriveLetter $DriveLetter
    return [pscustomobject]@{
        Drive        = $shellResult.Drive
        Method       = 'ShellCom'
        CliPath      = $null
        ExitCode     = $null
        Result       = if ($shellResult.StillPresent) { 'unknown' } else { 'ok' }
        VetoType     = $null
        VetoName     = $null
        StillPresent = $shellResult.StillPresent
        Message      = $shellResult.Message
        StdErr       = $null
        Payload      = $shellResult
    }
}

function Invoke-STCShellEject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $drivePath = "$letter`:\"
    if (-not (Test-Path -LiteralPath $drivePath)) {
        throw "Drive root not found: $drivePath"
    }

    $flushMessage = Invoke-STCFlush

    $shell = New-Object -ComObject Shell.Application
    $namespace = $shell.Namespace(17)
    $item = $namespace.ParseName("$letter`:")
    if ($null -eq $item) {
        throw "Shell could not locate drive $letter`:"
    }

    $ejectVerb = @($item.Verbs() | Where-Object { $_.Name.Replace('&', '') -match '(?i)Eject|弹出|安全删除|Safely Remove' } | Select-Object -First 1)[0]
    if ($null -eq $ejectVerb) {
        throw "No shell eject verb found for $letter`:. Use Windows tray safe-remove UI or shut down before unplugging."
    }

    $ejectVerb.DoIt()
    Start-Sleep -Seconds 2

    $stillPresent = Test-Path -LiteralPath $drivePath
    $result = [pscustomobject]@{
        Drive        = "$letter`:"
        FlushMessage = $flushMessage
        EjectVerb    = $ejectVerb.Name
        StillPresent = $stillPresent
        Message      = if ($stillPresent) { 'Eject command sent, but drive is still visible. Check blockers and Windows notification area.' } else { 'Eject command sent and drive path is no longer visible.' }
    }

    Write-STCLog -Category 'safe-eject' -Message "Shell eject attempted for $letter`:." -Data $result
    return $result
}
