@echo off
setlocal enabledelayedexpansion
title Azam Basha - Deploy Local Folder to VM

echo ================================================================
echo           AZAM BASHA - DEPLOY CURRENT FOLDER TO VM
echo ================================================================
echo.
echo This tool will copy the entire contents of this local directory:
echo   "%~dp0"
echo to your remote VM (/opt/azambasha) and launch the installer live.
echo.

set /p VM_IP="Enter VM IP Address [Default: 192.168.1.29]: "
if "%VM_IP%"=="" set VM_IP=192.168.1.29

set /p SSH_USER="Enter SSH Username [Default: root]: "
if "%SSH_USER%"=="" set SSH_USER=root

echo.
echo [*] Target VM: %SSH_USER%@%VM_IP%
echo [*] Preparing remote destination /opt/azambasha...
ssh -o StrictHostKeyChecking=accept-new %SSH_USER%@%VM_IP% "mkdir -p /opt/azambasha"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [-] Failed to connect to %SSH_USER%@%VM_IP% via SSH.
    echo     Please ensure the VM is powered on and SSH is accessible.
    pause
    exit /b 1
)

echo.
echo [*] Copying all local files to %SSH_USER%@%VM_IP%:/opt/azambasha...
scp -o StrictHostKeyChecking=accept-new -r "%~dp0*" %SSH_USER%@%VM_IP%:/opt/azambasha/
if %ERRORLEVEL% neq 0 (
    echo.
    echo [-] Error transferring files.
    pause
    exit /b 1
)

echo.
echo [+] Files transferred successfully!
echo [*] Executing Azam Basha Installer on VM...
echo ================================================================
ssh -t -o StrictHostKeyChecking=accept-new %SSH_USER%@%VM_IP% "sed -i 's/\r$//' /opt/azambasha/*.sh /opt/azambasha/scripts/*.sh 2>/dev/null || true; cd /opt/azambasha && sudo bash install.sh"

echo.
echo ================================================================
echo Deployment session finished.
echo Web Dashboard URL: https://%VM_IP%/
echo ================================================================
pause
endlocal
