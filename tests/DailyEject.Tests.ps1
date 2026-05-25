Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$libRoot = Join-Path $projectRoot 'src\lib'

. (Join-Path $libRoot 'Logging.ps1')
. (Join-Path $libRoot 'DailyEject.ps1')

$cases = @(
    @{
        Name = 'Ready'
        Args = @{
            Status = 'Ready'
            BlockerNames = @()
            HasCriticalDisk153 = $false
            HasDrivePnp225 = $false
            HasFormatMismatch = $false
            HasGlobalPnp225 = $false
        }
        ExpectedPrimaryAction = 'SafeEject'
    },
    @{
        Name = 'Caution'
        Args = @{
            Status = 'Caution'
            BlockerNames = @('SearchIndexer')
            HasCriticalDisk153 = $false
            HasDrivePnp225 = $false
            HasFormatMismatch = $false
            HasGlobalPnp225 = $false
        }
        ExpectedPrimaryAction = 'CloseAppsThenRetry'
    },
    @{
        Name = 'Blocked'
        Args = @{
            Status = 'Blocked'
            BlockerNames = @()
            HasCriticalDisk153 = $true
            HasDrivePnp225 = $false
            HasFormatMismatch = $false
            HasGlobalPnp225 = $false
        }
        ExpectedPrimaryAction = 'ShutdownBeforeUnplug'
    },
    @{
        Name = 'Unknown'
        Args = @{
            Status = 'Unknown'
            BlockerNames = @()
            HasCriticalDisk153 = $false
            HasDrivePnp225 = $false
            HasFormatMismatch = $false
            HasGlobalPnp225 = $false
        }
        ExpectedPrimaryAction = 'RefreshOrDiagnose'
    }
)

$results = @()
foreach ($case in $cases) {
    $argsForCase = $case.Args
    $result = ConvertTo-STCUserRecommendation @argsForCase
    $passed = $result.PrimaryAction -eq $case.ExpectedPrimaryAction
    if (-not $passed) {
        throw "DailyEject case failed: $($case.Name). Expected $($case.ExpectedPrimaryAction), got $($result.PrimaryAction)."
    }

    $results += [pscustomobject]@{
        Name = $case.Name
        PrimaryAction = $result.PrimaryAction
        Headline = $result.Headline
        Passed = $passed
    }
}

[pscustomobject]@{
    Status = 'OK'
    Cases = $results
} | ConvertTo-Json -Depth 6
