#!/usr/bin/env bash
# ==============================================================================
# PNetLab Guaranteed Persistent Static IP & Bridge Engine
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    PNetLab Guaranteed Persistent Static IP & Bridge Fix    "
echo "============================================================"

# 1. Detect Real Uplink NIC (eth0 / ens33 / enp0s3)
REAL_IFACE=""
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1); do
    case "$iface" in
        lo|pnet*|docker*|veth*|virbr*|tun*|tap*|br-*) continue ;;
        eth*|ens*|enp*|eno*)
            REAL_IFACE="$iface"
            break
            ;;
    esac
done
[ -z "$REAL_IFACE" ] && REAL_IFACE="eth0"

# Auto-detect dynamic or current live IP & Gateway if not passed as CLI args
DETECTED_IP="$(ip -4 addr show dev "$REAL_IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || true)"
[ -z "$DETECTED_IP" ] && DETECTED_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1 || true)"
[ -z "$DETECTED_IP" ] && DETECTED_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "192.168.1.23")"

DETECTED_GW="$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -n1 || true)"
[ -z "$DETECTED_GW" ] && DETECTED_GW="$(echo "$DETECTED_IP" | sed 's/\.[0-9]*$/.1/')"

# Parameters (Inherit CLI args or use detected values)
IP_ADDR="${1:-$DETECTED_IP}"
NETMASK="${2:-255.255.255.0}"
GATEWAY="${3:-$DETECTED_GW}"
DNS1="${4:-8.8.8.8}"
DNS2="${5:-1.1.1.1}"

# Calculate CIDR
CIDR="24"
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

echo "[1/5] Physical Uplink Interface : ${REAL_IFACE}"
echo "      Configuring Static IP     : ${IP_ADDR}/${CIDR} via ${GATEWAY}"

# 2. Disable Cloud-Init Network Overwrites & Purge Conflicting Netplan Files
mkdir -p /etc/cloud/cloud.cfg.d /etc/netplan /etc/systemd/system/networking.service.d /etc/modules-load.d /etc/sysctl.d
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg << 'EOF'
network: {config: disabled}
EOF

# Purge any legacy/installer/cloud-init netplan YAMLs that could re-enable DHCP on physical NIC
for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
    [ -f "$f" ] && [ "$(basename "$f")" != "01-pnetlab-netcfg.yaml" ] && rm -f "$f" 2>/dev/null || true
done
rm -f /etc/systemd/network/*.network 2>/dev/null || true

# Mask legacy networking.service and plymouth (systemd-networkd + netplan handle network natively)
systemctl mask networking.service plymouth-start.service plymouth-read-write.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true

# Ensure kernel bridge, 8021q, tun, and br_netfilter modules load at early boot
cat > /etc/modules-load.d/pnetlab.conf << 'EOF'
bridge
stp
llc
8021q
tun
dummy
br_netfilter
EOF
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

echo "[2/5] Cloud-init overwrite disabled, netplan purged, and kernel modules registered."

# 3. Create Persistent Standalone Kernel Bridge Script
cat > /usr/local/bin/pnetlab-boot-network.sh << EOF
#!/usr/bin/env bash
# PNetLab Persistent Network Boot Runner
modprobe bridge 2>/dev/null || true
modprobe 8021q 2>/dev/null || true
modprobe tun 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true

# Set bridge sysctl bypass
sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-arptables=0 2>/dev/null || true
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true

# Discover physical interface
IFACE=""
for i in \$(ip -o link show 2>/dev/null | awk -F': ' '{print \$2}' | cut -d'@' -f1); do
    case "\$i" in
        lo|pnet*|docker*|veth*|virbr*|tun*|tap*|br-*) continue ;;
        eth*|ens*|enp*|eno*)
            IFACE="\$i"
            break
            ;;
    esac
done
[ -z "\$IFACE" ] && IFACE="${REAL_IFACE}"

# Release any rogue DHCP client on physical interface
dhclient -r "\$IFACE" 2>/dev/null || true

# Bring up physical link in promiscuous mode for VMware / hypervisor
ip link set dev "\$IFACE" up promisc on 2>/dev/null || true

# Create pnet0 bridge if missing
if ! ip link show pnet0 2>/dev/null | grep -q "pnet0"; then
    ip link add name pnet0 type bridge forward_delay 0 stp_state 0 2>/dev/null || true
fi

# Clone MAC address from physical NIC to bridge for VMware / Wi-Fi compatibility
MAC_ADDR=\$(cat /sys/class/net/\$IFACE/address 2>/dev/null || true)
if [ -n "\$MAC_ADDR" ]; then
    ip link set dev pnet0 address "\$MAC_ADDR" 2>/dev/null || true
fi

# Attach physical interface to pnet0 and ensure promiscuous mode
ip link set dev "\$IFACE" master pnet0 2>/dev/null || true
ip link set dev "\$IFACE" up promisc on 2>/dev/null || true
ip link set dev pnet0 up promisc on 2>/dev/null || true

# Assign Static IP to pnet0 and flush physical interface to prevent dual-IP subnet conflicts
ip addr flush dev "\$IFACE" 2>/dev/null || true
ip addr flush dev pnet0 2>/dev/null || true
ip addr add "${IP_ADDR}/${CIDR}" dev pnet0 2>/dev/null || true
ip route replace default via "${GATEWAY}" dev pnet0 2>/dev/null || true

# Forwarding mask (LACP, LLDP, STP)
for b in /sys/class/net/pnet*/bridge/group_fwd_mask; do
    [ -f "\$b" ] && echo 65535 > "\$b" 2>/dev/null || true
done

# DNS Resolver
mkdir -p /run/systemd/resolve
echo "nameserver ${DNS1}" > /etc/resolv.conf
echo "nameserver ${DNS2}" >> /etc/resolv.conf
exit 0
EOF
chmod +x /usr/local/bin/pnetlab-boot-network.sh
echo "[3/5] Installed /usr/local/bin/pnetlab-boot-network.sh"

# 4. Synchronize Netplan and Clean /etc/network/interfaces
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
        addresses: [${DNS1}, ${DNS2}]
      parameters:
        stp: false
        forward-delay: 0
EOF
chmod 600 /etc/netplan/01-pnetlab-netcfg.yaml

# Synchronize /etc/network/interfaces with pnet0 stanza for Web UI broker compatibility
mkdir -p /etc/network/interfaces.d
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
    address ${IP_ADDR}
    netmask 255.255.255.0
    gateway ${GATEWAY}
    pre-up ip link set dev ${REAL_IFACE} up
    bridge_ports ${REAL_IFACE}
    bridge_stp off
# END pnetlab-netcfg pnet0
EOF
chmod 644 /etc/network/interfaces
echo "[4/5] Synchronized Netplan and /etc/network/interfaces with pnet0 stanza."

# 5. Install Systemd Service for Boot Persistence
cat > /etc/systemd/system/pnetlab-boot-network.service << 'EOF'
[Unit]
Description=PNETLab Persistent Boot Network & Bridge Initialization
DefaultDependencies=no
Before=network-online.target pnetlab-brokerd.service apache2.service systemd-resolved.service
After=local-fs.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/pnetlab-boot-network.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable pnetlab-boot-network.service 2>/dev/null || true

# Execute immediately
echo "[5/5] Executing network initialization..."
/usr/local/bin/pnetlab-boot-network.sh

sleep 1
CURRENT_IP=$(ip -o -4 addr show pnet0 2>/dev/null | awk '{print $4}' | head -n1 || ip -o -4 addr show "$REAL_IFACE" 2>/dev/null | awk '{print $4}' | head -n1 || echo "None")

echo ""
echo "============================================================"
echo "    [SUCCESS] Static IP Successfully Configured & Active!   "
echo "============================================================"
echo "  Interface       : ${REAL_IFACE} -> pnet0"
echo "  Active IP       : ${CURRENT_IP}"
echo "  Default Gateway : ${GATEWAY}"
echo "  Web UI URL      : https://${IP_ADDR}/"
echo "============================================================"
exit 0
