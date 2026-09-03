#!/usr/bin/env bash
# ==============================================================================
# PNETLab Automated Backup & Restore Utility
# Backs up & Restores:
# 1. PNETLab Labs directory (/opt/unetlab/labs)
# 2. MySQL database dump (pnetlab_db: users, labs, configs)
# 3. AI configuration & bridge secrets (/opt/unetlab/data/ai)
# 4. Custom device templates (/opt/unetlab/html/templates)
#
# Supports piped execution & non-root help.
# ==============================================================================
set -euo pipefail

# Support non-root help mode
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [backup | restore <BACKUP_FILE> | list]"
    echo ""
    echo "Commands:"
    echo "  backup                  Create a full timestamped backup archive"
    echo "  restore <BACKUP_FILE>   Restore database, labs, and configurations from an archive"
    echo "  list                    List all existing backup archives in /opt/unetlab/data/Backups"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

BACKUP_DIR="/opt/unetlab/data/Backups"
mkdir -p "$BACKUP_DIR"

COMMAND="${1:-backup}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

case "$COMMAND" in
    backup)
        echo "============================================================"
        echo "             PNETLab Appliance Backup Utility               "
        echo "============================================================"
        BACKUP_FILE="${BACKUP_DIR}/pnetlab_backup_${TIMESTAMP}.tar.gz"
        TEMP_DIR=$(mktemp -d --suffix=_pnetlab_backup)

        echo "[1/4] Dumping PNETLab MySQL database..."
        DB_DUMP="${TEMP_DIR}/pnetlab_db.sql"
        if mysql -u pnetlab -ppnetlab -e "USE pnetlab_db;" >/dev/null 2>&1; then
            mysqldump -u pnetlab -ppnetlab pnetlab_db > "$DB_DUMP" 2>/dev/null || true
        elif [ -f /etc/mysql/debian.cnf ] && mysql --defaults-file=/etc/mysql/debian.cnf -e "USE pnetlab_db;" >/dev/null 2>&1; then
            mysqldump --defaults-file=/etc/mysql/debian.cnf pnetlab_db > "$DB_DUMP" 2>/dev/null || true
        elif mysql -u root -e "USE pnetlab_db;" >/dev/null 2>&1; then
            mysqldump -u root pnetlab_db > "$DB_DUMP" 2>/dev/null || true
        else
            echo "Warning: Database dump skipped (could not connect to MySQL)."
        fi

        echo "[2/4] Archiving lab topology files (/opt/unetlab/labs)..."
        if [ -d /opt/unetlab/labs ]; then
            cp -r /opt/unetlab/labs "${TEMP_DIR}/labs"
        fi

        echo "[3/4] Archiving AI configuration & custom templates..."
        if [ -d /opt/unetlab/data/ai ]; then
            cp -r /opt/unetlab/data/ai "${TEMP_DIR}/ai"
        fi
        if [ -d /opt/unetlab/html/templates ]; then
            cp -r /opt/unetlab/html/templates "${TEMP_DIR}/templates" 2>/dev/null || true
        fi

        echo "[4/4] Creating compressed archive: $(basename "$BACKUP_FILE")..."
        (cd "$TEMP_DIR" && tar -czf "$BACKUP_FILE" .)
        rm -rf "$TEMP_DIR"
        chmod 640 "$BACKUP_FILE"

        BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
        echo ""
        echo "=== [SUCCESS] Backup created successfully! ==="
        echo "File: $BACKUP_FILE ($BACKUP_SIZE)"
        ;;

    restore)
        ARCHIVE="${2:-}"
        if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
            echo "[ERROR] Please specify a valid backup file to restore."
            echo "Example: sudo bash $0 restore /opt/unetlab/data/Backups/pnetlab_backup_YYYYMMDD_HHMMSS.tar.gz"
            exit 1
        fi

        echo "============================================================"
        echo "             PNETLab Appliance Restore Utility              "
        echo "============================================================"
        echo "[*] Restoring from: $ARCHIVE"
        TEMP_DIR=$(mktemp -d --suffix=_pnetlab_restore)
        tar -xzf "$ARCHIVE" -C "$TEMP_DIR"

        echo "[1/3] Restoring lab topologies..."
        if [ -d "${TEMP_DIR}/labs" ]; then
            cp -rn "${TEMP_DIR}/labs/." /opt/unetlab/labs/
            chown -R www-data:www-data /opt/unetlab/labs
        fi

        echo "[2/3] Restoring configurations and templates..."
        if [ -d "${TEMP_DIR}/ai" ]; then
            cp -rn "${TEMP_DIR}/ai/." /opt/unetlab/data/ai/
            chown -R root:pnetlab-mcp /opt/unetlab/data/ai
        fi
        if [ -d "${TEMP_DIR}/templates" ]; then
            cp -rn "${TEMP_DIR}/templates/." /opt/unetlab/html/templates/ 2>/dev/null || true
        fi

        echo "[3/3] Restoring database records..."
        if [ -f "${TEMP_DIR}/pnetlab_db.sql" ]; then
            if mysql -u pnetlab -ppnetlab -e "USE pnetlab_db;" >/dev/null 2>&1; then
                mysql -u pnetlab -ppnetlab pnetlab_db < "${TEMP_DIR}/pnetlab_db.sql" 2>/dev/null || true
            elif [ -f /etc/mysql/debian.cnf ] && mysql --defaults-file=/etc/mysql/debian.cnf -e "USE pnetlab_db;" >/dev/null 2>&1; then
                mysql --defaults-file=/etc/mysql/debian.cnf pnetlab_db < "${TEMP_DIR}/pnetlab_db.sql" 2>/dev/null || true
            fi
        fi

        rm -rf "$TEMP_DIR"
        systemctl restart apache2 || service apache2 restart || true
        echo ""
        echo "=== [SUCCESS] Restore completed successfully! ==="
        ;;

    list)
        echo "=== Existing PNETLab Backups in $BACKUP_DIR ==="
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found."
        ;;

    *)
        echo "Invalid command: $COMMAND"
        echo "Usage: sudo bash $0 [backup | restore <FILE> | list]"
        exit 1
        ;;
esac
