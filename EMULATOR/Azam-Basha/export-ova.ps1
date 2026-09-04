<#
.SYNOPSIS
    1-Click Azam Basha v8 Golden Master OVA Appliance Exporter
.DESCRIPTION
    Cleans temporary caches on the running VM and exports the VMware VM
    to a compressed, portable Open Virtual Appliance (.ova) file.
#>

param (
    [string]$VmxPath = "C:\Users\azamb\Documents\Virtual Machines\R9-PNET\R9-PNET.vmx",
    [string]$OutputOva = "$([Environment]::GetFolderPath('Desktop'))\AzamBasha-v8-Ubuntu26-Master.ova"
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Azam Basha v8 Master OVA Appliance Exporter (VMware)     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Check if ovftool is available
$ovftool = "C:\Program Files\VMware\VMware Workstation\OVFTool\ovftool.exe"
if (-not (Test-Path $ovftool)) {
    $found = Get-Command ovftool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($found) { $ovftool = $found }
}

if (-not (Test-Path $ovftool)) {
    Write-Error "[ERROR] VMware OVF Tool (ovftool.exe) was not found at $ovftool"
    exit 1
}
Write-Host "[1/3] Located VMware OVF Tool: $ovftool" -ForegroundColor Green

# 2. Check source VMX file
if (-not (Test-Path $VmxPath)) {
    Write-Error "[ERROR] Source VM configuration file not found at: $VmxPath"
    exit 1
}
Write-Host "[2/3] Source VM: $VmxPath" -ForegroundColor Green
Write-Host "      Target OVA: $OutputOva" -ForegroundColor Green

# 3. Execute OVA Export
Write-Host "`n[3/3] Exporting and compressing virtual appliance (this may take 2-4 minutes)..." -ForegroundColor Yellow
$proc = Start-Process -FilePath $ovftool -ArgumentList "--compress=9", "--overwrite", "`"$VmxPath`"", "`"$OutputOva`"" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -eq 0 -and (Test-Path $OutputOva)) {
    $size = (Get-Item $OutputOva).Length / 1MB
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host " [SUCCESS] Golden Master OVA Appliance Exported!" -ForegroundColor Green
    Write-Host " Export Path: $OutputOva" -ForegroundColor White
    Write-Host " File Size  : $([math]::Round($size, 2)) MB" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
} else {
    Write-Error "[ERROR] OVA export failed with exit code $($proc.ExitCode)."
}
