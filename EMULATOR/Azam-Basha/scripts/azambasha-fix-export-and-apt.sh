#!/usr/bin/env bash
# ==============================================================================
# PNETLab Lab Export & APT Sources Fix Script
# Fixes:
# 1. Conflicting repository list in /etc/apt/sources.list.d/
# 2. Missing zip / unzip utilities required for lab import/export
# 3. /opt/unetlab/html/Exports symlink and write permissions
# 4. /opt/unetlab/scripts/remove_uuid.sh recursive support for subfolders & nested labs
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
    echo "=== PNETLab Export & APT Diagnostic Check ==="
    echo -n "[*] Conflicting codeberg.list: "
    if [ -f /etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list ]; then
        echo "PRESENT (Needs removal)"
    else
        echo "CLEAN (None found)"
    fi

    echo -n "[*] zip / unzip tools: "
    if command -v zip &>/dev/null && command -v unzip &>/dev/null; then
        echo "INSTALLED"
    else
        echo "MISSING"
    fi

    echo -n "[*] /opt/unetlab/html/Exports symlink: "
    if [ -L /opt/unetlab/html/Exports ]; then
        echo "VALID -> $(readlink -f /opt/unetlab/html/Exports)"
    else
        echo "MISSING / NOT A SYMLINK"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Applying PNETLab Export & APT Sources Fix ==="

# 1. Remove duplicate/conflicting installer repo entry
echo "[1/5] Removing duplicate/conflicting installer repository entry..."
rm -f /etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list

# 2. Update APT and install zip / unzip if missing
echo "[2/5] Ensuring zip & unzip utilities are present..."
if ! command -v zip &>/dev/null || ! command -v unzip &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends zip unzip 2>/dev/null || true
else
    echo "      -> zip and unzip are already installed."
fi

# 3. Create the Exports directory and link it directly into Apache DocumentRoot
echo "[3/5] Setting up /opt/unetlab/data/Exports directory and symlink..."
mkdir -p /opt/unetlab/data/Exports
mkdir -p /opt/unetlab/html
ln -sfn /opt/unetlab/data/Exports /opt/unetlab/html/Exports
chown -R www-data:www-data /opt/unetlab/data/Exports /opt/unetlab/html/Exports || true
chmod -R 775 /opt/unetlab/data/Exports

# 4. Patch remove_uuid.sh to support subfolders, nested labs, and absolute target path resolution
echo "[4/5] Patching /opt/unetlab/scripts/remove_uuid.sh for recursive nested lab support..."
UUID_SCRIPT="/opt/unetlab/scripts/remove_uuid.sh"
mkdir -p "$(dirname "$UUID_SCRIPT")"
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

# Resolve absolute path before changing directory into TEMP
TARGET_ZIP="$(readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || echo "$1")"

TEMP=$(mktemp -d --suffix=_unetlab)
unzip -q -o -d "$TEMP" "$TARGET_ZIP"
if [ $? -ne 0 ]; then
    rm -rf "$TEMP"
    echo "ERROR: cannot unzip file."
    exit 15
fi

find "$TEMP" -name "*.unl" -exec sed -i "s/ id=\"[0-9a-f-]\{36\}\"//g" "{}" \;

(cd "$TEMP" && zip -q -r -u "$TARGET_ZIP" .)
rm -rf "$TEMP"
exit 0
EOF
chmod +x "$UUID_SCRIPT"

# 5. Patch Natural Ascending Sequence for Export Lists
echo "[5/6] Patching natural ascending sequence (0..9, A..Z) for export and folder lists..."

API_FOLDERS="/opt/unetlab/html/includes/api_folders.php"
if [ -f "$API_FOLDERS" ]; then
    sed -i "s/return strnatcasecmp(\$b\['name'\], \$a\['name'\]);/return strnatcasecmp(\$a\['name'\], \$b\['name'\]);/g" "$API_FOLDERS"
    sed -i "s/return strnatcasecmp(\$b\['file'\], \$a\['file'\]);/return strnatcasecmp(\$a\['file'\], \$b\['file'\]);/g" "$API_FOLDERS"
    echo "  [✔] Sorter patched in api_folders.php (Ascending 0..9, A..Z)"
fi

LABS_JS="/opt/unetlab/html/main/js/labs.js"
if [ -f "$LABS_JS" ]; then
    sed -i "s/var folders = (data\.folders || \[\])\.filter(function (f) { return f\.name !== '\.\.'; });/var folders = (data.folders || []).filter(function (f) { return f.name !== '..'; }).sort(function (a, b) { return cmpName(a.name, b.name); });/g" "$LABS_JS"
    sed -i "s/var labs = data\.labs || \[\];/var labs = (data.labs || []).slice().sort(function (a, b) { return cmpName(a.file || a.name, b.file || b.name); });/g" "$LABS_JS"
    echo "  [✔] Export dialog natural sort patched in labs.js"
fi

# 6. Restart Apache
echo "[6/6] Restarting Apache service..."
systemctl restart apache2 || service apache2 restart || true

echo "=== [SUCCESS] Lab Export and APT sources fixed successfully! ==="
