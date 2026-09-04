@echo off
setlocal
cd /d "%~dp0"
echo ========================================================
echo Launching PNETLab OVA Appliance Exporter...
echo ========================================================
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0export-ova.ps1" %*
echo.
pause
endlocal
