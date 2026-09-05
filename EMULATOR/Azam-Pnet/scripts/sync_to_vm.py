#!/usr/bin/env python3
"""
Synchronize all local changes in Azam-Pnet to remote VM (192.168.1.29)
and execute the upgrade & fix suite.
"""

import os
import sys
import time
import stat
import paramiko

VM_HOST = "192.168.1.29"
VM_PORT = 22
VM_USER = "root"
VM_PASS = "azam"
REMOTE_BASE = "/opt/azambasha"
LOCAL_BASE = r"e:\Git\EMULATOR\Azam-Pnet"

def create_ssh_client():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        VM_HOST,
        port=VM_PORT,
        username=VM_USER,
        password=VM_PASS,
        look_for_keys=False,
        allow_agent=False,
        timeout=15,
        banner_timeout=30
    )
    return client

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

def sync_files():
    print(f"[*] Connecting to {VM_USER}@{VM_HOST} via SSH/SFTP...")
    client = create_ssh_client()
    sftp = client.open_sftp()
    
    print(f"[*] Ensuring base directory {REMOTE_BASE} exists...")
    ensure_remote_dir(sftp, REMOTE_BASE)
    
    # Collect remote file sizes
    print("[*] Scanning remote directory tree...")
    def get_remote_tree(path):
        res = {}
        try:
            entries = sftp.listdir_attr(path)
        except Exception:
            return res
        for entry in entries:
            r_path = path + "/" + entry.filename
            if stat.S_ISDIR(entry.st_mode):
                res.update(get_remote_tree(r_path))
            else:
                res[r_path] = entry.st_size
        return res

    remote_tree = get_remote_tree(REMOTE_BASE)
    print(f"[+] Found {len(remote_tree)} existing files on remote VM.")
    
    to_upload = []
    total_upload_bytes = 0
    
    for root, dirs, files in os.walk(LOCAL_BASE):
        if ".git" in dirs:
            dirs.remove(".git")
        for f in files:
            local_path = os.path.join(root, f)
            rel_path = os.path.relpath(local_path, LOCAL_BASE).replace("\\", "/")
            remote_path = f"{REMOTE_BASE}/{rel_path}"
            l_size = os.path.getsize(local_path)
            
            if remote_path not in remote_tree or remote_tree[remote_path] != l_size:
                to_upload.append((local_path, remote_path, rel_path, l_size))
                total_upload_bytes += l_size

    print(f"\n[*] Files to sync: {len(to_upload)} files ({total_upload_bytes / (1024*1024):.2f} MB)")
    
    uploaded_bytes = 0
    start_time = time.time()
    
    for i, (l_path, r_path, rel_path, size) in enumerate(to_upload, 1):
        r_dir = os.path.dirname(r_path).replace("\\", "/")
        ensure_remote_dir(sftp, r_dir)
        
        print(f"[{i}/{len(to_upload)}] Uploading {rel_path} ({size / 1024:.1f} KB)...", end="", flush=True)
        t0 = time.time()
        sftp.put(l_path, r_path)
        elapsed = time.time() - t0
        speed = (size / (1024 * 1024)) / elapsed if elapsed > 0 else 0
        print(f" Done ({speed:.2f} MB/s)")
        uploaded_bytes += size

    sftp.close()
    
    total_elapsed = time.time() - start_time
    print(f"\n[+] All {len(to_upload)} files synchronized successfully in {total_elapsed:.1f}s!")
    
    client.close()

if __name__ == "__main__":
    sync_files()
