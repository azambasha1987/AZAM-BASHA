#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Master Administration, Fix & Performance Toolkit
# Unified launcher for all Azam Basha maintenance, optimization, and AI tools.
#
# Supports piped execution: curl -fsSL https://.../pnetlab-apply-all-fixes.sh | sudo bash
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Support non-root check/help modes
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [OPTION_NUMBER | --check]"
    echo ""
    echo "Options:"
    echo "  1    Permanent Session Fix (Never-Logout, 10-Year Session)"
    echo "  2    Lab Export & APT Sources Fix (zip/unzip, nested labs)"
    echo "  3    512MB Upload Limits & Docker Routing Fix"
    echo "  4    SSL IP-SAN Certificate, HTML5 Console & Cloud Bridge Fix"
    echo "  5    Database SQL Mode, 1M Limits, Logrotate & THP Deep-Fix"
    echo "  6    High-Performance Speed Optimizer Suite (KSM, OPcache, Gzip, Sysctl)"
    echo "  7    Silicon Dataplane Fast-Path Accelerator (2× Throughput, 1/3 CPU, MTU 9000)"
    echo "  8    Image Doctor & Virtual Disk Integrity Audit"
    echo "  9    Link Quality & Impairment Controller (latency, jitter, loss)"
    echo "  10   Packet Capture & Live Wireshark Streamer (TAP/Hub/Cloud)"
    echo "  11   Real-Time Per-Link Telemetry Monitor"
    echo "  12   Fix File Permissions, /dev/kvm & Clean Node Locks"
    echo "  13   System Health & Diagnostic Dashboard"
    echo "  14   Create Full Lab & Database Backup"
    echo "  15   Configure AI Lab Builder & Ollama Integration"
    echo "  16   Freeze Version & Block Future Updates (Anti-Conflict Lock)"
    echo "  17   Azam Basha Pure Black Dark Mode Theme Engine"
    echo "  18   Apply ALL Essential Fixes & Dark Mode Suite"
    echo "  19   Exit"
    echo "  --check  Run non-destructive diagnostic health check"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    if [ -f "${SCRIPT_DIR}/azambasha-health-check.sh" ]; then
        bash "${SCRIPT_DIR}/azambasha-health-check.sh"
    elif [ -f "${SCRIPT_DIR}/azambasha-speed-optimizer.sh" ]; then
        bash "${SCRIPT_DIR}/azambasha-speed-optimizer.sh" --check || true
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "    Azam Basha Master Administration & Deployment Tool      "
echo "============================================================"
echo "1) Permanent Session Fix (Never-Logout, 10-Year Session)"
echo "2) Lab Export & APT Sources Fix (zip/unzip, nested labs)"
echo "3) 512MB Upload Limits & Docker IP Routing Fix"
echo "4) SSL IP-SAN Certificate, HTML5 Console & Cloud Bridge Fix"
echo "5) Database SQL Mode, 1M Limits, Logrotate & THP Deep-Fix"
echo "6) High-Performance Speed Optimizer (KSM, OPcache, Gzip, Sysctl)"
echo "7) Silicon Dataplane Fast-Path Accelerator (~2× Throughput, MTU 9000)"
echo "8) Image Doctor & QCOW2 Disk Integrity Audit"
echo "9) Link Impairment Controller (Latency, Jitter, Packet Loss)"
echo "10) Packet Capture & Live Wireshark Streamer (TAP/Hub/Cloud)"
echo "11) Real-Time Per-Link Telemetry Monitor"
echo "12) Fix File Permissions, /dev/kvm & Node Recovery"
echo "13) System Health & Diagnostic Dashboard"
echo "14) Create Full Lab & Database Backup Archive"
echo "15) AI Lab Builder & Ollama MCP Integration"
echo "16) Freeze Version & Block Future Updates (Anti-Conflict Lock)"
echo "17) Azam Basha Pure Black Dark Mode Theme Engine"
echo "18) Apply ALL Essential Fixes & Dark Mode Suite"
echo "19) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^([1-9]|1[0-9])$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-19, default: 18]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-18}"
else
    CHOICE="18"
fi

case "$CHOICE" in
    1)
        bash "${SCRIPT_DIR}/azambasha-disable-logout.sh"
        ;;
    2)
        bash "${SCRIPT_DIR}/azambasha-fix-export-and-apt.sh"
        ;;
    3)
        bash "${SCRIPT_DIR}/azambasha-upload-and-docker-fix.sh"
        ;;
    4)
        bash "${SCRIPT_DIR}/azambasha-system-and-console-fix.sh"
        ;;
    5)
        bash "${SCRIPT_DIR}/azambasha-database-and-system-deep-fix.sh"
        ;;
    6)
        bash "${SCRIPT_DIR}/azambasha-speed-optimizer.sh"
        ;;
    7)
        bash "${SCRIPT_DIR}/azambasha-dataplane-engine.sh"
        ;;
    8)
        bash "${SCRIPT_DIR}/azambasha-image-doctor.sh" --fix
        ;;
    9)
        bash "${SCRIPT_DIR}/azambasha-link-impairment.sh" --help
        ;;
    10)
        bash "${SCRIPT_DIR}/azambasha-capture-stream.sh" --help
        ;;
    11)
        python3 "${SCRIPT_DIR}/azambasha-dataplane-stats.py"
        ;;
    12)
        bash "${SCRIPT_DIR}/azambasha-fix-permissions.sh"
        ;;
    13)
        bash "${SCRIPT_DIR}/azambasha-health-check.sh"
        ;;
    14)
        bash "${SCRIPT_DIR}/azambasha-backup-restore.sh" backup
        ;;
    15)
        HOST_IP=""
        MODEL="qwen2.5:14b-instruct"
        if [ -e /dev/tty ]; then
            read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP < /dev/tty || true
            read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " USER_MODEL < /dev/tty || true
            MODEL="${USER_MODEL:-$MODEL}"
        fi
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "$MODEL"
        ;;
    16)
        bash "${SCRIPT_DIR}/azambasha-block-updates.sh"
        ;;
    17)
        if [ -f "${SCRIPT_DIR}/azambasha-dark-theme.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-dark-theme.sh"
        fi
        ;;
    18)
        echo "--> [1/14] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/azambasha-disable-logout.sh"
        echo ""
        echo "--> [2/14] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/azambasha-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/14] Applying 512MB Upload Limits & Docker Routing..."
        bash "${SCRIPT_DIR}/azambasha-upload-and-docker-fix.sh"
        echo ""
        echo "--> [4/14] Applying SSL IP-SAN, Console & Cloud Bridge Fix..."
        bash "${SCRIPT_DIR}/azambasha-system-and-console-fix.sh"
        echo ""
        echo "--> [5/14] Applying Database SQL Mode, 1M Limits & Logrotate..."
        bash "${SCRIPT_DIR}/azambasha-database-and-system-deep-fix.sh"
        echo ""
        echo "--> [6/14] Fixing File Permissions & Sockets..."
        bash "${SCRIPT_DIR}/azambasha-fix-permissions.sh"
        echo ""
        echo "--> [7/14] Applying High-Performance Speed Optimizer (1024-Node Scaling)..."
        bash "${SCRIPT_DIR}/azambasha-speed-optimizer.sh"
        echo ""
        echo "--> [8/14] Activating Silicon Dataplane Fast-Path Accelerator (MTU 9000)..."
        bash "${SCRIPT_DIR}/azambasha-dataplane-engine.sh"
        echo ""
        echo "--> [9/14] Applying Cgroups v2 & System Limits..."
        if [ -f "${SCRIPT_DIR}/azambasha-cgroups-v2-engine.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-cgroups-v2-engine.sh" || true
        fi
        echo ""
        echo "--> [10/14] Freezing Version & Blocking Future Updates..."
        bash "${SCRIPT_DIR}/azambasha-block-updates.sh"
        echo ""
        echo "--> [11/14] Applying Azam Basha Enterprise Branding & Logo Assets..."
        if [ -f "${SCRIPT_DIR}/azambasha-apply-branding.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-apply-branding.sh" || true
        fi
        echo ""
        echo "--> [12/14] Applying Node Startup & Cisco IOSv Repair Engine..."
        if [ -f "${SCRIPT_DIR}/azambasha-fix-node-startup.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-fix-node-startup.sh" || true
        fi
        echo ""
        echo "--> [13/14] Auditing Virtual Disks with Image Doctor..."
        if [ -f "${SCRIPT_DIR}/azambasha-image-doctor.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-image-doctor.sh" --fix || true
        fi
        echo ""
        echo "--> [14/15] Applying Azam Basha Pure Black Dark Mode Theme..."
        if [ -f "${SCRIPT_DIR}/azambasha-dark-theme.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-dark-theme.sh" || true
        fi
        echo ""
        echo "--> [15/16] Applying Advanced UI, Telemetry Heatmap & Quad-Tree Suite..."
        if [ -f "${SCRIPT_DIR}/azambasha-ui-enhancements.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-ui-enhancements.sh" || true
        fi
        echo ""
        echo "--> [16/16] Applying Smart Alignment, Spotlight & Mini-Map GUI Suite..."
        if [ -f "${SCRIPT_DIR}/azambasha-gui-enhancements.sh" ]; then
            bash "${SCRIPT_DIR}/azambasha-gui-enhancements.sh" || true
        fi
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL ESSENTIAL ENHANCEMENTS APPLIED SUCCESSFULLY! "
        echo "============================================================"
        ;;
    19)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
