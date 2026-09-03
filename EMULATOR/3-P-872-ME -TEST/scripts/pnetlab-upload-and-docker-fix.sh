#!/usr/bin/env bash
# ==============================================================================
# PNETLab Large Lab Upload & Docker Networking Fix Utility
#
# Fixes:
# 1. PHP & Apache file upload limits (Increases upload_max_filesize to 512MB)
# 2. Upload timeouts & memory exhaustion during large lab/image imports
# 3. Kernel IP Forwarding (net.ipv4.ip_forward=1) for Docker-to-Router routing
# 4. Docker bridge iptables FORWARD drop policy
# ==============================================================================
set -euo pipefail

# Support non-root check/help modes
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --status]"
    echo ""
    echo "Options:"
    echo "  (no args)    Apply 512MB upload boost and Docker networking fixes"
    echo "  --check      Inspect current PHP upload limits and IP forwarding status"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== PNETLab Upload & Docker Networking Diagnostic ==="
    echo -n "[*] PHP upload_max_filesize: "
    php -r "echo ini_get('upload_max_filesize');" 2>/dev/null || echo "Unknown"
    echo ""

    echo -n "[*] PHP post_max_size:        "
    php -r "echo ini_get('post_max_size');" 2>/dev/null || echo "Unknown"
    echo ""

    echo -n "[*] PHP memory_limit:         "
    php -r "echo ini_get('memory_limit');" 2>/dev/null || echo "Unknown"
    echo ""

    echo -n "[*] Kernel IPv4 Forwarding:   "
    if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ]; then
        echo "ENABLED (Docker & multi-subnet routing active)"
    else
        echo "DISABLED (Packets between container & routers blocked)"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================================"
echo "    PNETLab Upload Limits & Docker Networking Fix Tool      "
echo "============================================================"

# 1. Boost PHP Upload Limits across all installed PHP versions
echo "[1/4] Configuring 512MB Upload Limits in PHP ini files..."
for PHP_INI in /etc/php/*/apache2/php.ini /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini; do
    if [ -f "$PHP_INI" ]; then
        [ ! -f "${PHP_INI}.bak" ] && cp "$PHP_INI" "${PHP_INI}.bak.${TIMESTAMP}"
        sed -i 's/^;*upload_max_filesize =.*/upload_max_filesize = 512M/' "$PHP_INI"
        sed -i 's/^;*post_max_size =.*/post_max_size = 512M/' "$PHP_INI"
        sed -i 's/^;*memory_limit =.*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^;*max_execution_time =.*/max_execution_time = 600/' "$PHP_INI"
        sed -i 's/^;*max_input_time =.*/max_input_time = 600/' "$PHP_INI"
    fi
done
echo "  -> PHP upload limits scaled to 512MB with 600s execution timeout."

# 2. Boost Apache Request Body Limit
echo "[2/4] Configuring Apache LimitRequestBody (512MB)..."
cat << 'EOF' > /etc/apache2/conf-available/pnetlab-upload-limit.conf
# Allow large lab and image uploads up to 512MB
LimitRequestBody 536870912
EOF
a2enconf pnetlab-upload-limit 2>/dev/null || true

# 3. Kernel IP Forwarding & Routing
echo "[3/4] Enabling Kernel IPv4 & IPv6 Packet Forwarding..."
cat << 'EOF' > /etc/sysctl.d/97-pnetlab-forwarding.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.proxy_arp = 1
EOF
sysctl -p /etc/sysctl.d/97-pnetlab-forwarding.conf 2>/dev/null || sysctl --system 2>/dev/null || true

# 4. Docker FORWARD policy fix
echo "[4/4] Ensuring Docker bridge forwarding policy..."
if command -v iptables &>/dev/null; then
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    # Persist via /etc/rc.local if present
    if [ -f /etc/rc.local ] && ! grep -q "iptables -P FORWARD ACCEPT" /etc/rc.local; then
        sed -i 's/^exit 0/iptables -P FORWARD ACCEPT\nexit 0/' /etc/rc.local 2>/dev/null || true
    fi
fi

# 5. Restart web services
echo "[*] Restarting web server and PHP daemons..."
systemctl restart apache2 2>/dev/null || service apache2 restart 2>/dev/null || true
for PHP_FPM in $(systemctl list-units --type=service --state=running 2>/dev/null | grep -o 'php[0-9.]*-fpm' || true); do
    systemctl restart "$PHP_FPM" 2>/dev/null || true
done

echo ""
echo "============================================================"
echo " [SUCCESS] 512MB Upload Limits & Docker Routing Configured! "
echo "============================================================"
