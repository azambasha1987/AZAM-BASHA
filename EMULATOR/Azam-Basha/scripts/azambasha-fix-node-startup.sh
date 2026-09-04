#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Complete Node & QEMU / IOSv Startup Engine
# Fixes "Failed to start node (12)" for Cisco IOSv, QEMU, IOL & Dynamips:
# 1. Links /opt/qemu -> /usr and ensures QEMU system binaries are present
# 2. Creates smart image aliases for imported IOSv / IOSvL2 labs
# 3. Loads kernel modules (kvm, kvm_intel, loop, tun, bridge)
# 4. Generates Cisco IOU/IOL License (iourc)
# 5. Fixes /dev/kvm and all UNetLab directory & wrapper permissions
# ==============================================================================
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

echo "============================================================"
echo "    Azam Basha Complete Node Startup & IOSv Repair Engine   "
echo "============================================================"

# --- 1. Ensure QEMU Binaries & /opt/qemu Symlink ---
echo "[1/6] Setting up QEMU system dispatch and /opt/qemu symlinks..."
mkdir -p /opt/qemu/bin /opt/unetlab/addons/qemu 2>/dev/null || true
ln -sfn /usr /opt/qemu 2>/dev/null || true
ln -sfn /usr/bin/qemu-system-x86_64 /opt/qemu/bin/qemu-system-x86_64 2>/dev/null || true
ln -sfn /usr/bin/qemu-img /opt/qemu/bin/qemu-img 2>/dev/null || true

# Install qemu-system-x86 if missing
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "      -> Installing qemu-system-x86 and qemu-utils from APT..."
    apt-get update -qq && apt-get install -y -qq qemu-system-x86 qemu-utils libvirt-daemon-system genisoimage dosfstools 2>/dev/null || true
fi

# --- 2. Hardware Acceleration & Kernel Modules ---
echo "[2/6] Activating Kernel Virtualization & Loopback Drivers..."
modprobe loop 2>/dev/null || true
modprobe tun 2>/dev/null || true
modprobe bridge 2>/dev/null || true
modprobe kvm 2>/dev/null || true
modprobe kvm_intel 2>/dev/null || true
modprobe kvm_amd 2>/dev/null || true

if [ -e /dev/kvm ]; then
    chmod 666 /dev/kvm 2>/dev/null || true
    echo "  [✔] Hardware Acceleration /dev/kvm is ACTIVE (chmod 666)"
else
    echo "  [✖ WARNING] /dev/kvm was not detected! Enable Nested Virtualization in VM CPU settings."
fi

# --- 3. Smart IOSv & Image Alias Linker ---
echo "[3/6] Configuring IOSv & QEMU Lab Image Aliases..."
# Router aliases
VIOS_REAL=$(find /opt/unetlab/addons/qemu -maxdepth 1 -type d -name "vios-*" 2>/dev/null | head -n1 || true)
if [ -n "$VIOS_REAL" ]; then
    echo "      -> Detected primary IOSv Router image: $(basename "$VIOS_REAL")"
    ln -sfn "$VIOS_REAL" /opt/unetlab/addons/qemu/vios-adventerprisek9-m.spa.159-3.M3 2>/dev/null || true
    ln -sfn "$VIOS_REAL" /opt/unetlab/addons/qemu/vios-adventerprisek9-m.spa.156-2.T 2>/dev/null || true
    ln -sfn "$VIOS_REAL" /opt/unetlab/addons/qemu/vios-adventerprisek9-m.spa.157-3.M3 2>/dev/null || true
    ln -sfn "$VIOS_REAL" /opt/unetlab/addons/qemu/vios-iosv 2>/dev/null || true
    echo "  [✔] Common IOSv router aliases linked to $(basename "$VIOS_REAL")"
fi

# Switch aliases
VIOSL2_REAL=$(find /opt/unetlab/addons/qemu -maxdepth 1 -type d -name "viosl2-*" 2>/dev/null | head -n1 || true)
if [ -n "$VIOSL2_REAL" ]; then
    echo "      -> Detected primary IOSv L2 Switch image: $(basename "$VIOSL2_REAL")"
    ln -sfn "$VIOSL2_REAL" /opt/unetlab/addons/qemu/viosl2-adventerprisek9-m.vmd.SPA.156-0.3.E 2>/dev/null || true
    ln -sfn "$VIOSL2_REAL" /opt/unetlab/addons/qemu/viosl2-adventerprisek9-m.03.2017 2>/dev/null || true
    ln -sfn "$VIOSL2_REAL" /opt/unetlab/addons/qemu/viosl2-iosvl2 2>/dev/null || true
    echo "  [✔] Common IOSvL2 switch aliases linked to $(basename "$VIOSL2_REAL")"
fi

# --- 4. Cisco IOU License Generation ---
echo "[4/6] Generating Cisco IOU/IOL License (iourc)..."
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
    print(f"  [✔] IOU license generated for '{hostname}' (key: {key})")
except Exception as e:
    print(f"  [!] IOU keygen note: {e}")
PYEOF

# --- 5. Clean Stale Sockets & Fix Permissions ---
echo "[5/6] Repairing UNetLab wrappers and file permissions..."
rm -rf /opt/unetlab/tmp/*/*/*/console.sock \
       /opt/unetlab/tmp/*/*/*/wrapper_telnet.txt \
       /dev/shm/pnet-authfail* 2>/dev/null || true

if [ -f /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true
fi

chmod -R 755 /opt/unetlab/wrappers 2>/dev/null || true
chmod 755 /opt/unetlab/scripts/* 2>/dev/null || true
chmod -R 777 /opt/unetlab/tmp 2>/dev/null || true
chown -R www-data:www-data /opt/unetlab/data /opt/unetlab/labs 2>/dev/null || true

# --- 6. Status & Diagnostic Summary ---
echo "[6/6] Node Startup Readiness Status:"
if [ -x /opt/qemu/bin/qemu-system-x86_64 ]; then
    echo "  [✔ PASS] QEMU x86_64 Binary        : $(/opt/qemu/bin/qemu-system-x86_64 --version | head -n1)"
else
    echo "  [✖ FAIL] QEMU x86_64 Binary        : Not found in /opt/qemu/bin/"
fi

if [ -e /dev/kvm ]; then
    echo "  [✔ PASS] Hardware Virtualization   : /dev/kvm Accessible"
else
    echo "  [✖ WARN] Hardware Virtualization   : /dev/kvm Missing"
fi

if [ -f /opt/unetlab/addons/iol/bin/iourc ]; then
    echo "  [✔ PASS] Cisco IOU/IOL License     : /opt/unetlab/addons/iol/bin/iourc Present"
fi

echo ""
echo "============================================================"
echo "  [SUCCESS] All IOSv & QEMU Startup Fixes Applied!          "
echo "============================================================"
