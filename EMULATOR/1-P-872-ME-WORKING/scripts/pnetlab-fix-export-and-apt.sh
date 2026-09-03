#!/usr/bin/env bash
# ==============================================================================
# PNETLab Lab Export & APT Sources Fix Script
# Fixes:
# 1. Conflicting repository list in /etc/apt/sources.list.d/
# 2. Missing zip / unzip utilities required for lab import/export
# 3. /opt/unetlab/html/Exports symlink and write permissions
# 4. /opt/unetlab/scripts/remove_uuid.sh recursive support for subfolders & nested labs
# ==============================================================================
set -euo pipefail

echo "=== Applying PNETLab Export & APT Sources Fix ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 1. Remove duplicate/conflicting installer repo entry
echo "[1/5] Removing duplicate/conflicting installer repository entry..."
rm -f /etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list

# 2. Update APT and install zip / unzip
echo "[2/5] Updating APT package cache and installing zip & unzip..."
apt-get update && apt-get install -y zip unzip

# 3. Create the Exports directory and link it directly into Apache DocumentRoot
echo "[3/5] Setting up /opt/unetlab/data/Exports directory and symlink..."
mkdir -p /opt/unetlab/data/Exports
ln -sfn /opt/unetlab/data/Exports /opt/unetlab/html/Exports
chown -R www-data:www-data /opt/unetlab/data/Exports /opt/unetlab/html/Exports
chmod -R 775 /opt/unetlab/data/Exports

# 4. Patch remove_uuid.sh to support subfolders and nested labs
echo "[4/5] Patching /opt/unetlab/scripts/remove_uuid.sh for recursive nested lab support..."
UUID_SCRIPT="/opt/unetlab/scripts/remove_uuid.sh"
[ -f "$UUID_SCRIPT" ] && cp "$UUID_SCRIPT" "${UUID_SCRIPT}.bak.${TIMESTAMP}"

cat << 'EOF' > "$UUID_SCRIPT"
#!/bin/bash
if [ $# -ne 1 ]; then
    echo "ERROR: wrong options given."
    exit 15
fi

if [ ! -f "$1" ]; then
    echo "ERROR: file does not exist."
    exit 15
fi

TEMP=$(mktemp -d --suffix=_unetlab)
unzip -q -o -d "$TEMP" "$1"
if [ $? -ne 0 ]; then
    rm -rf "$TEMP"
    echo "ERROR: cannot unzip file."
    exit 15
fi

find "$TEMP" -name "*.unl" -exec sed -i "s/ id=\"[0-9a-f-]\{36\}\"//g" "{}" \;

(cd "$TEMP" && zip -q -r -u "$1" .)
rm -rf "$TEMP"
exit 0
EOF
chmod +x "$UUID_SCRIPT"

# 5. Restart Apache
echo "[5/5] Restarting Apache service..."
systemctl restart apache2 || service apache2 restart || true

echo "=== [SUCCESS] Lab Export and APT sources fixed successfully! ==="
