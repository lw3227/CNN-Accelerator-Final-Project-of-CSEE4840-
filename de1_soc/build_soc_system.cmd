@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%"
set "PROJECT_NAME=soc_system"
set "QSYS_FILE=%PROJECT_DIR%%PROJECT_NAME%.qsys"
set "SOF_FILE=%PROJECT_DIR%output_files\%PROJECT_NAME%.sof"
set "RBF_FILE=%PROJECT_DIR%output_files\%PROJECT_NAME%.rbf"

call :find_tool quartus_sh.exe QUARTUS_SH
if not defined QUARTUS_SH goto :tool_error

call :find_tool qsys-generate.exe QSYS_GENERATE
if not defined QSYS_GENERATE goto :tool_error

call :find_tool quartus_cpf.exe QUARTUS_CPF

echo [1/3] Generating Qsys HDL...
pushd "%PROJECT_DIR%" >nul
"%QSYS_GENERATE%" "%QSYS_FILE%" --synthesis=VERILOG
if errorlevel 1 goto :build_error

echo [2/3] Compiling Quartus project...
"%QUARTUS_SH%" --flow compile "%PROJECT_NAME%"
if errorlevel 1 goto :build_error

if exist "%SOF_FILE%" (
    if defined QUARTUS_CPF (
        echo [3/3] Converting SOF to RBF...
        "%QUARTUS_CPF%" -c "%SOF_FILE%" "%RBF_FILE%"
        if errorlevel 1 goto :build_error
    ) else (
        echo [3/3] quartus_cpf.exe not found, skipping RBF conversion.
    )
) else (
    echo Expected SOF not found: "%SOF_FILE%"
    goto :build_error
)

popd >nul
echo.
echo Build complete.
echo SOF: "%SOF_FILE%"
if exist "%RBF_FILE%" echo RBF: "%RBF_FILE%"
exit /b 0

:tool_error
echo.
echo Required Quartus tools were not found.
echo Tried PATH, QUARTUS_ROOTDIR, and common install folders.
echo Install Quartus Prime 21.1 or add its bin64 folder to PATH.
exit /b 1

:build_error
set "ERR=%ERRORLEVEL%"
popd >nul
echo.
echo Build failed with exit code %ERR%.
exit /b %ERR%

:find_tool
set "TOOL_NAME=%~1"
set "%~2="

for %%P in ("%QUARTUS_ROOTDIR%\bin64\%TOOL_NAME%") do (
    if exist "%%~fP" (
        set "%~2=%%~fP"
        goto :eof
    )
)

for /f "delims=" %%P in ('where "%TOOL_NAME%" 2^>nul') do (
    set "%~2=%%~fP"
    goto :eof
)

for %%D in (
    "C:\intelFPGA_lite\*\quartus\bin64"
    "C:\intelFPGA\*\quartus\bin64"
    "C:\intelFPGA_lite\*\quartus\sopc_builder\bin"
    "C:\intelFPGA\*\quartus\sopc_builder\bin"
    "C:\Program Files\intelFPGA_lite\*\quartus\bin64"
    "C:\Program Files\intelFPGA\*\quartus\bin64"
    "C:\Program Files\intelFPGA_lite\*\quartus\sopc_builder\bin"
    "C:\Program Files\intelFPGA\*\quartus\sopc_builder\bin"
) do (
    for /d %%I in (%%~D) do (
        if exist "%%~fI\%TOOL_NAME%" (
            set "%~2=%%~fI\%TOOL_NAME%"
            goto :eof
        )
    )
)

goto :eof
