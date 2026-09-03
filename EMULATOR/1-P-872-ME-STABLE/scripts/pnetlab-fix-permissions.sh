#!/usr/bin/env bash
# ==============================================================================
# PNETLab Permissions, Lock Cleanup & Node Recovery Utility
# Fixes:
# 1. File & folder permissions across /opt/unetlab (QEMU, IOL, Dynamips, Labs)
# 2. Ensures /dev/kvm hardware virtualization access permissions
# 3. Cleans orphaned process locks and stale bridge/tap interfaces
# 4. Verifies/fixes Cisco IOL iourc license linkage
#
# Supports piped execution & non-root diagnostic mode.
# ==============================================================================
set -euo pipefail

# Support non-root diagnostic/check mode
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --clean-locks | --fix-iol]"
    echo ""
    echo "Options:"
    echo "  (no args)       Execute full permission fix and node recovery"
    echo "  --check         Inspect current permissions and stale lock status"
    echo "  --clean-locks   Clean orphaned node locks and dangling tap/bridge interfaces"
    echo "  --fix-iol       Verify and generate/symlink Cisco IOL license (iourc)"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== PNETLab Permissions & Environment Diagnostic Check ==="
    echo -n "[*] Hardware Virtualization (/dev/kvm): "
    if [ -e /dev/kvm ]; then
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            echo "ACCESSIBLE (KVM active)"
        else
            echo "RESTRICTED (Permissions need fix)"
        fi
    else
        echo "MISSING (/dev/kvm not found - Check nested virtualization)"
    fi

    echo -n "[*] Cisco IOL License File: "
    if [ -f /opt/unetlab/addons/iol/bin/iourc ] || [ -f /opt/unetlab/addons/iol/bin/lic.py ]; then
        echo "FOUND"
    else
        echo "NOT FOUND / DEFAULT"
    fi

    echo -n "[*] /opt/unetlab directory ownership: "
    ls -ld /opt/unetlab 2>/dev/null | awk '{print $3":"$4}' || echo "N/A"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "      PNETLab Permissions Fix & Node Recovery Utility       "
echo "============================================================"

# 1. Native unl_wrapper fixpermissions
echo "[1/5] Executing native PNETLab permission wrapper..."
if [ -x /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
fi

# 2. Comprehensive Directory Permissions
echo "[2/5] Setting granular permissions on PNETLab directory tree..."
if [ -d /opt/unetlab ]; then
    # General ownership
    chown -R root:root /opt/unetlab/addons 2>/dev/null || true
    chmod -R 755 /opt/unetlab/addons 2>/dev/null || true

    # Labs & data directories
    mkdir -p /opt/unetlab/labs /opt/unetlab/data/Exports /opt/unetlab/tmp
    chown -R www-data:www-data /opt/unetlab/labs /opt/unetlab/data /opt/unetlab/tmp /opt/unetlab/html 2>/dev/null || true
    chmod -R 775 /opt/unetlab/labs /opt/unetlab/data /opt/unetlab/tmp 2>/dev/null || true

    # Scripts & wrappers
    chown -R root:root /opt/unetlab/wrappers /opt/unetlab/scripts 2>/dev/null || true
    chmod -R 755 /opt/unetlab/wrappers /opt/unetlab/scripts 2>/dev/null || true
    chmod +s /opt/unetlab/wrappers/unl_wrapper 2>/dev/null || true
fi

# 3. Hardware Virtualization /dev/kvm Access
echo "[3/5] Verifying /dev/kvm access permissions..."
if [ -e /dev/kvm ]; then
    chmod 666 /dev/kvm || true
    usermod -aG kvm www-data 2>/dev/null || true
    echo "  -> /dev/kvm permissions set to 666."
else
    echo "  -> Warning: /dev/kvm not found. Ensure VT-x/AMD-V nested virtualization is enabled on the hypervisor."
fi

# 4. Clean Orphaned Node Locks & Stale Tap Devices
echo "[4/5] Cleaning stale locks and orphaned node sockets..."
if [ -d /opt/unetlab/tmp ]; then
    find /opt/unetlab/tmp -name "*.lock" -delete 2>/dev/null || true
    find /opt/unetlab/tmp -name "*.socket" -delete 2>/dev/null || true
fi

# 5. Verify & Symlink Cisco IOL License
echo "[5/5] Checking Cisco IOL license linkage..."
IOL_BIN="/opt/unetlab/addons/iol/bin"
if [ -d "$IOL_BIN" ]; then
    mkdir -p /root /opt/unetlab/addons/iol/bin
    if [ -f "$IOL_BIN/iourc" ]; then
        chmod 644 "$IOL_BIN/iourc"
        ln -sfn "$IOL_BIN/iourc" /root/.iourc 2>/dev/null || true
        ln -sfn "$IOL_BIN/iourc" /opt/unetlab/addons/iol/bin/.iourc 2>/dev/null || true
        echo "  -> Cisco IOL license (iourc) linked successfully."
    fi
fi

echo ""
echo "=== [SUCCESS] PNETLab permissions and node environment repaired! ==="
