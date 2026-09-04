#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Enterprise Branding & Logo Engine
# Completely replaces all PNetLab logos, titles, wordmarks, favicons & branding
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

echo "============================================================"
echo "       Azam Basha UI & Branding Customizer Engine           "
echo "============================================================"

# 1. Ensure Branding Data Directory & Configuration
BRAND_DIR="/opt/unetlab/data/branding"
mkdir -p "$BRAND_DIR"

cat > "${BRAND_DIR}/config.json" << 'EOF'
{
  "name": "Azam Basha",
  "login_header": "Azam Basha Network Emulation Platform",
  "hide_default_creds": false
}
EOF

# 2. Deploy Logo Assets
if [ -f "${ASSETS_DIR}/logo.png" ]; then
    cp -f "${ASSETS_DIR}/logo.png" "${BRAND_DIR}/logo.png"
    echo "  [✔] Custom branding logo deployed to ${BRAND_DIR}/logo.png"
fi

# 3. Overwrite all static stock web logos & icons
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

# 4. Enforce proper ownership & permissions for www-data
chown -R www-data:www-data "$BRAND_DIR" 2>/dev/null || true
chmod 0755 "$BRAND_DIR" 2>/dev/null || true
chmod 0644 "${BRAND_DIR}"/* 2>/dev/null || true

# 5. Refresh Web Server & PHP Cache
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload apache2 2>/dev/null || true
    systemctl reload php*-fpm 2>/dev/null || true
fi

echo "============================================================"
echo "  [SUCCESS] Azam Basha Branding & Logo Applied Globally!   "
echo "============================================================"
