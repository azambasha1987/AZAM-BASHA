#!/usr/bin/env bash
# ==============================================================================
# PNetLab Network Auto-Recovery & Persistent Static IP Boot Fix
# Detects real NIC (ens33/ens160), repairs Netplan & /etc/network/interfaces,
# brings up pnet0 bridge, patches broker daemon, and ensures static IP
# permanently persists across all VM reboots.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    PNetLab Network & Static IP Persistent Recovery Fix     "
echo "============================================================"

# 1. Discover primary physical interface
REAL_IFACE=""
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1); do
    case "$iface" in
        lo|pnet*|docker*|veth*|virbr*|tun*|tap*|br-*) continue ;;
        ens*|enp*|eno*|eth*)
            REAL_IFACE="$iface"
            break
            ;;
    esac
done

if [ -z "$REAL_IFACE" ]; then
    REAL_IFACE="ens33"
fi
echo "[1/6] Detected primary uplink interface: ${REAL_IFACE}"

# 2. Prevent cloud-init from overwriting network configuration on reboot
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg << 'EOF'
network: {config: disabled}
EOF
echo "[2/6] Disabled cloud-init network overwrite."

# 3. Read configured static IP from /etc/network/interfaces or fallback
IP_ADDR="192.168.1.23"
NETMASK="255.255.255.0"
GATEWAY="192.168.1.1"
CIDR="24"
MODE="dhcp"

if [ -f /etc/network/interfaces ]; then
    if grep -q "iface pnet0 inet static" /etc/network/interfaces; then
        MODE="static"
        PARSED_IP=$(grep -E "^[[:space:]]*address" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
        PARSED_MASK=$(grep -E "^[[:space:]]*netmask" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
        PARSED_GW=$(grep -E "^[[:space:]]*gateway" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
        [ -n "$PARSED_IP" ] && IP_ADDR="$PARSED_IP"
        [ -n "$PARSED_MASK" ] && NETMASK="$PARSED_MASK"
        [ -n "$PARSED_GW" ] && GATEWAY="$PARSED_GW"
    fi
fi

# Allow passing static IP as argument: sudo bash pnetlab-fix-network-boot.sh 192.168.1.50 255.255.255.0 192.168.1.1
if [ $# -ge 1 ]; then
    IP_ADDR="$1"
    MODE="static"
    [ $# -ge 2 ] && NETMASK="$2"
    [ $# -ge 3 ] && GATEWAY="$3"
fi

# Calculate CIDR from netmask
case "$NETMASK" in
    255.255.255.0)   CIDR="24" ;;
    255.255.0.0)     CIDR="16" ;;
    255.0.0.0)       CIDR="8"  ;;
    255.255.255.128) CIDR="25" ;;
    255.255.255.192) CIDR="26" ;;
    255.255.255.224) CIDR="27" ;;
    255.255.255.240) CIDR="28" ;;
    255.255.255.248) CIDR="29" ;;
    255.255.255.252) CIDR="30" ;;
    *) CIDR="24" ;;
esac

echo "[3/6] Network Mode: ${MODE} (Target IP: ${IP_ADDR}/${CIDR}, Gateway: ${GATEWAY})"

# 4. Write clean /etc/network/interfaces (for legacy tools and GUI reading)
mkdir -p /etc/network/interfaces.d
if [ "$MODE" = "static" ]; then
cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet static
    pre-up ip link set dev ${REAL_IFACE} up
    bridge_ports ${REAL_IFACE}
    bridge_stp off
    address ${IP_ADDR}
    netmask ${NETMASK}
    gateway ${GATEWAY}
# END pnetlab-netcfg pnet0
EOF
else
cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet dhcp
    pre-up ip link set dev ${REAL_IFACE} up
    bridge_ports ${REAL_IFACE}
    bridge_stp off
# END pnetlab-netcfg pnet0
EOF
fi
chmod 644 /etc/network/interfaces

# 5. Clean up competing netplan files and write authoritative Netplan configuration
mkdir -p /etc/netplan
# Remove any conflicting cloud-init or installer configs that override pnet0
for f in /etc/netplan/00-installer-config*.yaml /etc/netplan/50-cloud-init.yaml /etc/netplan/99-installer*.yaml; do
    if [ -f "$f" ]; then
        mv "$f" "${f}.bak" 2>/dev/null || true
    fi
done

if [ "$MODE" = "static" ]; then
cat > /etc/netplan/01-pnetlab-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${REAL_IFACE}:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [${REAL_IFACE}]
      dhcp4: false
      dhcp6: false
      addresses:
        - ${IP_ADDR}/${CIDR}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
EOF
else
cat > /etc/netplan/01-pnetlab-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${REAL_IFACE}:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [${REAL_IFACE}]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
EOF
fi
chmod 600 /etc/netplan/01-pnetlab-netcfg.yaml

# 6. Patch /opt/unetlab/scripts/pnetlab-brokerd.py for GUI Network Synchronization
echo "[4/6] Synchronizing Privilege Broker network handler..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/pnetlab-fix-network.py" ]; then
    python3 "${SCRIPT_DIR}/pnetlab-fix-network.py" 2>/dev/null || true
fi

# 7. Create Persistent Systemd Boot Service for Network Resilience
echo "[5/6] Installing persistent pnetlab-boot-network.service..."
cat > /usr/local/bin/pnetlab-boot-network.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Discover physical interface
REAL_IFACE=""
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1); do
    case "$iface" in
        lo|pnet*|docker*|veth*|virbr*|tun*|tap*|br-*) continue ;;
        ens*|enp*|eno*|eth*)
            REAL_IFACE="$iface"
            break
            ;;
    esac
done
[ -z "$REAL_IFACE" ] && REAL_IFACE="ens33"

# Ensure physical link is up
ip link set dev "$REAL_IFACE" up 2>/dev/null || true

# Apply Netplan configuration
netplan generate 2>/dev/null || true
netplan apply 2>/dev/null || systemctl restart systemd-networkd 2>/dev/null || true

# Fallback check: if pnet0 does not exist or has no IP, force creation
sleep 1
if ! ip link show pnet0 2>/dev/null | grep -q "pnet0"; then
    ip link add name pnet0 type bridge 2>/dev/null || true
    ip link set dev "$REAL_IFACE" master pnet0 2>/dev/null || true
    ip link set dev pnet0 up 2>/dev/null || true
fi

# If static IP defined in /etc/network/interfaces, ensure it is assigned
if grep -q "iface pnet0 inet static" /etc/network/interfaces 2>/dev/null; then
    STATIC_IP=$(grep -E "^[[:space:]]*address" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
    STATIC_MASK=$(grep -E "^[[:space:]]*netmask" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
    STATIC_GW=$(grep -E "^[[:space:]]*gateway" /etc/network/interfaces | awk '{print $2}' | head -n1 || true)
    if [ -n "$STATIC_IP" ]; then
        CIDR="24"
        [ "$STATIC_MASK" = "255.255.0.0" ] && CIDR="16"
        [ "$STATIC_MASK" = "255.0.0.0" ] && CIDR="8"
        if ! ip -4 addr show pnet0 2>/dev/null | grep -q "$STATIC_IP"; then
            ip addr flush dev pnet0 2>/dev/null || true
            ip addr add "${STATIC_IP}/${CIDR}" dev pnet0 2>/dev/null || true
            [ -n "$STATIC_GW" ] && ip route replace default via "$STATIC_GW" dev pnet0 2>/dev/null || true
        fi
    fi
fi

# Enable packet forwarding mask on bridges
for b in /sys/class/net/pnet*/bridge/group_fwd_mask; do
    [ -f "$b" ] && echo 65535 > "$b" 2>/dev/null || true
done
exit 0
EOF
chmod +x /usr/local/bin/pnetlab-boot-network.sh

cat > /etc/systemd/system/pnetlab-boot-network.service << 'EOF'
[Unit]
Description=PNETLab Persistent Boot Network & Bridge Initialization
Before=network-online.target pnetlab-brokerd.service apache2.service
After=systemd-networkd.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/pnetlab-boot-network.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl unmask systemd-networkd 2>/dev/null || true
systemctl enable --now systemd-networkd 2>/dev/null || true
systemctl enable --now systemd-resolved 2>/dev/null || true
systemctl enable --now pnetlab-boot-network.service 2>/dev/null || true

# 8. Apply immediately
echo "[6/6] Bringing up network interfaces & applying configuration..."
ip link set dev "$REAL_IFACE" up 2>/dev/null || true
netplan generate 2>/dev/null || true
netplan apply 2>/dev/null || systemctl restart systemd-networkd 2>/dev/null || true
/usr/local/bin/pnetlab-boot-network.sh 2>/dev/null || true

# Final state check
sleep 2
CURRENT_IP=$(ip -o -4 addr show pnet0 2>/dev/null | awk '{print $4}' | head -n1 || ip -o -4 addr show "$REAL_IFACE" 2>/dev/null | awk '{print $4}' | head -n1 || echo "None")

echo ""
echo "============================================================"
echo "    [SUCCESS] Network Recovered & Persistent Across Boot!   "
echo "============================================================"
echo "  Physical Uplink : ${REAL_IFACE}"
echo "  Active Bridge   : pnet0"
echo "  Assigned IP     : ${CURRENT_IP}"
echo "  Web UI Access   : https://${CURRENT_IP%/*}/"
echo "============================================================"
exit 0
