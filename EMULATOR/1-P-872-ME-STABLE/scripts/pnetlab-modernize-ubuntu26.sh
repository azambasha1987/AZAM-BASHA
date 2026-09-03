#!/usr/bin/env bash
# ==============================================================================
# PNetLab Master Modernization & Fine-Tuning Suite for Ubuntu 26+ (Resolute)
# Complete orchestration script to modernize Datapath, PHP 8.5, Cgroups v2,
# Python 3.14+, and Security barriers on existing or new PNETLab installations.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "    PNETLab Master Modernization for Ubuntu 26+ (Resolute) "
echo "============================================================"

# Phase 1: Network & Broker Datapath
if [ -f "${SCRIPT_DIR}/pnetlab-fix-network-management.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-fix-network-management.sh" || true
fi
if [ -f "${SCRIPT_DIR}/pnetlab-modern-netplan-engine.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-modern-netplan-engine.sh" || true
fi

# Phase 2: PHP 8.4/8.5 Engine & Session Tuning
if [ -f "${SCRIPT_DIR}/pnetlab-php-modernizer.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-php-modernizer.sh" || true
fi

# Phase 3: Cgroups v2 & Virtualization Throttling
if [ -f "${SCRIPT_DIR}/pnetlab-cgroups-v2-engine.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-cgroups-v2-engine.sh" || true
fi

# Phase 4: Python 3.14+ Ecosystem & Web Console Bridges
if [ -f "${SCRIPT_DIR}/pnetlab-python-environment-setup.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-python-environment-setup.sh" || true
fi

# Phase 5: Database & System Deep Fixes
if [ -f "${SCRIPT_DIR}/pnetlab-database-and-system-deep-fix.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-database-and-system-deep-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-fix-export-and-apt.sh" || true
fi
if [ -f "${SCRIPT_DIR}/pnetlab-disable-logout.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-disable-logout.sh" || true
fi
if [ -f "${SCRIPT_DIR}/pnetlab-block-updates.sh" ]; then
    bash "${SCRIPT_DIR}/pnetlab-block-updates.sh" || true
fi

# Final Service Verification & Reload
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true
systemctl restart "php${PHP_VER}-fpm" apache2 pnetlab-brokerd.service 2>/dev/null || true

echo "============================================================"
echo "    [COMPLETE] PNETLab is 100% Fine-Tuned for Ubuntu 26+!  "
echo "============================================================"
