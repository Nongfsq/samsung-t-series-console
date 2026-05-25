Set-StrictMode -Version Latest

if (-not (Get-Command Write-STCLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Logging.ps1')
}

function Get-STCSamsungMagicianPolicyStatus {
    [CmdletBinding()]
    param()

    $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)Samsung.*Magician|Magician.*Samsung' -or
        $_.DisplayName -match '(?i)Samsung.*Magician|Magician.*Samsung'
    })

    $processes = @(Get-Process -Name SamsungMagician, SamsungPortableSSD -ErrorAction SilentlyContinue |
        Select-Object ProcessName, Id, MainWindowTitle, Path)

    $items = @()
    foreach ($service in $services) {
        $items += [pscustomobject]@{
            Name        = $service.Name
            DisplayName = $service.DisplayName
            Status      = [string] $service.Status
            StartType   = [string] $service.StartType
            Target      = if ($service.Name -eq 'SamsungMagicianSVC') { 'Manual' } else { 'Review' }
            Action      = if ($service.Name -eq 'SamsungMagicianSVC' -and ([string] $service.StartType -ne 'Manual' -or [string] $service.Status -eq 'Running')) { 'SetManualAndStop' } else { 'None' }
        }
    }

    return [pscustomobject]@{
        Services  = @($items)
        Processes = @($processes)
    }
}

function Set-STCSamsungMagicianManualStartup {
    [CmdletBinding()]
    param()

    $before = Get-STCSamsungMagicianPolicyStatus
    $changes = @()

    $service = Get-Service -Name SamsungMagicianSVC -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        $changes += [pscustomobject]@{
            Service          = 'SamsungMagicianSVC'
            PreviousStartType = 'NotFound'
            NewStartType      = 'NotFound'
            Changed           = $false
            Error             = $null
        }
    } else {
        $previous = [string] $service.StartType
        $previousStatus = [string] $service.Status
        $errorMessage = $null
        $changed = $false
        if ($previous -ne 'Manual') {
            try {
                Set-Service -Name SamsungMagicianSVC -StartupType Manual -ErrorAction Stop
                $changed = $true
            } catch {
                $errorMessage = $_.Exception.Message
            }
        }

        try {
            $service = Get-Service -Name SamsungMagicianSVC -ErrorAction SilentlyContinue
            if ($service -and [string] $service.Status -eq 'Running') {
                Stop-Service -Name SamsungMagicianSVC -Force -ErrorAction Stop
                $changed = $true
            }
        } catch {
            $errorMessage = if ($errorMessage) { "$errorMessage; $($_.Exception.Message)" } else { $_.Exception.Message }
        }

        $afterService = Get-Service -Name SamsungMagicianSVC -ErrorAction SilentlyContinue
        $changes += [pscustomobject]@{
            Service           = 'SamsungMagicianSVC'
            PreviousStartType = $previous
            PreviousStatus    = $previousStatus
            NewStartType      = if ($afterService) { [string] $afterService.StartType } else { 'NotFound' }
            NewStatus         = if ($afterService) { [string] $afterService.Status } else { 'NotFound' }
            Changed           = $changed
            Error             = $errorMessage
        }
    }

    $after = Get-STCSamsungMagicianPolicyStatus
    $result = [pscustomobject]@{
        Policy  = 'SamsungMagicianManualStartup'
        Changed = [bool] @($changes | Where-Object { $_.Changed }).Count
        Before  = $before
        Changes = @($changes)
        After   = $after
    }

    Write-STCLog -Category 'system-policy' -Message 'Samsung Magician startup and runtime policy applied.' -Data $result
    return $result
}
