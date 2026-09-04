@echo off
setlocal
cd /d "%~dp0"
echo ========================================================
echo Launching Azam Basha Windows Host Connector...
echo ========================================================
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
    pwsh -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\pnetlab-connect.ps1" %*
) else (
    powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\pnetlab-connect.ps1" %*
)
echo.
pause
endlocal
