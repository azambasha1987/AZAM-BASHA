#!/usr/bin/env python3
# ==============================================================================
# PNetLab Permanent eth0 / First-Boot Wizard Fix for Ubuntu 24/26
# Eliminates the "Interface eth0 not found" dialog on restart / login by:
# 1. Neutralizing auto-execution of ovfconfig.sh in /etc/profile.d/ovf.sh
# 2. Patching /opt/ovf/ovfconfig.sh to dynamically support ens33/ens160/enp0s3
# 3. Patching /opt/ovf/ovfstartup.sh, pnet-bridges.sh & pnet-fwd-reconcile.sh
# 4. Marking /opt/ovf/.configured as permanently configured
# 5. Masking legacy first-boot wizards and clearing pending flags
# ==============================================================================
import os
import subprocess
import shutil
import re

print("=" * 60)
print("    Applying Permanent eth0 & OVF Setup Modernization Fix   ")
print("=" * 60)

# 1. Discover primary physical interface
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
print(f"[1/5] Detected primary physical uplink: {real_iface}")

# 2. Mark /opt/ovf/.configured permanently
print("[2/5] Marking OVF configuration flags...")
os.makedirs("/opt/ovf", exist_ok=True)
uuid = ""
try:
    uuid = subprocess.run(["dmidecode", "-s", "system-uuid"], capture_output=True, text=True, timeout=3).stdout.strip()
except Exception:
    pass

for flag_file in ["/opt/ovf/.configured", "/opt/ovf/configured", "/opt/unetlab/.configured"]:
    try:
        with open(flag_file, "w") as f:
            f.write(uuid if uuid else "configured\n")
        os.chmod(flag_file, 0o644)
    except Exception:
        pass

# Clear pending firstboot flag if present
for pending in ["/opt/unetlab/.netcfg_pending", "/opt/ovf/.netcfg_pending"]:
    try:
        if os.path.exists(pending):
            os.remove(pending)
    except Exception:
        pass
print("      -> Cleared legacy firstboot and pending flags")

# 3. Neutralize /etc/profile.d/ovf.sh
print("[3/5] Neutralizing auto-launch in /etc/profile.d/ovf.sh...")
profile_ovf = "/etc/profile.d/ovf.sh"
if os.path.exists(profile_ovf):
    content = """# PNetLab aliases and environment (Setup wizard auto-run disabled on modern Ubuntu)
alias unl_wrapper='/opt/unetlab/wrappers/unl_wrapper'
alias pnet_info='/opt/unetlab/scripts/pnet_info.sh'
"""
    with open(profile_ovf, "w") as f:
        f.write(content)
    os.chmod(profile_ovf, 0o644)
    print("      -> Updated /etc/profile.d/ovf.sh")

# 4. Patch /opt/ovf/ovfconfig.sh
print("[4/5] Patching /opt/ovf/ovfconfig.sh...")
ovfconfig_path = "/opt/ovf/ovfconfig.sh"
if os.path.exists(ovfconfig_path):
    with open(ovfconfig_path, "r", encoding="utf-8", errors="ignore") as f:
        c = f.read()
    
    # Replace eth0 check with dynamic check
    old_check = '''# Checking if eth0 exists
if [[ ! -e "/sys/class/net/eth0" ]]; then
    dialog --backtitle "${TITLE}" --no-cancel --stdout --title 'Networking' --msgbox '\nInterface eth0 not found.' 7 40
    exit
fi'''

    new_check = f'''# Dynamic interface check (modern Ubuntu)
REAL_IFACE=$(ip -o link show 2>/dev/null | awk -F': ' '{{print $2}}' | cut -d'@' -f1 | grep -E '^(ens|enp|eno|eth)' | head -n1)
[ -z "$REAL_IFACE" ] && REAL_IFACE="{real_iface}"
'''
    if old_check in c:
        c = c.replace(old_check, new_check)
    else:
        # Generic replacement of eth0 checks
        c = re.sub(r'if\s+\[\[\s+!\s+-e\s+"/sys/class/net/eth0"\s+\]\];.*?fi', new_check, c, flags=re.DOTALL)
    
    # Also replace references to eth0 in ovfconfig with $REAL_IFACE
    c = c.replace('eth0', '$REAL_IFACE')

    with open(ovfconfig_path, "w", encoding="utf-8") as f:
        f.write(c)
    os.chmod(ovfconfig_path, 0o755)
    print("      -> Successfully patched /opt/ovf/ovfconfig.sh")

# 5. Patch /opt/ovf/ovfstartup.sh, pnet-bridges.sh & pnet-fwd-reconcile.sh
print("[5/5] Patching ovfstartup, pnet-bridges, and ebtables firewall rules...")
for script in ["/opt/ovf/ovfstartup.sh", "/opt/ovf/pnet-bridges.sh", "/opt/ovf/pnet-fwd-reconcile.sh"]:
    if os.path.exists(script):
        with open(script, "r", encoding="utf-8", errors="ignore") as f:
            sc = f.read()
        
        # Replace ebtables / iptables -o eth0 with real_iface
        sc_patched = sc.replace("-o eth0", f"-o {real_iface}").replace("dev eth0", f"dev {real_iface}")
        with open(script, "w", encoding="utf-8") as f:
            f.write(sc_patched)
        os.chmod(script, 0o755)
        print(f"      -> Patched {script}")

# Mask firstboot service if present
subprocess.run(["systemctl", "mask", "pnetlab-netcfg-firstboot.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(["systemctl", "daemon-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

print("=" * 60)
print("    [SUCCESS] eth0 & First-Boot Wizard Permanently Neutralized! ")
print("=" * 60)
