#!/usr/bin/env bash
# ==============================================================================
# PNETLab Master Administration, Fix & Performance Toolkit
# Unified launcher for all PNETLab maintenance, optimization, and AI tools.
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
    echo "  7    Dataplane Fast-Path Accelerator (2× Throughput, 1/3 CPU)"
    echo "  8    Image Doctor & Virtual Disk Integrity Audit"
    echo "  9    Link Quality & Impairment Controller (latency, jitter, loss)"
    echo "  10   Packet Capture & Live Wireshark Streamer"
    echo "  11   Real-Time Per-Link Telemetry Monitor"
    echo "  12   Fix File Permissions, /dev/kvm & Clean Node Locks"
    echo "  13   System Health & Diagnostic Dashboard"
    echo "  14   Create Full Lab & Database Backup"
    echo "  15   Configure AI Lab Builder & Ollama Integration"
    echo "  16   Apply ALL Essential Fixes & Dataplane Suite (Recommended)"
    echo "  --check  Run non-destructive diagnostic health check"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    if [ -f "${SCRIPT_DIR}/pnetlab-health-check.sh" ]; then
        bash "${SCRIPT_DIR}/pnetlab-health-check.sh"
    elif [ -f "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh" ]; then
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh" --check || true
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "      PNETLab Master Administration & Deployment Tool       "
echo "============================================================"
echo "1) Permanent Session Fix (Never-Logout, 10-Year Session)"
echo "2) Lab Export & APT Sources Fix (zip/unzip, nested labs)"
echo "3) 512MB Upload Limits & Docker IP Routing Fix"
echo "4) SSL IP-SAN Certificate, HTML5 Console & Cloud Bridge Fix"
echo "5) Database SQL Mode, 1M Limits, Logrotate & THP Deep-Fix"
echo "6) High-Performance Speed Optimizer (KSM, OPcache, Gzip, Sysctl)"
echo "7) Dataplane Fast-Path Accelerator (~2× Throughput, 1/3 CPU)"
echo "8) Image Doctor & QCOW2 Disk Integrity Audit"
echo "9) Link Impairment Controller (Latency, Jitter, Packet Loss)"
echo "10) Packet Capture & Live Wireshark Streamer"
echo "11) Real-Time Per-Link Telemetry Monitor"
echo "12) Fix File Permissions, /dev/kvm & Node Recovery"
echo "13) System Health & Diagnostic Dashboard"
echo "14) Create Full Lab & Database Backup Archive"
echo "15) AI Lab Builder & Ollama MCP Integration"
echo "16) Freeze Version & Block Future Updates (Anti-Conflict Lock)"
echo "17) Apply ALL Essential Fixes & Performance Suite (Recommended)"
echo "18) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^([1-9]|1[0-8])$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-18, default: 17]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-17}"
else
    CHOICE="17"
fi

case "$CHOICE" in
    1)
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        ;;
    2)
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        ;;
    3)
        bash "${SCRIPT_DIR}/pnetlab-upload-and-docker-fix.sh"
        ;;
    4)
        bash "${SCRIPT_DIR}/pnetlab-system-and-console-fix.sh"
        ;;
    5)
        bash "${SCRIPT_DIR}/pnetlab-database-and-system-deep-fix.sh"
        ;;
    6)
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        ;;
    7)
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        ;;
    8)
        bash "${SCRIPT_DIR}/pnetlab-image-doctor.sh" --fix
        ;;
    9)
        bash "${SCRIPT_DIR}/pnetlab-link-impairment.sh" --help
        ;;
    10)
        bash "${SCRIPT_DIR}/pnetlab-capture-stream.sh" --help
        ;;
    11)
        python3 "${SCRIPT_DIR}/pnetlab-dataplane-stats.py"
        ;;
    12)
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        ;;
    13)
        bash "${SCRIPT_DIR}/pnetlab-health-check.sh"
        ;;
    14)
        bash "${SCRIPT_DIR}/pnetlab-backup-restore.sh" backup
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
        bash "${SCRIPT_DIR}/pnetlab-block-updates.sh"
        ;;
    17)
        echo "--> [1/9] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo ""
        echo "--> [2/9] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/9] Applying 512MB Upload Limits & Docker Routing..."
        bash "${SCRIPT_DIR}/pnetlab-upload-and-docker-fix.sh"
        echo ""
        echo "--> [4/9] Applying SSL IP-SAN, Console & Cloud Bridge Fix..."
        bash "${SCRIPT_DIR}/pnetlab-system-and-console-fix.sh"
        echo ""
        echo "--> [5/9] Applying Database SQL Mode, 1M Limits & Logrotate..."
        bash "${SCRIPT_DIR}/pnetlab-database-and-system-deep-fix.sh"
        echo ""
        echo "--> [6/9] Fixing File Permissions & Sockets..."
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        echo ""
        echo "--> [7/9] Applying High-Performance Speed Optimizer..."
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        echo ""
        echo "--> [8/9] Activating Dataplane Fast-Path Accelerator..."
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        echo ""
        echo "--> [9/9] Freezing Version & Blocking Future Updates..."
        bash "${SCRIPT_DIR}/pnetlab-block-updates.sh"
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL ESSENTIAL ENHANCEMENTS APPLIED SUCCESSFULLY! "
        echo "============================================================"
        ;;
    18)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
