#!/usr/bin/env bash
# ==============================================================================
# PNetLab Modern Netplan & Bridge Datapath Engine for Ubuntu 26+ (Resolute)
# Ensures dynamic interface discovery, dual Netplan/ifupdown synchronization,
# and kernel-native sysfs packet forwarding (group_fwd_mask 65535).
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    [1/4] Configuring Modern Netplan & Bridge Datapath...   "
echo "============================================================"

# 1. Discover Real Physical Uplink NIC
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
echo "      -> Detected primary physical uplink: ${REAL_IFACE}"

# 2. Ensure Required Directories Exist
mkdir -p /etc/network/interfaces.d
mkdir -p /opt/unetlab/data/netcfg-backups
mkdir -p /etc/systemd/resolved.conf.d
mkdir -p /etc/netplan
chmod 755 /opt/unetlab/data/netcfg-backups /etc/systemd/resolved.conf.d 2>/dev/null || true

# 3. Create /etc/network/interfaces Stanza
if [ ! -f /etc/network/interfaces ] || [ ! -s /etc/network/interfaces ] || ! grep -q "pnet0" /etc/network/interfaces; then
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
    chmod 644 /etc/network/interfaces
    echo "      -> Synchronized /etc/network/interfaces"
fi

# 4. Create /etc/netplan/01-pnetlab-netcfg.yaml for Native Ubuntu 26 Support
if [ ! -f /etc/netplan/01-pnetlab-netcfg.yaml ]; then
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
    chmod 600 /etc/netplan/01-pnetlab-netcfg.yaml
    echo "      -> Synchronized /etc/netplan/01-pnetlab-netcfg.yaml"
fi

# 5. Enable Kernel-Native Sysfs Frame Forwarding for all Bridges (LACP, LLDP, STP)
cat > /etc/systemd/system/pnetlab-bridge-fwd.service << 'EOF'
[Unit]
Description=PNETLab Kernel Bridge Control Frame Forwarding (group_fwd_mask 65535)
After=network.target network-online.target systemd-networkd.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for b in /sys/class/net/pnet*/bridge/group_fwd_mask; do [ -f "$b" ] && echo 65535 > "$b" 2>/dev/null || true; done'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable --now pnetlab-bridge-fwd.service 2>/dev/null || true

# Apply immediately to existing bridges
for b in /sys/class/net/pnet*/bridge/group_fwd_mask; do
    if [ -f "$b" ]; then
        echo 65535 > "$b" 2>/dev/null || true
    fi
done
echo "      -> Enabled kernel-native control frame forwarding (group_fwd_mask 65535)"

echo "============================================================"
echo "    [SUCCESS] Modern Netplan & Bridge Datapath Configured!  "
echo "============================================================"
