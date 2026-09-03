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
    echo "  4    High-Performance Speed Optimizer Suite (KSM, OPcache, Gzip, Sysctl)"
    echo "  5    Dataplane Fast-Path Accelerator (2× Throughput, 1/3 CPU)"
    echo "  6    Image Doctor & Virtual Disk Integrity Audit"
    echo "  7    Link Quality & Impairment Controller (latency, jitter, loss)"
    echo "  8    Packet Capture & Live Wireshark Streamer"
    echo "  9    Real-Time Per-Link Telemetry Monitor"
    echo "  10   Fix File Permissions, /dev/kvm & Clean Node Locks"
    echo "  11   System Health & Diagnostic Dashboard"
    echo "  12   Create Full Lab & Database Backup"
    echo "  13   Configure AI Lab Builder & Ollama Integration"
    echo "  14   Apply ALL Essential Fixes & Dataplane Suite (Recommended)"
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
echo "4) High-Performance Speed Optimizer (KSM, OPcache, Gzip, Sysctl)"
echo "5) Dataplane Fast-Path Accelerator (~2× Throughput, 1/3 CPU)"
echo "6) Image Doctor & QCOW2 Disk Integrity Audit"
echo "7) Link Impairment Controller (Latency, Jitter, Packet Loss)"
echo "8) Packet Capture & Live Wireshark Streamer"
echo "9) Real-Time Per-Link Telemetry Monitor"
echo "10) Fix File Permissions, /dev/kvm & Node Recovery"
echo "11) System Health & Diagnostic Dashboard"
echo "12) Create Full Lab & Database Backup Archive"
echo "13) AI Lab Builder & Ollama MCP Integration"
echo "14) Apply ALL Essential Fixes & Performance Suite (Recommended)"
echo "15) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^([1-9]|1[0-5])$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-15, default: 14]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-14}"
else
    CHOICE="14"
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
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        ;;
    5)
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        ;;
    6)
        bash "${SCRIPT_DIR}/pnetlab-image-doctor.sh" --fix
        ;;
    7)
        bash "${SCRIPT_DIR}/pnetlab-link-impairment.sh" --help
        ;;
    8)
        bash "${SCRIPT_DIR}/pnetlab-capture-stream.sh" --help
        ;;
    9)
        python3 "${SCRIPT_DIR}/pnetlab-dataplane-stats.py"
        ;;
    10)
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        ;;
    11)
        bash "${SCRIPT_DIR}/pnetlab-health-check.sh"
        ;;
    12)
        bash "${SCRIPT_DIR}/pnetlab-backup-restore.sh" backup
        ;;
    13)
        HOST_IP=""
        MODEL="qwen2.5:14b-instruct"
        if [ -e /dev/tty ]; then
            read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP < /dev/tty || true
            read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " USER_MODEL < /dev/tty || true
            MODEL="${USER_MODEL:-$MODEL}"
        fi
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "$MODEL"
        ;;
    14)
        echo "--> [1/6] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo ""
        echo "--> [2/6] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/6] Applying 512MB Upload Limits & Docker Routing..."
        bash "${SCRIPT_DIR}/pnetlab-upload-and-docker-fix.sh"
        echo ""
        echo "--> [4/6] Fixing File Permissions & Sockets..."
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        echo ""
        echo "--> [5/6] Applying High-Performance Speed Optimizer..."
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        echo ""
        echo "--> [6/6] Activating Dataplane Fast-Path Accelerator..."
        bash "${SCRIPT_DIR}/pnetlab-dataplane-engine.sh"
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL ESSENTIAL ENHANCEMENTS APPLIED SUCCESSFULLY! "
        echo "============================================================"
        ;;
    15)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
