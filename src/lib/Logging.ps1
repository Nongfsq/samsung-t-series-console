Set-StrictMode -Version Latest

$script:STCProjectRoot = $null

function Get-STCProjectRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:STCProjectRoot)) {
        return $script:STCProjectRoot
    }

    $script:STCProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    return $script:STCProjectRoot
}

function Get-STCLogRoot {
    $root = if ($env:STC_LOG_ROOT) {
        $env:STC_LOG_ROOT
    } else {
        Join-Path (Get-STCProjectRoot) 'logs'
    }

    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    return $root
}

function Write-STCLog {
    [CmdletBinding()]
    param(
        [string] $Category = 'general',
        [Parameter(Mandatory)]
        [string] $Message,
        [object] $Data
    )

    try {
        $entry = [ordered]@{
            timestamp = (Get-Date).ToString('o')
            category  = $Category
            message   = $Message
            data      = $Data
        }

        $path = Join-Path (Get-STCLogRoot) "$(Get-Date -Format 'yyyy-MM-dd').jsonl"
        $entry | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath $path -Encoding UTF8
    } catch {
        Write-Warning "Failed to write STC log: $($_.Exception.Message)"
    }
}

function Export-STCJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [object] $Data
    )

    $safeName = $Name -replace '[^a-zA-Z0-9_.-]', '_'
    $path = Join-Path (Get-STCLogRoot) "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$safeName.json"
    $Data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function ConvertTo-STCReadableText {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return ''
        }

        if ($InputObject -is [string]) {
            return $InputObject
        }

        return ($InputObject | Format-List * -Force | Out-String -Width 260)
    }
}
