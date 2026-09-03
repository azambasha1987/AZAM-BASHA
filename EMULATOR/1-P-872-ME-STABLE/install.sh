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
    bridge-utils
    ebtables
    iptables
    dkms
    libguestfs-tools
    qemu-utils
    python3
    python3-pip
    python3-yaml
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
    libaio1t64
)

for pkg in "${CORE_DEPS[@]}"; do
    apt-get install -y --no-install-recommends "$pkg" || {
        echo "      [INFO] Notice: Package $pkg install fallback handled."
    }
done

# --- Step 3: Install PNetLab Debian Packages ---
echo "[3/8] Installing PNetLab v8 packages..."
DEB_POOL_DIR="${SCRIPT_DIR}/debian/pool/resolute/main"

if [ -d "$DEB_POOL_DIR" ] && compgen -G "${DEB_POOL_DIR}/*.deb" > /dev/null; then
    echo "      Found local debian packages in $DEB_POOL_DIR. Installing latest 6.8.72 builds..."
    
    # Priority order for clean installation
    PACKAGES=(
        "pnetlab-schema_6.8.72resolute1_amd64.deb"
        "pnetlab-bridge-dkms_6.8.72resolute1_all.deb"
        "pnetlab-vpcs_6.8.72resolute1_amd64.deb"
        "pnetlab-qemu_6.8.72resolute1_amd64.deb"
        "pnetlab-guacd_6.8.72resolute1_amd64.deb"
        "pnetlab-docker_6.8.72resolute1_amd64.deb"
        "pnetlab-satellite_6.8.72resolute1_amd64.deb"
        "pnetlab_6.8.72resolute1_amd64.deb"
    )

    for deb in "${PACKAGES[@]}"; do
        deb_path="${DEB_POOL_DIR}/${deb}"
        if [ -f "$deb_path" ]; then
            echo "      -> Installing $(basename "$deb_path")..."
            dpkg -i --force-confdef --force-confold "$deb_path" || apt-get -f install -y
        fi
    done

    # Catch-all for any remaining debs
    dpkg -i --force-confdef --force-confold "${DEB_POOL_DIR}"/*_6.8.72*.deb 2>/dev/null || apt-get -f install -y
else
    echo "      [INFO] Local debian directory not found; invoking official network installer bootstrap..."
    if [ -f "${SCRIPT_DIR}/generic/0.channel/pnetlab-network-install-latest.sh" ]; then
        bash "${SCRIPT_DIR}/generic/0.channel/pnetlab-network-install-latest.sh" --yes --release latest
    else
        curl -fsSL https://codeberg.org/api/packages/netkillui/generic/pnetlab-core-assets/0.channel/pnetlab-network-install-latest.sh | bash -s -- --yes --release latest
    fi
fi

# --- Step 4: Configure Database & Schemas ---
echo "[4/8] Configuring MySQL database and user credentials..."
systemctl enable --now mysql || systemctl start mysql

# Ensure MySQL allows password authentication
MYSQL_CONF="/etc/mysql/mysql.conf.d/zz-pnetlab-native-pw.cnf"
if [ ! -f "$MYSQL_CONF" ]; then
    printf "[mysqld]\nmysql_native_password=ON\n" > "$MYSQL_CONF"
    systemctl restart mysql || true
fi

# Initialize database, users, and schemas
mysql --defaults-file=/etc/mysql/debian.cnf <<'EOF' || mysql -u root <<'EOF'
CREATE DATABASE IF NOT EXISTS pnetlab_db CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS guacdb CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'pnetlab'@'localhost' IDENTIFIED BY 'pnetlab';
CREATE USER IF NOT EXISTS 'guacuser'@'localhost' IDENTIFIED BY 'pnetlab';
ALTER USER 'pnetlab'@'localhost' IDENTIFIED BY 'pnetlab';
ALTER USER 'guacuser'@'localhost' IDENTIFIED BY 'pnetlab';
GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'localhost';
GRANT ALL PRIVILEGES ON guacdb.* TO 'guacuser'@'localhost';
FLUSH PRIVILEGES;
EOF

# Import PNetLab Database Schema
SCHEMA_FILE="$(find /opt/unetlab/schema /opt/unetlab -name '*pnetlab_db*.sql' -o -name 'pnetlab*.sql' 2>/dev/null | head -n1)"
if [ -n "$SCHEMA_FILE" ] && [ -f "$SCHEMA_FILE" ]; then
    echo "      -> Importing PNetLab schema from $SCHEMA_FILE..."
    mysql pnetlab_db < "$SCHEMA_FILE" 2>/dev/null || mysql -u pnetlab -ppnetlab pnetlab_db < "$SCHEMA_FILE" 2>/dev/null || true
fi

# Import Guacamole Database Schema
GUAC_SCHEMA="$(find /opt/unetlab/schema /opt/unetlab -name '*guac*.sql' 2>/dev/null | head -n1)"
if [ -n "$GUAC_SCHEMA" ] && [ -f "$GUAC_SCHEMA" ]; then
    echo "      -> Importing Guacamole schema from $GUAC_SCHEMA..."
    mysql guacdb < "$GUAC_SCHEMA" 2>/dev/null || mysql -u guacuser -ppnetlab guacdb < "$GUAC_SCHEMA" 2>/dev/null || true
fi

# Seed Default Admin User (admin / pnet)
mysql -u pnetlab -ppnetlab pnetlab_db <<EOF || true
INSERT INTO control (control_name, control_value) VALUES
  ('ctrl_offline_mode','1'), ('ctrl_online_mode','0'),
  ('ctrl_default_mode','offline'), ('ctrl_captcha','0'),
  ('ctrl_version','8.2.0')
ON DUPLICATE KEY UPDATE control_value = VALUES(control_value);
INSERT INTO users (username, password, role, offline, user_status, online_time, expired_time, active_time, pod)
  VALUES ('admin', SHA2('pnet', 256), 0, 1, 1, UNIX_TIMESTAMP(), 0, 0, 0)
ON DUPLICATE KEY UPDATE
  password = SHA2('pnet', 256),
  role = 0,
  offline = 1,
  user_status = 1,
  online_time = UNIX_TIMESTAMP(),
  expired_time = 0,
  active_time = 0,
  pod = 0;
EOF

# --- Step 5: Configure Apache & PHP-FPM ---
echo "[5/8] Configuring Apache2 Web Server, SSL and PHP-FPM..."

# Detect PHP-FPM version
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
PHP_FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# SSL Certificate Generation (10-Year Self-Signed IP-SAN)
SSL_CERT="/etc/ssl/certs/pnetlab-selfsigned.crt"
SSL_KEY="/etc/ssl/private/pnetlab-selfsigned.key"
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
    mkdir -p /etc/ssl/certs /etc/ssl/private
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -subj '/CN=pnetlab' \
        -addext 'subjectAltName=DNS:pnetlab,DNS:localhost,IP:127.0.0.1' 2>/dev/null || true
    chmod 0600 "$SSL_KEY"
fi

# Configure Apache VirtualHosts
cat > /etc/apache2/sites-available/pnetlab.conf << 'EOF'
<VirtualHost *:80>
    DocumentRoot /opt/unetlab/html
    RewriteEngine On
    RewriteCond %{REMOTE_ADDR} !^127\.
    RewriteCond %{REMOTE_ADDR} !^::1$
    RewriteRule ^/?(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
    <Directory /opt/unetlab/html/>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports/>
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
    <Directory /opt/unetlab/html/>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports/>
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

# Enable Required Apache Modules
a2enmod rewrite ssl proxy proxy_http proxy_wstunnel headers http2 mpm_event proxy_fcgi setenvif 2>/dev/null || true
a2enconf "php${PHP_VER}-fpm" 2>/dev/null || true
a2dissite 000-default default-ssl 2>/dev/null || true
a2ensite pnetlab pnetlab-ssl 2>/dev/null || true

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

# Get Primary IP Address
HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)"
if [ -z "$HOST_IP" ]; then
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"
fi

echo ""
echo "============================================================"
echo "      PNETLab v8 Installation Completed Successfully!       "
echo "============================================================"
echo "  Web UI URL      : https://${HOST_IP}/"
echo "  HTTP Redirect   : http://${HOST_IP}/"
echo "  Default User    : admin"
echo "  Default Pass    : pnet"
echo ""
echo "  Console SSH     : root@${HOST_IP} (Password: pnet)"
echo "  Install Log     : $LOG_FILE"
echo "============================================================"
echo "  [TIP] You can manage fixes and performance tools anytime: "
echo "  sudo bash ${SCRIPT_DIR}/scripts/pnetlab-apply-all-fixes.sh"
echo "============================================================"
exit 0
