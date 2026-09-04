@echo off
setlocal
cd /d "%~dp0"
echo ========================================================
echo Checking for Azam Basha Updates (Differential Sync Engine)
echo ========================================================
where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python azambasha_daily_change_sync.py %*
) else (
    where py >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        py -3 azambasha_daily_change_sync.py %*
    ) else (
        echo [ERROR] Python 3 executable not found in system PATH.
        echo Please ensure Python is installed and added to PATH.
    )
)
echo.
echo Process complete. Press any key to exit.
pause >nul
endlocal
