#!/usr/bin/env bash
# ==============================================================================
# Azam-Pnet Master Bootstrap & Installer for Ubuntu 26.04+ (Resolute)
# 
# Execution Flow:
#   1. Pre-installs and validates ALL kernel modules, system packages, PHP/Python
#      runtimes, and 32-bit libraries required by Ubuntu 26.04+.
#   2. Launches the Azam-Pnet core software installation and database setup.
#   3. Applies permanent network engine, bridge supervisor, and hardware branding.
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This installer must be run as root: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/opt/azambasha")"
mkdir -p /opt/azambasha /opt/pnetlab
if [ "$SCRIPT_DIR" != "/opt/azambasha" ] && [ -d "$SCRIPT_DIR" ]; then
    ln -sfn "$SCRIPT_DIR" /opt/azambasha 2>/dev/null || true
fi
ln -sfn /opt/azambasha /opt/pnetlab 2>/dev/null || true

echo "============================================================"
echo "    Azam-Pnet Master Bootstrap & Installer (Ubuntu 26.04+)   "
echo "============================================================"
echo "[*] Working Directory: $SCRIPT_DIR"
echo "[*] Start Time       : $(date)"
echo "============================================================"

# --- Step 1: Install All OS Modules & System Prerequisites ---
echo ""
echo ">>> STAGE 1: Provisioning All OS Modules & Kernel Drivers..."
PREREQ_SCRIPT="${SCRIPT_DIR}/scripts/azambasha-os-prerequisites.sh"
if [ -f "$PREREQ_SCRIPT" ]; then
    bash "$PREREQ_SCRIPT"
else
    echo "      -> Fetching OS prerequisites script..."
    PREREQ_URL="https://raw.githubusercontent.com/azambasha1987/AZAM-BASHA/main/scripts/azambasha-os-prerequisites.sh"
    curl -fsSL --connect-timeout 5 "$PREREQ_URL" -o /tmp/azambasha-os-prerequisites.sh 2>/dev/null || true
    if [ -f /tmp/azambasha-os-prerequisites.sh ]; then
        bash /tmp/azambasha-os-prerequisites.sh
        rm -f /tmp/azambasha-os-prerequisites.sh
    fi
fi

# --- Step 2: Launch Azam-Pnet Software Installation ---
echo ""
echo ">>> STAGE 2: Installing Azam-Pnet Core Software & Packages..."
INSTALLER_SCRIPT="${SCRIPT_DIR}/install.sh"
if [ -f "$INSTALLER_SCRIPT" ]; then
    bash "$INSTALLER_SCRIPT" "$@"
else
    echo "[ERROR] Core installer ($INSTALLER_SCRIPT) not found." >&2
    exit 1
fi

# --- Step 3: Enforce Permanent Network Engine & Post-Install Fixes ---
echo ""
echo ">>> STAGE 3: Enforcing Permanent Network Engine & Supervisor..."
if [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-network.py" ]; then
    python3 "${SCRIPT_DIR}/scripts/azambasha-fix-network.py"
fi

echo ""
echo "============================================================"
echo " [SUCCESS] Azam-Pnet Fully Provisioned & Installed!        "
echo "============================================================"
echo "You can now access your server via Web Browser at:"
REAL_IP="$(ip -o -4 addr show pnet0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || ip -o -4 addr show 2>/dev/null | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1 | head -n1 || echo 'YOUR_SERVER_IP')"
echo "      https://${REAL_IP}/"
echo "      http://${REAL_IP}/"
echo "Default Credentials: admin / pnet"
echo "============================================================"
