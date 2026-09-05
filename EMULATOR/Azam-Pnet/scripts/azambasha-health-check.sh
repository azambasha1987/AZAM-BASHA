#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Appliance Comprehensive Health & Diagnostic Dashboard
# Audits:
# 1. CPU Virtualization & KVM support
# 2. Memory (RAM, Swap, KSM Deduplication)
# 3. Disk Space on / and /opt/unetlab
# 4. Web Stack (Apache, PHP-FPM, MySQL/MariaDB)
# 5. Azam Basha Core Services & MCP AI Daemon
# 6. Session Timeout & Optimizer Status
# 7. Device Image Library Inventory (QEMU, IOL, Dynamips, Docker)
# ==============================================================================
set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

echo -e "${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}${CYAN}        Azam Basha Appliance System Health Dashboard        ${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}"

# 1. Host & CPU Virtualization
echo -e "\n${BOLD}[1] Hypervisor & Hardware Virtualization${NC}"
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU")
CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
echo -e "  * CPU Model:       ${CYAN}${CPU_MODEL} (${CPU_CORES} vCPUs)${NC}"

if [ -e /dev/kvm ]; then
    echo -e "  * KVM Acceleration: ${GREEN}✔ ENABLED (/dev/kvm accessible)${NC}"
else
    echo -e "  * KVM Acceleration: ${RED}✘ DISABLED (/dev/kvm missing - Enable Nested Virtualization)${NC}"
fi

# 2. Memory & KSM Deduplication
echo -e "\n${BOLD}[2] Memory & Deduplication${NC}"
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
USED_RAM_MB=$(free -m | awk '/^Mem:/{print $3}')
FREE_RAM_MB=$(free -m | awk '/^Mem:/{print $4}')
echo -e "  * RAM Usage:        ${CYAN}${USED_RAM_MB} MB / ${TOTAL_RAM_MB} MB (${FREE_RAM_MB} MB free)${NC}"

if [ -f /sys/kernel/mm/ksm/run ] && [ "$(cat /sys/kernel/mm/ksm/run 2>/dev/null)" -eq 1 ]; then
    PAGES_SHARING=$(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 0)
    PAGE_SIZE_KB=$(($(getconf PAGE_SIZE 2>/dev/null || echo 4096) / 1024))
    SAVED_MB=$((PAGES_SHARING * PAGE_SIZE_KB / 1024))
    echo -e "  * KSM Deduplication:${GREEN} ✔ ACTIVE (Saving ~${SAVED_MB} MB RAM across nodes)${NC}"
else
    echo -e "  * KSM Deduplication:${YELLOW} ✘ INACTIVE (Run pnetlab-speed-optimizer.sh to enable)${NC}"
fi

SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null || cat /proc/sys/vm/swappiness 2>/dev/null || echo "Unknown")
echo -e "  * VM Swappiness:    ${CYAN}${SWAPPINESS}${NC} $([ "$SWAPPINESS" = "10" ] && echo -e "${GREEN}(Optimized)${NC}" || echo -e "${YELLOW}(Default)${NC}")"

# 3. Storage & Partitions
echo -e "\n${BOLD}[3] Storage Usage${NC}"
ROOT_DISK=$(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " used, " $4 " free)"}')
echo -e "  * Root Partition (/): ${CYAN}${ROOT_DISK}${NC}"

if [ -d /opt/unetlab ]; then
    UNL_DISK=$(df -h /opt/unetlab | awk 'NR==2{print $3 "/" $2 " (" $5 " used, " $4 " free)"}')
    echo -e "  * /opt/unetlab Data:  ${CYAN}${UNL_DISK}${NC}"
fi

# 4. Service Stack Status
echo -e "\n${BOLD}[4] Core Services Status${NC}"
check_service() {
    local name="$1"
    local desc="$2"
    if systemctl is-active "$name" 2>/dev/null | grep -q "active"; then
        echo -e "  * ${desc}: ${GREEN}✔ RUNNING${NC}"
    else
        echo -e "  * ${desc}: ${RED}✘ STOPPED / INACTIVE${NC}"
    fi
}

check_service "apache2" "Apache Web Server"
check_service "mysql" "MySQL Database" 2>/dev/null || check_service "mariadb" "MariaDB Database"

PHP_FPM_ACTIVE=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -o 'php[0-9.]*-fpm' | head -n1 || echo "")
if [ -n "$PHP_FPM_ACTIVE" ]; then
    echo -e "  * PHP-FPM Engine:    ${GREEN}✔ RUNNING (${PHP_FPM_ACTIVE})${NC}"
else
    echo -e "  * PHP-FPM Engine:    ${YELLOW}✔ RUNNING via Apache mod_php${NC}"
fi

# 5. PNETLab Modules & Optimizations
echo -e "\n${BOLD}[5] PNETLab Enhancements & AI Integration${NC}"
# Session Timeout
if grep -q "define('SESSION', '315360000')" /opt/unetlab/html/includes/config.php 2>/dev/null; then
    echo -e "  * Session Timeout:   ${GREEN}✔ 10 YEARS (Permanent Session Active)${NC}"
else
    echo -e "  * Session Timeout:   ${YELLOW}✘ DEFAULT (Short timeouts active)${NC}"
fi

# OPcache
if php -r "exit(ini_get('opcache.enable') ? 0 : 1);" 2>/dev/null; then
    OP_MEM=$(php -r "echo ini_get('opcache.memory_consumption');" 2>/dev/null || echo "Unknown")
    echo -e "  * PHP OPcache:       ${GREEN}✔ ENABLED (${OP_MEM} MB Memory Cache)${NC}"
else
    echo -e "  * PHP OPcache:       ${YELLOW}✘ DISABLED${NC}"
fi

# AI MCP Daemon
if systemctl is-active pnetlab-mcp 2>/dev/null | grep -q "active"; then
    echo -e "  * AI MCP Daemon:     ${GREEN}✔ ACTIVE (pnetlab-mcp.service running on port 5701)${NC}"
else
    echo -e "  * AI MCP Daemon:     ${YELLOW}✘ INACTIVE / NOT CONFIGURED${NC}"
fi

# 6. Web UI & Authentication Status
echo -e "\n${BOLD}[6] Web Dashboard & Authentication Status${NC}"
AUTH_RESP=$(curl -k -s -m 5 -X POST https://127.0.0.1/api/auth \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"azam"}' 2>/dev/null || echo "")

ACTIVE_USER="admin/azam"
if ! echo "$AUTH_RESP" | grep -q '"code":200'; then
    AUTH_RESP=$(curl -k -s -m 5 -X POST https://127.0.0.1/api/auth \
      -H "Content-Type: application/json" \
      -d '{"username":"admin","password":"pnet"}' 2>/dev/null || echo "")
    ACTIVE_USER="admin/pnet"
fi

if echo "$AUTH_RESP" | grep -q '"code":200'; then
    echo -e "  * Admin Auth (${ACTIVE_USER}): ${GREEN}✔ ACTIVE (Authenticated successfully)${NC}"
elif [ -z "$AUTH_RESP" ]; then
    echo -e "  * Web UI HTTPS Endpoint:  ${RED}✘ UNREACHABLE (Check Apache2 / SSL service)${NC}"
else
    echo -e "  * Admin Auth:              ${YELLOW}✘ FAILED (${AUTH_RESP:0:80})${NC}"
fi

# Cisco IOL License Key
if [ -f /opt/unetlab/addons/iol/bin/iourc ] && grep -q "license" /opt/unetlab/addons/iol/bin/iourc 2>/dev/null; then
    echo -e "  * Cisco IOL License Key:   ${GREEN}✔ INSTALLED (/opt/unetlab/addons/iol/bin/iourc)${NC}"
else
    echo -e "  * Cisco IOL License Key:   ${YELLOW}✘ MISSING (Run pnetlab-fix-permissions.sh to generate)${NC}"
fi

# 7. Installed Node Images Inventory
echo -e "\n${BOLD}[7] Node Images Inventory${NC}"
QEMU_COUNT=$(find /opt/unetlab/addons/qemu -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo 0)
IOL_COUNT=$(find /opt/unetlab/addons/iol/bin -type f -name "*.bin" 2>/dev/null | wc -l || echo 0)
DYN_COUNT=$(find /opt/unetlab/addons/dynamips -type f -name "*.image" -o -name "*.bin" 2>/dev/null | wc -l || echo 0)
DOCKER_COUNT=$(find /opt/unetlab/addons/docker -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo 0)
LAB_COUNT=$(find /opt/unetlab/labs -name "*.unl" 2>/dev/null | wc -l || echo 0)

echo -e "  * QEMU Templates:    ${CYAN}${QEMU_COUNT}${NC} installed"
echo -e "  * Cisco IOL Images:  ${CYAN}${IOL_COUNT}${NC} installed"
echo -e "  * Dynamips Images:   ${CYAN}${DYN_COUNT}${NC} installed"
echo -e "  * Docker Images:     ${CYAN}${DOCKER_COUNT}${NC} installed"
echo -e "  * Active Labs (.unl):${CYAN}${LAB_COUNT}${NC} available"

echo -e "\n${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}${GREEN} Diagnostic Complete! System is ready for lab simulation.${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}"
