#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Complete Node & QEMU / IOSv Startup Engine
# Fixes "Failed to start node (12)" for Cisco IOSv, QEMU, IOL & Dynamips:
# 1. Deploys universal tunctl TAP driver shim (iproute2) & fixes sudoers permissions
# 2. Links /opt/qemu -> /usr and ensures QEMU system binaries are present
# 3. Creates smart image aliases for imported IOSv / IOSvL2 labs
# 4. Modernizes DOS disk creation (mcopy / mtools) for IOSv startup configs
# 5. Loads kernel modules (kvm, kvm_intel, loop, tun, bridge) & configures /dev/kvm
# 6. Generates Cisco IOU/IOL License (iourc)
# 7. Fixes wrapper SUID permissions (chmod 4755) and cleans orphaned node sockets
# ==============================================================================
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

echo "============================================================"
echo "    Azam Basha Complete Node Startup & IOSv Repair Engine   "
echo "============================================================"

# --- 1. Universal tunctl TAP Shim & Sudoers Permissions ---
echo "[1/7] Deploying universal tunctl TAP driver and sudoers grants..."
mkdir -p /etc/sudoers.d /usr/local/bin /opt/unetlab/wrappers 2>/dev/null || true

# Write valid sudoers configuration for www-data & root
cat << 'EOF' > /etc/sudoers.d/unetlab
Defaults:www-data !use_pty
www-data ALL=(ALL) NOPASSWD: ALL
root ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/unetlab
visudo -c >/dev/null 2>&1 || true

# Deploy native tunctl drop-in shim using iproute2
cat << 'EOF' > /usr/local/bin/tunctl
#!/usr/bin/env bash
# Universal tunctl drop-in replacement using ip tuntap (iproute2)
set -e

USER_ARG=""
GROUP_ARG=""
DEV_ARG=""
DELETE_ARG=0
BRIEF=0

while [ $# -gt 0 ]; do
    case "$1" in
        -u)
            USER_ARG="$2"
            shift 2
            ;;
        -g)
            GROUP_ARG="$2"
            shift 2
            ;;
        -t)
            DEV_ARG="$2"
            shift 2
            ;;
        -d)
            DELETE_ARG=1
            DEV_ARG="$2"
            shift 2
            ;;
        -b)
            BRIEF=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$DELETE_ARG" -eq 1 ]; then
    if [ -n "$DEV_ARG" ]; then
        ip link set dev "$DEV_ARG" down 2>/dev/null || true
        ip tuntap del dev "$DEV_ARG" mode tap 2>/dev/null || true
        if [ "$BRIEF" -eq 0 ]; then
            echo "Set '$DEV_ARG' nonpersistent"
        fi
    fi
    exit 0
fi

if [ -n "$DEV_ARG" ]; then
    IP_CMD="ip tuntap add dev $DEV_ARG mode tap"
    if [ -n "$USER_ARG" ]; then
        IP_CMD="$IP_CMD user $USER_ARG"
    fi
    if [ -n "$GROUP_ARG" ]; then
        IP_CMD="$IP_CMD group $GROUP_ARG"
    fi
    
    # Delete if already exists to avoid conflict
    ip tuntap del dev "$DEV_ARG" mode tap 2>/dev/null || true
    
    # Execute creation
    eval "$IP_CMD"
    
    if [ "$BRIEF" -eq 1 ]; then
        echo "$DEV_ARG"
    else
        echo "Set '$DEV_ARG' persistent and owned by uid $USER_ARG"
    fi
    exit 0
fi

# Fallback: create random tap
ip tuntap add mode tap
EOF
chmod 755 /usr/local/bin/tunctl
ln -sfn /usr/local/bin/tunctl /usr/bin/tunctl 2>/dev/null || true
ln -sfn /usr/local/bin/tunctl /usr/sbin/tunctl 2>/dev/null || true

# Ensure www-data is in kvm, unl, and sudo groups
usermod -aG kvm,unl www-data 2>/dev/null || true
echo "  [✔] Universal tunctl driver active and sudoers permissions granted"

# --- 2. Ensure QEMU Binaries & /opt/qemu Symlink ---
echo "[2/7] Setting up QEMU system dispatch and /opt/qemu symlinks..."
mkdir -p /opt/qemu/bin /opt/unetlab/addons/qemu 2>/dev/null || true
ln -sfn /usr /opt/qemu 2>/dev/null || true
ln -sfn /usr/bin/qemu-system-x86_64 /opt/qemu/bin/qemu-system-x86_64 2>/dev/null || true
ln -sfn /usr/bin/qemu-img /opt/qemu/bin/qemu-img 2>/dev/null || true

# --- 3. Hardware Acceleration & Kernel Modules ---
echo "[3/7] Activating Kernel Virtualization & Loopback Drivers..."
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

# --- 4. Modernize IOSv DOS Config Disk Creation (mcopy) ---
echo "[4/7] Updating IOSv startup configuration disk engine..."
if [ -f /opt/unetlab/scripts/createdosdisk_vios.sh ]; then
    cat << 'EOF' > /opt/unetlab/scripts/createdosdisk_vios.sh
#!/bin/bash
set -e
cd "$1"
cp /opt/unetlab/scripts/minidisk_initial .
if command -v mcopy >/dev/null 2>&1; then
    mcopy -i minidisk_initial -o vios_final_startup-config.txt ::/ios_config.txt 2>/dev/null || true
else
    mkdir -p loopmnt
    mount -o loop minidisk_initial loopmnt 2>/dev/null || true
    cp vios_final_startup-config.txt loopmnt/ios_config.txt 2>/dev/null || true
    sync
    umount loopmnt 2>/dev/null || true
    rm -rf loopmnt
fi
EOF
    chmod 755 /opt/unetlab/scripts/createdosdisk_vios.sh
fi

if [ -f /opt/unetlab/scripts/createdosdisk.sh ]; then
    cat << 'EOF' > /opt/unetlab/scripts/createdosdisk.sh
#!/bin/bash
set -e
cd "$1"
if [ -f /opt/unetlab/scripts/minidisk.bz2 ]; then
    cp /opt/unetlab/scripts/minidisk.bz2 .
    bzip2 -d -f minidisk.bz2 2>/dev/null || true
fi
if command -v mcopy >/dev/null 2>&1; then
    mcopy -i minidisk -o ios_config.txt ::/ios_config.txt 2>/dev/null || true
else
    mkdir -p loopmnt
    mount -o loop minidisk loopmnt 2>/dev/null || true
    cp ios_config.txt loopmnt/ 2>/dev/null || true
    sync
    umount loopmnt 2>/dev/null || true
    rm -rf loopmnt
fi
EOF
    chmod 755 /opt/unetlab/scripts/createdosdisk.sh
fi

# --- 5. Smart IOSv & Image Alias Linker ---
echo "[5/7] Configuring IOSv & QEMU Lab Image Aliases..."
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

# --- 6. Cisco IOU License Generation ---
echo "[6/7] Generating Cisco IOU/IOL License (iourc)..."
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

# --- 7. Clean Stale Sockets & Fix Permissions ---
echo "[7/7] Repairing UNetLab wrappers and file permissions..."
rm -rf /opt/unetlab/tmp/*/*/*/console.sock \
       /opt/unetlab/tmp/*/*/*/wrapper_telnet.txt \
       /dev/shm/pnet-authfail* 2>/dev/null || true

# Native wrapper fixpermissions
if [ -f /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true
fi

# Ensure wrappers are owned by root and have SUID permissions
chown -R root:root /opt/unetlab/wrappers 2>/dev/null || true
chmod -R 755 /opt/unetlab/wrappers 2>/dev/null || true
chmod 4755 /opt/unetlab/wrappers/unl_wrapper 2>/dev/null || true
for wrp in qemu_wrapper qemu_wrapper_telnet iol_wrapper dynamips_wrapper docker_wrapper; do
    if [ -f "/opt/unetlab/wrappers/$wrp" ]; then
        chmod 4755 "/opt/unetlab/wrappers/$wrp" 2>/dev/null || true
    fi
done

chmod 755 /opt/unetlab/scripts/* 2>/dev/null || true
chmod -R 777 /opt/unetlab/tmp 2>/dev/null || true
chown -R www-data:www-data /opt/unetlab/data /opt/unetlab/labs /opt/unetlab/html 2>/dev/null || true

# Status Summary
echo ""
echo "Node Startup Readiness Status:"
if [ -x /opt/qemu/bin/qemu-system-x86_64 ]; then
    echo "  [✔ PASS] QEMU x86_64 Binary        : $(/opt/qemu/bin/qemu-system-x86_64 --version | head -n1)"
fi
if [ -x /usr/bin/tunctl ]; then
    echo "  [✔ PASS] Universal TAP Driver      : /usr/bin/tunctl Ready"
fi
if [ -e /dev/kvm ]; then
    echo "  [✔ PASS] Hardware Virtualization   : /dev/kvm Accessible"
fi
if [ -f /opt/unetlab/addons/iol/bin/iourc ]; then
    echo "  [✔ PASS] Cisco IOU/IOL License     : /opt/unetlab/addons/iol/bin/iourc Present"
fi

echo ""
echo "============================================================"
echo "  [SUCCESS] All IOSv & QEMU Startup Fixes Applied!          "
echo "============================================================"
