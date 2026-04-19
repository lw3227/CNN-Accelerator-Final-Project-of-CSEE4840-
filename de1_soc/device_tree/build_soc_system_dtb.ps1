param(
    [string]$BaseDtb,
    [string]$BaseDts,
    [string]$OutDir = "de1_soc\device_tree\build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MinBootDtbBytes = 4096

if ([string]::IsNullOrWhiteSpace($BaseDtb) -and [string]::IsNullOrWhiteSpace($BaseDts)) {
    throw "Pass either -BaseDtb <path> or -BaseDts <path>."
}

if (-not [string]::IsNullOrWhiteSpace($BaseDtb) -and -not [string]::IsNullOrWhiteSpace($BaseDts)) {
    throw "Pass only one of -BaseDtb or -BaseDts."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$outDirAbs = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outDirAbs | Out-Null

$baseDtsAbs = $null
if (-not [string]::IsNullOrWhiteSpace($BaseDts)) {
    $baseDtsAbs = (Resolve-Path $BaseDts).Path
}

$baseDtbAbs = $null
if (-not [string]::IsNullOrWhiteSpace($BaseDtb)) {
    $baseDtbAbs = (Resolve-Path $BaseDtb).Path
}

$patchedDtsAbs = Join-Path $outDirAbs "soc_system_patched.dts"
$outDtbAbs = Join-Path $outDirAbs "soc_system.dtb"
$pythonScriptAbs = Join-Path $repoRoot "de1_soc\device_tree\patch_socfpga_dts.py"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)
    if (Test-Path $WindowsPath) {
        $resolved = (Resolve-Path $WindowsPath).Path
    } else {
        $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
    }
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $tail = $resolved.Substring(2).Replace("\", "/")
    return "/mnt/$drive$tail"
}

$wslPython = Convert-ToWslPath -WindowsPath $pythonScriptAbs
$wslPatchedDts = Convert-ToWslPath -WindowsPath $patchedDtsAbs
$wslOutDtb = Convert-ToWslPath -WindowsPath $outDtbAbs

if ($baseDtbAbs) {
    $baseDtsAbs = Join-Path $outDirAbs "base_from_dtb.dts"
    $wslBaseDtb = Convert-ToWslPath -WindowsPath $baseDtbAbs
    $wslBaseDts = Convert-ToWslPath -WindowsPath $baseDtsAbs
    & wsl.exe bash -lc "set -e; dtc -I dtb -O dts -o '$wslBaseDts' '$wslBaseDtb'"
    if ($LASTEXITCODE -ne 0) {
        throw "dtc failed while converting base DTB to DTS."
    }
}

$wslBaseDts = Convert-ToWslPath -WindowsPath $baseDtsAbs
& wsl.exe bash -lc "set -e; python3 '$wslPython' '$wslBaseDts' '$wslPatchedDts'; dtc -I dts -O dtb -o '$wslOutDtb' '$wslPatchedDts'"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to patch or compile DTS."
}

$outDtbInfo = Get-Item $outDtbAbs
if ($outDtbInfo.Length -lt $MinBootDtbBytes) {
    throw "Generated DTB is only $($outDtbInfo.Length) bytes. Refusing to use it as a boot DTB because it does not look like a complete SocFPGA device tree."
}

Write-Host "Patched DTS: $patchedDtsAbs"
Write-Host "Output DTB:  $outDtbAbs"
Write-Host "Next step: copy soc_system.dtb together with de1_soc/output_files/soc_system.rbf to the board boot media."
