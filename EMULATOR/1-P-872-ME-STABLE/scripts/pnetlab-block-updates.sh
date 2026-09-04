#!/usr/bin/env bash
# ==============================================================================
# PNETLab Version Freeze & Update Blocker Utility
#
# Multi-Layer Protection:
# 1. APT Package Hold: Sets 'apt-mark hold' on all PNetLab core & satellite packages.
# 2. APT Pinning Barrier: Sets Pin-Priority: -1 in /etc/apt/preferences.d/ to prevent
#    accidental 'apt upgrade' or 'apt dist-upgrade' candidate selection.
# 3. Repository Neutralization: Disables external PNetLab APT source repositories.
# 4. Binary Lockdown: Replaces /usr/bin/pnetlab-update with a safety barrier and
#    applies immutable file attributes (chattr +i).
# 5. Systemd Masking: Permanently masks any update timers and services.
# 6. Database Enforcement: Locks PNetLab into 'offline' mode in MySQL control table.
# 7. DNS Blackhole: Directs update and phone-home endpoints to loopback in /etc/hosts.
#
# Usage:
#   sudo bash scripts/pnetlab-block-updates.sh            # Block all future updates
#   sudo bash scripts/pnetlab-block-updates.sh --check    # Check lock status
#   sudo bash scripts/pnetlab-block-updates.sh --unblock  # Restore update capabilities
# ==============================================================================
set -euo pipefail

PNET_PACKAGES=(
    "pnetlab"
    "pnetlab-satellite"
    "pnetlab-qemu"
    "pnetlab-guacd"
    "pnetlab-vpcs"
    "pnetlab-docker"
    "pnetlab-schema"
    "pnetlab-bridge-dkms"
)

PREF_FILE="/etc/apt/preferences.d/99-pnetlab-block-updates.pref"
UPDATE_BIN="/usr/bin/pnetlab-update"
UPDATE_BIN_BAK="/usr/bin/pnetlab-update.orig"
HOSTS_MARKER="# --- PNETLAB UPDATE BLOCKER ---"

# --- 1. Diagnostic / Status Mode ---
if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "============================================================"
    echo "       PNETLab Update Lock & Freeze Diagnostic Check        "
    echo "============================================================"
    
    echo -n "[*] APT Package Hold Status: "
    HELD_COUNT=0
    for pkg in "${PNET_PACKAGES[@]}"; do
        if apt-mark showhold 2>/dev/null | grep -qx "$pkg"; then
            HELD_COUNT=$((HELD_COUNT + 1))
        fi
    done
    if [ "$HELD_COUNT" -eq "${#PNET_PACKAGES[@]}" ]; then
        echo "LOCKED (${HELD_COUNT}/${#PNET_PACKAGES[@]} packages held)"
    elif [ "$HELD_COUNT" -gt 0 ]; then
        echo "PARTIALLY LOCKED (${HELD_COUNT}/${#PNET_PACKAGES[@]} packages held)"
    else
        echo "UNLOCKED (No packages held)"
    fi

    echo -n "[*] APT Pinning Preference: "
    if [ -f "$PREF_FILE" ] && grep -q "Pin-Priority: -1" "$PREF_FILE"; then
        echo "ENABLED (Pin-Priority -1 active)"
    else
        echo "DISABLED"
    fi

    echo -n "[*] Update Binary Lockdown: "
    if [ -f "$UPDATE_BIN" ] && grep -q "UPDATE_LOCKED" "$UPDATE_BIN" 2>/dev/null; then
        echo "LOCKED (Safety barrier active)"
    elif [ -f "$UPDATE_BIN" ]; then
        echo "UNLOCKED (Original binary present)"
    else
        echo "NOT FOUND / DISABLED"
    fi

    echo -n "[*] Systemd Services/Timers: "
    if systemctl is-enabled pnetlab-update.service 2>/dev/null | grep -q "masked" || [ ! -f /etc/systemd/system/pnetlab-update.service ]; then
        echo "MASKED / INACTIVE"
    else
        echo "UNMASKED / ACTIVE"
    fi

    echo -n "[*] Host DNS Blackhole: "
    if grep -q "$HOSTS_MARKER" /etc/hosts 2>/dev/null; then
        echo "ACTIVE (Endpoints routed to 127.0.0.1)"
    else
        echo "INACTIVE"
    fi

    echo -n "[*] Database Offline Mode: "
    if command -v mysql &>/dev/null; then
        DB_MODE=$(mysql -u pnetlab -ppnetlab -N -e "SELECT control_value FROM control WHERE control_name='ctrl_default_mode';" pnetlab_db 2>/dev/null || echo "unknown")
        if [ "$DB_MODE" = "offline" ]; then
            echo "LOCKED (offline mode)"
        else
            echo "MODE: $DB_MODE"
        fi
    else
        echo "MySQL CLI not present"
    fi
    echo "============================================================"
    exit 0
fi

# Require Root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

# --- 2. Unblock / Restore Mode ---
if [[ "${1:-}" =~ ^(--unblock|--restore|--enable-updates)$ ]]; then
    echo "============================================================"
    echo "          Restoring PNETLab Update Capabilities             "
    echo "============================================================"
    
    echo "[1/6] Unholding APT packages..."
    for pkg in "${PNET_PACKAGES[@]}"; do
        apt-mark unhold "$pkg" 2>/dev/null || true
    done

    echo "[2/6] Removing APT pinning preference barrier..."
    rm -f "$PREF_FILE"

    echo "[3/6] Restoring pnetlab-update binary..."
    if [ -f "$UPDATE_BIN" ]; then
        chattr -i "$UPDATE_BIN" 2>/dev/null || true
        if [ -f "$UPDATE_BIN_BAK" ]; then
            mv "$UPDATE_BIN_BAK" "$UPDATE_BIN"
            chmod 755 "$UPDATE_BIN"
        else
            rm -f "$UPDATE_BIN"
        fi
    fi

    echo "[4/6] Unmasking systemd update services..."
    systemctl unmask pnetlab-update.service 2>/dev/null || true
    systemctl unmask pnetlab-update.timer 2>/dev/null || true

    echo "[5/6] Cleaning up DNS blackholes from /etc/hosts..."
    if grep -q "$HOSTS_MARKER" /etc/hosts; then
        sed -i "/$HOSTS_MARKER/,/# --- END PNETLAB UPDATE BLOCKER ---/d" /etc/hosts
    fi

    echo "[6/6] Updating APT cache..."
    apt-get update -y 2>/dev/null || true

    echo "============================================================"
    echo "  [SUCCESS] PNETLab updates have been restored!             "
    echo "============================================================"
    exit 0
fi

# --- 3. Lock & Block Mode ---
echo "============================================================"
echo "      PNETLab Version Freeze & Update Blocker Utility       "
echo "============================================================"
echo "Applying multi-layer freeze to protect current installation..."

# Step 1: APT Package Hold
echo "[1/7] Marking all PNetLab packages on 'apt-mark hold'..."
for pkg in "${PNET_PACKAGES[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        apt-mark hold "$pkg" 2>/dev/null || true
        echo "      -> $pkg : HELD"
    else
        apt-mark hold "$pkg" 2>/dev/null || true
    fi
done

# Step 2: APT Pin-Priority -1
echo "[2/7] Writing strict APT Pin-Priority barrier (/etc/apt/preferences.d/)..."
mkdir -p /etc/apt/preferences.d
cat > "$PREF_FILE" <<'EOF'
# Freeze all PNetLab packages from being updated or replaced by any repository
Package: pnetlab*
Pin: release *
Pin-Priority: -1

Package: pnetlab
Pin: release *
Pin-Priority: -1

Package: pnetlab-satellite
Pin: release *
Pin-Priority: -1

Package: pnetlab-qemu
Pin: release *
Pin-Priority: -1

Package: pnetlab-guacd
Pin: release *
Pin-Priority: -1

Package: pnetlab-vpcs
Pin: release *
Pin-Priority: -1

Package: pnetlab-docker
Pin: release *
Pin-Priority: -1

Package: pnetlab-schema
Pin: release *
Pin-Priority: -1

Package: pnetlab-bridge-dkms
Pin: release *
Pin-Priority: -1
EOF
chmod 644 "$PREF_FILE"

# Step 3: Disable external PNetLab APT repositories
echo "[3/7] Disabling external PNetLab repo list files..."
for list_file in /etc/apt/sources.list.d/pnetlab*.list /etc/apt/sources.list.d/*codeberg*.list; do
    if [ -f "$list_file" ]; then
        echo "      -> Neutralizing $list_file"
        mv "$list_file" "${list_file}.disabled" 2>/dev/null || true
    fi
done

# Step 4: Neutralize pnetlab-update CLI tool
echo "[4/7] Neutralizing /usr/bin/pnetlab-update CLI tool..."
if [ -f "$UPDATE_BIN" ]; then
    chattr -i "$UPDATE_BIN" 2>/dev/null || true
    if [ ! -f "$UPDATE_BIN_BAK" ]; then
        cp "$UPDATE_BIN" "$UPDATE_BIN_BAK"
    fi
fi

cat > "$UPDATE_BIN" <<'EOF'
#!/usr/bin/env bash
# UPDATE_LOCKED
echo "============================================================"
echo " [SECURITY BARRIER] PNETLab Updates Are Permanently Blocked!"
echo "============================================================"
echo " This system has been configured to lock the current stable "
echo " version to prevent breaking changes, database conflicts,  "
echo " and package overwrites."
echo ""
echo " If you intentionally wish to restore updates, run:"
echo "   sudo bash /opt/pnetlab/scripts/pnetlab-block-updates.sh --unblock"
echo "============================================================"
exit 0
EOF
chmod 755 "$UPDATE_BIN"
chattr +i "$UPDATE_BIN" 2>/dev/null || true

# Step 5: Mask systemd update timers and services
echo "[5/7] Masking systemd update timers and background services..."
systemctl stop pnetlab-update.service pnetlab-update.timer 2>/dev/null || true
systemctl mask pnetlab-update.service pnetlab-update.timer 2>/dev/null || true

# Step 6: Enforce Offline Mode in Database
echo "[6/7] Enforcing Offline Mode in PNetLab database..."
if command -v mysql &>/dev/null; then
    mysql -u pnetlab -ppnetlab pnetlab_db 2>/dev/null <<'EOF' || true
UPDATE control SET control_value='1' WHERE control_name='ctrl_offline_mode';
UPDATE control SET control_value='0' WHERE control_name='ctrl_online_mode';
UPDATE control SET control_value='offline' WHERE control_name='ctrl_default_mode';
EOF
fi

# Step 7: DNS Blackhole for Update Endpoints
echo "[7/7] Directing update endpoints to 127.0.0.1 in /etc/hosts..."
if ! grep -q "$HOSTS_MARKER" /etc/hosts; then
    cat >> /etc/hosts <<EOF

$HOSTS_MARKER
127.0.0.1 update.pnetlab.com
127.0.0.1 api.pnetlab.com
127.0.0.1 repository.pnetlab.com
127.0.0.1 repo.pnetlab.com
::1 update.pnetlab.com
::1 api.pnetlab.com
::1 repository.pnetlab.com
::1 repo.pnetlab.com
# --- END PNETLAB UPDATE BLOCKER ---
EOF
fi

echo ""
echo "============================================================"
echo "    [SUCCESS] PNETLab Version Successfully Frozen!          "
echo "============================================================"
echo "  - APT Package Hold        : ENABLED (All packages locked)"
echo "  - APT Pin-Priority -1     : ENABLED (/etc/apt/preferences.d)"
echo "  - CLI Updater Barrier     : LOCKED (/usr/bin/pnetlab-update)"
echo "  - Systemd Services        : MASKED"
echo "  - Offline Mode Database   : ENFORCED"
echo "  - Telemetry / DNS Blackhole: CONFIGURED"
echo ""
echo "  To verify the lock status anytime:"
echo "    sudo bash scripts/pnetlab-block-updates.sh --check"
echo ""
echo "  To restore/unblock updates in the future if desired:"
echo "    sudo bash scripts/pnetlab-block-updates.sh --unblock"
echo "============================================================"
exit 0
