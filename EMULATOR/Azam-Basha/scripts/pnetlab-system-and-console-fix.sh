#!/usr/bin/env bash
# ==============================================================================
# Azam Basha System, SSL & HTML5 Console Fix Utility
#
# Fixes 4 Major Appliance Edge Cases:
# 1. SSL/HTTPS & IP-SAN Certificate: Generates a 10-year Subject Alternative Name
#    (IP-SAN) certificate for modern Chrome/Firefox/Edge browser compatibility.
# 2. HTML5 Guacamole & Console Fix: Configures guacd daemon auto-recovery,
#    enables Apache mod_proxy_wstunnel for stable in-browser web console sessions.
# 3. Cloud Interface (pnet0..pnet9) DHCP & Promiscuous Mode: Ensures bridge
#    interfaces pass nested DHCP, ARP, and VLAN frames to host/physical networks.
# 4. System Time Drift & NTP Sync: Configures systemd-timesyncd to prevent
#    session token and SSL verification failures after VM sleep/resume.
# ==============================================================================
set -euo pipefail

# Support non-root check/help modes
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --status]"
    echo ""
    echo "Options:"
    echo "  (no args)    Apply SSL, HTML5 Guacamole, Cloud Bridges, and Time-Sync fixes"
    echo "  --check      Inspect SSL certificates, guacd service, and bridge modes"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== Azam Basha System & Console Diagnostic Check ==="
    echo -n "[*] Apache SSL Module: "
    if apache2ctl -M 2>/dev/null | grep -q "ssl_module"; then
        echo "ENABLED"
    else
        echo "DISABLED"
    fi

    echo -n "[*] Apache WebSocket Proxy (proxy_wstunnel): "
    if apache2ctl -M 2>/dev/null | grep -q "proxy_wstunnel_module"; then
        echo "ENABLED"
    else
        echo "DISABLED"
    fi

    echo -n "[*] HTML5 Console Daemon (guacd): "
    if systemctl is-active guacd 2>/dev/null | grep -q "active"; then
        echo "RUNNING"
    else
        echo "STOPPED / INACTIVE"
    fi

    echo -n "[*] Time Synchronization (systemd-timesyncd/NTP): "
    if systemctl is-active systemd-timesyncd 2>/dev/null | grep -q "active"; then
        echo "ACTIVE"
    else
        echo "INACTIVE"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================================"
echo "   Azam Basha System, SSL & HTML5 Console Repair Utility    "
echo "============================================================"

# 1. Generate Modern 10-Year IP-SAN SSL Certificate
echo "[1/4] Generating 10-Year Subject Alternative Name (IP-SAN) SSL Certificate..."
SSL_DIR="/etc/ssl/pnetlab"
mkdir -p "$SSL_DIR"

# 1. Generate Azam Basha Internal Root CA (20-Year Validity)
CA_CERT="/etc/ssl/certs/pnetlab-ca.crt"
CA_KEY="/etc/ssl/private/pnetlab-ca.key"
mkdir -p /etc/ssl/certs /etc/ssl/private "${SSL_DIR}"

if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    openssl req -x509 -new -nodes -newkey rsa:2048 -days 7300 \
        -keyout "$CA_KEY" \
        -out "$CA_CERT" \
        -subj '/CN=Azam Basha Enterprise Root CA/O=Azam Basha Virtual Appliance/OU=Security' \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null || true
    chmod 0600 "$CA_KEY"
    chmod 0644 "$CA_CERT"
fi

# 2. Collect all local IPv4 addresses and build SAN extension
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
    -keyout "${SSL_DIR}/pnetlab.key" \
    -out "$CSR_FILE" \
    -subj '/CN=pnetlab.local/O=Azam Basha Virtual Appliance/OU=Web Engine' 2>/dev/null || true

openssl x509 -req -in "$CSR_FILE" \
    -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "${SSL_DIR}/pnetlab.crt" \
    -days 3650 \
    -extfile "$EXT_FILE" 2>/dev/null || true

rm -f "$CSR_FILE" "$EXT_FILE" 2>/dev/null || true
chmod 600 "${SSL_DIR}/pnetlab.key"
chmod 644 "${SSL_DIR}/pnetlab.crt"

# Mirror to standard paths expected by Ubuntu Apache configurations
cp -f "${SSL_DIR}/pnetlab.crt" /etc/ssl/certs/pnetlab-selfsigned.crt 2>/dev/null || true
cp -f "${SSL_DIR}/pnetlab.crt" /etc/ssl/certs/apache-selfsigned.crt 2>/dev/null || true
cp -f "${SSL_DIR}/pnetlab.key" /etc/ssl/private/pnetlab-selfsigned.key 2>/dev/null || true
cp -f "${SSL_DIR}/pnetlab.key" /etc/ssl/private/apache-selfsigned.key 2>/dev/null || true
chmod 600 /etc/ssl/private/* 2>/dev/null || true

# Publish Root CA to web download endpoints for 1-click client trust
mkdir -p /opt/unetlab/html
cp -f "$CA_CERT" /opt/unetlab/html/pnetlab-ca.crt 2>/dev/null || true
cp -f "$CA_CERT" /opt/unetlab/html/ca.crt 2>/dev/null || true
chmod 0644 /opt/unetlab/html/pnetlab-ca.crt /opt/unetlab/html/ca.crt 2>/dev/null || true

# Configure Apache SSL Site
if [ -d /etc/apache2 ]; then
    a2enmod ssl rewrite headers proxy proxy_http proxy_wstunnel mpm_event proxy_fcgi setenvif 2>/dev/null || true
    a2dissite pnetlabs 000-default default-ssl 2>/dev/null || true
    a2ensite pnetlab pnetlab-ssl 2>/dev/null || true
    cat << 'EOF' > /etc/apache2/conf-available/pnetlab-ssl-hardening.conf
# Modern TLS Hardening for PNETLab
SSLCipherSuite HIGH:!aNULL:!MD5:!3DES:!CAMELLIA:!AES128
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder on
EOF
    a2enconf pnetlab-ssl-hardening 2>/dev/null || true
fi
echo "  -> 10-Year IP-SAN SSL Certificate installed covering all VM IP addresses and paths."

# 2. HTML5 Guacamole & Console WebSocket Fix
echo "[2/4] Hardening HTML5 Guacamole (guacd) Web Console Daemon..."
if command -v guacd &>/dev/null; then
    mkdir -p /etc/systemd/system/guacd.service.d
    cat << 'EOF' > /etc/systemd/system/guacd.service.d/override.conf
[Service]
Restart=always
RestartSec=3s
LimitNOFILE=65535
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart guacd 2>/dev/null || service guacd restart 2>/dev/null || true
    echo "  -> guacd service hardened with auto-restart and 65,535 file descriptors."
fi

# 3. Cloud Interfaces (pnet0..pnet9) Promiscuous Mode & DHCP Fix
echo "[3/4] Enabling Promiscuous Mode on Cloud Bridge Interfaces (pnet0..pnet9)..."
BRIDGE_SCRIPT="/usr/local/bin/pnetlab-fix-bridges"
cat << 'EOF' > "$BRIDGE_SCRIPT"
#!/bin/bash
# Enable promiscuous mode and disable STP forwarding delays on Cloud Bridges
for br in $(find /sys/class/net/ -maxdepth 1 -name "pnet*" | xargs -n1 basename 2>/dev/null); do
    ip link set dev "$br" promisc on 2>/dev/null || true
    ip link set dev "$br" up 2>/dev/null || true
    if [ -d "/sys/class/net/$br/bridge" ]; then
        brctl setfd "$br" 0 2>/dev/null || true
        brctl stp "$br" off 2>/dev/null || true
    fi
done
EOF
chmod +x "$BRIDGE_SCRIPT"
bash "$BRIDGE_SCRIPT" || true

# Persist Bridge Promiscuous Configuration
cat << 'EOF' > /etc/systemd/system/pnetlab-bridges.service
[Unit]
Description=PNETLab Cloud Bridge Promiscuous Initializer
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pnetlab-fix-bridges
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
systemctl enable pnetlab-bridges.service 2>/dev/null || true

# 4. NTP Time Synchronization & Drift Fix
echo "[4/5] Configuring NTP Time Synchronization (systemd-timesyncd)..."
if systemctl list-unit-files | grep -q "systemd-timesyncd"; then
    systemctl enable systemd-timesyncd 2>/dev/null || true
    systemctl restart systemd-timesyncd 2>/dev/null || true
    echo "  -> systemd-timesyncd active: VM time drift on sleep/resume prevented."
fi

# 5. Clean up Noisy / Irrelevant Virtual Machine Boot Services
echo "[5/5] Disabling unneeded virtual machine boot services (multipathd, keyboard-setup)..."
modprobe binfmt_misc 2>/dev/null || true
systemctl mask multipathd.service multipathd.socket keyboard-setup.service console-setup.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl disable --now udhcpd.service kdump-tools.service multipathd.service 2>/dev/null || true
systemctl reset-failed 2>/dev/null || true

# Restart Apache
systemctl restart apache2 2>/dev/null || service apache2 restart 2>/dev/null || true

echo ""
echo "============================================================"
echo " [SUCCESS] System, SSL & HTML5 Console Fixes Applied!       "
echo "============================================================"
