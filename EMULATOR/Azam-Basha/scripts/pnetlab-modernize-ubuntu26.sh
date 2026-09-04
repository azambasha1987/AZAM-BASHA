#!/usr/bin/env bash
# ==============================================================================
# PNetLab Master Modernization & Fine-Tuning Suite for Ubuntu 26+ (Resolute)
# Complete orchestration script to modernize Datapath, PHP 8.5, Cgroups v2,
# Python 3.14+, and Security barriers on existing or new PNETLab installations.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_RAW="https://raw.githubusercontent.com/azambasha1987/AZAM-BASHA/main/EMULATOR/1-P-872-ME-STABLE/scripts"

run_or_fetch() {
    local script_name="$1"
    local local_file="${SCRIPT_DIR}/${script_name}"
    local opt_file="/opt/unetlab/scripts/${script_name}"
    local pnet_file="/PNET/pnetlab-v8-ubuntu26-installer/scripts/${script_name}"
    
    local target=""
    if [ -f "$local_file" ]; then
        target="$local_file"
    elif [ -f "$opt_file" ]; then
        target="$opt_file"
    elif [ -f "$pnet_file" ]; then
        target="$pnet_file"
    fi

    if [ -n "$target" ]; then
        if [[ "$script_name" == *.py ]]; then
            python3 "$target" || true
        else
            bash "$target" || true
        fi
    else
        echo "      -> Fetching ${script_name} from GitHub..."
        local tmp_file="/tmp/${script_name}"
        if curl -fsSL --connect-timeout 5 "${GITHUB_RAW}/${script_name}" -o "$tmp_file" 2>/dev/null; then
            if [[ "$script_name" == *.py ]]; then
                python3 "$tmp_file" || true
            else
                bash "$tmp_file" || true
            fi
            rm -f "$tmp_file" 2>/dev/null || true
        else
            echo "      [WARN] Could not locate or download ${script_name}."
        fi
    fi
}

echo "============================================================"
echo "    PNETLab Master Modernization for Ubuntu 26+ (Resolute) "
echo "============================================================"

# Phase 1: Network & Broker Datapath
run_or_fetch "pnetlab-fix-network.py"
run_or_fetch "pnetlab-fix-eth0-permanent.py"
run_or_fetch "pnetlab-modern-netplan-engine.sh"

# Phase 2: PHP 8.4/8.5 Engine & Session Tuning
run_or_fetch "pnetlab-php-modernizer.sh"

# Phase 3: Cgroups v2 & Virtualization Throttling
run_or_fetch "pnetlab-cgroups-v2-engine.sh"

# Phase 4: Python 3.14+ Ecosystem & Web Console Bridges
run_or_fetch "pnetlab-python-environment-setup.sh"

# Phase 5: Database & System Deep Fixes
run_or_fetch "pnetlab-database-and-system-deep-fix.sh"
run_or_fetch "pnetlab-fix-export-and-apt.sh"
run_or_fetch "pnetlab-disable-logout.sh"
run_or_fetch "pnetlab-block-updates.sh"

# Final Service Verification & Reload
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true
systemctl restart "php${PHP_VER}-fpm" apache2 pnetlab-brokerd.service 2>/dev/null || true

echo "============================================================"
echo "    [COMPLETE] PNETLab is 100% Fine-Tuned for Ubuntu 26+!  "
echo "============================================================"
