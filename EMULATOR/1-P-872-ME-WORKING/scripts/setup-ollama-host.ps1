<#
.SYNOPSIS
    PNETLab Host Machine Setup for Local Ollama Integration.
.DESCRIPTION
    Binds Ollama to 0.0.0.0, adds Windows Defender Firewall rule for port 11434,
    restarts Ollama, pulls the recommended qwen2.5:14b-instruct model, and outputs
    host IPv4 address.
#>

# Requires Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script in PowerShell as Administrator."
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PNETLab AI Lab Builder: Windows Host Setup for Ollama     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Configure OLLAMA_HOST environment variable
Write-Host "[1/4] Configuring OLLAMA_HOST environment variable..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', '0.0.0.0:11434', 'Machine')
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', '0.0.0.0:11434', 'User')
$env:OLLAMA_HOST = '0.0.0.0:11434'

# 2. Allow inbound traffic on TCP Port 11434 through Windows Defender Firewall
Write-Host "[2/4] Configuring Windows Defender Firewall rule for TCP 11434..." -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -DisplayName "Ollama Port 11434" -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -DisplayName "Ollama Port 11434" -Direction Inbound -LocalPort 11434 -Protocol TCP -Action Allow -Profile Any -Description "Allows PNETLab VM to access local Ollama LLM endpoint" | Out-Null
    Write-Host "  -> Firewall rule created successfully." -ForegroundColor Green
} else {
    Write-Host "  -> Firewall rule already exists." -ForegroundColor Green
}

# 3. Restart Ollama process
Write-Host "[3/4] Restarting Ollama background process..." -ForegroundColor Yellow
Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Search possible Ollama executable paths
$possiblePaths = @(
    "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe",
    "$env:ProgramFiles\Ollama\ollama app.exe",
    "${env:ProgramFiles(x86)}\Ollama\ollama app.exe"
)

$started = $false
foreach ($p in $possiblePaths) {
    if (Test-Path $p) {
        Start-Process -FilePath $p
        Write-Host "  -> Ollama app launched from: $p" -ForegroundColor Green
        $started = $true
        break
    }
}

if (-not $started) {
    $ollamaCmd = Get-Command "ollama.exe" -ErrorAction SilentlyContinue
    if ($ollamaCmd) {
        Start-Process -FilePath $ollamaCmd.Source -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Host "  -> Ollama server started via PATH ($($ollamaCmd.Source))." -ForegroundColor Green
    } else {
        Write-Warning "Ollama executable not found in standard paths. Please ensure Ollama is installed."
    }
}

Start-Sleep -Seconds 3

# 4. Pull recommended model
Write-Host "[4/4] Pulling recommended tool-calling model (qwen2.5:14b-instruct)..." -ForegroundColor Yellow
Write-Host "  Note: Requires internet connection and ~9GB disk space." -ForegroundColor DarkGray
try {
    ollama pull qwen2.5:14b-instruct
    Write-Host "  -> Model pull completed." -ForegroundColor Green
} catch {
    Write-Warning "Failed to pull model automatically. Run 'ollama pull qwen2.5:14b-instruct' manually if needed."
}

# Display IPv4 addresses
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Host Setup Complete! Detected IPv4 Address(es):" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254*" } | Select-Object IPAddress, InterfaceAlias | Format-Table -AutoSize

Write-Host "Run the following command inside your PNETLab VM:" -ForegroundColor Yellow
Write-Host "sudo bash setup-ollama.sh <YOUR_HOST_IP>" -ForegroundColor White
