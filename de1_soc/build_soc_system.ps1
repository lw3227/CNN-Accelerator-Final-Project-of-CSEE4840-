$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectDir = $PSScriptRoot
$projectName = "soc_system"
$qsys = Join-Path $projectDir "$projectName.qsys"
$qpf = Join-Path $projectDir "$projectName.qpf"
$rbf = Join-Path $projectDir "output_files\$projectName.rbf"
$sof = Join-Path $projectDir "output_files\$projectName.sof"

$quartusBins = @(
    "qsys-generate",
    "quartus_sh",
    "quartus_cpf",
    "C:\intelFPGA_lite\21.1\quartus\bin64\qsys-generate.exe",
    "C:\intelFPGA\21.1\quartus\bin64\qsys-generate.exe",
    "C:\Program Files\intelFPGA_lite\21.1\quartus\bin64\qsys-generate.exe",
    "C:\Program Files\intelFPGA\21.1\quartus\bin64\qsys-generate.exe",
    "C:\intelFPGA_lite\21.1\quartus\bin64\quartus_sh.exe",
    "C:\intelFPGA\21.1\quartus\bin64\quartus_sh.exe",
    "C:\Program Files\intelFPGA_lite\21.1\quartus\bin64\quartus_sh.exe",
    "C:\Program Files\intelFPGA\21.1\quartus\bin64\quartus_sh.exe",
    "C:\intelFPGA_lite\21.1\quartus\bin64\quartus_cpf.exe",
    "C:\intelFPGA\21.1\quartus\bin64\quartus_cpf.exe",
    "C:\Program Files\intelFPGA_lite\21.1\quartus\bin64\quartus_cpf.exe",
    "C:\Program Files\intelFPGA\21.1\quartus\bin64\quartus_cpf.exe"
)

function Find-QuartusTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    foreach ($candidate in $quartusBins) {
        if ($candidate -notmatch [regex]::Escape($ToolName)) {
            continue
        }

        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }

        if (Test-Path $candidate) {
            return $candidate
        }
    }

    if ($env:QUARTUS_ROOTDIR) {
        $toolFromEnv = Join-Path $env:QUARTUS_ROOTDIR "bin64\$ToolName"
        if (Test-Path $toolFromEnv) {
            return $toolFromEnv
        }
    }

    $searchRoots = @(
        "C:\intelFPGA_lite",
        "C:\intelFPGA",
        "C:\Program Files\intelFPGA_lite",
        "C:\Program Files\intelFPGA"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $matches = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "quartus\bin64\$ToolName" } |
            Where-Object { Test-Path $_ }

        if ($matches) {
            return $matches[0]
        }
    }

    return $null
}

$quartusSh = Find-QuartusTool "quartus_sh.exe"
if (-not $quartusSh) {
    throw "quartus_sh not found. Install Quartus Prime 21.1 Lite or add it to PATH."
}

$qsysGenerate = Find-QuartusTool "qsys-generate.exe"
if (-not $qsysGenerate) {
    throw "qsys-generate not found. Install Platform Designer / Quartus Prime 21.1 or add it to PATH."
}

$quartusCpf = Find-QuartusTool "quartus_cpf.exe"
if (-not $quartusCpf) {
    Write-Warning "quartus_cpf not found. RBF conversion will be skipped."
}

$quartusRoot = Split-Path -Parent (Split-Path -Parent $quartusSh)
$quartusMap = Join-Path $quartusRoot "bin64\quartus_map.exe"
$quartusFit = Join-Path $quartusRoot "bin64\quartus_fit.exe"
$quartusAsm = Join-Path $quartusRoot "bin64\quartus_asm.exe"

Push-Location $projectDir
try {
    & $qsysGenerate $qsys --synthesis=VERILOG
    if ($LASTEXITCODE -ne 0) {
        throw "qsys-generate failed with exit code $LASTEXITCODE"
    }

    & $quartusSh --flow compile $projectName
    if ($LASTEXITCODE -ne 0) {
        throw "quartus_sh --flow compile failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path $sof)) {
        throw "Expected SOF not found at $sof"
    }

    if ($quartusCpf) {
        & $quartusCpf -c $sof $rbf
        if ($LASTEXITCODE -ne 0) {
            throw "quartus_cpf failed with exit code $LASTEXITCODE"
        }
    }
} finally {
    Pop-Location
}

Write-Host "SOF: $sof"
if (Test-Path $rbf) {
    Write-Host "RBF: $rbf"
}
