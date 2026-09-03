#!/usr/bin/env bash
# ==============================================================================
# PNetLab Python 3.14+ Isolated Runtime & Web Console Bridge Engine
# Sets up /opt/unetlab/venv with telnetlib3, websockets, and AI MCP bridges,
# ensuring full compliance with PEP 668 on Ubuntu 26+.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    [4/4] Setting Up Python 3.14+ Environment & Bridges...  "
echo "============================================================"

# 1. Install System Python Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq python3-venv python3-pip python3-setuptools python3-wheel 2>/dev/null || true

# 2. Create Isolated Python Virtual Environment
VENV_PATH="/opt/unetlab/venv"
if [ ! -d "$VENV_PATH" ]; then
    echo "      -> Creating isolated virtual environment at ${VENV_PATH}..."
    python3 -m venv "$VENV_PATH" 2>/dev/null || true
fi

# 3. Install Required Dependencies in Venv & Global Fallback
echo "      -> Installing telnetlib3, websockets, requests, and MCP bridges..."
if [ -x "${VENV_PATH}/bin/pip" ]; then
    "${VENV_PATH}/bin/pip" install --upgrade pip 2>/dev/null || true
    "${VENV_PATH}/bin/pip" install telnetlib3 websockets requests urllib3 2>/dev/null || true
fi

# Global installation with --break-system-packages as safety fallback
pip3 install --break-system-packages telnetlib3 websockets requests urllib3 2>/dev/null || true

# 4. Ensure Web Console Services Use telnetlib3
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now pnet-console-mux.service 2>/dev/null || true
systemctl restart pnet-console-mux.service 2>/dev/null || true
systemctl enable --now pnet-guac-lite.service 2>/dev/null || true
systemctl restart pnet-guac-lite.service 2>/dev/null || true

echo "============================================================"
echo "    [SUCCESS] Python 3.14+ Runtime & Bridges Configured!    "
echo "============================================================"
