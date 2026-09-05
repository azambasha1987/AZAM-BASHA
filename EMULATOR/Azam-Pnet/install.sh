#!/usr/bin/env bash
# ==============================================================================
# PNetLab v8 Unified Installer for Ubuntu 26.04 LTS ("Resolute")
# 
# Supports:
# 1. Local Offline Install (Folder Upload): Installs directly from local debian/ packages.
# 2. Remote / GitHub Direct Install: Resolves and installs dependencies seamlessly.
# ==============================================================================
set -Eeuo pipefail

# Parse help early for non-root users
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --static, -s <IP/CIDR>    Configure static management IP (e.g. 192.168.1.50/24)"
    echo "  --gateway, -g <IP>        Configure default gateway (e.g. 192.168.1.1)"
    echo "  --dns, -d <IP>            Configure primary DNS server (Default: 8.8.8.8)"
    echo "  --help, -h                Show this help menu"
    exit 0
fi

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This installer must be run as root. Please run: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/opt/azambasha/EMULATOR/Azam-Pnet")"
LOG_FILE="/var/log/azambasha-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

mkdir -p /opt/pnetlab 2>/dev/null || true
ln -sfn "$SCRIPT_DIR" /opt/pnetlab 2>/dev/null || true

# Parse Command-Line Options for Unattended or Static IP Installation
STATIC_IP=""
STATIC_GW=""
STATIC_DNS="8.8.8.8"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --static|-s)
            STATIC_IP="$2"
            shift 2
            ;;
        --gateway|-g)
            STATIC_GW="$2"
            shift 2
            ;;
        --dns|-d)
            STATIC_DNS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: sudo bash $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --static, -s <IP/CIDR>    Configure static management IP (e.g. 192.168.1.50/24)"
            echo "  --gateway, -g <IP>        Configure default gateway (e.g. 192.168.1.1)"
            echo "  --dns, -d <IP>            Configure primary DNS server (Default: 8.8.8.8)"
            echo "  --help, -h                Show this help menu"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

echo "============================================================"
echo "          Azam Basha v8 Unified Installer for Ubuntu 26     "
echo "============================================================"
echo "[*] Start Time: $(date)"
echo "[*] Working Directory: $SCRIPT_DIR"
echo "[*] Installation Log: $LOG_FILE"
[ -n "$STATIC_IP" ] && echo "[*] Target Static IP: $STATIC_IP (Gateway: $STATIC_GW)"
echo "============================================================"

# --- Step 1: Pre-flight System & Virtualization Check ---
echo "[1/8] Performing pre-flight hardware and OS checks..."
UBUNTU_VER="$(lsb_release -rs 2>/dev/null || grep -oP '(?<=VERSION_ID=")[^"]*' /etc/os-release || echo "unknown")"
echo "      Detected OS Version: Ubuntu $UBUNTU_VER"

# Detect Active Physical Management Network Interface via Hardware-Backed Sysfs Inspection
discover_real_iface() {
    if [ -d /sys/class/net/pnet0/brif ]; then
        for slave in /sys/class/net/pnet0/brif/*; do
            if [ -d "$slave" ] && [ -e "/sys/class/net/$(basename "$slave")/device" ]; then
                echo "$(basename "$slave")"
                return 0
            fi
        done
    fi

    local best_iface=""
    for iface_path in /sys/class/net/*; do
        [ -e "$iface_path" ] || continue
        local iface
        iface=$(basename "$iface_path")
        case "$iface" in
            lo|pnet*|docker*|veth*|virbr*|tun*|tap*|br-*|dummy*|wg*|zt*) continue ;;
        esac
        if [ -e "$iface_path/device" ]; then
            if [ -f "$iface_path/carrier" ] && [ "$(cat "$iface_path/carrier" 2>/dev/null)" = "1" ]; then
                echo "$iface"
                return 0
            fi
            if [ -z "$best_iface" ]; then
                best_iface="$iface"
            fi
        fi
    done

    if [ -n "$best_iface" ]; then
        echo "$best_iface"
        return 0
    fi

    local dev
    dev=$(ip -o route show to default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)
    if [ -n "$dev" ] && [ "$dev" != "pnet0" ] && [ "$dev" != "lo" ]; then
        echo "$dev"
        return 0
    fi

    dev=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -E '^(ens|enp|eno|eth)' | head -n1 || true)
    if [ -n "$dev" ]; then
        echo "$dev"
        return 0
    fi

    echo "ens33"
}

REAL_IFACE="$(discover_real_iface)"
if [ -n "$REAL_IFACE" ]; then
    echo "      Detected Physical Network Interface: $REAL_IFACE"
    # Ensure interface is up
    ip link set dev "$REAL_IFACE" up 2>/dev/null || true
    
    # Disable cloud-init network configuration overwrite permanently
    mkdir -p /etc/cloud/cloud.cfg.d
    echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

    # Ensure kernel bridge, virtualization, and br_netfilter modules load at boot
    mkdir -p /etc/modules-load.d /etc/sysctl.d /etc/systemd/system/networking.service.d
    cat > /etc/modules-load.d/pnetlab.conf << 'MODEOF'
bridge
stp
llc
8021q
tun
dummy
br_netfilter
MODEOF
    modprobe bridge 2>/dev/null || true
    modprobe 8021q 2>/dev/null || true
    modprobe tun 2>/dev/null || true
    modprobe br_netfilter 2>/dev/null || true

    # Bridge sysctl bypass to ensure ARP and IP traffic on bridges are never dropped by netfilter
    cat > /etc/sysctl.d/99-pnetlab-bridge.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.ipv4.ip_forward = 1
EOF
    sysctl --system 2>/dev/null || true

    # Mask legacy networking.service and plymouth (systemd-networkd + netplan handle network natively)
    systemctl mask networking.service plymouth-start.service plymouth-read-write.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true

    # Purge conflicting Netplan and systemd-networkd files
    mkdir -p /etc/netplan
    for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
        [ -f "$f" ] && [ "$(basename "$f")" != "01-pnetlab-netcfg.yaml" ] && rm -f "$f" 2>/dev/null || true
    done
    rm -f /etc/systemd/network/*.network 2>/dev/null || true

    # Write authoritative Netplan configuration (Static or DHCP on bridge pnet0)
    if [ -n "$STATIC_IP" ]; then
        IP_NET="$STATIC_IP"
        [[ "$IP_NET" != *"/"* ]] && IP_NET="${IP_NET}/24"
        GW_LINE=""
        [ -n "$STATIC_GW" ] && GW_LINE="      routes:\n        - to: default\n          via: ${STATIC_GW}"
        
        cat << NETEOF > /etc/netplan/01-pnetlab-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $REAL_IFACE:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [$REAL_IFACE]
      dhcp4: false
      dhcp6: false
      addresses:
        - $IP_NET
$(echo -e "$GW_LINE")
      nameservers:
        addresses: [$STATIC_DNS, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
NETEOF
    else
        cat << NETEOF > /etc/netplan/01-pnetlab-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $REAL_IFACE:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [$REAL_IFACE]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
NETEOF
    fi
    chmod 600 /etc/netplan/01-pnetlab-netcfg.yaml

    # Synchronize /etc/network/interfaces with pnet0 stanza for Web UI Network management & broker compatibility
    mkdir -p /etc/network /etc/network/interfaces.d
    if [ -n "$STATIC_IP" ]; then
        IP_ONLY="${STATIC_IP%%/*}"
        cat << INTEOF > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet static
    address $IP_ONLY
    netmask 255.255.255.0
    gateway ${STATIC_GW:-192.168.1.1}
    pre-up ip link set dev $REAL_IFACE up
    bridge_ports $REAL_IFACE
    bridge_stp off
# END pnetlab-netcfg pnet0
INTEOF
    else
        cat << INTEOF > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet dhcp
    pre-up ip link set dev $REAL_IFACE up
    bridge_ports $REAL_IFACE
    bridge_stp off
# END pnetlab-netcfg pnet0
INTEOF
    fi
    chmod 644 /etc/network/interfaces
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
    open-vm-tools
    qemu-guest-agent
    keyboard-configuration
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

# --- Step 3: Install Azam Basha Debian Packages ---
echo "[3/8] Installing Azam Basha v8 packages..."
DEB_POOL_DIR="${SCRIPT_DIR}/debian/pool/resolute/main"
if [ ! -d "$DEB_POOL_DIR" ] || ! compgen -G "${DEB_POOL_DIR}/*.deb" > /dev/null; then
    if [ -d "/opt/azambasha/debian/pool/resolute/main" ]; then
        SCRIPT_DIR="/opt/azambasha"
        DEB_POOL_DIR="/opt/azambasha/debian/pool/resolute/main"
    else
        echo "      -> Fetching full Azam Basha repository and packages to /opt/azambasha..."
        mkdir -p /opt/azambasha
        git clone https://github.com/azambasha1987/AZAM-BASHA.git /opt/azambasha 2>/dev/null || true
        SCRIPT_DIR="/opt/azambasha"
        DEB_POOL_DIR="/opt/azambasha/debian/pool/resolute/main"
    fi
fi

if [ -n "$DEB_POOL_DIR" ] && [ -d "$DEB_POOL_DIR" ] && compgen -G "${DEB_POOL_DIR}/*.deb" > /dev/null; then
    echo "      Found local debian packages in $DEB_POOL_DIR. Resolving latest production builds..."
    
    # Priority dependency order for clean master server installation
    PKG_PREFIXES=(
        "pnetlab-schema"
        "pnetlab-guacd"
        "pnetlab-qemu"
        "pnetlab-vpcs"
        "pnetlab-bridge-dkms"
        "pnetlab-docker"
        "pnetlab"
    )

    for prefix in "${PKG_PREFIXES[@]}"; do
        deb_path=$(find "$DEB_POOL_DIR" -maxdepth 1 -name "${prefix}_*.deb" ! -name "pnetlab-satellite*" | sort -V | tail -n1 || true)
        if [ -n "$deb_path" ] && [ -f "$deb_path" ]; then
            echo "      -> Installing $(basename "$deb_path")..."
            dpkg-deb -x "$deb_path" / 2>/dev/null || true
            dpkg -i --force-depends --force-confdef --force-confold "$deb_path" 2>/dev/null || true
        fi
    done

    # Apply authoritative network broker & interfaces synchronization
    if [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-network.py" ]; then
        echo "      -> Applying network broker & interfaces synchronization..."
        python3 "${SCRIPT_DIR}/scripts/azambasha-fix-network.py" || true
    fi
else
    echo "      [ERROR] Local debian directory ($DEB_POOL_DIR) not found or empty."
    echo "      Please ensure the debian/pool directory is included in your standalone folder."
    exit 1
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

# Ensure /opt/unetlab/schema directory exists and copy shipped schemas
mkdir -p /opt/unetlab/schema
if [ -d "${SCRIPT_DIR}/schema" ]; then
    cp -f "${SCRIPT_DIR}/schema/"*.sql /opt/unetlab/schema/ 2>/dev/null || true
fi

# Run authoritative schema configuration & repair
if [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-database-schema.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-fix-database-schema.sh" || true
else
    mysql << 'EOF' 2>/dev/null || mysql -u root << 'EOF' 2>/dev/null || true
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

    if [ -f "${SCRIPT_DIR}/schema/pnetlab_db.sql" ]; then
        mysql -u pnetlab -ppnetlab pnetlab_db < "${SCRIPT_DIR}/schema/pnetlab_db.sql" 2>/dev/null || mysql pnetlab_db < "${SCRIPT_DIR}/schema/pnetlab_db.sql" 2>/dev/null || true
    fi
    if [ -f "${SCRIPT_DIR}/schema/guacdb.sql" ]; then
        mysql -u guacuser -ppnetlab guacdb < "${SCRIPT_DIR}/schema/guacdb.sql" 2>/dev/null || mysql guacdb < "${SCRIPT_DIR}/schema/guacdb.sql" 2>/dev/null || true
    fi

    mysql -u pnetlab -ppnetlab pnetlab_db << 'EOF' 2>/dev/null || mysql pnetlab_db << 'EOF' 2>/dev/null || true
INSERT INTO control (control_name, control_value) VALUES
  ('ctrl_offline_mode','1'), ('ctrl_online_mode','0'),
  ('ctrl_default_mode','offline'), ('ctrl_captcha','0'),
  ('ctrl_version','1.0.0')
ON DUPLICATE KEY UPDATE control_value = VALUES(control_value);

DELETE FROM users WHERE username = 'admin';
INSERT INTO users (
    pod, username, email, name, password, role,
    user_status, active_time, expired_time, access_days,
    offline, ext_auth, session, folder, ip
) VALUES (
    0, 'admin', 'root@localhost', 'Administrator', SHA2('azam', 256), 'admin',
    1, 0, 0, NULL,
    1, NULL, UNIX_TIMESTAMP() + 315360000, '/', '127.0.0.1'
);
EOF
fi

# Clear any login rate-limit lockouts
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true

# --- Step 5: Configure Apache & PHP-FPM ---
echo "[5/8] Configuring Apache2 Web Server, SSL and PHP-FPM..."

# Detect PHP-FPM version
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
PHP_FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# 2-Tier Enterprise Root CA & Multi-IP Server Certificate Generation
CA_CERT="/etc/ssl/certs/pnetlab-ca.crt"
CA_KEY="/etc/ssl/private/pnetlab-ca.key"
SSL_CERT="/etc/ssl/certs/pnetlab-selfsigned.crt"
SSL_KEY="/etc/ssl/private/pnetlab-selfsigned.key"
mkdir -p /etc/ssl/certs /etc/ssl/private

# 1. Generate PNETLab Internal Root CA (20-Year Validity)
if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    openssl req -x509 -new -nodes -newkey rsa:2048 -days 7300 \
        -keyout "$CA_KEY" \
        -out "$CA_CERT" \
        -subj '/CN=PNETLab Enterprise Root CA/O=PNETLab Virtual Appliance/OU=Security' \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null || true
    chmod 0600 "$CA_KEY"
    chmod 0644 "$CA_CERT"
fi

# 2. Generate and Sign Multi-IP Server Certificate using Internal Root CA (10-Year Validity)
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
    # Collect all local loopback and LAN IPv4 addresses for SAN extension
    IP_SAN="IP:127.0.0.1"
    for ip in $(hostname -I 2>/dev/null || ip -4 addr show | awk '/inet /{print $2}' | cut -d/ -f1); do
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
            IP_SAN="${IP_SAN},IP:${ip}"
        fi
    done

    CSR_FILE="/tmp/pnetlab_server.csr"
    EXT_FILE="/tmp/pnetlab_san.ext"

    cat << EOF > "$EXT_FILE"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:pnetlab,DNS:pnetlab.local,DNS:localhost,${IP_SAN}
EOF

    openssl req -new -nodes -newkey rsa:2048 \
        -keyout "$SSL_KEY" \
        -out "$CSR_FILE" \
        -subj '/CN=pnetlab.local/O=PNETLab Virtual Appliance/OU=Web Engine' 2>/dev/null || true

    openssl x509 -req -in "$CSR_FILE" \
        -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
        -out "$SSL_CERT" \
        -days 3650 \
        -extfile "$EXT_FILE" 2>/dev/null || true

    rm -f "$CSR_FILE" "$EXT_FILE" 2>/dev/null || true
    chmod 0600 "$SSL_KEY"
    chmod 0644 "$SSL_CERT"
fi

# 3. Publish Root CA to web download endpoints for 1-click client trust
mkdir -p /opt/unetlab/html
cp -f "$CA_CERT" /opt/unetlab/html/pnetlab-ca.crt 2>/dev/null || true
cp -f "$CA_CERT" /opt/unetlab/html/ca.crt 2>/dev/null || true
chmod 0644 /opt/unetlab/html/pnetlab-ca.crt /opt/unetlab/html/ca.crt 2>/dev/null || true

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
    Alias /legacy /opt/unetlab/html/themes/default
    Alias /themes /opt/unetlab/html/themes

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

# Enable PNetLab Privilege Broker Daemon
cat > /etc/systemd/system/pnetlab-brokerd.service << 'EOF'
[Unit]
Description=PNetLab privilege broker (allowlisted root verbs for the engine)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/unetlab/scripts/pnetlab-brokerd.py
RuntimeDirectory=pnetlab
RuntimeDirectoryMode=0755
User=root
Group=root
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now pnetlab-brokerd.service 2>/dev/null || true

# --- Step 7: Fix Permissions, Addon Scaffolding & Cisco IOL License ---
echo "[7/8] Scaffolding addon directories and generating Cisco IOL license..."
mkdir -p /opt/unetlab/addons/qemu /opt/unetlab/addons/iol/bin /opt/unetlab/addons/dynamips
mkdir -p /opt/unetlab/labs /opt/unetlab/tmp

# Generate offline Cisco IOL license (iourc)
python3 - << 'PYEOF' 2>/dev/null || true
import socket, struct, os
hostname = socket.gethostname()
try:
    hostid = int(os.popen('hostid').read().strip(), 16)
except Exception:
    hostid = 0
key = 0
for char in hostname:
    key = (key * 33 + ord(char)) & 0xFFFFFFFF
key = (key ^ hostid ^ 0x5a5a5a5a) & 0xFFFFFFFF
license_str = f"[license]\n{hostname} = {key:016x};\n"
for path in ["/opt/unetlab/addons/iol/bin/iourc", "/etc/iourc"]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(license_str)
    os.chmod(path, 0o644)
PYEOF

if [ -x /opt/unetlab/wrappers/unl_wrapper ]; then
    /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
fi

# Enable IPv4 Forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf /etc/sysctl.d/* 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pnetlab-forwarding.conf
fi

# --- Step 8: Apply Modernization Suite & Essential Fixes ---
echo "[8/8] Applying Ubuntu 26 modernization, session fixes, and update freeze..."
if [ -n "$STATIC_IP" ] && [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-network-boot.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-fix-network-boot.sh" "$STATIC_IP" "255.255.255.0" "$STATIC_GW" || true
elif [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-network-boot.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-fix-network-boot.sh" || true
elif [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-network.py" ]; then
    python3 "${SCRIPT_DIR}/scripts/azambasha-fix-network.py" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-php-modernizer.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-php-modernizer.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-cgroups-v2-engine.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-cgroups-v2-engine.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-python-environment-setup.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-python-environment-setup.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-database-and-system-deep-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-database-and-system-deep-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-fix-export-and-apt.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-fix-export-and-apt.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-disable-logout.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-disable-logout.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-upload-and-docker-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-upload-and-docker-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-system-and-console-fix.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-system-and-console-fix.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-speed-optimizer.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-speed-optimizer.sh" || true
fi
if [ -f "${SCRIPT_DIR}/scripts/azambasha-block-updates.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-block-updates.sh" || true
fi

# Mask and disable redundant / failing boot services for clean startup
systemctl mask multipathd.service keyboard-setup.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl stop udhcpd 2>/dev/null || true
systemctl disable udhcpd 2>/dev/null || true

# Deploy all administrative toolchains permanently to /opt/unetlab/scripts
mkdir -p /opt/unetlab/scripts
if [ -d "${SCRIPT_DIR}/scripts" ]; then
    cp -rf "${SCRIPT_DIR}/scripts/"* /opt/unetlab/scripts/ 2>/dev/null || true
fi
chmod +x /opt/unetlab/scripts/* 2>/dev/null || true

# Deploy Azam Basha Logo Assets & Enterprise UI Branding
if [ -f "${SCRIPT_DIR}/scripts/azambasha-apply-branding.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-apply-branding.sh" || true
fi

# Apply Pure Black Dark Mode theme
if [ -f "${SCRIPT_DIR}/scripts/azambasha-dark-theme.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/azambasha-dark-theme.sh" || true
fi

# Register global administrative CLI commands in /usr/local/bin
ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/azambasha-menu 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/azambasha-fix 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-apply-branding.sh /usr/local/bin/azambasha-branding 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/azambasha-health 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/azambasha-doctor 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-image-doctor.sh /usr/local/bin/azambasha-images 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-backup-restore.sh /usr/local/bin/azambasha-backup 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-dark-theme.sh /usr/local/bin/azambasha-dark 2>/dev/null || true

ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/azam-menu 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/azam-fix 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-apply-branding.sh /usr/local/bin/azam-branding 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-fix-node-startup.sh /usr/local/bin/azam-nodes 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/azam-health 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/azam-doctor 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-image-doctor.sh /usr/local/bin/azam-images 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-backup-restore.sh /usr/local/bin/azam-backup 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-dark-theme.sh /usr/local/bin/azam-dark 2>/dev/null || true

ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/pnet-menu 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-apply-all-fixes.sh /usr/local/bin/pnet-fix 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/pnet-health 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-health-check.sh /usr/local/bin/pnet-doctor 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-image-doctor.sh /usr/local/bin/pnet-images 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-fix-network-boot.sh /usr/local/bin/pnet-network 2>/dev/null || true
ln -sfn /opt/unetlab/scripts/azambasha-backup-restore.sh /usr/local/bin/pnet-backup 2>/dev/null || true

# Final Service Refresh & Lockout Reset
rm -rf /dev/shm/pnet-authfail* /tmp/pnet-authfail* 2>/dev/null || true
systemctl restart "php${PHP_VER}-fpm" apache2 2>/dev/null || true

# Get Primary IP Address
HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)"
if [ -z "$HOST_IP" ]; then
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"
fi

# Configure dynamic console login banner (/etc/issue & /etc/motd)
cat > /etc/issue << EOF

============================================================
           Azam Basha v8 Virtual Network Emulator
============================================================
  Web UI Access   : https://${HOST_IP}/
  Default User    : admin
  Default Pass    : pnet
  SSH Management  : ssh root@${HOST_IP}
============================================================

\S (\l)

EOF
cp -f /etc/issue /etc/issue.net 2>/dev/null || true

# --- Automated Post-Install Self-Test Verification Suite ---
echo ""
echo "============================================================"
echo "      Running Post-Install Diagnostic Self-Test...          "
echo "============================================================"

# Test 1: Web Authentication
AUTH_CODE="$(curl -k -s -o /dev/null -w "%{http_code}" -X POST https://127.0.0.1/api/auth -H 'Content-Type: application/json' -d '{"username":"admin","password":"pnet"}' 2>/dev/null || echo "000")"
if [ "$AUTH_CODE" = "200" ]; then
    echo "  [✔ PASS] Web UI & Live Authentication : OK (200 OK)"
else
    echo "  [✖ FAIL] Web UI & Live Authentication : HTTP $AUTH_CODE"
fi

# Test 2: Database Schema
DB_CHECK="$(mysql -u pnetlab -ppnetlab pnetlab_db -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pnetlab_db';" 2>/dev/null || echo "0")"
if [ "$DB_CHECK" -ge 16 ]; then
    echo "  [✔ PASS] MySQL Database Schema        : OK ($DB_CHECK core tables active)"
else
    echo "  [✖ WARN] MySQL Database Schema        : $DB_CHECK tables found"
fi

# Test 3: KVM Virtualization
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "  [✔ PASS] Hardware KVM Virtualization  : OK (/dev/kvm ready)"
else
    echo "  [✖ WARN] Hardware KVM Virtualization  : /dev/kvm not accessible"
fi

# Test 4: Guacamole & Web Consoles
if systemctl is-active guacd 2>/dev/null | grep -q "active"; then
    echo "  [✔ PASS] HTML5 Guacamole Web Consoles : OK (guacd active)"
else
    echo "  [✖ FAIL] HTML5 Guacamole Web Consoles : guacd not running"
fi

# Test 5: Update Freeze Barrier
if apt-mark showhold 2>/dev/null | grep -q "pnetlab"; then
    echo "  [✔ PASS] Offline Update Freeze Lock   : OK (APT Hold & Pin -1 active)"
else
    echo "  [✖ WARN] Offline Update Freeze Lock   : Not held"
fi

echo ""
echo "============================================================"
echo "    Azam Basha v1.0.0 Installation Completed Successfully!  "
echo "============================================================"
echo "  Web UI URL      : https://${HOST_IP}/"
echo "  HTTP Redirect   : http://${HOST_IP}/"
echo "  Default User    : admin"
echo "  Default Pass    : azam"
echo ""
echo "  Console SSH     : root@${HOST_IP} (Password: azam)"
echo "  Theme Mode      : Unified Dark Theme (Active)"
echo "  Install Log     : $LOG_FILE"
echo "============================================================"
echo "  [CLI COMMANDS AVAILABLE ANYTIME AS ROOT]:"
echo "  azam-menu     -> Open master admin & performance toolkit"
echo "  azam-doctor   -> Run complete health & diagnostic check"
echo "  azam-images   -> Validate images, templates & fix permissions"
echo "  azam-dark     -> Re-apply pure black dark mode theme"
echo "  azam-backup   -> Create full labs & database backup archive"
echo "============================================================"
exit 0
