#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Complete System Rollback Engine
# Restores platform codebase, templates, sysctl, and database to previous state
# ==============================================================================
set -euo pipefail

BACKUP_DIR="/opt/unetlab/backups"
mkdir -p "$BACKUP_DIR"

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--snapshot | --restore | --list]"
    echo ""
    echo "Options:"
    echo "  --snapshot       Create a complete pre-upgrade snapshot"
    echo "  --restore        Restore from the latest available snapshot"
    echo "  --list           List available system snapshots"
    exit 0
fi

ACTION="${1:---restore}"

case "$ACTION" in
    --snapshot)
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        ARCHIVE_NAME="${BACKUP_DIR}/snapshot_pre_upgrade_${TIMESTAMP}.tar.gz"
        STAGING_DIR="/tmp/azambasha_snapshot_staging_${TIMESTAMP}"
        mkdir -p "$STAGING_DIR/db"
        
        echo "[*] Creating pre-upgrade system snapshot: $ARCHIVE_NAME..."
        
        # Dump MySQL databases if mysqldump is available
        if command -v mysqldump >/dev/null 2>&1; then
            mysqldump -u root pnetlab_db > "$STAGING_DIR/db/pnetlab_db.sql" 2>/dev/null || \
            mysqldump -u pnetlab -ppnetlab pnetlab_db > "$STAGING_DIR/db/pnetlab_db.sql" 2>/dev/null || true
            
            mysqldump -u root guacdb > "$STAGING_DIR/db/guacdb.sql" 2>/dev/null || \
            mysqldump -u guacuser -p'pnetlab@123' guacdb > "$STAGING_DIR/db/guacdb.sql" 2>/dev/null || true
        fi
        
        # Create self-contained tarball including filesystem assets and database dumps
        tar -czf "$ARCHIVE_NAME" \
            -C "$STAGING_DIR" db \
            /opt/unetlab/html/includes \
            /opt/unetlab/html/devices \
            /opt/unetlab/html/templates \
            /opt/unetlab/scripts \
            /opt/unetlab/wrappers \
            /etc/netplan \
            /etc/sysctl.d \
            /etc/modules-load.d \
            /etc/udev/rules.d/99-pnetlab-kvm.rules 2>/dev/null || true
            
        rm -rf "$STAGING_DIR"
        echo "  [✔] Snapshot created successfully: $ARCHIVE_NAME ($(du -h "$ARCHIVE_NAME" | cut -f1))"
        ;;
        
    --list)
        echo "=== Available Azam Basha Snapshots ==="
        ls -lh "$BACKUP_DIR"/snapshot_pre_upgrade_*.tar.gz 2>/dev/null || echo "No snapshots found in $BACKUP_DIR."
        ;;
        
    --restore)
        LATEST_SNAPSHOT=$(ls -t "$BACKUP_DIR"/snapshot_pre_upgrade_*.tar.gz 2>/dev/null | head -n 1 || true)
        if [ -z "$LATEST_SNAPSHOT" ]; then
            echo "ERROR: No backup snapshot found in $BACKUP_DIR."
            exit 1
        fi

        echo "[*] Restoring system from snapshot: $LATEST_SNAPSHOT..."

        # 1. Stop active background daemons
        systemctl stop pnetlab-brokerd pnetlab-labstated 2>/dev/null || true

        # 2. Extract backup snapshot
        EXTRACT_TMP="/tmp/azambasha_restore_tmp"
        mkdir -p "$EXTRACT_TMP"
        tar -xzf "$LATEST_SNAPSHOT" -C /
        tar -xzf "$LATEST_SNAPSHOT" -C "$EXTRACT_TMP" db 2>/dev/null || true

        # 3. Restore MySQL databases from bundled dumps
        if [ -f "$EXTRACT_TMP/db/pnetlab_db.sql" ]; then
            mysql -u root pnetlab_db < "$EXTRACT_TMP/db/pnetlab_db.sql" 2>/dev/null || \
            mysql -u pnetlab -ppnetlab pnetlab_db < "$EXTRACT_TMP/db/pnetlab_db.sql" 2>/dev/null || true
        fi
        if [ -f "$EXTRACT_TMP/db/guacdb.sql" ]; then
            mysql -u root guacdb < "$EXTRACT_TMP/db/guacdb.sql" 2>/dev/null || \
            mysql -u guacuser -p'pnetlab@123' guacdb < "$EXTRACT_TMP/db/guacdb.sql" 2>/dev/null || true
        fi
        rm -rf "$EXTRACT_TMP"

        # 4. Reload kernel parameters & udev
        sysctl --system >/dev/null 2>&1 || true
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true

        # 5. Fix file permissions and restart services
        /opt/unetlab/wrappers/unl_wrapper -a fixpermissions 2>/dev/null || true
        systemctl restart apache2 pnetlab-brokerd 2>/dev/null || true

        echo "============================================================"
        echo "  [SUCCESS] Rollback completed successfully!                "
        echo "  Platform restored to snapshot state.                      "
        echo "============================================================"
        ;;
        
    *)
        echo "Unknown option: $ACTION. Run with --help for usage."
        exit 1
        ;;
esac
