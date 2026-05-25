Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$libRoot = Join-Path $projectRoot 'src\lib'

. (Join-Path $libRoot 'Logging.ps1')
. (Join-Path $libRoot 'DriveDetection.ps1')
. (Join-Path $libRoot 'SearchPolicy.ps1')
. (Join-Path $libRoot 'MagicianPolicy.ps1')

$drives = @(Get-SamsungTDrive)
$searchPolicy = @(Get-STCWindowsSearchSamsungPolicyStatus)
$magicianPolicy = Get-STCSamsungMagicianPolicyStatus

if ($searchPolicy.Count -ne $drives.Count) {
    throw "Expected Windows Search policy status for $($drives.Count) drive(s), got $($searchPolicy.Count)."
}

foreach ($item in $searchPolicy) {
    if ($item.SearchUrl -notmatch '^file:///[A-Z]:\\$') {
        throw "Unexpected Windows Search URL for $($item.Drive): $($item.SearchUrl)"
    }
}

$targetService = @($magicianPolicy.Services | Where-Object { $_.Name -eq 'SamsungMagicianSVC' })
if ($targetService.Count -gt 1) {
    throw "Expected at most one SamsungMagicianSVC entry, got $($targetService.Count)."
}

[pscustomobject]@{
    Status = 'OK'
    SamsungDriveCount = $drives.Count
    WindowsSearchPolicy = $searchPolicy | Select-Object Drive, SearchUrl, Excluded, Action
    SamsungMagicianPolicy = $magicianPolicy.Services | Select-Object Name, Status, StartType, Action
} | ConvertTo-Json -Depth 8
