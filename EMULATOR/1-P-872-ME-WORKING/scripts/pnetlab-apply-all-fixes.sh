#!/usr/bin/env bash
# ==============================================================================
# PNETLab Master Fix, Enhancement & Performance Deployment Tool
# Applies:
# 1. Permanent Session & Never-Logout Fix (10 Years)
# 2. Lab Export & APT Sources Fix (zip/unzip, nested labs)
# 3. High-Performance Speed Optimizer (KSM, OPcache, Apache Gzip, Sysctl)
# 4. AI Lab Builder & Local Ollama MCP Integration
#
# Supports piped execution: curl -fsSL https://.../pnetlab-apply-all-fixes.sh | sudo bash
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Support non-root check/help modes
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [OPTION_NUMBER | --check]"
    echo "Options:"
    echo "  1    Apply Permanent Session Fix"
    echo "  2    Apply Lab Export & APT Sources Fix"
    echo "  3    Apply High-Performance Speed Optimizer Suite"
    echo "  4    Configure AI Lab Builder & Ollama Integration"
    echo "  5    Apply ALL Fixes & Performance Enhancements (1 + 2 + 3 + 4)"
    echo "  --check  Run diagnostic health check across all modules"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== Running PNETLab System Diagnostic Health Check ==="
    if [ -f "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh" ]; then
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh" --check || true
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "      PNETLab Master Fix & Performance Deployment Tool      "
echo "============================================================"
echo "1) Permanent Session Fix (Never-Logout, 10-Year Session)"
echo "2) Lab Export & APT Sources Fix (zip/unzip, nested labs)"
echo "3) High-Performance Speed Optimizer (KSM, OPcache, Gzip, Sysctl)"
echo "4) AI Lab Builder & Ollama MCP Integration"
echo "5) Apply ALL Fixes & Performance Optimizations (Recommended)"
echo "6) Exit"
echo "============================================================"

# Handle interactive /dev/tty or non-interactive argument/fallback
CHOICE=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^[1-6]$ ]]; then
    CHOICE="$1"
elif [ -e /dev/tty ]; then
    read -rp "Select an option [1-6, default: 5]: " USER_INPUT < /dev/tty || true
    CHOICE="${USER_INPUT:-5}"
else
    CHOICE="5"
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
        echo "--> [1/4] Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo ""
        echo "--> [2/4] Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo ""
        echo "--> [3/4] Applying High-Performance Speed Optimizer..."
        bash "${SCRIPT_DIR}/pnetlab-speed-optimizer.sh"
        echo ""
        echo "--> [4/4] Configuring Ollama AI Integration..."
        HOST_IP=""
        MODEL="qwen2.5:14b-instruct"
        if [ -e /dev/tty ]; then
            read -rp "Enter Ollama Host IP (or press ENTER to auto-detect/skip): " HOST_IP < /dev/tty || true
        fi
        if [ -n "$HOST_IP" ]; then
            bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "$MODEL"
        else
            echo "Skipping Ollama configuration (no Host IP provided). Run option 4 anytime to configure."
        fi
        echo ""
        echo "============================================================"
        echo "  [SUCCESS] ALL REQUESTED FIXES & PERFORMANCE APPLIED!      "
        echo "============================================================"
        ;;
    6)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection: $CHOICE"
        exit 1
        ;;
esac
