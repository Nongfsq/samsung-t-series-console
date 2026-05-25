Set-StrictMode -Version Latest

function Get-STCFormatRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [object] $ContentProfile
    )

    $drive = Get-STCDriveByLetter -DriveLetter $DriveLetter
    if ($null -eq $drive) {
        throw "Samsung T-series drive not found at $DriveLetter`:"
    }

    $expectedAU = if (($drive.Model -match '(?i)T7 Shield') -and $drive.SizeGB -gt 3000) {
        256
    } elseif ($null -ne $ContentProfile -and $ContentProfile.PSObject.Properties.Name -contains 'RecommendedAllocationUnitKB') {
        [int] $ContentProfile.RecommendedAllocationUnitKB
    } else {
        128
    }

    $requiresFormat = $false
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($drive.FileSystem -ne 'exFAT') {
        $requiresFormat = $true
        $reasons.Add("Filesystem is $($drive.FileSystem), expected exFAT for Windows/macOS sharing.") | Out-Null
    }

    if ($drive.AllocationUnitKB -ne $expectedAU) {
        $requiresFormat = $true
        $reasons.Add("Allocation unit is $($drive.AllocationUnitKB)KB; recommended profile is $expectedAU`KB.") | Out-Null
    }

    if (($drive.Model -match '(?i)PSSD\s+T7') -and $drive.SizeGB -lt 2000 -and $drive.AllocationUnitKB -eq 128 -and $drive.FileSystem -eq 'exFAT') {
        $reasons.Add('T7 mixed-use baseline: exFAT + 128KB is reasonable. Do not reformat unless benchmark/audit fails.') | Out-Null
    }

    if (($drive.Model -match '(?i)T7 Shield') -and $drive.SizeGB -gt 3000 -and $drive.AllocationUnitKB -eq 256 -and $drive.FileSystem -eq 'exFAT') {
        $reasons.Add('T7 Shield 4TB baseline: exFAT + 256KB matches a large-media profile.') | Out-Null
    }

    return [pscustomobject]@{
        Drive                         = $drive.Drive
        Model                         = $drive.Model
        Serial                        = $drive.Serial
        CurrentFileSystem             = $drive.FileSystem
        CurrentAllocationUnitKB       = $drive.AllocationUnitKB
        RecommendedFileSystem         = 'exFAT'
        RecommendedAllocationUnitKB   = $expectedAU
        RequiresFormatForPolicyMatch  = $requiresFormat
        ConfirmationPhrase            = "FORMAT $($drive.Drive) EXFAT $expectedAU`KB"
        Reasons                       = @($reasons)
    }
}

function Invoke-STCFormatProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter,
        [ValidateSet(128, 256)]
        [int] $AllocationUnitKB,
        [Parameter(Mandatory)]
        [string] $Label,
        [Parameter(Mandatory)]
        [string] $ConfirmationPhrase
    )

    $drive = Get-STCDriveByLetter -DriveLetter $DriveLetter
    if ($null -eq $drive) {
        throw "Samsung T-series drive not found at $DriveLetter`:"
    }

    $expectedPhrase = "FORMAT $($drive.Drive) EXFAT $AllocationUnitKB`KB"
    if ($ConfirmationPhrase -ne $expectedPhrase) {
        throw "Confirmation phrase mismatch. Expected: $expectedPhrase"
    }

    if ($drive.IsBoot -or $drive.IsSystem) {
        throw "Refusing to format boot/system disk."
    }

    $allocationBytes = $AllocationUnitKB * 1KB
    if ($PSCmdlet.ShouldProcess($drive.Drive, "Format exFAT allocation unit $AllocationUnitKB`KB")) {
        Write-STCLog -Category 'format' -Message "Formatting requested for $($drive.Drive)." -Data @{
            Drive = $drive
            AllocationUnitKB = $AllocationUnitKB
            Label = $Label
        }

        Format-Volume -DriveLetter $DriveLetter.ToUpperInvariant() -FileSystem exFAT -AllocationUnitSize $allocationBytes -NewFileSystemLabel $Label -Confirm:$false -Force
    }
}
