Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$libRoot = Join-Path $projectRoot 'src\lib'

. (Join-Path $libRoot 'Logging.ps1')
. (Join-Path $libRoot 'DriveDetection.ps1')
. (Join-Path $libRoot 'RiskAudit.ps1')
. (Join-Path $libRoot 'ContentProfile.ps1')
. (Join-Path $libRoot 'PerformanceTest.ps1')
. (Join-Path $libRoot 'FormatPolicy.ps1')
. (Join-Path $libRoot 'SafeEject.ps1')
. (Join-Path $libRoot 'SearchPolicy.ps1')
. (Join-Path $libRoot 'MagicianPolicy.ps1')
. (Join-Path $libRoot 'DailyEject.ps1')

$drives = @(Get-SamsungTDrive)
$audit = @(Get-STCRiskAudit -DaysBack 1)
$dashboard = Get-STCDailyDashboardState
$searchPolicy = @(Get-STCWindowsSearchSamsungPolicyStatus)
$magicianPolicy = Get-STCSamsungMagicianPolicyStatus

[pscustomobject]@{
    Status = 'OK'
    DetectedDriveCount = $drives.Count
    Drives = $drives | Select-Object Drive, Model, Serial, FileSystem, AllocationUnitKB, HealthStatus, DiskNumber
    AuditCount = $audit.Count
    DailyDashboardCount = $dashboard.Count
    DailyDashboard = $dashboard.Drives | Select-Object Drive, Status, Headline, PrimaryAction
    WindowsSearchPolicyCount = $searchPolicy.Count
    SamsungMagicianServiceCount = $magicianPolicy.Services.Count
} | ConvertTo-Json -Depth 8
