#!/usr/bin/env bash
# ==============================================================================
# PNETLab Never-Logout Script
# Sets infinite/10-year session timeout across PHP, Database, Cookies & Frontend
# Compatibility: PNETLab v5, v6, v7, v8 (Ubuntu 18.04 / 20.04 / 22.04 / 24.04 / 26.04)
#
# Supports piped execution & non-root diagnostic checks.
# ==============================================================================
set -euo pipefail

# Support non-root diagnostic/check mode
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --status]"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== PNETLab Session Timeout Diagnostic Check ==="
    echo -n "[*] config.php SESSION constant: "
    if grep -q "define('SESSION', '315360000')" /opt/unetlab/html/includes/config.php 2>/dev/null; then
        echo "10 YEARS (315360000s)"
    else
        echo "DEFAULT / UNPATCHED"
    fi

    echo -n "[*] Database Session Timeout: "
    if mysql -u pnetlab -ppnetlab pnetlab_db -e "SELECT control_value FROM control WHERE control_name='ctrl_session_timeout';" 2>/dev/null | tail -n1; then
        :
    elif mysql --defaults-file=/etc/mysql/debian.cnf pnetlab_db -e "SELECT control_value FROM control WHERE control_name='ctrl_session_timeout';" 2>/dev/null | tail -n1; then
        :
    else
        echo "Could not query database"
    fi

    echo -n "[*] Frontend Keepalive Heartbeat: "
    if grep -q "pnetlab-keepalive.js" /opt/unetlab/html/main/index.html 2>/dev/null; then
        echo "INSTALLED"
    else
        echo "MISSING"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TIMEOUT_SECONDS=315360000   # 10 years (3650 days)

echo "=== Applying PNETLab Permanent Session Fix ==="

# 1. Update /opt/unetlab/html/includes/config.php
echo "[1/7] Updating /opt/unetlab/html/includes/config.php..."
CONFIG_FILE="/opt/unetlab/html/includes/config.php"
mkdir -p "$(dirname "$CONFIG_FILE")"
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.${TIMESTAMP}"

cat << 'EOF' > "$CONFIG_FILE"
<?php
if (!defined('SESSION')) { define('SESSION', '315360000'); }
if (!defined('TEMPLATE_DISABLED')) { define('TEMPLATE_DISABLED', '.hided'); }
ini_set('session.gc_maxlifetime', 315360000);
ini_set('session.cookie_lifetime', 315360000);
EOF
chown www-data:www-data "$CONFIG_FILE" || true
chmod 644 "$CONFIG_FILE"

# 2. Update MySQL/MariaDB database (pnetlab_db)
echo "[2/7] Updating database session limits in pnetlab_db..."
MYSQL_CMD=""
if mysql -u pnetlab -ppnetlab -e "USE pnetlab_db;" >/dev/null 2>&1; then
    MYSQL_CMD="mysql -u pnetlab -ppnetlab pnetlab_db"
elif [ -f /etc/mysql/debian.cnf ] && mysql --defaults-file=/etc/mysql/debian.cnf -e "USE pnetlab_db;" >/dev/null 2>&1; then
    MYSQL_CMD="mysql --defaults-file=/etc/mysql/debian.cnf pnetlab_db"
elif mysql -u root -e "USE pnetlab_db;" >/dev/null 2>&1; then
    MYSQL_CMD="mysql -u root pnetlab_db"
elif command -v mariadb &>/dev/null && mariadb -u root -e "USE pnetlab_db;" >/dev/null 2>&1; then
    MYSQL_CMD="mariadb -u root pnetlab_db"
else
    MYSQL_CMD="mysql pnetlab_db"
fi

$MYSQL_CMD << SQL || true
INSERT INTO control (control_name, control_value) 
VALUES ('ctrl_session_timeout', '${TIMEOUT_SECONDS}') 
ON DUPLICATE KEY UPDATE control_value = '${TIMEOUT_SECONDS}';

UPDATE users SET 
    session = UNIX_TIMESTAMP() + ${TIMEOUT_SECONDS},
    expiration = -1, expired_time = 0, active_time = 0,
    access_days = NULL, user_status = 1;
SQL

# 3. Patch status/api.php timeout bound
echo "[3/7] Patching status/api.php timeout bound..."
STATUS_API="/opt/unetlab/html/status/api.php"
if [ -f "$STATUS_API" ]; then
    cp "$STATUS_API" "${STATUS_API}.bak.${TIMESTAMP}"
    sed -i -E 's/\$seconds\s*>\s*[0-9]+/\$seconds > '"${TIMEOUT_SECONDS}"'/g' "$STATUS_API"
fi

# 4. Patch sliding cookie renewal in functions.php
echo "[4/7] Patching sliding cookie renewal in functions.php..."
FUNCTIONS_FILE="/opt/unetlab/html/includes/functions.php"
if [ -f "$FUNCTIONS_FILE" ] && ! grep -q "Never-Logout Sliding Cookie" "$FUNCTIONS_FILE"; then
    cp "$FUNCTIONS_FILE" "${FUNCTIONS_FILE}.bak.${TIMESTAMP}"
    python3 - "$FUNCTIONS_FILE" << 'PYEOF' || true
import sys

functions_file = sys.argv[1]
with open(functions_file, "r", encoding="utf-8", errors="ignore") as f:
    content = f.read()

target = "function updateUserCookie"
if target in content:
    idx = content.find(target)
    brace_idx = content.find("{", idx)
    if brace_idx != -1:
        injection = '\n        // Never-Logout Sliding Cookie\n        if (!headers_sent()) {\n            @setcookie("token", $cookie, [\n                "expires"  => time() + 315360000,\n                "path"     => "/",\n                "secure"   => true,\n                "httponly" => true,\n                "samesite" => "Strict",\n            ]);\n        }\n'
        content = content[:brace_idx+1] + injection + content[brace_idx+1:]
        with open(functions_file, "w", encoding="utf-8") as f:
            f.write(content)
PYEOF
fi

# 5. Configure PHP ini files
echo "[5/7] Updating session settings in PHP ini files..."
for PHP_INI in /etc/php/*/apache2/php.ini /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini; do
    if [ -f "$PHP_INI" ]; then
        sed -i 's/^;*session.gc_maxlifetime =.*/session.gc_maxlifetime = 315360000/' "$PHP_INI"
        sed -i 's/^;*session.cookie_lifetime =.*/session.cookie_lifetime = 315360000/' "$PHP_INI"
        sed -i 's/^;*session.cache_expire =.*/session.cache_expire = 5256000/' "$PHP_INI"
    fi
done

# 6. Inject background keepalive heartbeat
echo "[6/7] Installing keepalive heartbeat script..."
KEEPALIVE_JS="/opt/unetlab/html/themes/default/js/pnetlab-keepalive.js"
mkdir -p "$(dirname "$KEEPALIVE_JS")"
cat << 'EOF' > "$KEEPALIVE_JS"
(function() {
    if (window.__pnetKeepaliveActive) return;
    window.__pnetKeepaliveActive = true;
    setInterval(function() {
        fetch('/api/auth', { credentials: 'same-origin' }).catch(function() {});
    }, 180000);
})();
EOF
chown www-data:www-data "$KEEPALIVE_JS" || true
chmod 644 "$KEEPALIVE_JS"

MAIN_HTML="/opt/unetlab/html/main/index.html"
if [ -f "$MAIN_HTML" ] && ! grep -q "pnetlab-keepalive.js" "$MAIN_HTML"; then
    if grep -iq "</body>" "$MAIN_HTML"; then
        sed -i -E 's|</body>|<script src="/themes/default/js/pnetlab-keepalive.js"></script></body>|I' "$MAIN_HTML"
    else
        echo '<script src="/themes/default/js/pnetlab-keepalive.js"></script>' >> "$MAIN_HTML"
    fi
fi

# 7. Restart services
echo "[7/7] Restarting web server and PHP services..."
systemctl restart apache2 2>/dev/null || service apache2 restart 2>/dev/null || true
for PHP_FPM in $(systemctl list-units --type=service --state=running 2>/dev/null | grep -o 'php[0-9.]*-fpm' || true); do
    systemctl restart "$PHP_FPM" 2>/dev/null || true
done

echo "=== [SUCCESS] Session timeout set to 10 Years! Persistent logins active. ==="
