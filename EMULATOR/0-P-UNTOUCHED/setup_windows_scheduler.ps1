# PowerShell Script to register Windows Task Scheduler job for 24-Hour PNetLab Differential Sync
$TaskName = "PNetLab-24h-Sync"
$ScriptPath = "e:\Git\EMULATOR\0-P-UNTOUCHED\pnetlab_daily_change_sync.py"
$PythonExe = (Get-Command python.exe).Source

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Registering Windows Scheduled Task: $TaskName" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Python Executable: $PythonExe"
Write-Host "Target Script:     $ScriptPath"

$Action = New-ScheduledTaskAction -Execute $PythonExe -Argument "`"$ScriptPath`"" -WorkingDirectory "e:\Git\EMULATOR\0-P-UNTOUCHED"
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
