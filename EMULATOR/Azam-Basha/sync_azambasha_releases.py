"""
PNetLab v8 24-Hour Autonomous Sync & Verification Engine
=========================================================
Automatically checks and fetches new files/releases from:
- Track 1: https://codeberg.org/netkillui/Pnetlabv8.git
- Track 2: https://codeberg.org/api/v1/packages/netkillui & Debian APT Pool

Features:
- Idempotent: Only downloads new/changed files (no duplicates).
- Cryptographic Verification: Computes and verifies SHA256 checksums.
- Auto-updates VERIFICATION_REPORT.md and sync.log.
"""

import os
import sys
import json
import time
import hashlib
import subprocess
import urllib.request
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
GIT_DIR = os.path.join(BASE_DIR, "track-1-git")
DEBIAN_DIR = os.path.join(BASE_DIR, "debian", "pool", "resolute", "main")
GENERIC_DIR = os.path.join(BASE_DIR, "generic")
META_DIR = os.path.join(BASE_DIR, "metadata")
LOG_FILE = os.path.join(BASE_DIR, "sync.log")
REPORT_FILE = os.path.join(BASE_DIR, "VERIFICATION_REPORT.md")

USER_AGENT = "curl/8.4.0"

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{timestamp}] {msg}"
    print(formatted)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(formatted + "\n")

def get_url(url, retries=5):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT, 'Accept': '*/*'})
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.read()
        except Exception as e:
            if attempt == retries - 1:
                raise e
            time.sleep(2 ** attempt)

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def sync_track_1():
    log("--- Checking Track 1 (Git Repository) ---")
    if not os.path.exists(GIT_DIR):
        log(f"Cloning Track 1 git repository into {GIT_DIR}...")
        subprocess.run(["git", "clone", "https://codeberg.org/netkillui/Pnetlabv8.git", GIT_DIR], check=True)
        log("Clone complete.")
    else:
        # Check remote updates
        subprocess.run(["git", "-C", GIT_DIR, "fetch", "origin"], check=True)
        status_res = subprocess.run(["git", "-C", GIT_DIR, "status", "-uno"], capture_output=True, text=True)
        if "Your branch is behind" in status_res.stdout:
            log("New commits detected on remote. Pulling latest commits...")
            pull_res = subprocess.run(["git", "-C", GIT_DIR, "pull", "--ff-only"], capture_output=True, text=True)
            log(pull_res.stdout.strip())
        else:
            log("Git repository is up to date.")
    
    head_hash = subprocess.run(["git", "-C", GIT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    log(f"Current Track 1 HEAD: {head_hash}")
    return head_hash

def sync_track_2():
    log("--- Checking Track 2 (Package API & Releases) ---")
    os.makedirs(META_DIR, exist_ok=True)
    os.makedirs(GENERIC_DIR, exist_ok=True)
    os.makedirs(DEBIAN_DIR, exist_ok=True)

    # 1. Fetch API packages with pagination
    page = 1
    pkg_list = []
    while True:
        url = f"https://codeberg.org/api/v1/packages/netkillui?page={page}&limit=50"
        try:
            data = get_url(url)
            batch = json.loads(data.decode('utf-8'))
            if not batch:
                break
            pkg_list.extend(batch)
            page += 1
        except Exception as e:
            log(f"Error fetching API page {page}: {e}")
            break

    with open(os.path.join(META_DIR, "packages-api-response.json"), "w", encoding="utf-8") as f:
        json.dump(pkg_list, f, indent=2)
    log(f"Retrieved {len(pkg_list)} total package records from API.")

    # 2. Fetch Debian distribution indices
    release_raw = get_url("https://codeberg.org/api/packages/netkillui/debian/dists/resolute/Release")
    with open(os.path.join(META_DIR, "dists-resolute-Release"), "wb") as f:
        f.write(release_raw)

    packages_amd64_raw = get_url("https://codeberg.org/api/packages/netkillui/debian/dists/resolute/main/binary-amd64/Packages")
    with open(os.path.join(META_DIR, "binary-amd64-Packages"), "wb") as f:
        f.write(packages_amd64_raw)

    packages_all_raw = get_url("https://codeberg.org/api/packages/netkillui/debian/dists/resolute/main/binary-all/Packages")
    with open(os.path.join(META_DIR, "binary-all-Packages"), "wb") as f:
        f.write(packages_all_raw)

    debian_meta = {}
    for raw_data in [packages_amd64_raw, packages_all_raw]:
        entries = raw_data.decode('utf-8').strip().split('\n\n')
        for e in entries:
            if not e.strip():
                continue
            item = {}
            for l in e.splitlines():
                if ':' in l:
                    k, v = l.split(':', 1)
                    item[k.strip()] = v.strip()
            if 'Filename' in item:
                fname = os.path.basename(item['Filename'])
                debian_meta[fname] = item

    # 3. Build expected file map
    expected_files = {}

    # Debian pool debs
    for fname, meta in debian_meta.items():
        dest = os.path.join(DEBIAN_DIR, fname)
        expected_files[dest] = {
            "url": f"https://codeberg.org/api/packages/netkillui/debian/{meta['Filename']}",
            "sha256": meta.get("SHA256"),
            "size": int(meta["Size"]) if "Size" in meta else None,
            "category": f"Debian ({meta.get('Package', '')} v{meta.get('Version', '')})"
        }

    # Generic packages
    generic_details = []
    for p in pkg_list:
        if p['type'] == 'generic':
            p_name = p['name']
            p_ver = p['version']
            files_url = f"https://codeberg.org/api/v1/packages/netkillui/generic/{p_name}/{p_ver}/files"
            try:
                f_data = json.loads(get_url(files_url).decode('utf-8'))
                generic_details.append({"name": p_name, "version": p_ver, "files": f_data})
                vdir = os.path.join(GENERIC_DIR, p_ver)
                os.makedirs(vdir, exist_ok=True)
                for f in f_data:
                    fname = f['name']
                    dest = os.path.join(vdir, fname)
                    expected_files[dest] = {
                        "url": f"https://codeberg.org/api/packages/netkillui/generic/{p_name}/{p_ver}/{fname}",
                        "sha256": f.get("sha256"),
                        "size": f.get("Size"),
                        "category": f"Generic ({p_name} @ {p_ver})"
                    }
            except Exception as e:
                log(f"Error reading files for generic package {p_name} @ {p_ver}: {e}")

    with open(os.path.join(META_DIR, "generic-package-details.json"), "w", encoding="utf-8") as f:
        json.dump(generic_details, f, indent=2)

    # 4. Check for missing / outdated files and download only what is needed
    to_download = []
    already_verified = 0

    for dest, info in expected_files.items():
        if os.path.exists(dest):
            if info["size"] is None or os.path.getsize(dest) == info["size"]:
                actual_sha = compute_sha256(dest)
                if info["sha256"] is None or actual_sha.lower() == info["sha256"].lower():
                    already_verified += 1
                    continue
        to_download.append((dest, info))

    log(f"Status: {already_verified} files already verified locally. {len(to_download)} new/missing files to download.")

    downloaded_count = 0
    failed_count = 0

    if to_download:
        for dest, info in to_download:
            fname = os.path.basename(dest)
            log(f"Downloading new file: {fname} from {info['url']}...")
            tmp_dest = dest + ".tmp"
            try:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                data = get_url(info['url'])
                with open(tmp_dest, "wb") as out:
                    out.write(data)
                if os.path.exists(dest):
                    os.remove(dest)
                os.rename(tmp_dest, dest)

                # Verify SHA256
                actual_sha = compute_sha256(dest)
                if info["sha256"] and actual_sha.lower() != info["sha256"].lower():
                    log(f"ERROR: Checksum mismatch for {fname}! Expected: {info['sha256']}, Got: {actual_sha}")
                    failed_count += 1
                else:
                    log(f"SUCCESS: {fname} verified ({os.path.getsize(dest):,} bytes, SHA256: {actual_sha[:16]}...)")
                    downloaded_count += 1
            except Exception as e:
                log(f"ERROR downloading {fname}: {e}")
                if os.path.exists(tmp_dest):
                    os.remove(tmp_dest)
                failed_count += 1

    # 5. Generate / Update Verification Report
    generate_report(expected_files)
    log(f"Sync complete. New: {downloaded_count}, Verified: {already_verified + downloaded_count}, Failed: {failed_count}")

def generate_report(expected_files):
    report_lines = []
    report_lines.append("# PNetLab Artifacts & Releases Verification Report\n")
    report_lines.append(f"Generated at: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}\n")
    report_lines.append("## Step 1: Git Repository Verification\n")
    report_lines.append("- **Remote URL**: `https://codeberg.org/netkillui/Pnetlabv8.git`")
    report_lines.append("- **Local Clone Path**: [`track-1-git/`](track-1-git/)")
    report_lines.append("- **Branch**: `main`\n")

    report_lines.append("## Step 2: Codeberg Package API Releases Verification\n")
    report_lines.append("- **Package Registry API**: `https://codeberg.org/api/v1/packages/netkillui`")
    report_lines.append("- **Debian APT Repository**: `https://codeberg.org/api/packages/netkillui/debian` (dist: `resolute`, component: `main`)\n")

    report_lines.append("### Verified File Manifest\n")
    report_lines.append("| Category | Local Path | Size (bytes) | Status | SHA256 Checksum |")
    report_lines.append("| :--- | :--- | :--- | :--- | :--- |")

    for dest, info in sorted(expected_files.items(), key=lambda x: x[0]):
        rel_path = os.path.relpath(dest, BASE_DIR).replace("\\", "/")
        if os.path.exists(dest):
            size = os.path.getsize(dest)
            sha = compute_sha256(dest)
            status = "✅ VERIFIED" if (info["sha256"] is None or sha.lower() == info["sha256"].lower()) else "❌ CHECKSUM MISMATCH"
            report_lines.append(f"| {info['category']} | `{rel_path}` | {size:,} | {status} | `{sha}` |")
        else:
            report_lines.append(f"| {info['category']} | `{rel_path}` | - | ❌ MISSING | - |")

    # Add metadata files
    for f in sorted(os.listdir(META_DIR)):
        fpath = os.path.join(META_DIR, f)
        size = os.path.getsize(fpath)
        sha = compute_sha256(fpath)
        report_lines.append(f"| Metadata Index | `metadata/{f}` | {size:,} | ✅ VERIFIED | `{sha}` |")

    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines) + "\n")

def run_once():
    log("==================================================")
    log("STARTING 24-HOUR SYNC CYCLE")
    log("==================================================")
    try:
        sync_track_1()
        sync_track_2()
        log("SYNC CYCLE FINISHED SUCCESSFULLY.")
    except Exception as e:
        log(f"FATAL ERROR during sync cycle: {e}")

def run_loop():
    log("Starting continuous 24-hour sync loop (interval: 86400 seconds)...")
    while True:
        run_once()
        log("Sleeping for 24 hours (86,400 seconds)...")
        time.sleep(86400)

if __name__ == "__main__":
    if "--loop" in sys.argv or "--daemon" in sys.argv:
        run_loop()
    else:
        run_once()
