$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectDir = $PSScriptRoot
$projectName = "soc_system"
$qpf = Join-Path $projectDir "$projectName.qpf"
$rbf = Join-Path $projectDir "output_files\$projectName.rbf"
$sof = Join-Path $projectDir "output_files\$projectName.sof"

$quartusBins = @(
    "quartus_sh",
    "C:\intelFPGA_lite\21.1\quartus\bin64\quartus_sh.exe",
    "C:\intelFPGA\21.1\quartus\bin64\quartus_sh.exe",
    "C:\Program Files\intelFPGA_lite\21.1\quartus\bin64\quartus_sh.exe",
    "C:\Program Files\intelFPGA\21.1\quartus\bin64\quartus_sh.exe"
)

$quartusSh = $null
foreach ($candidate in $quartusBins) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
        $quartusSh = $cmd.Source
        break
    }
    if (Test-Path $candidate) {
        $quartusSh = $candidate
        break
    }
}

if (-not $quartusSh) {
    throw "quartus_sh not found. Install Quartus Prime 21.1 Lite or add it to PATH."
}

$quartusRoot = Split-Path -Parent (Split-Path -Parent $quartusSh)
$quartusMap = Join-Path $quartusRoot "bin64\quartus_map.exe"
$quartusFit = Join-Path $quartusRoot "bin64\quartus_fit.exe"
$quartusAsm = Join-Path $quartusRoot "bin64\quartus_asm.exe"
$quartusCpf = Join-Path $quartusRoot "bin64\quartus_cpf.exe"

Push-Location $projectDir
try {
    & $quartusSh --flow compile $qpf

    if (-not (Test-Path $sof)) {
        throw "Expected SOF not found at $sof"
    }

    if (Test-Path $quartusCpf) {
        & $quartusCpf -c $sof $rbf
    }
} finally {
    Pop-Location
}

Write-Host "SOF: $sof"
if (Test-Path $rbf) {
    Write-Host "RBF: $rbf"
}
