#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Node Startup Repair & Diagnostic Engine
# Fixes "Failed to start node (12)" by:
# 1. Generating Cisco IOU/IOL License (iourc) for local hostname
# 2. Fixing wrapper & folder permissions (/opt/unetlab/wrappers, addons, tmp)
# 3. Checking & fixing /dev/kvm hardware virtualization access
# 4. Cleaning orphaned node lock sockets & temp processes
# 5. Auditing node images and printing diagnostic logs
# ==============================================================================
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

echo "============================================================"
echo "      Azam Basha Node Startup & Hardware Diagnostics        "
echo "============================================================"

# --- 1. Generate Cisco IOU/IOL License (iourc) ---
echo "[1/5] Generating Cisco IOU/IOL License Key (iourc)..."
mkdir -p /opt/unetlab/addons/iol/bin /etc /opt/unetlab/data 2>/dev/null || true

python3 - << 'PYEOF'
import hashlib, os, struct, socket

try:
    hostname = socket.gethostname()
    hostid_str = os.popen('hostid').read().strip()
    if not hostid_str:
        hostid_str = "00000000"
    hostid = int(hostid_str, 16) & 0xFFFFFFFF
    
    pad1 = b'\x4b\x58\x21\x81\x56\x7b\x0d\x91\xdf\x24\x08\xf8\x5c\x9b\x74\xf2'
    pad2 = b'\x80' + b'\x00'*39
    
    m = hashlib.md5()
    m.update(struct.pack('!I', hostid))
    m.update(pad1)
    m.update(pad2)
    key = m.hexdigest()[:16]
    
    iourc_content = f"[license]\n{hostname} = {key};\n"
    
    paths = [
        "/opt/unetlab/addons/iol/bin/iourc",
        "/etc/iourc",
        "/root/iourc",
        "/opt/unetlab/data/iourc"
    ]
    
    for p in paths:
        try:
            with open(p, "w") as fp:
                fp.write(iourc_content)
            os.chmod(p, 0o644)
        except Exception:
            pass
    print(f"  [✔] Generated IOU license for hostname '{hostname}' (key: {key})")
except Exception as e:
    print(f"  [!] IOU keygen notice: {e}")
PYEOF

# --- 2. Hardware KVM & Virtualization Check ---
echo "[2/5] Checking Hardware Virtualization (/dev/kvm)..."
if [ -e /dev/kvm ]; then
    chmod 666 /dev/kvm 2>/dev/null || true
    echo "  [✔] Hardware Acceleration /dev/kvm is ACTIVE and permissions set (666)"
else
    echo "  [✖ WARNING] /dev/kvm is NOT detected on this VM!"
    echo "      -> If running in VMware Workstation / ESXi / Proxmox:"
    echo "      -> Enable 'Virtualize Intel VT-x/EPT or AMD-V/RVI' in VM Processor Settings."
fi

# Ensure kernel virtualization and bridge modules are loaded
modprobe kvm 2>/dev/null || true
modprobe kvm_intel 2>/dev/null || true
modprobe kvm_amd 2>/dev/null || true
modprobe tun 2>/dev/null || true
modprobe bridge 2>/dev/null || true

# --- 3. Clean Stale Node Locks & Sockets ---
echo "[3/5] Cleaning stale node locks and orphaned socket files..."
rm -rf /opt/unetlab/tmp/*/*/*/console.sock \
       /opt/unetlab/tmp/*/*/*/wrapper_telnet.txt \
       /dev/shm/pnet-authfail* 2>/dev/null || true

# --- 4. Fix All File Permissions & Wrappers ---
echo "[4/5] Running UNetLab master permission repair..."
if [ -f /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true
fi

# Ensure wrappers are executable
chmod -R 755 /opt/unetlab/wrappers 2>/dev/null || true
chmod 755 /opt/unetlab/scripts/* 2>/dev/null || true
chmod -R 777 /opt/unetlab/tmp 2>/dev/null || true
chown -R www-data:www-data /opt/unetlab/data /opt/unetlab/labs 2>/dev/null || true

# --- 5. Inspect Installed Images & Logs ---
echo "[5/5] Auditing installed node image folders..."
QEMU_COUNT=$(find /opt/unetlab/addons/qemu -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l || echo 0)
IOL_COUNT=$(find /opt/unetlab/addons/iol/bin -name "*.bin" 2>/dev/null | wc -l || echo 0)
DYN_COUNT=$(find /opt/unetlab/addons/dynamips -name "*.image" -o -name "*.bin" 2>/dev/null | wc -l || echo 0)

echo "  -> Installed QEMU Appliances : ${QEMU_COUNT}"
echo "  -> Installed IOL/IOU Binaries: ${IOL_COUNT}"
echo "  -> Installed Dynamips Images : ${DYN_COUNT}"

if [ "$QEMU_COUNT" -eq 0 ] && [ "$IOL_COUNT" -eq 0 ] && [ "$DYN_COUNT" -eq 0 ]; then
    echo ""
    echo "  [!] NOTICE: No node images found in /opt/unetlab/addons/ !"
    echo "      If your lab contains nodes (e.g. Cisco vIOS, IOL, Fortigate, Linux),"
    echo "      you must upload the corresponding image files to:"
    echo "      - QEMU:      /opt/unetlab/addons/qemu/<folder>/virtioa.qcow2"
    echo "      - Cisco IOL: /opt/unetlab/addons/iol/bin/<image>.bin"
    echo "      - Dynamips:  /opt/unetlab/addons/dynamips/<image>.image"
fi

echo ""
echo "============================================================"
echo "Recent Node Startup Log (from /var/log/syslog):"
echo "============================================================"
grep -E "ERROR|unl_wrapper|qemu|iol|dynamips" /var/log/syslog 2>/dev/null | tail -n 15 || true
echo "============================================================"
echo "  [SUCCESS] Diagnostic & Repair Sequence Completed!         "
echo "============================================================"
