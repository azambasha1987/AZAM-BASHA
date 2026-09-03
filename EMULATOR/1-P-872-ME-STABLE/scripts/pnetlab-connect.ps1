<#
.SYNOPSIS
    PNETLab Windows Host Connector, Web UI Launcher & Node Port Scanner
.DESCRIPTION
    Auto-discovers PNETLab VM IP address, tests reachability, opens the Web UI in the default
    browser, scans active node telnet/SSH console ports (30001-30128), and launches SSH sessions.
#>

param (
    [string]$VmIp = "",
    [switch]$ScanNodes,
    [switch]$LaunchWeb,
    [switch]$Ssh
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "    PNETLab Windows Host Connector & Node Port Scanner      " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Discover or Prompt for VM IP
if (-not $VmIp) {
    # Check default gateway or common subnets
    $defaultGw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop | Select-Object -First 1)
    
    # Check ARP table for VMware/VirtualBox MAC prefixes
    $arpEntries = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -match "^(00-0c-29|00-50-56|08-00-27|52-54-00)" }
    if ($arpEntries) {
        $suggestedIp = ($arpEntries | Select-Object -First 1).IPAddress
    } else {
        $suggestedIp = "192.168.1.100"
    }

    $inputIp = Read-Host "Enter PNETLab VM IP Address [Default: $suggestedIp]"
    $VmIp = if ($inputIp) { $inputIp } else { $suggestedIp }
}

Write-Host "`n[*] Target PNETLab VM: $VmIp" -ForegroundColor Yellow

# 2. Test Reachability
Write-Host "[*] Testing network connectivity..." -ForegroundColor DarkGray
$ping = Test-Connection -ComputerName $VmIp -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($ping) {
    Write-Host "  -> VM is ONLINE and responding to ICMP ping." -ForegroundColor Green
} else {
    Write-Warning "  -> VM did not respond to ICMP ping. Checking Web/SSH ports directly..."
}

# 3. Test Web Port (443 / 80)
$webHttps = Test-NetConnection -ComputerName $VmIp -Port 443 -WarningAction SilentlyContinue
$webHttp = Test-NetConnection -ComputerName $VmIp -Port 80 -WarningAction SilentlyContinue
$sshPort = Test-NetConnection -ComputerName $VmIp -Port 22 -WarningAction SilentlyContinue

Write-Host "`n=== Service Status on $VmIp ===" -ForegroundColor Cyan
if ($webHttps.TcpTestSucceeded) {
    Write-Host "  * HTTPS Web UI (Port 443):  OPEN -> https://$VmIp/" -ForegroundColor Green
} elseif ($webHttp.TcpTestSucceeded) {
    Write-Host "  * HTTP Web UI (Port 80):    OPEN -> http://$VmIp/" -ForegroundColor Green
} else {
    Write-Host "  * Web UI (Port 80/443):     CLOSED / UNREACHABLE" -ForegroundColor Red
}

if ($sshPort.TcpTestSucceeded) {
    Write-Host "  * SSH Management (Port 22): OPEN (ssh root@$VmIp)" -ForegroundColor Green
} else {
    Write-Host "  * SSH Management (Port 22): CLOSED" -ForegroundColor Red
}

# 4. Interactive Action Menu
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Select an Action:" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " 1) Open PNETLab Web UI in Default Browser"
Write-Host " 2) Scan Active Lab Node Console Ports (Ports 30001-30050)"
Write-Host " 3) Launch SSH Session (ssh root@$VmIp)"
Write-Host " 4) Exit"
Write-Host "============================================================" -ForegroundColor Cyan

$action = Read-Host "Select option [1-4, Default: 1]"
if (-not $action) { $action = "1" }

switch ($action) {
    "1" {
        $url = if ($webHttps.TcpTestSucceeded) { "https://$VmIp/" } else { "http://$VmIp/" }
        Write-Host "Opening $url in browser..." -ForegroundColor Green
        Start-Process $url
    }
    "2" {
        Write-Host "`nScanning active node console ports on $VmIp (30001-30050)..." -ForegroundColor Yellow
        $activeNodes = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($p in 30001..30050) {
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $async = $client.BeginConnect($VmIp, $p, $null, $null)
                if ($async.AsyncWaitHandle.WaitOne(60, $false) -and $client.Connected) {
                    $nodeId = $p - 30000
                    $activeNodes.Add([PSCustomObject]@{
                        NodeID  = $nodeId
                        Port    = $p
                        Status  = "ACTIVE"
                        Connect = "telnet $VmIp $p"
                    })
                }
            } catch {} finally {
                $client.Close()
            }
        }
        if ($activeNodes.Count -gt 0) {
            $activeNodes | Format-Table -AutoSize
        } else {
            Write-Host "  -> No active node console ports found in range 30001-30050." -ForegroundColor DarkGray
        }
    }
    "3" {
        Write-Host "Launching SSH to root@$VmIp..." -ForegroundColor Green
        Start-Process "ssh" -ArgumentList "root@$VmIp"
    }
    "4" {
        Write-Host "Exiting."
    }
}
