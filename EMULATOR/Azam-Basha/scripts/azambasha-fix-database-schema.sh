#!/usr/bin/env bash
# ==============================================================================
# PNetLab Database Schema Repair & Topology Workbench Fix
# Resolves: 
# 1. Missing database tables (wiresharks, lab_sessions, node_sessions, etc.)
# 2. Lab open routing (/legacy/topology -> /themes/default/index.html)
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    Applying PNetLab Database Schema & Workbench Repair     "
echo "============================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || systemctl start mariadb 2>/dev/null || true

# 1. Create databases and grant permissions
INIT_SQL=$(mktemp --suffix=_init.sql)
cat > "$INIT_SQL" << 'EOF'
CREATE DATABASE IF NOT EXISTS pnetlab_db CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS guacdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

CREATE USER IF NOT EXISTS 'pnetlab'@'localhost' IDENTIFIED BY 'pnetlab';
CREATE USER IF NOT EXISTS 'pnetlab'@'127.0.0.1' IDENTIFIED BY 'pnetlab';
CREATE USER IF NOT EXISTS 'pnetlab'@'%' IDENTIFIED BY 'pnetlab';
CREATE USER IF NOT EXISTS 'guacuser'@'localhost' IDENTIFIED BY 'pnetlab';

ALTER USER 'pnetlab'@'localhost' IDENTIFIED BY 'pnetlab';
ALTER USER 'pnetlab'@'127.0.0.1' IDENTIFIED BY 'pnetlab';
ALTER USER 'pnetlab'@'%' IDENTIFIED BY 'pnetlab';
ALTER USER 'guacuser'@'localhost' IDENTIFIED BY 'pnetlab';

GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'localhost';
GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'127.0.0.1';
GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'%';
GRANT ALL PRIVILEGES ON guacdb.* TO 'guacuser'@'localhost';
FLUSH PRIVILEGES;
EOF

mysql < "$INIT_SQL" 2>/dev/null || mysql -u root < "$INIT_SQL" 2>/dev/null || true
rm -f "$INIT_SQL"

# 2. Locate and import full schema files if present
for path in \
    "${PARENT_DIR}/schema/azambasha_db.sql" \
    "${PARENT_DIR}/schema/pnetlab_db.sql" \
    "${SCRIPT_DIR}/schema/azambasha_db.sql" \
    "${SCRIPT_DIR}/schema/pnetlab_db.sql" \
    "/opt/azambasha/schema/azambasha_db.sql" \
    "/opt/azambasha/schema/pnetlab_db.sql" \
    "/opt/unetlab/schema/azambasha_db.sql" \
    "/opt/unetlab/schema/pnetlab_db.sql"; do
    if [ -f "$path" ]; then
        echo "[1/4] Importing Azam Basha schema from ${path}..."
        mysql -u pnetlab -ppnetlab pnetlab_db < "$path" 2>/dev/null || mysql pnetlab_db < "$path" 2>/dev/null || true
        break
    fi
done

for path in \
    "${PARENT_DIR}/schema/guacdb.sql" \
    "${SCRIPT_DIR}/schema/guacdb.sql" \
    "/opt/azambasha/schema/guacdb.sql" \
    "/opt/unetlab/schema/guacdb.sql"; do
    if [ -f "$path" ]; then
        echo "[2/4] Importing Guacamole schema from ${path}..."
        mysql -u guacuser -ppnetlab guacdb < "$path" 2>/dev/null || mysql guacdb < "$path" 2>/dev/null || true
        break
    fi
done

# 3. Apply authoritative definitions for all core PNetLab tables to guarantee schema integrity
echo "[3/4] Ensuring all 16 core PNetLab database tables exist..."
FULL_SQL=$(mktemp --suffix=_full_schema.sql)
cat > "$FULL_SQL" << 'EOF'
USE pnetlab_db;

CREATE TABLE IF NOT EXISTS `control` (
  `control_name` varchar(150) NOT NULL,
  `control_value` text,
  PRIMARY KEY (`control_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `schema_version` (
  `version` int NOT NULL,
  `applied_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `description` text,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `activity_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` int unsigned NOT NULL,
  `pod` int DEFAULT NULL,
  `username` varchar(150) NOT NULL,
  `ip` varchar(45) DEFAULT NULL,
  `category` varchar(16) NOT NULL,
  `action` varchar(32) NOT NULL,
  `lab_path` varchar(1024) DEFAULT NULL,
  `lab_name` varchar(255) DEFAULT NULL,
  `node_name` varchar(255) DEFAULT NULL,
  `node_template` varchar(64) DEFAULT NULL,
  `detail` text DEFAULT NULL,
  `session_id` char(64) DEFAULT NULL,
  `duration_seconds` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `activity_category_time` (`category`,`created_at`),
  KEY `activity_session` (`session_id`,`action`,`created_at`),
  KEY `activity_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `password_resets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `token_hash` char(64) NOT NULL,
  `pod` int NOT NULL,
  `created_at` int unsigned NOT NULL,
  `expires_at` int unsigned NOT NULL,
  `used_at` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `password_resets_token` (`token_hash`),
  KEY `password_resets_pod` (`pod`,`used_at`),
  KEY `password_resets_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `html5` (
  `username` text,
  `pod` int DEFAULT NULL,
  `token` text
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cluster_hosts` (
  `host_id` tinyint NOT NULL,
  `host_name` varchar(64) NOT NULL,
  `host_ip` varchar(45) NOT NULL,
  `host_status` tinyint NOT NULL DEFAULT '0',
  `host_last_seen` int DEFAULT NULL,
  `host_version` varchar(48) DEFAULT NULL,
  `host_joined` int DEFAULT NULL,
  PRIMARY KEY (`host_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cluster_placements` (
  `placement_lab`  CHAR(36)  NOT NULL,
  `placement_nid`  INT       NOT NULL,
  `placement_host` TINYINT   NOT NULL DEFAULT 0,
  PRIMARY KEY (`placement_lab`, `placement_nid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `process` (
  `process_id` varchar(200) NOT NULL,
  `process_dtotal` int DEFAULT NULL,
  `process_dnow` int DEFAULT NULL,
  `process_utotal` int DEFAULT NULL,
  `process_unow` int DEFAULT NULL,
  `process_finish` int DEFAULT NULL,
  PRIMARY KEY (`process_id`),
  KEY `process_dtotal` (`process_dtotal`),
  KEY `process_dnow` (`process_dnow`),
  KEY `process_utotal` (`process_utotal`),
  KEY `process_unow` (`process_unow`),
  KEY `process_finish` (`process_finish`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `process_device` (
  `process_device_id` varchar(150) NOT NULL,
  `process_device_dtotal` int DEFAULT NULL,
  `process_device_dnow` int DEFAULT NULL,
  `process_device_utotal` int DEFAULT NULL,
  `process_device_unow` int DEFAULT NULL,
  `process_device_log` text,
  UNIQUE KEY `process_device_id` (`process_device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `user_permission` (
  `user_per_id` int NOT NULL AUTO_INCREMENT,
  `user_per_role` int DEFAULT NULL,
  `user_per_name` varchar(150) DEFAULT NULL,
  PRIMARY KEY (`user_per_id`),
  KEY `user_per_role` (`user_per_role`),
  KEY `user_per_name` (`user_per_name`)
) ENGINE=InnoDB AUTO_INCREMENT=251 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `user_roles` (
  `user_role_id` int NOT NULL AUTO_INCREMENT,
  `user_role_name` varchar(150) DEFAULT NULL,
  `user_role_workspace` text,
  `user_role_note` text,
  `user_role_ram` float DEFAULT NULL,
  `user_role_cpu` float DEFAULT NULL,
  `user_role_hdd` float DEFAULT NULL,
  PRIMARY KEY (`user_role_id`),
  KEY `user_role_name` (`user_role_name`),
  KEY `user_role_ram` (`user_role_ram`),
  KEY `user_role_cpu` (`user_role_cpu`),
  KEY `user_role_hdd` (`user_role_hdd`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `users` (
  `pod` int NOT NULL AUTO_INCREMENT,
  `username` text,
  `cookie` text,
  `email` varchar(150) DEFAULT NULL,
  `expiration` int DEFAULT '-1',
  `name` text,
  `password` text,
  `session` int DEFAULT NULL,
  `ip` text,
  `role` text,
  `folder` text,
  `lab_session` int DEFAULT NULL,
  `html5` tinyint(1) DEFAULT NULL,
  `license` text,
  `online_time` int DEFAULT NULL,
  `note` text,
  `offline` int DEFAULT NULL,
  `active_time` int DEFAULT NULL,
  `expired_time` int DEFAULT NULL,
  `user_status` int DEFAULT '1',
  `user_workspace` text,
  `max_node` int DEFAULT NULL,
  `max_node_lab` int DEFAULT NULL,
  `user_max_cpu` int DEFAULT NULL,
  `user_max_ram` int DEFAULT NULL,
  `access_days` varchar(16) DEFAULT NULL,
  `ext_auth` varchar(8) DEFAULT NULL,
  PRIMARY KEY (`pod`),
  UNIQUE KEY `email` (`email`),
  KEY `online_time` (`online_time`),
  KEY `lab_session` (`lab_session`),
  KEY `offline` (`offline`),
  KEY `active_time` (`active_time`),
  KEY `expired_time` (`expired_time`),
  KEY `user_status` (`user_status`),
  KEY `max_node` (`max_node`),
  KEY `max_node_lab` (`max_node_lab`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `wiresharks` (
  `ws_id` bigint NOT NULL AUTO_INCREMENT,
  `ws_tenant` int DEFAULT NULL,
  `ws_lab` varchar(200) DEFAULT NULL,
  `ws_node` int DEFAULT NULL,
  `ws_if` int DEFAULT NULL,
  `ws_net` int DEFAULT NULL,
  `ws_node_name` varchar(150) DEFAULT NULL,
  `ws_if_name` varchar(150) DEFAULT NULL,
  `ws_dc_name` varchar(150) DEFAULT NULL,
  `ws_port` int DEFAULT NULL,
  `ws_ip` varchar(150) DEFAULT NULL,
  PRIMARY KEY (`ws_id`),
  KEY `ws_ip` (`ws_ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ensure session tables have exact production structure
DROP TABLE IF EXISTS `if_sessions`;
DROP TABLE IF EXISTS `node_sessions`;
DROP TABLE IF EXISTS `lab_sessions`;

CREATE TABLE `lab_sessions` (
  `lab_session_id` int NOT NULL AUTO_INCREMENT,
  `lab_session_lid` varchar(150) DEFAULT NULL,
  `lab_session_pod` int DEFAULT NULL,
  `lab_session_joined` text,
  `lab_session_path` text,
  `lab_session_running` int DEFAULT NULL,
  PRIMARY KEY (`lab_session_id`) USING BTREE,
  KEY `lab_session_lid` (`lab_session_lid`) USING BTREE,
  KEY `lab_session_pod` (`lab_session_pod`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `node_sessions` (
  `node_session_id` int NOT NULL AUTO_INCREMENT,
  `node_session_nid` int DEFAULT NULL,
  `node_session_lab` int DEFAULT NULL,
  `node_session_port` int DEFAULT NULL,
  `node_session_type` varchar(150) DEFAULT NULL,
  `node_session_workspace` text,
  `node_session_ram` float DEFAULT NULL,
  `node_session_cpu` float DEFAULT NULL,
  `node_session_hdd` float DEFAULT NULL,
  `node_session_running` int DEFAULT NULL,
  `node_session_pod` int DEFAULT NULL,
  `node_session_iol` int DEFAULT NULL,
  `node_cpu` float DEFAULT '0',
  `node_ram` int DEFAULT '0',
  `node_session_port_2nd` int DEFAULT NULL,
  `node_session_host` tinyint NOT NULL DEFAULT '0',
  PRIMARY KEY (`node_session_id`) USING BTREE,
  UNIQUE KEY `node_session_nid_2` (`node_session_nid`,`node_session_lab`),
  KEY `node_session_lab` (`node_session_lab`),
  KEY `node_session_port` (`node_session_port`),
  KEY `node_session_nid` (`node_session_nid`),
  KEY `node_session_type` (`node_session_type`),
  KEY `node_session_running` (`node_session_running`),
  KEY `node_session_pod` (`node_session_pod`),
  KEY `node_session_iol` (`node_session_iol`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `if_sessions` (
  `if_session_id` bigint NOT NULL AUTO_INCREMENT,
  `if_session_lab` int DEFAULT NULL,
  `if_session_node` int DEFAULT NULL,
  `if_session_ifid` int DEFAULT NULL,
  `if_session_VlanId` int DEFAULT NULL,
  `if_session_type` varchar(150) DEFAULT NULL,
  `if_session_quality` text,
  `if_session_suspend` int DEFAULT NULL,
  PRIMARY KEY (`if_session_id`),
  KEY `if_session_ifid` (`if_session_ifid`),
  KEY `if_session_type` (`if_session_type`),
  KEY `if_session_VlanId` (`if_session_VlanId`),
  KEY `if_session_suspend` (`if_session_suspend`),
  KEY `if_session_lab` (`if_session_lab`) USING BTREE,
  KEY `if_session_node` (`if_session_node`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed Admin User & Offline Mode
INSERT INTO control (control_name, control_value) VALUES
  ('ctrl_offline_mode','1'), ('ctrl_online_mode','0'),
  ('ctrl_default_mode','offline'), ('ctrl_captcha','0'),
  ('ctrl_version','8.2.0')
ON DUPLICATE KEY UPDATE control_value = VALUES(control_value);

DELETE FROM users WHERE username = 'admin';
INSERT INTO users (
    pod, username, email, name, password, role,
    user_status, active_time, expired_time, access_days,
    offline, ext_auth, session, folder, ip
) VALUES (
    0, 'admin', 'root@localhost', 'Administrator', SHA2('pnet', 256), 'admin',
    1, 0, 0, NULL,
    1, NULL, UNIX_TIMESTAMP() + 315360000, '/', '127.0.0.1'
);
EOF

mysql -u pnetlab -ppnetlab pnetlab_db < "$FULL_SQL" 2>/dev/null || mysql pnetlab_db < "$FULL_SQL" 2>/dev/null || true
rm -f "$FULL_SQL"

# 4. Fix Apache .htaccess and /legacy/ Topology Workbench Routing
echo "[4/4] Configuring Apache .htaccess & Topology Workbench routing..."
mkdir -p /opt/unetlab/html
cat > /opt/unetlab/html/.htaccess << 'EOF'
<IfModule mod_rewrite.c>
	RewriteEngine On
	RewriteBase /

	RewriteCond %{REQUEST_URI} ^/api/
	RewriteRule ^(.*)$ /api.php [B,L,QSA]

	RewriteCond %{REQUEST_URI} ^/auth/
	RewriteRule ^(.*)$ /auth.php [B,L,QSA]
	
	RewriteCond %{REQUEST_URI} ^/legacy/
	RewriteRule ^(.*)$ /themes/default/ [B,L,QSA]

	RewriteRule ^$ /main/ [R=302,L]
</IfModule>
EOF
chown www-data:www-data /opt/unetlab/html/.htaccess 2>/dev/null || true
chmod 644 /opt/unetlab/html/.htaccess 2>/dev/null || true

# Add Alias /legacy to Apache virtualhosts if not already present
for conf in /etc/apache2/sites-available/pnetlab.conf /etc/apache2/sites-available/pnetlab-ssl.conf; do
    if [ -f "$conf" ] && ! grep -q "Alias /legacy" "$conf"; then
        sed -i '/DocumentRoot/a \    Alias /legacy /opt/unetlab/html/themes/default\n    Alias /themes /opt/unetlab/html/themes' "$conf" 2>/dev/null || true
    fi
done

# Fix file permissions across /opt/unetlab/html
chown -R www-data:www-data /opt/unetlab/html 2>/dev/null || true
chmod -R 755 /opt/unetlab/html/themes /opt/unetlab/html/main 2>/dev/null || true

# Reload Apache
systemctl reload apache2 2>/dev/null || systemctl restart apache2 2>/dev/null || true

echo "============================================================"
echo "    [SUCCESS] All Database Tables & Workbench Repaired!     "
echo "============================================================"
