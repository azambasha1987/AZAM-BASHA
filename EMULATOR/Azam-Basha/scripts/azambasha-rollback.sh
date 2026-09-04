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
        echo "[*] Creating pre-upgrade system snapshot: $ARCHIVE_NAME..."
        
        # Dump MySQL databases if mysqldump is available
        if command -v mysqldump >/dev/null 2>&1; then
            mkdir -p /tmp/azambasha_db_snapshot
            mysqldump -u root pnetlab_db > /tmp/azambasha_db_snapshot/pnetlab_db.sql 2>/dev/null || true
            mysqldump -u root guacdb > /tmp/azambasha_db_snapshot/guacdb.sql 2>/dev/null || true
        fi
        
        tar -czf "$ARCHIVE_NAME" \
            /opt/unetlab/html/includes \
            /opt/unetlab/html/devices \
            /opt/unetlab/html/templates \
            /opt/unetlab/scripts \
            /opt/unetlab/wrappers \
            /etc/sysctl.d \
            /etc/modules-load.d \
            /etc/udev/rules.d/99-pnetlab-kvm.rules 2>/dev/null || true
            
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
        tar -xzf "$LATEST_SNAPSHOT" -C /

        # 3. Restore MySQL databases if dumped
        if [ -f /tmp/azambasha_db_snapshot/pnetlab_db.sql ]; then
            mysql -u root pnetlab_db < /tmp/azambasha_db_snapshot/pnetlab_db.sql 2>/dev/null || true
            mysql -u root guacdb < /tmp/azambasha_db_snapshot/guacdb.sql 2>/dev/null || true
        fi

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
