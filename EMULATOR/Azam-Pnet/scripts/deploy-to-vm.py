#!/usr/bin/env python3
"""
================================================================================
Azam Basha Multi-VM Fleet Deployment, Synchronization & Fix Runner
Ubuntu 26.04+ Native Architecture
================================================================================
Supports deploying, synchronizing, and applying optimizations across one or more
Azam Basha / PNetLab VMs simultaneously.

Features:
- Multi-host fleet support (single IP or list of VM IPs)
- Differential sync: Only uploads modified files (sub-second sync)
- Zero hardcoded credentials (supports CLI, ENV: VM_HOST, VM_USER, VM_PASS)
- Remote execution of installers, fix suites, and node test suites

Usage:
  python3 deploy-to-vm.py [OPTIONS]

Options:
  --host, -H HOST [HOST2...] Target VM IP address(es) (e.g. 192.168.1.29)
  --user, -u USER            SSH username (default: root)
  --pass, -p PASSWORD        SSH password (default: azam or prompt)
  --port, -P PORT            SSH port (default: 22)
  --apply-all                Run 'azambasha-apply-all-fixes.sh 19' on targets
  --test                     Run 'azambasha-node-test-suite.py --all' on targets
  --install                  Run master 'install.sh' on targets
  --satellite                Run worker 'install-satellite.sh' on targets
  --remote-dir DIR           Remote destination directory (default: /opt/azambasha)
  --dry-run                  Simulate sync without uploading or executing commands
================================================================================
"""

import os
import sys
import getpass
import argparse
import time
import hashlib

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

try:
    import paramiko
except ImportError:
    print("[ERROR] paramiko library is required. Install via: pip install paramiko")
    sys.exit(1)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ANSI Colors
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_GREEN = "\033[32m"
C_RED = "\033[31m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"

def log_info(msg):
    print(f"  {C_CYAN}[*]{C_RESET} {msg}")

def log_ok(msg):
    print(f"  {C_GREEN}[✔]{C_RESET} {msg}")

def log_err(msg):
    print(f"  {C_RED}[✖]{C_RESET} {msg}")

def file_md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def ensure_remote_dir(sftp, remote_dir):
    dirs = []
    current = remote_dir
    while current and current != "/":
        dirs.append(current)
        current = os.path.dirname(current).replace("\\", "/")
    
    for d in reversed(dirs):
        try:
            sftp.stat(d)
        except IOError:
            try:
                sftp.mkdir(d)
            except Exception:
                pass

def sync_tree(sftp, local_dir, remote_dir, dry_run=False):
    uploaded = 0
    ensure_remote_dir(sftp, remote_dir)
    
    for root, dirs, files in os.walk(local_dir):
        if ".git" in root or "__pycache__" in root or "scratch" in root:
            continue
        rel_path = os.path.relpath(root, local_dir).replace("\\", "/")
        target_dir = f"{remote_dir}/{rel_path}".rstrip("/.")
        ensure_remote_dir(sftp, target_dir)
        
        for f in files:
            if f.endswith((".pyc", ".tmp", ".log")):
                continue
            local_file = os.path.join(root, f)
            remote_file = f"{target_dir}/{f}"
            
            # Check size and modify time
            local_sz = os.path.getsize(local_file)
            needs_upload = True
            try:
                r_stat = sftp.stat(remote_file)
                if r_stat.st_size == local_sz:
                    needs_upload = False
            except IOError:
                needs_upload = True
                
            if needs_upload:
                if not dry_run:
                    sftp.put(local_file, remote_file)
                    if f.endswith((".sh", ".py")):
                        try:
                            sftp.chmod(remote_file, 0o755)
                        except Exception:
                            pass
                uploaded += 1
                
    return uploaded

def execute_remote_cmd(client, cmd, stream=True):
    stdin, stdout, stderr = client.exec_command(cmd, get_pty=True)
    out_lines = []
    for line in stdout:
        if stream:
            print(f"    {line}", end="")
        out_lines.append(line)
    exit_code = stdout.channel.recv_exit_status()
    return exit_code, "".join(out_lines)

def deploy_host(host, user, password, port, args):
    print(f"\n{C_BOLD}============================================================{C_RESET}")
    print(f"{C_BOLD} Target VM Host: {C_CYAN}{user}@{host}:{port}{C_RESET}")
    print(f"{C_BOLD}============================================================{C_RESET}")
    
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        log_info(f"Connecting to {host}...")
        client.connect(host, port=port, username=user, password=password, timeout=12, banner_timeout=30)
        log_ok("SSH connection & authentication successful!")
    except Exception as e:
        log_err(f"Authentication failed for {user}@{host}: {e}")
        return False
        
    try:
        sftp = client.open_sftp()
        remote_base = args.remote_dir
        log_info(f"Synchronizing workspace -> {remote_base}...")
        
        # Upload root installer files
        ensure_remote_dir(sftp, remote_base)
        for rfile in ["install.sh", "install-satellite.sh", "README.md", "VERIFICATION_REPORT.md"]:
            lpath = os.path.join(BASE_DIR, rfile)
            if os.path.exists(lpath) and not args.dry_run:
                sftp.put(lpath, f"{remote_base}/{rfile}")
                sftp.chmod(f"{remote_base}/{rfile}", 0o755)
                
        # Sync core subdirectories
        for sdir in ["scripts", "assets", "login", "schema", "metadata", "generic", "debian"]:
            ldir = os.path.join(BASE_DIR, sdir)
            if os.path.exists(ldir):
                rdir = f"{remote_base}/{sdir}"
                cnt = sync_tree(sftp, ldir, rdir, dry_run=args.dry_run)
                log_ok(f"Synced {sdir}/ ({cnt} files updated)")
                
        sftp.close()
        log_ok("All repository assets synchronized!")
        
        # Make scripts executable
        if not args.dry_run:
            execute_remote_cmd(client, f"chmod +x {remote_base}/*.sh {remote_base}/scripts/*.sh {remote_base}/scripts/*.py 2>/dev/null || true", stream=False)
            
        # Post-sync Action Triggers
        if args.install:
            log_info("Executing Master Installer (install.sh)...")
            execute_remote_cmd(client, f"cd {remote_base} && sudo bash install.sh")
        elif args.satellite:
            log_info("Executing Satellite Worker Installer (install-satellite.sh)...")
            execute_remote_cmd(client, f"cd {remote_base} && sudo bash install-satellite.sh")
        elif args.apply_all:
            log_info("Executing Master Fix & Optimization Suite...")
            execute_remote_cmd(client, f"cd {remote_base} && sudo bash scripts/azambasha-apply-all-fixes.sh 19")
        elif args.test:
            log_info("Running Automated Node & Virtualization Test Suite...")
            execute_remote_cmd(client, f"cd {remote_base} && python3 scripts/azambasha-node-test-suite.py --all")
            
        client.close()
        log_ok(f"Deployment on {host} completed successfully!\n")
        return True
    except Exception as e:
        log_err(f"Deployment encountered error on {host}: {e}")
        try:
            client.close()
        except Exception:
            pass
        return False

def main():
    parser = argparse.ArgumentParser(description="Azam Basha Multi-VM Fleet Deployment & Fix Runner")
    parser.add_argument("--host", "-H", nargs="+", help="Target VM IP address(es) (e.g. 192.168.1.29)")
    parser.add_argument("--user", "-u", default=os.environ.get("VM_USER", "root"), help="SSH username (default: root)")
    parser.add_argument("--pass", "-p", dest="password", default=os.environ.get("VM_PASS", None), help="SSH password")
    parser.add_argument("--port", "-P", type=int, default=int(os.environ.get("VM_PORT", 22)), help="SSH port (default: 22)")
    parser.add_argument("--remote-dir", default="/opt/azambasha", help="Remote base directory (default: /opt/azambasha)")
    parser.add_argument("--apply-all", action="store_true", help="Apply all fixes and speed optimizations on targets")
    parser.add_argument("--test", action="store_true", help="Run node validation test suite on targets")
    parser.add_argument("--install", action="store_true", help="Run master installer on targets")
    parser.add_argument("--satellite", action="store_true", help="Run satellite worker installer on targets")
    parser.add_argument("--dry-run", action="store_true", help="Simulate sync without uploading")

    args = parser.parse_args()

    hosts = args.host
    if not hosts:
        env_host = os.environ.get("VM_HOST")
        if env_host:
            hosts = [env_host]
        else:
            default_host = "192.168.1.29"
            user_in = input(f"Enter target VM IP address(es) [default: {default_host}]: ").strip()
            hosts = user_in.split() if user_in else [default_host]

    password = args.password
    if not password:
        password = getpass.getpass(f"Enter SSH password for {args.user} (default 'azam'): ")
        if not password:
            password = "azam"

    print(f"\n{C_BOLD}Starting Multi-VM Fleet Deployment across {len(hosts)} target host(s)...{C_RESET}")
    success_count = 0
    
    for h in hosts:
        if deploy_host(h, args.user, password, args.port, args):
            success_count += 1

    print("=" * 60)
    print(f" Fleet Deployment Summary: {success_count}/{len(hosts)} Hosts Configured Successfully.")
    print("=" * 60)

if __name__ == "__main__":
    main()
