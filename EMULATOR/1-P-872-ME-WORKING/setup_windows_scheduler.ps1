# PowerShell Script to register Windows Task Scheduler job for 24-Hour PNetLab Differential Sync
$TaskName = "PNetLab-24h-Sync"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$ScriptPath = Join-Path $ScriptDir "pnetlab_daily_change_sync.py"
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

# Unregister existing task if present
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Register new task
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Automated 24-hour differential check and download for PNetLab Git source and Codeberg Package API releases."

Write-Host ""
Write-Host "SUCCESS: Task '$TaskName' is registered to run daily at 03:00 AM." -ForegroundColor Green
Write-Host "To test or trigger manually now, run:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
