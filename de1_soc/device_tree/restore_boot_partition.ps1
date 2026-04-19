param(
    [Parameter(Mandatory = $true)]
    [string]$BootDriveLetter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$bootRoot = "{0}:\" -f $BootDriveLetter.TrimEnd(':')
if (-not (Test-Path $bootRoot)) {
    throw "Boot drive not found: $bootRoot"
}

$targetRbf = Join-Path $bootRoot "soc_system.rbf"
$targetDtb = Join-Path $bootRoot "soc_system.dtb"

function Restore-LatestBackup {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $candidates = @()
    $stampBackups = Get-ChildItem -Path "$TargetPath.bak_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($stampBackups) {
        $candidates += $stampBackups
    }

    foreach ($suffix in @(".bak_2", ".bak")) {
        $p = "$TargetPath$suffix"
        if (Test-Path $p) {
            $candidates += Get-Item $p
        }
    }

    if (-not $candidates) {
        throw "No backup found for $TargetPath"
    }

    $targetName = [System.IO.Path]::GetFileName($TargetPath)
    if ($targetName -ieq "soc_system.dtb") {
        $validCandidates = @(
            $candidates |
                Where-Object { $_.Length -ge 4096 } |
                Sort-Object `
                    @{ Expression = "Length"; Descending = $true }, `
                    @{ Expression = "LastWriteTime"; Descending = $true }
        )
        if (-not $validCandidates) {
            throw "No valid DTB backup found for $TargetPath"
        }

        $candidates = $validCandidates
    }

    $backup = $candidates | Select-Object -First 1
    Copy-Item $backup.FullName $TargetPath -Force
    return Get-Item $TargetPath
}

$restoredDtb = Restore-LatestBackup -TargetPath $targetDtb
$restoredRbf = Restore-LatestBackup -TargetPath $targetRbf

Write-Host "Restored boot artifacts from backups on $bootRoot"
$restoredDtb, $restoredRbf | Format-Table FullName,Length,LastWriteTime -AutoSize
