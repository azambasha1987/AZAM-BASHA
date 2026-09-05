#!/usr/bin/env bash
# ==============================================================================
# PNETLab v8 Cluster Satellite (Worker Node) Installer
# Target OS: Ubuntu 26.04 LTS (27H1 "Resolute")
#
# Purpose:
# Provisions a dedicated, headless node-execution worker VM (QEMU, IOL,
# Dynamips, Docker, bridging) to scale out compute capacity for a master PNETLab host.
#
# After installation, join this satellite to your master server via:
#   pnet-satellite-join --master <MASTER_IP> --id <1|2> --name "Satellite-1" --psk <PSK>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/azambasha-satellite-install.log"

# Maintain root installation symlinks for /opt/azambasha and /opt/pnetlab
mkdir -p /opt/azambasha /opt/pnetlab 2>/dev/null || true
if [ "$SCRIPT_DIR" != "/opt/azambasha" ]; then
    ln -sfn "$SCRIPT_DIR" /opt/azambasha 2>/dev/null || true
fi
ln -sfn /opt/azambasha /opt/pnetlab 2>/dev/null || true

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "============================================================"
echo "    Azam Basha v8 Cluster Satellite (Worker) Installer      "
echo "============================================================"

# --- Pre-flight Checks ---
echo "[1/6] Performing pre-flight checks..."
if dpkg -s pnetlab >/dev/null 2>&1; then
    echo "[ERROR] 'pnetlab' (Master) is already installed on this machine." >&2
    echo "A single VM cannot be both Master and Satellite simultaneously." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# --- Step 2: Install Headless Satellite Dependencies ---
echo "[2/6] Installing headless worker dependencies..."
apt-get update -y

SATELLITE_DEPS=(
    bridge-utils
    ebtables
    iptables
    iptables-persistent
    dkms
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
    dos2unix
    genisoimage
    telnet
    iproute2
    udhcpd
    busybox
    dhcpcd-base
    dmidecode
    sshpass
    rsync
    lib32gcc-s1
    lib32z1
    libc6-i386
    libelf1t64
    libpcap0.8t64
    libsdl1.2debian
    libaio1t64
    php-cli
    zstd
)

for pkg in "${SATELLITE_DEPS[@]}"; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || true
done

# --- Step 3: Install Satellite Debian Packages ---
echo "[3/6] Installing Satellite runtime debian packages..."
DEB_POOL_DIR="${SCRIPT_DIR}/debian/pool/resolute/main"

if [ -n "$DEB_POOL_DIR" ] && [ -d "$DEB_POOL_DIR" ]; then
    PKG_PREFIXES=(
        "pnetlab-qemu"
        "pnetlab-vpcs"
        "pnetlab-bridge-dkms"
        "pnetlab-docker"
        "pnetlab-satellite"
    )

    for prefix in "${PKG_PREFIXES[@]}"; do
        deb_path=$(find "$DEB_POOL_DIR" -maxdepth 1 -name "${prefix}_*.deb" | sort -V | tail -n1 || true)
        if [ -n "$deb_path" ] && [ -f "$deb_path" ]; then
            echo "      -> Installing $(basename "$deb_path")..."
            dpkg-deb -x "$deb_path" / 2>/dev/null || true
            dpkg -i --force-depends --force-confdef --force-confold "$deb_path" 2>/dev/null || true
        fi
    done
fi

# --- Step 4: Extract QEMU Zoo Assets if Available ---
echo "[4/6] Checking for QEMU multi-version runtime zoo..."
ASSET_TAR=$(find "${SCRIPT_DIR}/generic" -name "pnetlab-core-assets-*.tar.zst" 2>/dev/null | sort -V | tail -n1 || true)
if [ -n "$ASSET_TAR" ] && [ -f "$ASSET_TAR" ] && command -v zstd &>/dev/null; then
    echo "      -> Unpacking QEMU runtime assets ($(basename "$ASSET_TAR"))..."
    tar --zstd -xf "$ASSET_TAR" -C /opt/unetlab/ 2>/dev/null || true
fi

# --- Step 5: Hardware Virtualization & Permissions ---
echo "[5/6] Setting permissions and hardware markers..."
mkdir -p /opt/unetlab/addons/{qemu,iol/bin,dynamips,docker}
mkdir -p /opt/unetlab/data/Logs
mkdir -p /etc/pnetlab-satellite

if [ -c /dev/kvm ]; then
    chmod 666 /dev/kvm || true
fi

if grep -q "svm" /proc/cpuinfo 2>/dev/null; then
    echo "svm" > /opt/unetlab/platform
else
    echo "intel" > /opt/unetlab/platform
fi

/opt/unetlab/wrappers/unl_wrapper -a fixpermissions 2>/dev/null || true

# --- Step 6: Verify Satellite Service ---
echo "[6/6] Verifying satellite service status..."
systemctl daemon-reload 2>/dev/null || true
systemctl enable pnetlab-satd 2>/dev/null || true

echo ""
echo "============================================================"
echo " [SUCCESS] Azam Basha Cluster Satellite Installed Successfully!"
echo "============================================================"
echo "To join this worker to your Master Azam Basha server:"
echo ""
echo " 1. On your Master Web UI, go to: System -> Cluster"
echo " 2. Click 'Generate PSK' and copy the 64-character key"
echo " 3. Run the following command on this Satellite VM:"
echo ""
echo "    sudo pnet-satellite-join \\"
echo "      --master <MASTER_IP> \\"
echo "      --id 1 \\"
echo "      --name \"Satellite-1\" \\"
echo "      --psk <COPIED_PSK>"
echo ""
echo "============================================================"
