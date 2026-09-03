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
    echo "  3    High-Performance Speed Optimizer Suite (KSM, OPcache, Gzip, Sysctl)"
    echo "  4    High-Performance Dataplane Accelerator (2× Throughput, 1/3 CPU)"
    echo "  5    Link Quality & Impairment Controller (latency, jitter, loss)"
    echo "  6    Packet Capture & Live Wireshark Streamer"
    echo "  7    Real-Time Per-Link Telemetry Monitor"
    echo "  8    Fix File Permissions, /dev/kvm & Clean Node Locks"
    echo "  9    System Health & Diagnostic Dashboard"
    echo "  10   Create Full Lab & Database Backup"
    echo "  11   Configure AI Lab Builder & Ollama Integration"
    echo "  12   Apply ALL Essential Fixes & Dataplane Suite (Recommended)"
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
echo "3) High-Performance Speed Optimizer (KSM, OPcache, Gzip, Sysctl)"
echo "4) Dataplane Fast-Path Accelerator (~2× Throughput, 1/3 CPU)"
echo "5) Link Impairment Controller (Latency, Jitter, Packet Loss)"
echo "6) Packet Capture & Live Wireshark Streamer"
echo "7) Real-Time Per-Link Telemetry Monitor"
echo "8) Fix File Permissions, /dev/kvm & Node Recovery"
echo "9) System Health & Diagnostic Dashboard"
echo "10) Create Full Lab & Database Backup Archive"
echo "11) AI Lab Builder & Ollama MCP Integration"
echo "12) Apply ALL Essential Fixes & Performance Suite (Recommended)"
echo "13) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^([1-9]|1[0-3])$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-13, default: 12]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-12}"
else
    CHOICE="12"
fi

case "$CHOICE" in
    1)
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        ;;
    2)
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        ;;
    3)
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        ;;
    4)
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        ;;
    5)
        bash "${SCRIPT_DIR}/pnetlab-link-impairment.sh" --help
        ;;
    6)
        bash "${SCRIPT_DIR}/pnetlab-capture-stream.sh" --help
        ;;
    7)
        python3 "${SCRIPT_DIR}/pnetlab-dataplane-stats.py"
        ;;
    8)
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        ;;
    9)
        bash "${SCRIPT_DIR}/pnetlab-health-check.sh"
        ;;
    10)
        bash "${SCRIPT_DIR}/pnetlab-backup-restore.sh" backup
        ;;
    11)
        HOST_IP=""
        MODEL="qwen2.5:14b-instruct"
        if [ -e /dev/tty ]; then
            read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP < /dev/tty || true
            read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " USER_MODEL < /dev/tty || true
            MODEL="${USER_MODEL:-$MODEL}"
        fi
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "$MODEL"
        ;;
    12)
        echo "--> [1/5] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo ""
        echo "--> [2/5] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/5] Fixing File Permissions & Sockets..."
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        echo ""
        echo "--> [4/5] Applying High-Performance Speed Optimizer..."
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        echo ""
        echo "--> [5/5] Activating Dataplane Fast-Path Accelerator..."
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL ESSENTIAL ENHANCEMENTS APPLIED SUCCESSFULLY! "
        echo "============================================================"
        ;;
    13)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
