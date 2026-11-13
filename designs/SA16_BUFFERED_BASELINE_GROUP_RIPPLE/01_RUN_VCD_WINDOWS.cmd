@echo off
setlocal DisableDelayedExpansion
rem Run outside the Vivado GUI. Optional override: set PE_VIVADO_ROOT=C:\Xilinx\Vivado\2024.1
if defined PE_VIVADO_ROOT goto root_set
if defined XILINX_VIVADO set "PE_VIVADO_ROOT=%XILINX_VIVADO%"
if defined PE_VIVADO_ROOT goto root_set
if exist "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" set "PE_VIVADO_ROOT=C:\Xilinx\Vivado\2024.1"
if defined PE_VIVADO_ROOT goto root_set
if exist "C:\AMD\Vivado\2024.1\bin\vivado.bat" set "PE_VIVADO_ROOT=C:\AMD\Vivado\2024.1"
:root_set
if not exist "%PE_VIVADO_ROOT%\bin\vivado.bat" goto missing
if not exist "%PE_VIVADO_ROOT%\bin\xvlog.bat" goto missing
if not exist "%PE_VIVADO_ROOT%\bin\xelab.bat" goto missing
set "XILINX_VIVADO=%PE_VIVADO_ROOT%"
if exist "%PE_VIVADO_ROOT%\settings64.bat" call "%PE_VIVADO_ROOT%\settings64.bat"
if not exist "%~dp0logs" mkdir "%~dp0logs"
if exist "%~dp0logs\vivado_capture_completed.txt" del /q "%~dp0logs\vivado_capture_completed.txt"
echo Running the checked buffered array VCD comparison. Keep this window open.
call "%PE_VIVADO_ROOT%\bin\vivado.bat" -mode batch -nojournal -log "%~dp0logs\vivado_driver.log" -source "%~dp001_RUN_VIVADO.tcl"
set "PE_RUN_STATUS=%errorlevel%"
if not "%PE_RUN_STATUS%"=="0" goto failed
if not exist "%~dp0logs\vivado_capture_completed.txt" set "PE_RUN_STATUS=1"
if not "%PE_RUN_STATUS%"=="0" goto failed
echo.
echo SUCCESS: checked VCDs and PASS metadata are in each selected variants folder.
goto done
:failed
echo FAILED: inspect logs\vivado_driver.log and the selected variant's logs\vivado_vcd\LAST_RUN.txt.
echo If Windows still blocks compiler execution, this log now identifies the failing tool.
goto done
:missing
set "PE_RUN_STATUS=1"
echo Vivado compiler files were not found.
echo In Command Prompt set PE_VIVADO_ROOT to your installed Vivado directory, then run this file again.
echo Example: set "PE_VIVADO_ROOT=C:\Xilinx\Vivado\2024.1"
:done
if not defined PE_NO_PAUSE pause
exit /b %PE_RUN_STATUS%
