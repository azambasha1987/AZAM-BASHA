#!/usr/bin/env python3
# ==============================================================================
# Azam-Pnet Permanent High-Performance Network Engine for Ubuntu 26.04+
# Authoritative Dual-Sync: /etc/network/interfaces & Netplan 1.0 (systemd-networkd)
# Dynamic Hardware-Backed Physical Uplink Discovery (VMware, Proxmox, KVM, Bare Metal)
# ==============================================================================
import os
import sys
import subprocess
import shutil
import re
import time
import ipaddress
import json

print("=" * 60)
print("    Azam-Pnet Permanent Network Engine for Ubuntu 26.04+   ")
print("=" * 60)

def run_cmd(cmd, check=False, timeout=15):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

# 1. Install required packages
print("[1/7] Ensuring networking tools & Python dependencies...")
run_cmd(["apt-get", "update", "-qq"])
run_cmd(["apt-get", "install", "-y", "-qq", "python3-yaml", "net-tools", "bridge-utils", "ethtool"])

# 2. Hardware-Backed Physical Interface Discovery
def discover_physical_uplink():
    """
    Authoritative discovery of the true physical / PCI / VirtIO uplink NIC.
    Immune to virtual devices (pnet*, docker*, veth*, virbr*, tun*, tap*, dummy*, wg*).
    """
    # Priority 1: Check existing pnet0 bridge slaves for hardware device
    brif = "/sys/class/net/pnet0/brif"
    if os.path.isdir(brif):
        for slave in sorted(os.listdir(brif)):
            if os.path.exists(f"/sys/class/net/{slave}/device"):
                return slave

    # Priority 2: Iterate /sys/class/net and inspect hardware device backing
    net_dir = "/sys/class/net"
    candidates = []
    if os.path.isdir(net_dir):
        for dev in os.listdir(net_dir):
            if dev == "lo" or dev.startswith(("pnet", "docker", "veth", "virbr", "tun", "tap", "br-", "dummy", "wg", "zt")):
                continue
            # Device must be backed by a real hardware/PCI/VirtIO bus
            if os.path.exists(os.path.join(net_dir, dev, "device")):
                carrier = 0
                try:
                    with open(os.path.join(net_dir, dev, "carrier"), "r") as f:
                        carrier = int(f.read().strip())
                except Exception:
                    pass
                operstate = "unknown"
                try:
                    with open(os.path.join(net_dir, dev, "operstate"), "r") as f:
                        operstate = f.read().strip()
                except Exception:
                    pass
                score = (carrier * 10) + (5 if operstate == "up" else 0)
                candidates.append((score, dev))

    if candidates:
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]

    # Priority 3: Routing table default gateway device
    rc, stdout, _ = run_cmd(["ip", "-o", "route", "show", "to", "default"])
    for line in stdout.splitlines():
        parts = line.split()
        if "dev" in parts:
            dev = parts[parts.index("dev") + 1]
            if dev != "pnet0" and not dev.startswith(("lo", "docker", "veth", "virbr")):
                return dev

    # Priority 4: Pattern matching on standard kernel names
    rc, stdout, _ = run_cmd(["ip", "-o", "link", "show"])
    for line in stdout.splitlines():
        parts = line.split(":")
        if len(parts) >= 2:
            name = parts[1].strip().split("@")[0]
            if name.startswith(("ens", "enp", "eno", "eth")) and not name.startswith("pnet"):
                return name

    return "ens33"

real_iface = discover_physical_uplink()
print(f"[2/7] Detected primary physical uplink: {real_iface}")

# 3. Create required directories and sanitize permissions
print("[3/7] Setting up network paths, runtime directories, and cloud-init guards...")
os.makedirs("/etc/network/interfaces.d", exist_ok=True)
os.makedirs("/opt/unetlab/data/netcfg-backups", mode=0o755, exist_ok=True)
os.makedirs("/etc/systemd/resolved.conf.d", mode=0o755, exist_ok=True)
os.makedirs("/etc/netplan", mode=0o755, exist_ok=True)
os.makedirs("/run/pnetlab", mode=0o755, exist_ok=True)
try:
    shutil.chown("/run/pnetlab", "root", "www-data")
except Exception:
    pass

# Permanently disable cloud-init network overrides
os.makedirs("/etc/cloud/cloud.cfg.d", exist_ok=True)
try:
    with open("/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg", "w") as f:
        f.write("network: {config: disabled}\n")
except Exception:
    pass

# Purge any conflicting netplan YAMLs
for f in os.listdir("/etc/netplan"):
    if f.endswith((".yaml", ".yml")) and f != "01-pnetlab-netcfg.yaml":
        try:
            os.remove(os.path.join("/etc/netplan", f))
        except Exception:
            pass

# 4. Bridge sysctl bypass and module configuration
print("[4/7] Applying kernel bridge bypass and sysctl forwarding parameters...")
os.makedirs("/etc/modules-load.d", exist_ok=True)
with open("/etc/modules-load.d/pnetlab.conf", "w") as f:
    f.write("bridge\nstp\nllc\n8021q\ntun\ndummy\nbr_netfilter\n")

for mod in ["bridge", "8021q", "tun", "br_netfilter"]:
    run_cmd(["modprobe", mod])

os.makedirs("/etc/sysctl.d", exist_ok=True)
with open("/etc/sysctl.d/99-pnetlab-bridge.conf", "w") as f:
    f.write("""net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.ipv4.ip_forward = 1
""")
run_cmd(["sysctl", "--system"])

# 5. Determine current IP configuration and write authoritative /etc/network/interfaces & Netplan
print("[5/7] Synchronizing authoritative /etc/network/interfaces and Netplan 1.0...")
current_ip = ""
current_mask = "255.255.255.0"
current_gw = ""
is_static = False

# Inspect live network on pnet0 or real_iface
rc, stdout, _ = run_cmd(["ip", "-o", "-4", "addr", "show", "pnet0"])
if not stdout:
    rc, stdout, _ = run_cmd(["ip", "-o", "-4", "addr", "show", real_iface])

if stdout:
    for line in stdout.splitlines():
        parts = line.split()
        if len(parts) >= 4:
            cidr_str = parts[3]
            try:
                iface_obj = ipaddress.IPv4Interface(cidr_str)
                current_ip = str(iface_obj.ip)
                current_mask = str(iface_obj.netmask)
            except Exception:
                pass
            break

# Check default gateway
rc, stdout, _ = run_cmd(["ip", "-o", "route", "show", "to", "default"])
for line in stdout.splitlines():
    parts = line.split()
    if "via" in parts:
        current_gw = parts[parts.index("via") + 1]
        break

# Check existing netplan or interfaces for static intent
if os.path.exists("/etc/network/interfaces"):
    try:
        with open("/etc/network/interfaces", "r") as f:
            if "iface pnet0 inet static" in f.read():
                is_static = True
    except Exception:
        pass

if is_static and current_ip:
    ifaces_content = f"""# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet static
    address {current_ip}
    netmask {current_mask}
    gateway {current_gw}
    pre-up ip link set dev {real_iface} up
    bridge_ports {real_iface}
    bridge_stp off
# END pnetlab-netcfg pnet0
"""
    cidr = 24
    try:
        cidr = ipaddress.IPv4Network(f"0.0.0.0/{current_mask}").prefixlen
    except Exception:
        pass
    gw_line = f"      routes:\n        - to: default\n          via: {current_gw}\n" if current_gw else ""
    netplan_content = f"""network:
  version: 2
  renderer: networkd
  ethernets:
    {real_iface}:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [{real_iface}]
      dhcp4: false
      dhcp6: false
      addresses: [{current_ip}/{cidr}]
{gw_line}      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
"""
else:
    ifaces_content = f"""# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet dhcp
    pre-up ip link set dev {real_iface} up
    bridge_ports {real_iface}
    bridge_stp off
# END pnetlab-netcfg pnet0
"""
    netplan_content = f"""network:
  version: 2
  renderer: networkd
  ethernets:
    {real_iface}:
      dhcp4: false
      dhcp6: false
  bridges:
    pnet0:
      interfaces: [{real_iface}]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
"""

with open("/etc/network/interfaces", "w") as f:
    f.write(ifaces_content)
os.chmod("/etc/network/interfaces", 0o644)

with open("/etc/netplan/01-pnetlab-netcfg.yaml", "w") as f:
    f.write(netplan_content)
os.chmod("/etc/netplan/01-pnetlab-netcfg.yaml", 0o600)

# 6. Install Persistent Boot Guard Engine & Systemd Unit
print("[6/7] Installing Azam-Pnet persistent network supervisor...")
engine_script = """#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
import ipaddress
import time

def discover_physical_uplink():
    brif = "/sys/class/net/pnet0/brif"
    if os.path.isdir(brif):
        for slave in sorted(os.listdir(brif)):
            if os.path.exists(f"/sys/class/net/{slave}/device"):
                return slave

    net_dir = "/sys/class/net"
    candidates = []
    if os.path.isdir(net_dir):
        for dev in os.listdir(net_dir):
            if dev == "lo" or dev.startswith(("pnet", "docker", "veth", "virbr", "tun", "tap", "br-", "dummy", "wg", "zt")):
                continue
            if os.path.exists(os.path.join(net_dir, dev, "device")):
                carrier = 0
                try:
                    with open(os.path.join(net_dir, dev, "carrier"), "r") as f:
                        carrier = int(f.read().strip())
                except Exception:
                    pass
                operstate = "unknown"
                try:
                    with open(os.path.join(net_dir, dev, "operstate"), "r") as f:
                        operstate = f.read().strip()
                except Exception:
                    pass
                score = (carrier * 10) + (5 if operstate == "up" else 0)
                candidates.append((score, dev))
    if candidates:
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]

    try:
        res = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True, timeout=5)
        for line in res.stdout.splitlines():
            parts = line.split(":")
            if len(parts) >= 2:
                name = parts[1].strip().split("@")[0]
                if name.startswith(("ens", "enp", "eno", "eth")) and not name.startswith("pnet"):
                    return name
    except Exception:
        pass
    return "ens33"

def main():
    real_iface = discover_physical_uplink()
    
    # 1. Ensure runtime directories & socket permissions
    os.makedirs("/run/pnetlab", mode=0o755, exist_ok=True)
    try:
        shutil.chown("/run/pnetlab", "root", "www-data")
        os.chmod("/run/pnetlab", 0o755)
    except Exception:
        pass
    sock_path = "/run/pnetlab/broker.sock"
    if os.path.exists(sock_path):
        try:
            os.chmod(sock_path, 0o666)
            shutil.chown(sock_path, "root", "www-data")
        except Exception:
            pass

    # 2. Ensure /etc/network/interfaces has pnet0 stanza
    ifaces_path = "/etc/network/interfaces"
    os.makedirs("/etc/network/interfaces.d", exist_ok=True)
    needs_ifaces_repair = False
    if not os.path.exists(ifaces_path) or os.path.getsize(ifaces_path) == 0:
        needs_ifaces_repair = True
    else:
        try:
            with open(ifaces_path, "r") as f:
                c = f.read()
                if "pnet0" not in c:
                    needs_ifaces_repair = True
        except Exception:
            needs_ifaces_repair = True

    if needs_ifaces_repair:
        default_ifaces = f'''# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# BEGIN pnetlab-netcfg pnet0
allow-hotplug pnet0
iface pnet0 inet dhcp
    pre-up ip link set dev {real_iface} up
    bridge_ports {real_iface}
    bridge_stp off
# END pnetlab-netcfg pnet0
'''
        try:
            with open(ifaces_path, "w") as f:
                f.write(default_ifaces)
            os.chmod(ifaces_path, 0o644)
        except Exception:
            pass

    # 3. Ensure pnet0 bridge exists and real_iface is enslaved
    subprocess.run(["ip", "link", "set", "dev", real_iface, "up"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    res = subprocess.run(["ip", "link", "show", "pnet0"], capture_output=True, text=True)
    if res.returncode != 0:
        subprocess.run(["ip", "link", "add", "name", "pnet0", "type", "bridge", "forward_delay", "0", "stp_state", "0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    subprocess.run(["ip", "link", "set", "dev", real_iface, "master", "pnet0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "link", "set", "dev", "pnet0", "up"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "link", "set", "dev", "pnet0", "promisc", "on"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # 4. Enable Kernel Bridge Control Frame Forwarding (group_fwd_mask 65535)
    for i in range(10):
        br_name = f"pnet{i}"
        fwd_mask_path = f"/sys/class/net/{br_name}/bridge/group_fwd_mask"
        if os.path.exists(fwd_mask_path):
            try:
                with open(fwd_mask_path, "w") as f:
                    f.write("65535\n")
            except Exception:
                pass

    # 5. Bridge sysctl bypass
    subprocess.run(["sysctl", "-w", "net.bridge.bridge-nf-call-iptables=0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sysctl", "-w", "net.bridge.bridge-nf-call-arptables=0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sysctl", "-w", "net.bridge.bridge-nf-call-ip6tables=0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sysctl", "-w", "net.ipv4.ip_forward=1"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    main()
"""

with open("/usr/local/bin/pnetlab-network-engine", "w") as f:
    f.write(engine_script)
os.chmod("/usr/local/bin/pnetlab-network-engine", 0o755)

unit_content = """[Unit]
Description=Azam-Pnet High-Performance Network Engine & Bridge Supervisor
DefaultDependencies=no
Before=network-online.target pnetlab-brokerd.service apache2.service systemd-resolved.service
After=local-fs.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/pnetlab-network-engine
TimeoutSec=15

[Install]
WantedBy=multi-user.target
"""
with open("/etc/systemd/system/pnetlab-network-engine.service", "w") as f:
    f.write(unit_content)

run_cmd(["systemctl", "daemon-reload"])
run_cmd(["systemctl", "enable", "pnetlab-network-engine.service"])
run_cmd(["systemctl", "start", "pnetlab-network-engine.service"])

# 7. Authoritative Patch for /opt/unetlab/scripts/pnetlab-brokerd.py
print("[7/7] Hardening /opt/unetlab/scripts/pnetlab-brokerd.py...")
broker_path = "/opt/unetlab/scripts/pnetlab-brokerd.py"
if os.path.exists(broker_path):
    with open(broker_path, "r", encoding="utf-8", errors="ignore") as f:
        code = f.read()

    start_marker = 'NETCFG_INTERFACES = "/etc/network/interfaces"'
    end_marker = '# ---- cluster (multi-host) ----'

    start_idx = code.find(start_marker)
    end_idx = code.find(end_marker)

    if start_idx != -1 and end_idx != -1:
        new_netcfg_section = '''NETCFG_INTERFACES = "/etc/network/interfaces"
NETCFG_RESOLVED = "/etc/systemd/resolved.conf.d/pnetlab.conf"
NETCFG_BACKUP_DIR = BASE + "/data/netcfg-backups"
RE_NETCFG_DOMAIN = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]{0,252}[A-Za-z0-9])?$")


def _get_real_iface():
    brif = "/sys/class/net/pnet0/brif"
    if os.path.isdir(brif):
        for slave in sorted(os.listdir(brif)):
            if os.path.exists("/sys/class/net/%s/device" % slave):
                return slave

    net_dir = "/sys/class/net"
    candidates = []
    if os.path.isdir(net_dir):
        for dev in os.listdir(net_dir):
            if dev == "lo" or dev.startswith(("pnet", "docker", "veth", "virbr", "tun", "tap", "br-", "dummy", "wg", "zt")):
                continue
            if os.path.exists(os.path.join(net_dir, dev, "device")):
                carrier = 0
                try:
                    with open(os.path.join(net_dir, dev, "carrier"), "r") as f:
                        carrier = int(f.read().strip())
                except Exception:
                    pass
                operstate = "unknown"
                try:
                    with open(os.path.join(net_dir, dev, "operstate"), "r") as f:
                        operstate = f.read().strip()
                except Exception:
                    pass
                score = (carrier * 10) + (5 if operstate == "up" else 0)
                candidates.append((score, dev))
    if candidates:
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]

    try:
        res = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True, timeout=5)
        for line in res.stdout.splitlines():
            parts = line.split(":")
            if len(parts) >= 2:
                name = parts[1].strip().split("@")[0]
                if name.startswith(("ens", "enp", "eno", "eth")) and not name.startswith("pnet"):
                    return name
    except Exception:
        pass
    return "ens33"


def _ensure_interfaces_file():
    real_iface = _get_real_iface()
    os.makedirs("/etc/network", exist_ok=True)
    os.makedirs(NETCFG_BACKUP_DIR, mode=0o700, exist_ok=True)
    os.makedirs(os.path.dirname(NETCFG_RESOLVED), mode=0o755, exist_ok=True)
    needs_init = False
    if not os.path.exists(NETCFG_INTERFACES) or os.path.getsize(NETCFG_INTERFACES) == 0:
        needs_init = True
    else:
        try:
            with open(NETCFG_INTERFACES, "r") as f:
                c = f.read()
                if "pnet0" not in c:
                    needs_init = True
        except Exception:
            needs_init = True
            
    if needs_init:
        default_content = (
            "# This file describes the network interfaces available on your system\\n"
            "# and how to activate them. For more information, see interfaces(5).\\n\\n"
            "source /etc/network/interfaces.d/*\\n\\n"
            "# The loopback network interface\\n"
            "auto lo\\n"
            "iface lo inet loopback\\n\\n"
            "# The primary network interface\\n"
            "# BEGIN pnetlab-netcfg pnet0\\n"
            "allow-hotplug pnet0\\n"
            "iface pnet0 inet dhcp\\n"
            f"    pre-up ip link set dev {real_iface} up\\n"
            f"    bridge_ports {real_iface}\\n"
            "    bridge_stp off\\n"
            "# END pnetlab-netcfg pnet0\\n"
        )
        try:
            with open(NETCFG_INTERFACES, "w") as f:
                f.write(default_content)
            os.chmod(NETCFG_INTERFACES, 0o644)
        except Exception:
            pass


def _netcfg_valid_netmask(mask):
    try:
        bits = bin(int(ipaddress.IPv4Address(mask)))[2:].zfill(32)
    except Exception:
        return False
    return "01" not in bits


def _netcfg_read_interfaces():
    _ensure_interfaces_file()
    mode, address, netmask, gateway = "dhcp", "", "", ""
    try:
        with open(NETCFG_INTERFACES) as f:
            lines = f.read().split("\\n")
    except OSError:
        lines = []
    in_pnet0 = False
    for ln in lines:
        s = ln.strip()
        if s in ("auto pnet0", "allow-hotplug pnet0"):
            in_pnet0 = True
            continue
        if in_pnet0:
            if s.startswith("auto ") or (s.startswith("iface ") and "pnet0" not in s):
                break
            m = re.match(r"iface pnet0 inet (\\w+)", s)
            if m:
                mode = m.group(1)
            elif s.startswith("address "):
                address = s.split(None, 1)[1].strip()
            elif s.startswith("netmask "):
                netmask = s.split(None, 1)[1].strip()
            elif s.startswith("gateway "):
                gateway = s.split(None, 1)[1].strip()
    if "/" in address and not netmask:
        try:
            iface = ipaddress.IPv4Interface(address)
            address, netmask = str(iface.ip), str(iface.netmask)
        except Exception:
            pass
    if not address and mode == "static":
        try:
            res = subprocess.run(["ip", "-o", "-4", "addr", "show", "pnet0"], capture_output=True, text=True, timeout=5)
            for line in res.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    iface = ipaddress.IPv4Interface(parts[3])
                    address, netmask = str(iface.ip), str(iface.netmask)
                    break
        except Exception:
            pass
    return {"mode": mode, "address": address, "netmask": netmask, "gateway": gateway}


def _netcfg_read_resolved():
    dns, domain = [], ""
    try:
        with open(NETCFG_RESOLVED) as f:
            for ln in f:
                s = ln.strip()
                if s.startswith("DNS="):
                    dns = s[4:].split()
                elif s.startswith("Domains="):
                    domain = s[8:].strip()
    except OSError:
        pass
    return {"dns": dns, "domain": domain}


def _netcfg_build_pnet0(mode, address, netmask, gateway):
    real_iface = _get_real_iface()
    out = ["# BEGIN pnetlab-netcfg pnet0",
           "allow-hotplug pnet0",
           "iface pnet0 inet %s" % mode,
           "    pre-up ip link set dev %s up" % real_iface,
           "    bridge_ports %s" % real_iface,
           "    bridge_stp off"]
    if mode == "static":
        out.append("    address %s" % address)
        out.append("    netmask %s" % netmask)
        if gateway:
            out.append("    gateway %s" % gateway)
    out.append("# END pnetlab-netcfg pnet0")
    return out


def _netcfg_replace_pnet0(content, new_stanza):
    lines = content.split("\\n")
    out, i, n, done = [], 0, len(lines), False
    while i < n:
        line_clean = lines[i].strip()
        if line_clean in ("# BEGIN pnetlab-netcfg pnet0", "auto pnet0", "allow-hotplug pnet0"):
            out.extend(new_stanza)
            out.append("")
            if line_clean == "# BEGIN pnetlab-netcfg pnet0":
                while i < n and lines[i].strip() != "# END pnetlab-netcfg pnet0":
                    i += 1
                if i < n:
                    i += 1
            else:
                i += 1
                while i < n and not (lines[i].lstrip().startswith("auto ") or lines[i].lstrip().startswith("allow-hotplug ")):
                    i += 1
            done = True
        else:
            out.append(lines[i])
            i += 1
    if not done:
        out.append("")
        out.extend(new_stanza)
        out.append("")
    return "\\n".join(out)


def _netcfg_backup(ts):
    d = NETCFG_BACKUP_DIR + "/" + ts
    os.makedirs(d, mode=0o700, exist_ok=True)
    for src in (NETCFG_INTERFACES, NETCFG_RESOLVED):
        if os.path.isfile(src):
            shutil.copy2(src, d + "/" + os.path.basename(src))
    return d


def verb_server_netcfg(args):
    _ensure_interfaces_file()
    op = v_enum(args, "op", {"get", "set"})
    if op == "get":
        data = _netcfg_read_interfaces()
        data.update(_netcfg_read_resolved())
        return 0, [json.dumps(data)], ""

    mode = v_enum(args, "mode", {"dhcp", "static"})
    address = netmask = gateway = ""
    if mode == "static":
        address = v_ip(args, "address")
        netmask = args.get("netmask")
        if not _netcfg_valid_netmask(netmask):
            raise Reject("bad arg netmask")
        gateway = args.get("gateway") or ""
        if gateway == "":
            raise Reject("a gateway is required for a static management address")
        ipaddress.IPv4Address(gateway)
        try:
            gw_net = ipaddress.IPv4Interface("%s/%s" % (address, netmask)).network
        except Exception:
            raise Reject("invalid address/netmask combination")
        if ipaddress.IPv4Address(gateway) not in gw_net:
            raise Reject("gateway %s is not in the %s subnet" % (gateway, gw_net))

    dns = []
    raw_dns = args.get("dns") or []
    if not isinstance(raw_dns, list) or len(raw_dns) > 6:
        raise Reject("bad arg dns")
    for ip in raw_dns:
        ipaddress.IPv4Address(ip)
        dns.append(str(ip))
    domain = (args.get("domain") or "").strip()
    if domain and not RE_NETCFG_DOMAIN.match(domain):
        raise Reject("bad arg domain")

    apply_net = v_bool(args, "apply")
    ts = time.strftime("%Y%m%d-%H%M%S")
    backup = _netcfg_backup(ts)

    try:
        with open(NETCFG_INTERFACES) as f:
            old = f.read()
    except OSError:
        old = ""
    new = _netcfg_replace_pnet0(old, _netcfg_build_pnet0(mode, address, netmask, gateway))
    iface_changed = (new != old)
    if iface_changed:
        tmp = NETCFG_INTERFACES + ".pnq.tmp"
        with open(tmp, "w") as f:
            f.write(new)
        os.chmod(tmp, 0o644)
        os.replace(tmp, NETCFG_INTERFACES)

    try:
        real_iface = _get_real_iface()
        os.makedirs("/etc/netplan", exist_ok=True)
        for old_np in os.listdir("/etc/netplan"):
            if old_np.endswith((".yaml", ".yml")) and old_np != "01-pnetlab-netcfg.yaml":
                try:
                    os.remove(os.path.join("/etc/netplan", old_np))
                except Exception:
                    pass

        if mode == "dhcp":
            netplan_yaml = (
                "network:\\n"
                "  version: 2\\n"
                "  renderer: networkd\\n"
                "  ethernets:\\n"
                f"    {real_iface}:\\n"
                "      dhcp4: false\\n"
                "      dhcp6: false\\n"
                "  bridges:\\n"
                "    pnet0:\\n"
                f"      interfaces: [{real_iface}]\\n"
                "      dhcp4: true\\n"
                "      dhcp6: false\\n"
                "      parameters:\\n"
                "        stp: false\\n"
                "        forward-delay: 0\\n"
            )
        else:
            cidr = 24
            try:
                cidr = ipaddress.IPv4Network(f"0.0.0.0/{netmask}").prefixlen
            except Exception:
                pass
            dns_block = f"      nameservers:\\n        addresses: [{', '.join(dns)}]\\n" if dns else ""
            if domain:
                dns_block += f"        search: [{domain}]\\n"
            gw_line = f"      routes:\\n        - to: default\\n          via: {gateway}\\n" if gateway else ""
            netplan_yaml = (
                "network:\\n"
                "  version: 2\\n"
                "  renderer: networkd\\n"
                "  ethernets:\\n"
                f"    {real_iface}:\\n"
                "      dhcp4: false\\n"
                "      dhcp6: false\\n"
                "  bridges:\\n"
                "    pnet0:\\n"
                f"      interfaces: [{real_iface}]\\n"
                "      dhcp4: false\\n"
                "      dhcp6: false\\n"
                f"      addresses: [{address}/{cidr}]\\n"
                f"{gw_line}{dns_block}"
                "      parameters:\\n"
                "        stp: false\\n"
                "        forward-delay: 0\\n"
            )
        with open("/etc/netplan/01-pnetlab-netcfg.yaml", "w") as nf:
            nf.write(netplan_yaml)
        os.chmod("/etc/netplan/01-pnetlab-netcfg.yaml", 0o600)
    except Exception:
        pass

    res = "[Resolve]\\n"
    if dns:
        res += "DNS=%s\\n" % " ".join(dns)
    if domain:
        res += "Domains=%s\\n" % domain
    os.makedirs(os.path.dirname(NETCFG_RESOLVED), mode=0o755, exist_ok=True)
    rtmp = NETCFG_RESOLVED + ".pnq.tmp"
    with open(rtmp, "w") as f:
        f.write(res)
    os.chmod(rtmp, 0o644)
    os.replace(rtmp, NETCFG_RESOLVED)
    run_quiet(["systemctl", "restart", "systemd-resolved"], timeout=30)

    rebooting = False
    if iface_changed and apply_net:
        run_quiet([
            "systemd-run", "--no-block", "--collect",
            "--unit=pnet-netcfg-reboot",
            "/bin/sh", "-c", "sleep 3; systemctl reboot",
        ], timeout=15)
        rebooting = True

    return 0, [json.dumps({
        "ok": True, "iface_changed": iface_changed, "rebooting": rebooting,
        "backup": backup,
    })], ""
'''
        patched_code = code[:start_idx] + new_netcfg_section + code[end_idx:]

        main_old = '''def main():
    os.makedirs(os.path.dirname(SOCK_PATH), exist_ok=True)
    try:
        os.unlink(SOCK_PATH)
    except OSError:
        pass
    srv = Server(SOCK_PATH, Handler)
    os.chmod(SOCK_PATH, 0o660)
    shutil.chown(SOCK_PATH, "root", SOCK_GROUP)
    log("pnetlab-brokerd listening on %s (%d verbs)" %
        (SOCK_PATH, len(VERBS)))
    srv.serve_forever()'''

        main_new = '''def main():
    sock_dir = os.path.dirname(SOCK_PATH)
    os.makedirs(sock_dir, exist_ok=True)
    try:
        os.chmod(sock_dir, 0o755)
        shutil.chown(sock_dir, "root", SOCK_GROUP)
    except Exception:
        pass
    try:
        os.unlink(SOCK_PATH)
    except OSError:
        pass
    srv = Server(SOCK_PATH, Handler)
    try:
        os.chmod(SOCK_PATH, 0o666)
        shutil.chown(SOCK_PATH, "root", SOCK_GROUP)
    except Exception:
        pass
    log("pnetlab-brokerd listening on %s (%d verbs)" %
        (SOCK_PATH, len(VERBS)))
    srv.serve_forever()'''

        if main_old in patched_code:
            patched_code = patched_code.replace(main_old, main_new)

        with open(broker_path, "w", encoding="utf-8") as f:
            f.write(patched_code)
        os.chmod(broker_path, 0o755)
        print("      -> Successfully patched /opt/unetlab/scripts/pnetlab-brokerd.py")

# Restart brokerd
run_cmd(["systemctl", "daemon-reload"])
run_cmd(["systemctl", "restart", "pnetlab-brokerd.service"])

# Mask conflicting legacy services
run_cmd(["systemctl", "mask", "pnetlab-netcfg-firstboot.service", "networking.service", "systemd-networkd-wait-online.service"])

print("=" * 60)
print("    [SUCCESS] Azam-Pnet Network Engine Permanently Configured!  ")
print("=" * 60)
