param(
    [Parameter(Mandatory = $true)]
    [string]$BootDriveLetter,
    [string]$RbfPath = "de1_soc\output_files\soc_system.rbf",
    [string]$DtbPath = "de1_soc\device_tree\build\soc_system.dtb"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$rbfAbs = (Resolve-Path (Join-Path $repoRoot $RbfPath)).Path
$dtbAbs = (Resolve-Path (Join-Path $repoRoot $DtbPath)).Path

$bootRoot = "{0}:\" -f $BootDriveLetter.TrimEnd(':')
if (-not (Test-Path $bootRoot)) {
    throw "Boot drive not found: $bootRoot"
}

$targetRbf = Join-Path $bootRoot "soc_system.rbf"
$targetDtb = Join-Path $bootRoot "soc_system.dtb"

$rbfInfo = Get-Item $rbfAbs
$dtbInfo = Get-Item $dtbAbs
if ($dtbInfo.Length -lt 4096) {
    throw "Refusing to stage DTB smaller than 4096 bytes: $dtbAbs ($($dtbInfo.Length) bytes)"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (Test-Path $targetRbf) {
    Copy-Item $targetRbf "$targetRbf.bak_$stamp" -Force
}
if (Test-Path $targetDtb) {
    Copy-Item $targetDtb "$targetDtb.bak_$stamp" -Force
}

Copy-Item $rbfAbs $targetRbf -Force
Copy-Item $dtbAbs $targetDtb -Force

Write-Host "Staged boot artifacts to $bootRoot"
Get-Item $targetRbf, $targetDtb | Format-Table FullName,Length,LastWriteTime -AutoSize
