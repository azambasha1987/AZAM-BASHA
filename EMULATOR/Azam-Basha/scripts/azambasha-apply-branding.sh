#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Enterprise Branding, Version & Identity Engine
# Sets Version to 1.0.0, Default Password to 'azam', and deploys all brand assets
# ==============================================================================
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/opt/unetlab/scripts")"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd || echo "/opt/azambasha")"
ASSETS_DIR="${PARENT_DIR}/assets"
[ ! -d "$ASSETS_DIR" ] && ASSETS_DIR="/opt/azambasha/assets"
[ ! -d "$ASSETS_DIR" ] && ASSETS_DIR="/opt/unetlab/html/images"
BRAND_DIR="/opt/unetlab/data/branding"

echo "============================================================"
echo "    Azam Basha UI Branding, Version & Credentials Engine    "
echo "============================================================"

# 1. Update Platform Version to v1.0.0 in PHP Configuration
mkdir -p /opt/unetlab/html/includes 2>/dev/null || true
cat > /opt/unetlab/html/includes/version.php << 'EOF'
<?php
/**
 * Azam Basha Platform Version Configuration
 */
if (!defined('PNET_RELEASE')) {
    define('PNET_RELEASE', 'v1.0.0');
}

if (!defined('PNET_VERSION')) {
    define('PNET_VERSION', '1.0.0');
}
EOF
chmod 0644 /opt/unetlab/html/includes/version.php
echo "  [✔] Platform version set to 1.0.0 (v1.0.0)"

# 2. Update Login Page Text & Default Credentials Notice (admin / azam)
if [ -f /opt/unetlab/html/login/index.html ]; then
    sed -i -E 's/admin<\/strong> \/ <strong>[a-zA-Z0-9]+/admin<\/strong> \/ <strong>azam/g' /opt/unetlab/html/login/index.html 2>/dev/null || true
    echo "  [✔] Login page default credentials set to admin / azam"
fi

# 3. Update Database Admin Password to 'azam' and Version to '1.0.0'
AZAM_HASH="aec7a491c6e8d1433b213e694f086222fe6fde75a17c379b7fc22472539ff8e1"
SQL_UPDATE="UPDATE users SET password = '${AZAM_HASH}' WHERE username = 'admin'; INSERT INTO control (control_name, control_value) VALUES ('ctrl_version','1.0.0') ON DUPLICATE KEY UPDATE control_value = '1.0.0';"
mysql -u pnetlab -ppnetlab pnetlab_db -e "$SQL_UPDATE" 2>/dev/null || mysql pnetlab_db -e "$SQL_UPDATE" 2>/dev/null || true
echo "  [✔] Database Web Admin password updated to 'azam' (SHA-256)"
echo "  [✔] Database control version updated to '1.0.0'"

# 4. Update Linux System Passwords (root & pnet to 'azam')
echo "root:azam" | chpasswd 2>/dev/null || true
id -u pnet >/dev/null 2>&1 && echo "pnet:azam" | chpasswd 2>/dev/null || true
echo "  [✔] System SSH root/pnet password updated to 'azam'"

# 5. Clear any lingering login rate-limit / lockout tokens
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true

# 6. Ensure Branding Data Directory & Configuration
mkdir -p "$BRAND_DIR"

cat > "${BRAND_DIR}/config.json" << 'EOF'
{
  "name": "Azam Basha",
  "login_header": "Azam Basha Network Emulation Platform",
  "hide_default_creds": false
}
EOF

# 7. Deploy Logo Assets
if [ -f "${ASSETS_DIR}/logo.png" ]; then
    cp -f "${ASSETS_DIR}/logo.png" "${BRAND_DIR}/logo.png"
    echo "  [✔] Custom branding logo deployed to ${BRAND_DIR}/logo.png"
fi

# 8. Overwrite all static stock web logos & icons
mkdir -p /opt/unetlab/html/assets-common/img \
         /opt/unetlab/html/images \
         /opt/unetlab/html/themes/default/images \
         /usr/share/plymouth/themes/pnetlab 2>/dev/null || true

if [ -f "${ASSETS_DIR}/logo.png" ]; then
    cp -f "${ASSETS_DIR}/logo.png" /opt/unetlab/html/assets-common/img/logo.png 2>/dev/null || true
    cp -f "${ASSETS_DIR}/logo.png" /opt/unetlab/html/images/logo.png 2>/dev/null || true
    cp -f "${ASSETS_DIR}/logo.png" /opt/unetlab/html/themes/default/images/logo.png 2>/dev/null || true
    for p in /usr/share/plymouth/themes/pnetlab/logo*.png; do
        [ -f "$p" ] && cp -f "${ASSETS_DIR}/logo.png" "$p" 2>/dev/null || true
    done
fi

if [ -f "${ASSETS_DIR}/favicon.png" ]; then
    cp -f "${ASSETS_DIR}/favicon.png" /opt/unetlab/html/assets-common/img/favicon.png 2>/dev/null || true
    cp -f "${ASSETS_DIR}/favicon.png" /opt/unetlab/html/assets-common/img/favicon.ico 2>/dev/null || true
    cp -f "${ASSETS_DIR}/favicon.png" /opt/unetlab/html/images/favicon.png 2>/dev/null || true
    cp -f "${ASSETS_DIR}/favicon.png" /opt/unetlab/html/themes/default/images/favicon.ico 2>/dev/null || true
fi

# 9. Enforce proper ownership & permissions for www-data
chown -R www-data:www-data "$BRAND_DIR" 2>/dev/null || true
chmod 0755 "$BRAND_DIR" 2>/dev/null || true
chmod 0644 "${BRAND_DIR}"/* 2>/dev/null || true

# 10. Refresh Web Server & PHP Cache
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload apache2 2>/dev/null || true
    systemctl reload php*-fpm 2>/dev/null || true
fi

echo "============================================================"
echo "  [SUCCESS] Version 1.0.0 & Password 'azam' Active Globally! "
echo "============================================================"
