@echo off
cd /d "e:\Git\EMULATOR\0-P-UNTOUCHED"
echo ========================================================
echo Running Automated Workflow Test...
echo ========================================================
python test_workflow.py
echo.
echo Press any key to exit.
pause >nul
