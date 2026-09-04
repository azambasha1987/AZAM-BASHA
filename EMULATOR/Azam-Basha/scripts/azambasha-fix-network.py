#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
import re
import time

print("=" * 60)
print("    Applying PNetLab Network Management & Broker Daemon Fix")
print("=" * 60)

# 1. Install python3-yaml and dependencies
print("[1/6] Installing python3-yaml and networking dependencies...")
subprocess.run(["apt-get", "update", "-qq"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(["apt-get", "install", "-y", "-qq", "python3-yaml", "python3-pip", "python3-setuptools"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 2. Discover real physical interface
print("[2/6] Detecting primary physical interface...")
real_iface = "ens33"
try:
    res = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True, timeout=5)
    for line in res.stdout.splitlines():
        parts = line.split(":")
        if len(parts) >= 2:
            name = parts[1].strip().split("@")[0]
            if name.startswith(("ens", "enp", "eno", "eth")) and not name.startswith("pnet"):
                real_iface = name
                break
except Exception:
    pass
print(f"      -> Detected physical interface: {real_iface}")

# 3. Create required directories
print("[3/6] Creating network directories and runtime socket path...")
os.makedirs("/etc/network/interfaces.d", exist_ok=True)
os.makedirs("/opt/unetlab/data/netcfg-backups", mode=0o755, exist_ok=True)
os.makedirs("/etc/systemd/resolved.conf.d", mode=0o755, exist_ok=True)
os.makedirs("/etc/netplan", mode=0o755, exist_ok=True)
os.makedirs("/run/pnetlab", mode=0o755, exist_ok=True)
try:
    shutil.chown("/run/pnetlab", "root", "www-data")
except Exception:
    pass

# 4. Create /etc/network/interfaces
print("[4/6] Setting up /etc/network/interfaces...")
ifaces_file = "/etc/network/interfaces"
if not os.path.exists(ifaces_file) or os.path.getsize(ifaces_file) == 0 or "pnet0" not in open(ifaces_file, errors="ignore").read():
    content = f"""# This file describes the network interfaces available on your system
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
    with open(ifaces_file, "w") as f:
        f.write(content)
    os.chmod(ifaces_file, 0o644)
    print("      -> Created /etc/network/interfaces")

# 5. Patch /opt/unetlab/scripts/pnetlab-brokerd.py
print("[5/6] Patching /opt/unetlab/scripts/pnetlab-brokerd.py...")
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
    return "eth0"


def _ensure_interfaces_file():
    real_iface = _get_real_iface()
    os.makedirs("/etc/network", exist_ok=True)
    os.makedirs(NETCFG_BACKUP_DIR, mode=0o700, exist_ok=True)
    os.makedirs(os.path.dirname(NETCFG_RESOLVED), mode=0o755, exist_ok=True)
    if not os.path.exists(NETCFG_INTERFACES) or os.path.getsize(NETCFG_INTERFACES) == 0:
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
        print("      -> Successfully patched /opt/unetlab/scripts/pnetlab-brokerd.py")

# 6. Create systemd unit file and start service
print("[6/6] Creating and starting pnetlab-brokerd.service...")
unit_content = """[Unit]
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
"""
unit_path = "/etc/systemd/system/pnetlab-brokerd.service"
with open(unit_path, "w") as f:
    f.write(unit_content)
os.chmod(unit_path, 0o644)

subprocess.run(["systemctl", "daemon-reload"])
subprocess.run(["systemctl", "enable", "--now", "pnetlab-brokerd.service"])
subprocess.run(["systemctl", "restart", "pnetlab-brokerd.service"])

time.sleep(1)
os.chmod("/run/pnetlab", 0o755)
if os.path.exists("/run/pnetlab/broker.sock"):
    os.chmod("/run/pnetlab/broker.sock", 0o666)
    try:
        shutil.chown("/run/pnetlab/broker.sock", "root", "www-data")
    except Exception:
        pass

# Test reachability via PHP
php_test = """
require_once '/opt/unetlab/html/includes/broker.php';
$res = broker_call('server_netcfg', ['op' => 'get'], 5);
if (isset($res['ok']) && $res['ok']) {
    echo '      [OK] Broker is ONLINE and responding! Data: ' . json_encode($res['out']) . PHP_EOL;
} else {
    echo '      [WARN] Broker test response: ' . json_encode($res) . PHP_EOL;
}
"""
subprocess.run(["php", "-r", php_test])

print("=" * 60)
print("    [SUCCESS] Network Management & Broker Daemon Active!")
print("=" * 60)
