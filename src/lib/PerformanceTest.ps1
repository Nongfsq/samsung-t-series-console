Set-StrictMode -Version Latest

function Invoke-STCPerformanceTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [ValidateRange(1, 64)]
        [int] $SizeGiB = 8,
        [ValidateRange(1, 1024)]
        [int] $BufferMiB = 16
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $root = "$letter`:\"
    if (-not (Test-Path -LiteralPath $root)) {
        throw "Drive root not found: $root"
    }

    $drive = Get-STCDriveByLetter -DriveLetter $letter
    if ($null -eq $drive) {
        throw "Samsung T-series drive not found at $letter`:"
    }

    $testPath = Join-Path $root ".stc-benchmark-$([guid]::NewGuid().ToString('N')).bin"
    $sizeBytes = [int64] $SizeGiB * 1GB
    $bufferBytes = $BufferMiB * 1MB
    $buffer = New-Object byte[] $bufferBytes
    $rng = [System.Random]::new(20260522)
    $rng.NextBytes($buffer)

    $result = $null
    $stream = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $options = [System.IO.FileOptions]::WriteThrough -bor [System.IO.FileOptions]::SequentialScan
        $stream = [System.IO.FileStream]::new($testPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, $bufferBytes, $options)
        [int64] $written = 0

        while ($written -lt $sizeBytes) {
            $remaining = $sizeBytes - $written
            $toWrite = [int] [math]::Min($bufferBytes, $remaining)
            $stream.Write($buffer, 0, $toWrite)
            $written += $toWrite
        }

        $stream.Flush($true)
        $sw.Stop()

        $mbps = [math]::Round(($sizeBytes / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 2)
        $result = [pscustomobject]@{
            Drive       = "$letter`:"
            Model       = $drive.Model
            Serial      = $drive.Serial
            DiskNumber  = $drive.DiskNumber
            SizeGiB     = $SizeGiB
            BufferMiB   = $BufferMiB
            Seconds     = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            WriteMBps   = $mbps
            TestPath    = $testPath
            Timestamp   = (Get-Date).ToString('o')
            Interpretation = if ($mbps -ge 600) {
                'Healthy for Samsung T7/T7 Shield on USB 10Gbps-class link.'
            } elseif ($mbps -ge 300) {
                'Below expected full-speed T7 result; check cable, port, thermal state, and background access.'
            } else {
                'Abnormally slow; suspect filesystem state, device retry, cable/port fallback, or firmware/tool interference.'
            }
        }

        Write-STCLog -Category 'performance' -Message "Performance test completed for $letter`:." -Data $result
        return $result
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }

        if (Test-Path -LiteralPath $testPath) {
            Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
        }
    }
}
