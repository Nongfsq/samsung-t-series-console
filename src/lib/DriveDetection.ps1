Set-StrictMode -Version Latest

function Test-STCSamsungTSeriesDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Disk
    )

    $name = [string] $Disk.FriendlyName
    if ($Disk.BusType -ne 'USB') {
        return $false
    }

    return ($name -match '(?i)(Samsung\s+PSSD|PSSD\s+T[579]|T7|T9)')
}

function Get-SamsungTDrive {
    [CmdletBinding()]
    param()

    $results = New-Object System.Collections.Generic.List[object]
    $disks = @(Get-Disk -ErrorAction Stop | Where-Object { Test-STCSamsungTSeriesDisk -Disk $_ })

    foreach ($disk in $disks) {
        $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        foreach ($partition in $partitions) {
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
            if ($null -eq $volume) {
                continue
            }

            $allocationUnit = $null
            try {
                $allocationUnit = [int64] $volume.AllocationUnitSize
            } catch {
                $allocationUnit = $null
            }

            $driveLetter = [string] $partition.DriveLetter
            $displayName = '{0}: {1} [{2}] {3}, AU {4}KB' -f $driveLetter, $disk.FriendlyName, $volume.FileSystemLabel, $volume.FileSystem, $(if ($allocationUnit) { [math]::Round($allocationUnit / 1KB, 0) } else { 'n/a' })

            $results.Add([pscustomobject]@{
                DriveLetter        = $driveLetter
                Drive              = "$driveLetter`:"
                Root               = "$driveLetter`:\"
                Label              = $volume.FileSystemLabel
                FileSystem         = $volume.FileSystem
                AllocationUnitSize = $allocationUnit
                AllocationUnitKB   = if ($allocationUnit) { [int64] ($allocationUnit / 1KB) } else { $null }
                SizeGB             = [math]::Round($volume.Size / 1GB, 2)
                FreeGB             = [math]::Round($volume.SizeRemaining / 1GB, 2)
                HealthStatus       = [string] $volume.HealthStatus
                OperationalStatus  = ($volume.OperationalStatus -join ',')
                DiskNumber         = [int] $disk.Number
                BusType            = [string] $disk.BusType
                Model              = [string] $disk.FriendlyName
                Serial             = [string] $disk.SerialNumber
                PartitionStyle     = [string] $disk.PartitionStyle
                IsBoot             = [bool] $disk.IsBoot
                IsSystem           = [bool] $disk.IsSystem
                DisplayName        = $displayName
            }) | Out-Null
        }
    }

    $items = @($results | Sort-Object DriveLetter)
    Write-STCLog -Category 'detect' -Message 'Detected Samsung T-series drives.' -Data $items
    return $items
}

function Get-STCDriveByLetter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $matches = @(Get-SamsungTDrive | Where-Object { $_.DriveLetter -eq $letter })
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}
