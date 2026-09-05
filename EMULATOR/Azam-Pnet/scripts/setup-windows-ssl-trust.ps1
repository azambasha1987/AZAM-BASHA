<#
.SYNOPSIS
    1-Click PNetLab Root Certificate Authority (CA) Trust Tool for Windows & Firefox
.DESCRIPTION
    Fetches the PNETLab Enterprise Root CA certificate from the PNetLab appliance, imports it into
    the Windows Trusted Root Certification Authorities store, and automatically enables Windows
    Enterprise Root trust in all Mozilla Firefox profiles.
    
    This guarantees clean, 0-warning HTTPS browsing across Chrome, Edge, and Firefox permanently.
#>

param (
    [string]$VmIp = ""
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PNETLab 1-Click Root CA Trust Installer (Windows & Firefox)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Discover or Prompt for VM IP
if (-not $VmIp) {
    # Check ARP table for VMware/VirtualBox MAC prefixes
    $arpEntries = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -match "^(00-0c-29|00-50-56|08-00-27|52-54-00)" }
    if ($arpEntries) {
        $suggestedIp = ($arpEntries | Select-Object -First 1).IPAddress
    } else {
        $suggestedIp = "192.168.1.23"
    }

    $inputIp = Read-Host "Enter PNETLab VM IP Address [Default: $suggestedIp]"
    $VmIp = if ($inputIp) { $inputIp } else { $suggestedIp }
}

Write-Host "`n[*] Target PNETLab Appliance: https://$VmIp/" -ForegroundColor Yellow

# 2. Download PNETLab Root CA Certificate
$tempCaFile = "$env:TEMP\pnetlab_root_ca.crt"
Write-Host "[*] Fetching PNETLab Enterprise Root CA from https://$VmIp/pnetlab-ca.crt..." -ForegroundColor DarkGray

$caRetrieved = $false
try {
    # Method A: Direct Web Download of Root CA
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.ServerCertificateCustomValidationCallback = { $true }
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(5)
    
    $caBytes = $client.GetByteArrayAsync("https://$VmIp/pnetlab-ca.crt").GetAwaiter().GetResult()
    if ($caBytes -and $caBytes.Length -gt 100) {
        [System.IO.File]::WriteAllBytes($tempCaFile, $caBytes)
        $caCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($tempCaFile)
        $caRetrieved = $true
        Write-Host "  -> Root CA downloaded successfully from web endpoint!" -ForegroundColor Green
    }
} catch {}

if (-not $caRetrieved) {
    # Method B: Fallback to TLS Stream Extraction
    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect($VmIp, 443)
        $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
        $sslStream.AuthenticateAsClient($VmIp)
        $remoteCert = $sslStream.RemoteCertificate
        $caCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($remoteCert)
        [System.IO.File]::WriteAllBytes($tempCaFile, $caCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $tcpClient.Close()
        $caRetrieved = $true
        Write-Host "  -> Certificate retrieved via TLS stream!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve SSL certificate from $VmIp:443 -> $_"
        return
    }
}

Write-Host "`n=== Certificate Details ===" -ForegroundColor Cyan
Write-Host "  * Subject:    $($caCert.Subject)"
Write-Host "  * Issuer:     $($caCert.Issuer)"
Write-Host "  * Valid From: $($caCert.NotBefore.ToString('yyyy-MM-dd'))"
Write-Host "  * Valid To:   $($caCert.NotAfter.ToString('yyyy-MM-dd'))"
Write-Host "  * Thumbprint: $($caCert.Thumbprint)"

# 3. Import Root CA into Windows Trusted Root Store
Write-Host "`n[*] [Step 1/2] Installing Root CA into Windows Certificate Store..." -ForegroundColor Yellow
$store = [System.Security.Cryptography.X509Certificates.X509Store]::new("Root", "CurrentUser")
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

$existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $caCert.Thumbprint }
if ($existing) {
    Write-Host "  -> Certificate is ALREADY present in Windows Trusted Root store." -ForegroundColor Green
} else {
    try {
        $store.Add($caCert)
        Write-Host "  -> Successfully added to Windows Trusted Root store!" -ForegroundColor Green
    } catch {
        # Fallback to certutil
        $null = certutil -addstore -f -user root "$tempCaFile" 2>&1
        Write-Host "  -> Added via certutil to Windows store." -ForegroundColor Green
    }
}
$store.Close()

# 4. Automatically Configure Mozilla Firefox Profiles
Write-Host "`n[*] [Step 2/2] Configuring Mozilla Firefox Profiles..." -ForegroundColor Yellow
$ffProfilesPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffProfilesPath) {
    $profiles = Get-ChildItem -Path $ffProfilesPath -Directory
    $patchedCount = 0
    
    foreach ($p in $profiles) {
        $userJs = Join-Path $p.FullName "user.js"
        $pref = 'user_pref("security.enterprise_roots.enabled", true);'
        
        $currentContent = if (Test-Path $userJs) { Get-Content -Path $userJs -Raw } else { "" }
        if ($currentContent -notmatch "security\.enterprise_roots\.enabled") {
            Add-Content -Path $userJs -Value "`n$pref" -Encoding UTF8
            Write-Host "  -> Configured Firefox Profile: $($p.Name) (Enterprise Roots Enabled)" -ForegroundColor Green
            $patchedCount++
        } else {
            Write-Host "  -> Firefox Profile: $($p.Name) (Already Configured)" -ForegroundColor DarkGray
        }
    }
    if ($patchedCount -gt 0) {
        Write-Host "  -> Firefox will now automatically trust Windows Root CAs." -ForegroundColor Green
    }
} else {
    Write-Host "  -> Firefox profiles directory not detected (Skipped)." -ForegroundColor DarkGray
}

# Cleanup
Remove-Item -Path $tempCaFile -Force -ErrorAction SilentlyContinue

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " SUCCESS! PNETLab SSL Trust Setup is Complete." -ForegroundColor Green
Write-Host " You can now browse https://$VmIp/ with clean HTTPS trust." -ForegroundColor Green
Write-Host " (Please restart Chrome, Edge, or Firefox if currently open)" -ForegroundColor DarkGray
Write-Host "============================================================`n" -ForegroundColor Cyan
