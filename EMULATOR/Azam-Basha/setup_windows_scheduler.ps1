# PowerShell Script to register Windows Task Scheduler job for 24-Hour Azam Basha Differential Sync
$TaskName = "AzamBasha-24h-Sync"

# Check Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Registering a scheduled task requires Administrator privileges."
    Write-Host "Please run this script from an elevated PowerShell prompt (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$ScriptPath = Join-Path $ScriptDir "azambasha_daily_change_sync.py"
$PythonExe = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $PythonExe) { $PythonExe = "python.exe" }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Registering Windows Scheduled Task: $TaskName" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Working Directory: $ScriptDir"
Write-Host "Python Executable: $PythonExe"
Write-Host "Target Script:     $ScriptPath"

$Action = New-ScheduledTaskAction -Execute $PythonExe -Argument "`"$ScriptPath`"" -WorkingDirectory "$ScriptDir"
$Trigger = New-ScheduledTaskTrigger -Daily -At 03:00AM
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest

# Unregister existing task if present
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Register new task
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Automated 24-hour differential check and download for PNetLab Git source and Codeberg Package API releases." | Out-Null

Write-Host ""
Write-Host "SUCCESS: Task '$TaskName' is registered to run daily at 03:00 AM with Highest Privileges." -ForegroundColor Green
Write-Host "To test or trigger manually now, run:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
