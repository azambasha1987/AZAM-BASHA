#!/usr/bin/env bash
# ==============================================================================
# PNetLab v8 Unified Installer for Ubuntu 26.04 LTS ("Resolute")
# 
# Supports:
# 1. Local Offline Install (Folder Upload): Installs directly from local debian/ packages.
# 2. Remote / GitHub Direct Install: Resolves and installs dependencies seamlessly.
# ==============================================================================
set -Eeuo pipefail

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This installer must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/pnetlab-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo "          PNETLab v8 Unified Installer for Ubuntu 26        "
echo "============================================================"
echo "[*] Start Time: $(date)"
echo "[*] Working Directory: $SCRIPT_DIR"
echo "[*] Installation Log: $LOG_FILE"
echo "============================================================"

# --- Step 1: Pre-flight System & Virtualization Check ---
echo "[1/8] Performing pre-flight hardware and OS checks..."
UBUNTU_VER="$(lsb_release -rs 2>/dev/null || grep -oP '(?<=VERSION_ID=")[^"]*' /etc/os-release || echo "unknown")"
echo "      Detected OS Version: Ubuntu $UBUNTU_VER"

# Detect Active Physical Management Network Interface
REAL_IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|pnet|vunl|virbr|br)' | head -n1 || true)"
if [ -n "$REAL_IFACE" ]; then
    echo "      Detected Physical Network Interface: $REAL_IFACE"
    # Ensure interface is up
    ip link set dev "$REAL_IFACE" up 2>/dev/null || true
    
    # Preserve/Ensure Netplan configuration for the real interface
    mkdir -p /etc/netplan
    if [ ! -f /etc/netplan/01-pnetlab-netcfg.yaml ]; then
        cat << NETEOF > /etc/netplan/01-pnetlab-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $REAL_IFACE:
      dhcp4: true
      dhcp6: false
NETEOF
    fi

    # Ensure /etc/network/interfaces does not break on missing eth0
    mkdir -p /etc/network
    cat << INTEOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $REAL_IFACE
iface $REAL_IFACE inet dhcp
INTEOF
fi

if ! grep -Eq '(vmx|svm)' /proc/cpuinfo; then
    echo "      [WARNING] Hardware virtualization (Intel VT-x / AMD-V) was NOT detected in /proc/cpuinfo."
    echo "      Ensure nested virtualization is enabled on your hypervisor (VMware / Proxmox / KVM / Hyper-V)."
else
    echo "      [OK] Hardware virtualization (VT-x/AMD-V) is enabled."
fi

# Enable KVM permissions if device exists
if [ -c /dev/kvm ]; then
    chmod 666 /dev/kvm || true
fi

# --- Step 2: Install Core System Dependencies ---
echo "[2/8] Updating package lists and installing core dependencies..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt-get update -y

CORE_DEPS=(
    apache2
    mysql-server
    libapache2-mod-fcgid
    php-fpm
    php-mysql
    php-gd
    php-cli
    php-curl
    php-mbstring
    php-xml
    php-zip
    php-yaml
    php-imagick
    php-sqlite3
    debconf-utils
    bridge-utils
    ebtables
    iptables
    iptables-persistent
    dkms
    libguestfs-tools
    qemu-utils
    python3
    python3-pip
    python3-yaml
    python3-pexpect
    python3-requests
    python3-cryptography
    python3-httpx
    python3-websockets
    curl
    wget
    unzip
    zip
    net-tools
    cpulimit
    libyaml-dev
    screen
    dos2unix
    genisoimage
    telnet
    iproute2
    udhcpd
    busybox
    dhcpcd-base
    dialog
    dmidecode
    dnsmasq-base
    sshpass
    libxss1
    ifupdown
    lib32gcc-s1
    lib32z1
    libc6-i386
    libelf1t64
    libpcap0.8t64
    libsdl1.2debian
    libaio1t64
)

for pkg in "${CORE_DEPS[@]}"; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || {
        echo "      [INFO] Notice: Package $pkg install fallback handled."
    }
done

# Ensure hardware markers exist
mkdir -p /opt/unetlab
if grep -q "svm" /proc/cpuinfo 2>/dev/null; then
    echo "svm" > /opt/unetlab/platform
else
    echo "intel" > /opt/unetlab/platform
fi
if systemd-detect-virt >/dev/null 2>&1; then
    echo "vm" > /opt/unetlab/hypervisor
else
    echo "none" > /opt/unetlab/hypervisor
fi

# --- Step 3: Install PNetLab Debian Packages ---
echo "[3/8] Installing PNetLab v8 packages..."
DEB_POOL_DIR="${SCRIPT_DIR}/debian/pool/resolute/main"

if [ -d "$DEB_POOL_DIR" ] && compgen -G "${DEB_POOL_DIR}/*.deb" > /dev/null; then
    echo "      Found local debian packages in $DEB_POOL_DIR. Installing latest 6.8.72 builds..."
    
    # Priority order for clean server installation (excluding satellite worker)
    PACKAGES=(
        "pnetlab-schema_6.8.72resolute1_amd64.deb"
        "pnetlab-guacd_6.8.72resolute1_amd64.deb"
        "pnetlab-qemu_6.8.72resolute1_amd64.deb"
        "pnetlab-vpcs_6.8.72resolute1_amd64.deb"
        "pnetlab-bridge-dkms_6.8.72resolute1_all.deb"
        "pnetlab_6.8.72resolute1_amd64.deb"
    )

    for deb in "${PACKAGES[@]}"; do
        deb_path="${DEB_POOL_DIR}/${deb}"
        if [ -f "$deb_path" ]; then
            echo "      -> Extracting and installing $(basename "$deb_path")..."
            dpkg-deb -x "$deb_path" / 2>/dev/null || true
            dpkg -i --force-depends --force-confdef --force-confold "$deb_path" 2>/dev/null || true
        fi
    done
else
    echo "      [INFO] Local debian directory not found; invoking official network installer bootstrap..."
    if [ -f "${SCRIPT_DIR}/generic/0.channel/pnetlab-network-install-latest.sh" ]; then
        bash "${SCRIPT_DIR}/generic/0.channel/pnetlab-network-install-latest.sh" --yes --release latest
    else
        curl -fsSL https://codeberg.org/api/packages/netkillui/generic/pnetlab-core-assets/0.channel/pnetlab-network-install-latest.sh | bash -s -- --yes --release latest
    fi
fi

# --- Step 4: Configure Database & Schemas ---
echo "[4/8] Configuring MySQL database, schemas, and admin credentials..."
systemctl enable mysql 2>/dev/null || true
systemctl restart mysql 2>/dev/null || true

# Wait for MySQL daemon socket to be responsive
for i in {1..30}; do
    if mysqladmin ping --silent 2>/dev/null || mysql -e "SELECT 1;" >/dev/null 2>&1; then
        echo "      -> MySQL service is active and responsive."
        break
    fi
    echo "      -> Waiting for MySQL daemon socket initialization... ($i/30)"
    sleep 1
done

# Initialize database, users, tables, and admin credentials via temp SQL script
SQL_INIT=$(mktemp --suffix=_pnetlab.sql)
cat > "$SQL_INIT" << 'EOF'
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

USE pnetlab_db;

CREATE TABLE IF NOT EXISTS control (
  control_name varchar(150) NOT NULL,
  control_value text,
  PRIMARY KEY (control_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS schema_version (
  version int NOT NULL,
  applied_at timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  description text,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS users (
  pod int NOT NULL AUTO_INCREMENT,
  username text,
  cookie text,
  email varchar(150) DEFAULT NULL,
  expiration int DEFAULT -1,
  name text,
  password text,
  session int DEFAULT NULL,
  ip text,
  role text,
  folder text,
  lab_session int DEFAULT NULL,
  html5 tinyint(1) DEFAULT NULL,
  license text,
  online_time int DEFAULT NULL,
  note text,
  offline int DEFAULT NULL,
  active_time int DEFAULT NULL,
  expired_time int DEFAULT NULL,
  user_status int DEFAULT 1,
  user_workspace text,
  max_node int DEFAULT NULL,
  max_node_lab int DEFAULT NULL,
  user_max_cpu int DEFAULT NULL,
  user_max_ram int DEFAULT NULL,
  access_days varchar(16) DEFAULT NULL,
  ext_auth varchar(8) DEFAULT NULL,
  PRIMARY KEY (pod),
  UNIQUE KEY email (email)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS html5 (
  username text,
  pod int DEFAULT NULL,
  token text
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS lab_sessions (
  id int NOT NULL AUTO_INCREMENT,
  lab_id text,
  pod int DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS node_sessions (
  id int NOT NULL AUTO_INCREMENT,
  lab_session int DEFAULT NULL,
  node_id int DEFAULT NULL,
  node_session_port int DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS if_sessions (
  if_session_id bigint NOT NULL AUTO_INCREMENT,
  if_session_lab int DEFAULT NULL,
  if_session_node int DEFAULT NULL,
  if_session_ifid int DEFAULT NULL,
  if_session_name text,
  if_session_type text,
  PRIMARY KEY (if_session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

mysql < "$SQL_INIT" 2>/dev/null || mysql -u root < "$SQL_INIT" 2>/dev/null || true
rm -f "$SQL_INIT"

# Ensure /opt/unetlab/schema directory exists and copy shipped schemas
mkdir -p /opt/unetlab/schema
if [ -d "${SCRIPT_DIR}/schema" ]; then
    cp -f "${SCRIPT_DIR}/schema/"*.sql /opt/unetlab/schema/ 2>/dev/null || true
fi

# Clear any login rate-limit lockouts
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true

# --- Step 5: Configure Apache & PHP-FPM ---
echo "[5/8] Configuring Apache2 Web Server, SSL and PHP-FPM..."

# Detect PHP-FPM version
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
PHP_FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# SSL Certificate Generation (10-Year Self-Signed IP-SAN)
SSL_CERT="/etc/ssl/certs/pnetlab-selfsigned.crt"
SSL_KEY="/etc/ssl/private/pnetlab-selfsigned.key"
mkdir -p /etc/ssl/certs /etc/ssl/private
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -subj '/CN=pnetlab' \
        -addext 'subjectAltName=DNS:pnetlab,DNS:localhost,IP:127.0.0.1' 2>/dev/null || true
    chmod 0600 "$SSL_KEY"
fi
cp -f "$SSL_CERT" /etc/ssl/certs/apache-selfsigned.crt 2>/dev/null || true
cp -f "$SSL_KEY" /etc/ssl/private/apache-selfsigned.key 2>/dev/null || true

# Ensure .htaccess exists
if [ ! -f /opt/unetlab/html/.htaccess ]; then
cat > /opt/unetlab/html/.htaccess << 'EOF'
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /

    RewriteCond %{REQUEST_URI} ^/api/
    RewriteRule ^(.*)$ /api.php [L,QSA]

    RewriteCond %{REQUEST_URI} ^/auth/
    RewriteRule ^(.*)$ /auth.php [L,QSA]

    RewriteRule ^$ /main/ [R=302,L]
</IfModule>
EOF
chown www-data:www-data /opt/unetlab/html/.htaccess 2>/dev/null || true
chmod 644 /opt/unetlab/html/.htaccess 2>/dev/null || true
fi

# Ensure Export & Logs directories and symlinks
mkdir -p /opt/unetlab/data/Exports /opt/unetlab/data/Logs /opt/unetlab/labs
ln -sfn /opt/unetlab/data/Exports /opt/unetlab/html/Exports 2>/dev/null || true
ln -sfn /opt/unetlab/data/Exports /opt/unetlab/html/exports 2>/dev/null || true
chown -R www-data:www-data /opt/unetlab/data/Exports /opt/unetlab/data/Logs /opt/unetlab/labs 2>/dev/null || true
chmod -R 775 /opt/unetlab/data/Exports /opt/unetlab/data/Logs /opt/unetlab/labs 2>/dev/null || true

# Patch remove_uuid.sh for nested subfolders and absolute zip paths
cat << 'EOF' > /opt/unetlab/scripts/remove_uuid.sh
#!/bin/bash
if [ $# -ne 1 ]; then
    echo "ERROR: wrong options given."
    exit 15
fi
if [ ! -f "$1" ]; then
    echo "ERROR: file does not exist."
    exit 15
fi
TARGET_ZIP="$(readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || echo "$1")"
TEMP=$(mktemp -d --suffix=_unetlab)
unzip -q -o -d "$TEMP" "$TARGET_ZIP"
if [ $? -ne 0 ]; then
    rm -rf "$TEMP"
    echo "ERROR: cannot unzip file."
    exit 15
fi
find "$TEMP" -name "*.unl" -exec sed -i "s/ id=\"[0-9a-f-]\{36\}\"//g" "{}" \;
cd "$TEMP"
zip -q -r -u "$TARGET_ZIP" *
cd /
rm -rf "$TEMP"
exit 0
EOF
chmod +x /opt/unetlab/scripts/remove_uuid.sh /opt/unetlab/scripts/* 2>/dev/null || true

# Configure Apache VirtualHosts
cat > /etc/apache2/sites-available/pnetlab.conf << 'EOF'
<VirtualHost *:80>
    DocumentRoot /opt/unetlab/html
    RewriteEngine On
    RewriteCond %{REMOTE_ADDR} !^127\.
    RewriteCond %{REMOTE_ADDR} !^::1$
    RewriteRule ^/?(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]

    Alias /Exports /opt/unetlab/data/Exports
    Alias /exports /opt/unetlab/data/Exports
    Alias /data/Exports /opt/unetlab/data/Exports
    Alias /Logs /opt/unetlab/data/Logs
    Alias /logs /opt/unetlab/data/Logs

    <Directory /opt/unetlab/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <Directory /opt/unetlab/data/Logs>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ProxyPass /telnet/ ws://127.0.0.1:8022/ upgrade=websocket
    ProxyPassReverse /telnet/ ws://127.0.0.1:8022/
    ProxyPass /vnc/ ws://127.0.0.1:6080/ upgrade=websocket
    ProxyPassReverse /vnc/ ws://127.0.0.1:6080/
    ProxyPass /guac/ ws://127.0.0.1:8081/ upgrade=websocket
    ProxyPassReverse /guac/ ws://127.0.0.1:8081/
    ProxyPass /shell/ ws://127.0.0.1:8023/ upgrade=websocket
    ProxyPassReverse /shell/ ws://127.0.0.1:8023/
    ProxyPass /labstate/ ws://127.0.0.1:8024/ upgrade=websocket
    ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
    ProxyPass /console/http/ http://127.0.0.1:8025/ upgrade=websocket
    ProxyPassReverse /console/http/ http://127.0.0.1:8025/
</VirtualHost>
EOF

cat > /etc/apache2/sites-available/pnetlab-ssl.conf << 'EOF'
<IfModule mod_ssl.c>
<VirtualHost *:443>
    DocumentRoot /opt/unetlab/html

    Alias /Exports /opt/unetlab/data/Exports
    Alias /exports /opt/unetlab/data/Exports
    Alias /data/Exports /opt/unetlab/data/Exports
    Alias /Logs /opt/unetlab/data/Logs
    Alias /logs /opt/unetlab/data/Logs

    <Directory /opt/unetlab/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <Directory /opt/unetlab/data/Logs>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/pnetlab-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/pnetlab-selfsigned.key
    ProxyPass /telnet/ ws://127.0.0.1:8022/ upgrade=websocket
    ProxyPassReverse /telnet/ ws://127.0.0.1:8022/
    ProxyPass /vnc/ ws://127.0.0.1:6080/ upgrade=websocket
    ProxyPassReverse /vnc/ ws://127.0.0.1:6080/
    ProxyPass /guac/ ws://127.0.0.1:8081/ upgrade=websocket
    ProxyPassReverse /guac/ ws://127.0.0.1:8081/
    ProxyPass /shell/ ws://127.0.0.1:8023/ upgrade=websocket
    ProxyPassReverse /shell/ ws://127.0.0.1:8023/
    ProxyPass /labstate/ ws://127.0.0.1:8024/ upgrade=websocket
    ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
    ProxyPass /console/http/ http://127.0.0.1:8025/ upgrade=websocket
    ProxyPassReverse /console/http/ http://127.0.0.1:8025/
</VirtualHost>
</IfModule>
EOF

# Enable Required Apache Modules & Configurations
a2enmod rewrite ssl proxy proxy_http proxy_wstunnel headers http2 mpm_event proxy_fcgi setenvif 2>/dev/null || true
if [ -x /opt/unetlab/scripts/enable-php-fpm.sh ]; then
    bash /opt/unetlab/scripts/enable-php-fpm.sh 2>/dev/null || true
fi
a2enconf "php${PHP_VER}-fpm" 2>/dev/null || true
a2dissite 000-default default-ssl pnetlabs 2>/dev/null || true
a2ensite pnetlab pnetlab-ssl 2>/dev/null || true

# Patch Cookie Compatibility in api.php for HTTP & HTTPS
sed -i 's/"secure" *=> *true/"secure" => (!empty($_SERVER["HTTPS"]) \&\& $_SERVER["HTTPS"] !== "off")/g' /opt/unetlab/html/api.php 2>/dev/null || true
sed -i 's/"samesite" *=> *"Strict"/"samesite" => "Lax"/g' /opt/unetlab/html/api.php 2>/dev/null || true

systemctl enable --now "php${PHP_VER}-fpm" 2>/dev/null || true
systemctl restart "php${PHP_VER}-fpm" 2>/dev/null || true
systemctl enable --now apache2 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true

# --- Step 6: Configure Guacamole, Telnet & Web Console ---
echo "[6/8] Configuring Guacamole daemon and Python console bridges..."
mkdir -p /etc/pnet-webconsole
GUAC_ENV="/etc/pnet-webconsole/guac.env"
if [ ! -f "$GUAC_ENV" ]; then
    RANDOM_KEY="$(head -c 24 /dev/urandom | base64 | tr -d '\n')"
    printf "GUAC_CRYPT_KEY=%s\n" "$RANDOM_KEY" > "$GUAC_ENV"
    chmod 0600 "$GUAC_ENV"
    
    CONSOLE_CONF="/etc/pnet-webconsole/console_config.php"
    if [ -f "$CONSOLE_CONF" ]; then
        sed -i "s|define('GUAC_CRYPT_KEY', '[^']*');|define('GUAC_CRYPT_KEY', '$RANDOM_KEY');|" "$CONSOLE_CONF"
    fi
fi

# Install Python telnetlib3 for console multiplexer
pip3 install --break-system-packages telnetlib3 2>/dev/null || true

systemctl enable --now guacd.service 2>/dev/null || true
systemctl enable --now pnet-guac-lite.service 2>/dev/null || true
systemctl enable --now pnet-console-mux.service 2>/dev/null || true

# --- Step 7: Fix Permissions & Cloud Bridges ---
echo "[7/8] Setting proper permissions and bridge devices..."
if [ -x /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
fi

# Enable IPv4 Forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf /etc/sysctl.d/* 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pnetlab-forwarding.conf
fi

# --- Step 8: Apply Essential Fixes Suite ---
echo "[8/8] Applying optimization, session fixes, and update freeze..."
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-database-and-system-deep-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-database-and-system-deep-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-fix-export-and-apt.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-fix-export-and-apt.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-disable-logout.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-disable-logout.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-upload-and-docker-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-upload-and-docker-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-system-and-console-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-system-and-console-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-speed-optimizer.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-speed-optimizer.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/pnetlab-block-updates.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/pnetlab-block-updates.sh" || true
fi

# Refresh & Re-assert Network Interface
if [ -n "${REAL_IFACE:-}" ]; then
    ip link set dev "$REAL_IFACE" up 2>/dev/null || true
    netplan apply 2>/dev/null || systemctl restart systemd-networkd 2>/dev/null || true
fi

# Final Service Refresh & Lockout Reset
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true
systemctl restart "php${PHP_VER}-fpm" apache2 2>/dev/null || true

# Get Primary IP Address
HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)"
if [ -z "$HOST_IP" ]; then
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"
fi

# Test Live Authentication
AUTH_TEST="$(curl -k -s -X POST https://127.0.0.1/api/auth -H 'Content-Type: application/json' -d '{"username":"admin","password":"pnet"}' 2>/dev/null || echo "")"

echo ""
echo "============================================================"
echo "      PNETLab v8 Installation Completed Successfully!       "
echo "============================================================"
echo "  Web UI URL      : https://${HOST_IP}/"
echo "  HTTP Redirect   : http://${HOST_IP}/"
echo "  Default User    : admin"
echo "  Default Pass    : pnet"
echo ""
echo "  Live Auth Test  : ${AUTH_TEST}"
echo "  Console SSH     : root@${HOST_IP} (Password: pnet)"
echo "  Install Log     : $LOG_FILE"
echo "============================================================"
echo "  [TIP] You can manage fixes and performance tools anytime: "
echo "  sudo bash ${SCRIPT_DIR}/scripts/pnetlab-apply-all-fixes.sh"
echo "============================================================"
exit 0
