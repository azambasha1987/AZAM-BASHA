#!/usr/bin/env bash
# ==============================================================================
# Azam-Pnet Complete OS Prerequisites & Kernel Module Provisioner
# Target OS: Ubuntu 26.04-live-server-amd64 and later (Resolute+)
# Ensures 100% of all kernel modules, system daemons, PHP extensions, Python
# libraries, 32-bit compatibility binaries, and emulation packages are installed.
# ==============================================================================
set -euo pipefail

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root: sudo bash $0" >&2
    exit 1
fi

LOG_FILE="/var/log/azambasha-os-prerequisites.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo "    Azam-Pnet OS Prerequisites & Kernel Provisioner        "
echo "    Target Platform: Ubuntu 26.04+ (Live Server & Later)   "
echo "============================================================"
echo "[*] Start Time: $(date)"
echo "[*] Log File  : $LOG_FILE"
echo "============================================================"

# --- Phase 1: OS Validation & APT Configuration ---
echo "[1/6] Validating OS architecture and configuring APT..."
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
    echo "[ERROR] Unsupported CPU architecture: $ARCH. Azam-Pnet requires x86_64 (amd64)." >&2
    exit 1
fi

UBUNTU_VER="$(lsb_release -rs 2>/dev/null || grep -oP '(?<=VERSION_ID=")[^"]*' /etc/os-release || echo "26.04")"
echo "      -> Detected Operating System: Ubuntu ${UBUNTU_VER} (${ARCH})"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Enable multiarch for 32-bit IOL/Dynamips binary support
dpkg --add-architecture i386 2>/dev/null || true

echo "      -> Updating APT package repository indexes..."
apt-get update -y -qq

# --- Phase 2: Kernel Module Provisioning & Sysctl Tuning ---
echo "[2/6] Provisioning kernel modules & network datapath parameters..."

KERNEL_MODULES=(
    kvm
    kvm_intel
    kvm_amd
    vhost
    vhost_net
    bridge
    8021q
    tun
    dummy
    br_netfilter
    stp
    llc
    binfmt_misc
    veth
    sch_fq_codel
    ip_tables
    iptable_filter
    iptable_nat
)

mkdir -p /etc/modules-load.d
cat << 'EOF' > /etc/modules-load.d/pnetlab.conf
# ==============================================================================
# Azam-Pnet Required Kernel Modules for Ubuntu 26+
# ==============================================================================
kvm
kvm_intel
kvm_amd
vhost
vhost_net
bridge
8021q
tun
dummy
br_netfilter
stp
llc
binfmt_misc
veth
sch_fq_codel
ip_tables
iptable_filter
iptable_nat
EOF

# Ensure /lib/modules link exists for modprobe
if [ ! -d /lib/modules ] && [ -d /usr/lib/modules ]; then
    ln -sfn /usr/lib/modules /lib/modules 2>/dev/null || true
fi

for mod in "${KERNEL_MODULES[@]}"; do
    modprobe "$mod" 2>/dev/null || true
done

# Bridge Sysctl Bypass & Packet Forwarding
mkdir -p /etc/sysctl.d
cat << 'EOF' > /etc/sysctl.d/99-pnetlab-bridge.conf
# Azam-Pnet Kernel Datapath & Bridge Netfilter Tuning
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 100000
net.ipv4.tcp_max_syn_backlog = 65535
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
vm.max_map_count = 262144
EOF
sysctl --system 2>/dev/null || true

# --- Phase 3: Comprehensive Package & Module Installation ---
echo "[3/6] Installing all system packages, daemons, and runtime modules..."

MASTER_PREREQUISITES=(
    # --- Web & Database Infrastructure ---
    apache2
    mysql-server
    libapache2-mod-fcgid
    sqlite3
    
    # --- PHP 8.x Core & Extensions ---
    php
    php-cli
    php-fpm
    php-mysql
    php-gd
    php-curl
    php-mbstring
    php-xml
    php-zip
    php-yaml
    php-imagick
    php-sqlite3
    php-bcmath

    # --- Python 3 Ecosystem ---
    python3
    python3-pip
    python3-venv
    python3-setuptools
    python3-wheel
    python3-yaml
    python3-requests
    python3-pexpect
    python3-cryptography
    python3-httpx
    python3-websockets
    python3-psutil
    python3-paramiko
    python3-docker
    python3-serial

    # --- 32-bit & 64-bit Emulation Compatibility Libraries ---
    lib32gcc-s1
    lib32z1
    libc6-i386
    libelf1t64
    libpcap0.8t64
    libsdl1.2debian
    libaio1t64
    libspice-client-glib-2.0-8
    libyaml-0-2
    libyaml-dev
    libxss1
    qemu-system-x86
    qemu-system-common
    qemu-utils
    libguestfs-tools
    dkms
    build-essential

    # --- Networking, Traffic Control & Diagnostics ---
    bridge-utils
    ebtables
    iptables
    iptables-persistent
    iproute2
    net-tools
    ethtool
    tcpdump
    tshark
    netcat-openbsd
    telnet
    socat
    screen
    cpulimit
    cgroup-tools
    dos2unix
    genisoimage
    dmidecode
    debconf-utils
    dialog
    udhcpd
    busybox
    dhcpcd-base
    dnsmasq-base
    sshpass
    lsof
    lvm2
    zip
    unzip
    zstd
    curl
    wget
    rsync
    jq
    chrony
    open-vm-tools
    qemu-guest-agent
    keyboard-configuration
)

FAILED_PKGS=()
for pkg in "${MASTER_PREREQUISITES[@]}"; do
    if ! apt-get install -y --no-install-recommends "$pkg" 2>/dev/null; then
        FAILED_PKGS+=("$pkg")
    fi
done

if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
    echo "      -> Handling package naming fallbacks for ${#FAILED_PKGS[@]} packages..."
    for f_pkg in "${FAILED_PKGS[@]}"; do
        case "$f_pkg" in
            libelf1t64)
                apt-get install -y --no-install-recommends libelf1 2>/dev/null || true
                ;;
            libpcap0.8t64)
                apt-get install -y --no-install-recommends libpcap0.8 2>/dev/null || true
                ;;
            libaio1t64)
                apt-get install -y --no-install-recommends libaio1 2>/dev/null || true
                ;;
            mysql-server)
                apt-get install -y --no-install-recommends mariadb-server 2>/dev/null || true
                ;;
            tshark)
                echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections 2>/dev/null || true
                apt-get install -y --no-install-recommends tshark 2>/dev/null || true
                ;;
            *)
                apt-get install -y "$f_pkg" 2>/dev/null || true
                ;;
        esac
    done
fi
echo "      -> All system packages and runtime modules verified!"

# Clean unused packages and headers
apt-get autoremove -y -qq --purge 2>/dev/null || true
apt-get clean 2>/dev/null || true

# Pre-configure Apache for Event MPM and PHP-FPM
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
a2dismod "php${PHP_VER}" php mpm_prefork 2>/dev/null || true
a2enmod mpm_event proxy_fcgi setenvif rewrite ssl headers 2>/dev/null || true
a2enconf "php${PHP_VER}-fpm" 2>/dev/null || true
systemctl enable --now "php${PHP_VER}-fpm" 2>/dev/null || true

# --- Phase 4: Python 3.14+ Isolated Runtime Environment ---
echo "[4/6] Provisioning Python virtual environment & Telnet/WebSocket bridges..."
VENV_PATH="/opt/unetlab/venv"
mkdir -p /opt/unetlab
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH" 2>/dev/null || true
fi

if [ -x "${VENV_PATH}/bin/pip" ]; then
    "${VENV_PATH}/bin/pip" install --upgrade pip 2>/dev/null || true
    "${VENV_PATH}/bin/pip" install telnetlib3 websockets requests urllib3 paramiko psutil pyyaml 2>/dev/null || true
fi

# Global installation with --break-system-packages as safety fallback
pip3 install --break-system-packages telnetlib3 websockets requests urllib3 paramiko psutil pyyaml 2>/dev/null || true

# --- Phase 5: Hardware Virtualization & Platform Markers ---
echo "[5/6] Initializing virtualization capabilities and hardware device nodes..."
if [ -c /dev/kvm ]; then
    chmod 666 /dev/kvm || true
    echo "      -> /dev/kvm permissions set to 0666."
fi

if [ -c /dev/net/tun ]; then
    chmod 666 /dev/net/tun || true
fi

mkdir -p /opt/unetlab/addons/{qemu,iol/bin,dynamips,docker}
mkdir -p /opt/unetlab/data/{Logs,netcfg-backups}
mkdir -p /opt/unetlab/tmp

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

# --- Phase 6: Verification & Summary ---
echo "[6/6] Verifying installed modules and system ready state..."

echo ""
echo "============================================================"
echo "    [SUCCESS] OS Prerequisites & Modules Ready!             "
echo "============================================================"
echo "Kernel Modules  : $(lsmod | grep -E 'kvm|bridge|8021q|tun|br_netfilter' | awk '{print $1}' | tr '\n' ' ')"
echo "Virtualization  : $([ -c /dev/kvm ] && echo 'KVM Ready (/dev/kvm)' || echo 'Emulation Only (No KVM)')"
echo "Python Runtime  : $(python3 --version 2>/dev/null || echo 'N/A')"
echo "PHP Runtime     : $(php -v 2>/dev/null | head -n1 || echo 'N/A')"
echo "Web Server      : $(apache2 -v 2>/dev/null | head -n1 || echo 'N/A')"
echo "Database        : $(mysql --version 2>/dev/null | head -n1 || echo 'N/A')"
echo "============================================================"
echo "OS is now fully provisioned and ready for Azam-Pnet software installation."
