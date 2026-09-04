#!/bin/bash
# fix-db-migrations.sh — re-apply the pnetlab deb's DB migrations on a box
# whose schema seed predates them. Root cause: install-noble.sh installs the
# debs (whose postinst carries these idempotent ALTERs) BEFORE pnetlab_db is
# created and seeded, so on a FRESH install they all no-op into a missing DB
# (&>/dev/null). Symptom: "Unknown column 'node_session_host' in 'field list'"
# on first node/lab use. Safe to re-run (duplicate-column errors ignored).
set -u
M() { mysql --host=localhost --user=root --password=pnetlab pnetlab_db "$@"; }

# Pre-migration backup (mirrors the pnetlab.postinst guard): snapshot labs + DB
# before touching the schema. Never blocks: the script exits 0 on any failure.
if [ -d /opt/unetlab/labs ] && [ -x /opt/unetlab/scripts/pnet-premigrate-backup.sh ] \
   && M -N -e "SELECT 1" >/dev/null 2>&1; then
    bash /opt/unetlab/scripts/pnet-premigrate-backup.sh \
        "$(dpkg-query -W -f='${Version}' pnetlab 2>/dev/null || echo manual)" \
        || echo "fix-db-migrations: pre-migration backup FAILED (continuing)" >&2
fi

if ! M -e "CREATE TABLE IF NOT EXISTS schema_version (version INT PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, description TEXT)" 2>/dev/null; then
    echo "fix-db-migrations: WARNING: could not bootstrap schema_version" >&2
else
    migration_001() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='user_max_cpu'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE users ADD COLUMN user_max_cpu INT DEFAULT NULL" 2>/dev/null; }
    migration_002() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='user_max_ram'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE users ADD COLUMN user_max_ram INT DEFAULT NULL" 2>/dev/null; }
    migration_003() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='access_days'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE users ADD COLUMN access_days VARCHAR(16) DEFAULT NULL" 2>/dev/null; }
    migration_004() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='ext_auth'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE users ADD COLUMN ext_auth VARCHAR(8) DEFAULT NULL" 2>/dev/null; }
    migration_005() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_cpu'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE node_sessions ADD COLUMN node_cpu FLOAT DEFAULT 0" 2>/dev/null; }
    migration_006() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_ram'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE node_sessions ADD COLUMN node_ram INT DEFAULT 0" 2>/dev/null; }
    migration_007() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_session_port_2nd'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE node_sessions ADD COLUMN node_session_port_2nd INT(11) DEFAULT NULL" 2>/dev/null; }
    migration_008() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_session_host'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "ALTER TABLE node_sessions ADD COLUMN node_session_host TINYINT NOT NULL DEFAULT 0" 2>/dev/null; }
    migration_009() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cluster_hosts'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "CREATE TABLE cluster_hosts (host_id TINYINT NOT NULL PRIMARY KEY, host_name VARCHAR(64) NOT NULL, host_ip VARCHAR(45) NOT NULL, host_status TINYINT NOT NULL DEFAULT 0, host_last_seen INT DEFAULT NULL, host_version VARCHAR(48) DEFAULT NULL, host_joined INT DEFAULT NULL) ENGINE=InnoDB" 2>/dev/null; }
    migration_010() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cluster_placements'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "CREATE TABLE cluster_placements (placement_lab CHAR(36) NOT NULL, placement_nid INT NOT NULL, placement_host TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (placement_lab, placement_nid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" 2>/dev/null; }
    migration_011() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='activity_log'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "CREATE TABLE activity_log (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, created_at INT UNSIGNED NOT NULL, pod INT DEFAULT NULL, username VARCHAR(150) NOT NULL, ip VARCHAR(45) DEFAULT NULL, category VARCHAR(16) NOT NULL, action VARCHAR(32) NOT NULL, lab_path VARCHAR(1024) DEFAULT NULL, lab_name VARCHAR(255) DEFAULT NULL, node_name VARCHAR(255) DEFAULT NULL, node_template VARCHAR(64) DEFAULT NULL, detail TEXT DEFAULT NULL, session_id CHAR(64) DEFAULT NULL, duration_seconds INT UNSIGNED DEFAULT NULL, PRIMARY KEY (id), KEY activity_category_time (category, created_at), KEY activity_session (session_id, action, created_at), KEY activity_created_at (created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" 2>/dev/null; }
    migration_012() { local n; n=$(M -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='password_resets'" 2>/dev/null) || return 1; [ "$n" != 0 ] || M -e "CREATE TABLE password_resets (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, token_hash CHAR(64) NOT NULL, pod INT NOT NULL, created_at INT UNSIGNED NOT NULL, expires_at INT UNSIGNED NOT NULL, used_at INT UNSIGNED DEFAULT NULL, PRIMARY KEY (id), UNIQUE KEY password_resets_token (token_hash), KEY password_resets_pod (pod, used_at), KEY password_resets_expires (expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" 2>/dev/null; }
    migrations=(migration_001 migration_002 migration_003 migration_004 migration_005 migration_006 migration_007 migration_008 migration_009 migration_010 migration_011 migration_012)
    descriptions=("users.user_max_cpu" "users.user_max_ram" "users.access_days" "users.ext_auth" "node_sessions.node_cpu" "node_sessions.node_ram" "node_sessions.node_session_port_2nd" "node_sessions.node_session_host" "cluster_hosts" "cluster_placements" "activity_log" "password_resets")
    for i in "${!migrations[@]}"; do
        version=$((i + 1))
        done_row=$(M -N -e "SELECT COUNT(*) FROM schema_version WHERE version=$version" 2>/dev/null) || { echo "fix-db-migrations: WARNING: could not inspect schema_version $version" >&2; break; }
        [ "$done_row" != 0 ] && continue
        "${migrations[$i]}" || { echo "fix-db-migrations: WARNING: migration $version failed" >&2; break; }
        M -e "INSERT INTO schema_version (version, description) VALUES ($version, '${descriptions[$i]}')" 2>/dev/null || { echo "fix-db-migrations: WARNING: could not record schema migration $version" >&2; break; }
    done
fi

echo "--- verify ---"
mysql -uroot -ppnetlab -N -e "SELECT column_name FROM information_schema.columns WHERE table_schema='pnetlab_db' AND table_name='node_sessions' AND column_name IN ('node_session_host','node_session_port_2nd','node_cpu','node_ram')" 2>/dev/null
mysql -uroot -ppnetlab -N -e "SHOW TABLES IN pnetlab_db LIKE 'cluster%'" 2>/dev/null
mysql -uroot -ppnetlab -N -e "SHOW TABLES IN pnetlab_db WHERE Tables_in_pnetlab_db IN ('activity_log','password_resets')" 2>/dev/null
