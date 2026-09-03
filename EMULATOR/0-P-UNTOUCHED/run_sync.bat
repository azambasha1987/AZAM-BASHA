@echo off
cd /d "e:\Git\EMULATOR\0-P-UNTOUCHED"
echo ========================================================
echo Checking for PNetLab Updates (Differential Sync Engine)
echo ========================================================
python pnetlab_daily_change_sync.py
echo.
echo Process complete. Press any key to exit.
pause >nul
