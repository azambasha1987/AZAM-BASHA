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
    echo "  1    Apply Permanent Session Fix (Never-Logout, 10-Year Session)"
    echo "  2    Apply Lab Export & APT Sources Fix"
    echo "  3    Apply High-Performance Speed Optimizer Suite"
    echo "  4    Configure AI Lab Builder & Ollama Integration"
    echo "  5    Fix File Permissions, /dev/kvm & Node Recovery"
    echo "  6    Run Comprehensive Health & Diagnostic Dashboard"
    echo "  7    Create Full Lab & Database Backup"
    echo "  8    Apply ALL Essential Fixes & Optimizations (1 + 2 + 3 + 5)"
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
echo "4) AI Lab Builder & Ollama MCP Integration"
echo "5) Fix File Permissions, /dev/kvm & Clean Node Locks"
echo "6) System Health & Diagnostic Dashboard"
echo "7) Create Full Lab & Database Backup Archive"
echo "8) Apply ALL Essential Fixes & Performance Suite (Recommended)"
echo "9) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^[1-9]$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-9, default: 8]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-8}"
else
    CHOICE="8"
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
        HOST_IP=""
        MODEL="qwen2.5:14b-instruct"
        if [ -e /dev/tty ]; then
            read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP < /dev/tty || true
            read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " USER_MODEL < /dev/tty || true
            MODEL="${USER_MODEL:-$MODEL}"
        fi
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "$MODEL"
        ;;
    5)
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        ;;
    6)
        bash "${SCRIPT_DIR}/pnetlab-health-check.sh"
        ;;
    7)
        bash "${SCRIPT_DIR}/pnetlab-backup-restore.sh" backup
        ;;
    8)
        echo "--> [1/4] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo ""
        echo "--> [2/4] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/4] Fixing File Permissions & Sockets..."
        bash "${SCRIPT_DIR}/pnetlab-fix-permissions.sh"
        echo ""
        echo "--> [4/4] Applying High-Performance Speed Optimizer..."
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL ESSENTIAL ENHANCEMENTS APPLIED SUCCESSFULLY! "
        echo "============================================================"
        ;;
    9)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
