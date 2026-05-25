Set-StrictMode -Version Latest

if (-not (Get-Command Get-STCDriveByLetter -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Logging.ps1')
    . (Join-Path $PSScriptRoot 'DriveDetection.ps1')
}

function Get-STCContentProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $root = "$letter`:\"
    if (-not (Test-Path -LiteralPath $root)) {
        throw "Drive root not found: $root"
    }

    $drive = Get-STCDriveByLetter -DriveLetter $letter
    $extensionStats = @{}
    $bucketStats = [ordered]@{
        '0-1MB'      = [ordered]@{ Count = 0; Bytes = [int64] 0 }
        '1-10MB'     = [ordered]@{ Count = 0; Bytes = [int64] 0 }
        '10-100MB'   = [ordered]@{ Count = 0; Bytes = [int64] 0 }
        '100MB-1GB'  = [ordered]@{ Count = 0; Bytes = [int64] 0 }
        '1GB+'       = [ordered]@{ Count = 0; Bytes = [int64] 0 }
    }

    $fileCount = 0
    [int64] $totalBytes = 0
    [int64] $largeBytes = 0
    $mediaExtensions = @('.arw', '.raw', '.dng', '.cr2', '.cr3', '.nef', '.raf', '.rw2', '.orf', '.jpg', '.jpeg', '.heic', '.tif', '.tiff', '.mp4', '.mov', '.mkv', '.avi', '.iso')
    [int64] $mediaBytes = 0

    Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $fileCount++
        $length = [int64] $_.Length
        $totalBytes += $length
        $ext = if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '<none>' }

        if (-not $extensionStats.ContainsKey($ext)) {
            $extensionStats[$ext] = [ordered]@{ Count = 0; Bytes = [int64] 0 }
        }
        $extensionStats[$ext].Count++
        $extensionStats[$ext].Bytes += $length

        if ($mediaExtensions -contains $ext) {
            $mediaBytes += $length
        }

        $bucket = if ($length -lt 1MB) {
            '0-1MB'
        } elseif ($length -lt 10MB) {
            '1-10MB'
        } elseif ($length -lt 100MB) {
            '10-100MB'
        } elseif ($length -lt 1GB) {
            '100MB-1GB'
        } else {
            '1GB+'
        }

        if ($length -ge 100MB) {
            $largeBytes += $length
        }

        $bucketStats[$bucket].Count++
        $bucketStats[$bucket].Bytes += $length
    }

    $topExtensions = @($extensionStats.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Extension = $_.Key
            Count     = $_.Value.Count
            GB        = [math]::Round($_.Value.Bytes / 1GB, 2)
            Bytes     = [int64] $_.Value.Bytes
            Percent   = if ($totalBytes -gt 0) { [math]::Round(100 * $_.Value.Bytes / $totalBytes, 2) } else { 0 }
        }
    } | Sort-Object Bytes -Descending | Select-Object -First 15)

    $bucketObjects = @($bucketStats.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Bucket  = $_.Key
            Count   = $_.Value.Count
            GB      = [math]::Round($_.Value.Bytes / 1GB, 2)
            Percent = if ($totalBytes -gt 0) { [math]::Round(100 * $_.Value.Bytes / $totalBytes, 2) } else { 0 }
        }
    })

    $largePercent = if ($totalBytes -gt 0) { 100 * $largeBytes / $totalBytes } else { 0 }
    $mediaPercent = if ($totalBytes -gt 0) { 100 * $mediaBytes / $totalBytes } else { 0 }
    $knownLargeMediaDisk = $false
    if ($null -ne $drive) {
        $knownLargeMediaDisk = (
            (($drive.Model -match '(?i)T7 Shield') -and $drive.SizeGB -gt 3000)
        )
    }

    $recommendedAllocationUnitKB = if ($knownLargeMediaDisk -or $largePercent -ge 35 -or $mediaPercent -ge 60 -or $totalBytes -gt 2TB) { 256 } else { 128 }
    $recommendationReason = if ($knownLargeMediaDisk) {
        'T7 Shield 4TB large-media baseline; keep exFAT + 256KB even when the disk is currently empty.'
    } elseif ($recommendedAllocationUnitKB -eq 256) {
        'Large RAW/video/ISO-heavy profile or high total payload.'
    } else {
        'Mixed profile; 128KB balances space efficiency and large-file performance.'
    }

    $profile = [pscustomobject]@{
        Drive                       = "$letter`:"
        Root                        = $root
        FileCount                   = $fileCount
        TotalGB                     = [math]::Round($totalBytes / 1GB, 2)
        LargeFileBytesPercent       = [math]::Round($largePercent, 2)
        MediaBytesPercent           = [math]::Round($mediaPercent, 2)
        RecommendedAllocationUnitKB = $recommendedAllocationUnitKB
        RecommendationReason        = $recommendationReason
        SizeBuckets                 = $bucketObjects
        TopExtensions               = $topExtensions
    }

    Write-STCLog -Category 'content-profile' -Message "Content profile completed for $letter`:." -Data $profile
    return $profile
}
