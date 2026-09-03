@echo off
cd /d "%~dp0"
echo ========================================================
echo Launching PNETLab Windows Host Connector...
echo ========================================================
powershell -ExecutionPolicy Bypass -NoProfile -File "scripts\pnetlab-connect.ps1"
echo.
pause
