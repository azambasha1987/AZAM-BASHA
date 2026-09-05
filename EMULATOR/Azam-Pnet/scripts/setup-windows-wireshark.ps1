<#
.SYNOPSIS
    PNETLab Windows 1-Click Wireshark & SecureCRT / PuTTY Protocol Integrator
.DESCRIPTION
    Registers the 'pnetlab://' and 'capture://' URL protocol handlers in the Windows Registry.
    Allows clicking 'Capture' on any link in the PNETLab Web UI to automatically launch local
    Wireshark.exe with a real-time live SSH packet stream from the PNETLab VM.
#>

param (
    [switch]$Uninstall
)

# Elevate to Admin if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsPrincipalScope]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Requesting Administrator privileges to register Windows URI Protocol Handler..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

$InstallDir = "$env:ProgramData\PNETLab"
$WiresharkWrapper = "$InstallDir\pnetlab-wireshark.bat"

if ($Uninstall) {
    Write-Host "Uninstalling PNETLab Windows Protocol Handler..." -ForegroundColor Yellow
    Remove-Item -Path "HKCR:\pnetlab" -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCR:\capture" -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "$InstallDir" -Recurse -ErrorAction SilentlyContinue
    Write-Host "[OK] PNETLab Wireshark handler removed." -ForegroundColor Green
    exit 0
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "    PNETLab 1-Click Live Wireshark Protocol Integrator      " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Locate Wireshark.exe
$WiresharkPaths = @(
    "C:\Program Files\Wireshark\Wireshark.exe",
    "C:\Program Files (x86)\Wireshark\Wireshark.exe",
    "$env:LOCALAPPDATA\Programs\Wireshark\Wireshark.exe"
)

$FoundWireshark = ""
foreach ($path in $WiresharkPaths) {
    if (Test-Path $path) {
        $FoundWireshark = $path
        break
    }
}

if (-not $FoundWireshark) {
    Write-Warning "Wireshark.exe was not found in default locations."
    $inputPath = Read-Host "Please enter full path to Wireshark.exe (or press Enter to skip)"
    if ($inputPath -and (Test-Path $inputPath)) {
        $FoundWireshark = $inputPath
    } else {
        $FoundWireshark = "C:\Program Files\Wireshark\Wireshark.exe"
    }
}

Write-Host "[1/3] Wireshark Path: $FoundWireshark" -ForegroundColor Green

# 2. Create Wrapper Batch Script
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$BatchContent = @"
@echo off
setlocal enabledelayedexpansion

:: PNETLab Wireshark Protocol Handler
:: Input format: pnetlab://<HOST>/<NODE_ID>/<IF_INDEX> or pnetlab://capture?host=<HOST>&net=<IF>
set "RAW_URL=%~1"
set "RAW_URL=!RAW_URL:pnetlab://=!"
set "RAW_URL=!RAW_URL:capture://=!"
set "RAW_URL=!RAW_URL:/= !"

for /f "tokens=1,2,3" %%A in ("!RAW_URL!") do (
    set "HOST=%%A"
    set "DEVICE=%%B"
    set "IFACE=%%C"
)

if "!IFACE!"=="" set "IFACE=vnet0"

echo Connecting to PNETLab Host !HOST! on interface !IFACE!...
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root !HOST! "tcpdump -U -n -i !IFACE! -w - 2>/dev/null" | "$FoundWireshark" -k -i -
"@

Set-Content -Path $WiresharkWrapper -Value $BatchContent -Encoding ASCII
Write-Host "[2/3] Wrapper Script Created: $WiresharkWrapper" -ForegroundColor Green

# 3. Register 'pnetlab://' and 'capture://' in Windows Registry
Write-Host "[3/3] Registering Windows URI Protocol Scheme (pnetlab:// & capture://)..." -ForegroundColor Yellow

foreach ($proto in @("pnetlab", "capture")) {
    $regPath = "Registry::HKEY_CLASSES_ROOT\$proto"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(default)" -Value "URL:PNETLab Live Packet Capture Protocol" | Out-Null
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value "" | Out-Null
    
    $cmdPath = "$regPath\shell\open\command"
    New-Item -Path $cmdPath -Force | Out-Null
    Set-ItemProperty -Path $cmdPath -Name "(default)" -Value "`"$WiresharkWrapper`" `"%1`"" | Out-Null
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  [SUCCESS] 1-Click Wireshark Protocol Registered on Windows! " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Clicking 'Capture' on any link in the PNETLab Web UI will  "
Write-Host " now automatically stream live packets directly into Wireshark."
Write-Host "============================================================" -ForegroundColor Cyan
