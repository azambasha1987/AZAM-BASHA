#!/usr/bin/env bash
# ==============================================================================
# PNETLab Master Fix & Enhancement Runner
# Applies Permanent Session Fix, Lab Export / APT Fix, and optional Ollama AI Setup
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "          PNETLab Master Fix & Deployment Tool              "
echo "============================================================"
echo "1) Apply Permanent Session Fix (Never-Logout, 10 Years)"
echo "2) Apply Lab Export & APT Sources Fix (zip/unzip, nested labs)"
echo "3) Configure AI Lab Builder & Ollama Integration"
echo "4) Apply ALL Fixes (Session + Export + Ollama)"
echo "5) Exit"
echo "============================================================"
read -rp "Select an option [1-5]: " CHOICE

case "$CHOICE" in
    1)
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        ;;
    2)
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        ;;
    3)
        read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP
        read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " MODEL
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "${MODEL:-qwen2.5:14b-instruct}"
        ;;
    4)
        echo "--> Applying Permanent Session Fix..."
        bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh"
        echo "--> Applying Lab Export & APT Fix..."
        bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh"
        echo "--> Configuring Ollama AI Integration..."
        read -rp "Enter Ollama Host IP (e.g. 192.168.1.19): " HOST_IP
        read -rp "Enter Ollama Model [default: qwen2.5:14b-instruct]: " MODEL
        bash "${SCRIPT_DIR}/setup-ollama.sh" "$HOST_IP" "${MODEL:-qwen2.5:14b-instruct}"
        echo "=== ALL FIXES APPLIED SUCCESSFULLY ==="
        ;;
    5)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection."
        exit 1
        ;;
esac
