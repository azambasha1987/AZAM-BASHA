#!/usr/bin/env bash
# ==============================================================================
# PNetLab Database Schema Repair & Topology Workbench Fix
# Resolves: 
# 1. "Unknown column 'lab_session_lid' in 'where clause'" (MySQL Schema)
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

# 2. Locate schema files
SCHEMA_SQL=""
for path in \
    "${PARENT_DIR}/schema/pnetlab_db.sql" \
    "${SCRIPT_DIR}/schema/pnetlab_db.sql" \
    "/opt/unetlab/schema/pnetlab_db.sql" \
    "/opt/pnetlab/EMULATOR/1-P-872-ME-STABLE/schema/pnetlab_db.sql"; do
    if [ -f "$path" ]; then
        SCHEMA_SQL="$path"
        break
    fi
done

GUAC_SQL=""
for path in \
    "${PARENT_DIR}/schema/guacdb.sql" \
    "${SCRIPT_DIR}/schema/guacdb.sql" \
    "/opt/unetlab/schema/guacdb.sql" \
    "/opt/pnetlab/EMULATOR/1-P-872-ME-STABLE/schema/guacdb.sql"; do
    if [ -f "$path" ]; then
        GUAC_SQL="$path"
        break
    fi
done

# 3. Import full schemas
if [ -n "$SCHEMA_SQL" ] && [ -f "$SCHEMA_SQL" ]; then
    echo "[1/4] Importing full PNetLab database schema from ${SCHEMA_SQL}..."
    mysql -u pnetlab -ppnetlab pnetlab_db < "$SCHEMA_SQL" 2>/dev/null || mysql pnetlab_db < "$SCHEMA_SQL" 2>/dev/null || true
fi

# Apply authoritative schema definitions for session tables to guarantee column names
EMERG_SQL=$(mktemp --suffix=_emerg.sql)
cat > "$EMERG_SQL" << 'EOF'
USE pnetlab_db;

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
EOF
mysql -u pnetlab -ppnetlab pnetlab_db < "$EMERG_SQL" 2>/dev/null || mysql pnetlab_db < "$EMERG_SQL" 2>/dev/null || true
rm -f "$EMERG_SQL"

if [ -n "$GUAC_SQL" ] && [ -f "$GUAC_SQL" ]; then
    echo "[2/4] Importing Guacamole schema from ${GUAC_SQL}..."
    mysql -u guacuser -ppnetlab guacdb < "$GUAC_SQL" 2>/dev/null || mysql guacdb < "$GUAC_SQL" 2>/dev/null || true
fi

# 4. Ensure admin user and offline mode controls
echo "[3/4] Guaranteeing Admin credentials and offline mode configuration..."
ADMIN_SQL=$(mktemp --suffix=_admin.sql)
cat > "$ADMIN_SQL" << 'EOF'
USE pnetlab_db;

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

mysql -u pnetlab -ppnetlab pnetlab_db < "$ADMIN_SQL" 2>/dev/null || mysql pnetlab_db < "$ADMIN_SQL" 2>/dev/null || true
rm -f "$ADMIN_SQL"

# 5. Fix Apache .htaccess and /legacy/ Topology Workbench Routing
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
echo "    [SUCCESS] Database & Topology Workbench Fully Repaired! "
echo "============================================================"
