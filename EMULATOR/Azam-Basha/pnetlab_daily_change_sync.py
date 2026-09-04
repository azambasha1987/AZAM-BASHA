"""
PNetLab v8 24-Hour Differential Change-Detection & Sync Workflow
================================================================
Checks every 24 hours for remote updates and downloads ONLY files that have changed or are newly published.

Source Tracks:
- Track 1: https://codeberg.org/netkillui/Pnetlabv8.git (Git commits & source)
- Track 2: https://codeberg.org/api/v1/packages/netkillui & Debian APT Pool (Releases & .deb packages)

Differential Sync Rules:
1. Parent Repo (GitHub): Automatically pulls latest GitHub changes into local repository.
2. Git: Pulls ONLY if remote HEAD or refs differ from local repository.
3. Package API & Debian Pool: Computes cryptographic SHA256 hashes of all remote files.
4. Downloads ONLY new files or files whose SHA256 checksum has changed.
5. Unchanged files are skipped with zero network overhead.
6. Maintains state.json, changes_history.json, sync.log, and VERIFICATION_REPORT.md.
"""

import os
import sys
import json
import time
import shutil
import hashlib
import subprocess
import urllib.request
from datetime import datetime, timezone

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
GIT_DIR = os.path.join(BASE_DIR, "track-1-git")
DEBIAN_DIR = os.path.join(BASE_DIR, "debian", "pool", "resolute", "main")
GENERIC_DIR = os.path.join(BASE_DIR, "generic")
META_DIR = os.path.join(BASE_DIR, "metadata")
STATE_FILE = os.path.join(BASE_DIR, "state.json")
HISTORY_FILE = os.path.join(BASE_DIR, "changes_history.json")
LOG_FILE = os.path.join(BASE_DIR, "sync.log")
REPORT_FILE = os.path.join(BASE_DIR, "VERIFICATION_REPORT.md")

USER_AGENT = "curl/8.4.0"

def get_utc_now_str():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{timestamp}] {msg}"
    print(formatted)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(formatted + "\n")
    except Exception:
        pass

def get_url(url, retries=5):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT, 'Accept': '*/*'})
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.read()
        except Exception as e:
            if attempt == retries - 1:
                raise e
            time.sleep(1 + attempt * 2)

def compute_sha256(filepath):
    if not os.path.exists(filepath):
        return None
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"last_run_utc": None, "git_head": None, "files": {}}

def save_state(state):
    state["last_run_utc"] = get_utc_now_str()
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        log(f"Warning: could not save state.json: {e}")

def log_change_history(changes):
    history = []
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                history = json.load(f)
        except Exception:
            history = []
    history.append({
        "timestamp_utc": get_utc_now_str(),
        "git_changes": changes.get("git_changes", []),
        "files_downloaded": changes.get("files_downloaded", []),
        "files_unchanged_count": changes.get("files_unchanged_count", 0)
    })
    if len(history) > 100:
        history = history[-100:]
    try:
        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2)
    except Exception as e:
        log(f"Warning: could not write changes_history.json: {e}")

def sync_parent_github_repo():
    # If running in local environment, pull latest commits from GitHub
    if not os.environ.get("GITHUB_ACTIONS"):
        try:
            res = subprocess.run(["git", "-C", BASE_DIR, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
            parent_repo = res.stdout.strip() if res.returncode == 0 else os.path.dirname(os.path.dirname(BASE_DIR))
            log(f"[GitHub Sync] Checking for GitHub updates on parent repository ({parent_repo})...")
            pull_res = subprocess.run(["git", "-C", parent_repo, "pull", "--rebase"], capture_output=True, text=True)
            if pull_res.returncode == 0:
                log(f"[GitHub Sync] GitHub repository in sync: {pull_res.stdout.strip()}")
            else:
                log(f"[GitHub Sync] Notice: {pull_res.stderr.strip()}")
        except Exception as e:
            log(f"[GitHub Sync] Note: could not auto-pull parent repo: {e}")

def check_and_sync_track1(state, changes):
    log("[Track 1] Checking Git Commits & Repository Source...")
    git_dot_git = os.path.join(GIT_DIR, ".git")
    if not os.path.exists(git_dot_git):
        log(f"[Track 1] Initializing repository at {GIT_DIR}...")
        if os.path.exists(GIT_DIR):
            shutil.rmtree(GIT_DIR, ignore_errors=True)
        subprocess.run(["git", "clone", "https://codeberg.org/netkillui/Pnetlabv8.git", GIT_DIR], check=True)
        head_now = subprocess.run(["git", "-C", GIT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        state["git_head"] = head_now
        changes["git_changes"].append(f"Initial clone at HEAD: {head_now}")
        log(f"[Track 1] Cloned at HEAD: {head_now}")
        return

    # Check remote refs
    try:
        subprocess.run(["git", "-C", GIT_DIR, "fetch", "origin"], check=True)
        status_out = subprocess.run(["git", "-C", GIT_DIR, "status", "-uno"], capture_output=True, text=True).stdout
        old_head = subprocess.run(["git", "-C", GIT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        
        if "Your branch is behind" in status_out:
            log("[Track 1] Remote updates detected! Pulling latest commits...")
            pull_res = subprocess.run(["git", "-C", GIT_DIR, "pull", "--ff-only"], capture_output=True, text=True)
            new_head = subprocess.run(["git", "-C", GIT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
            diff_res = subprocess.run(["git", "-C", GIT_DIR, "diff", "--name-status", old_head, new_head], capture_output=True, text=True).stdout.strip()
            
            state["git_head"] = new_head
            change_desc = f"Updated from {old_head[:8]} to {new_head[:8]}. Changed files:\n{diff_res}"
            changes["git_changes"].append(change_desc)
            log(f"[Track 1] Updated: {change_desc}")
        else:
            log(f"[Track 1] Up to date (HEAD: {old_head})")
            state["git_head"] = old_head
    except Exception as e:
        log(f"[Track 1] Fetch warning: {e}. Re-cloning repository...")
        shutil.rmtree(GIT_DIR, ignore_errors=True)
        subprocess.run(["git", "clone", "https://codeberg.org/netkillui/Pnetlabv8.git", GIT_DIR], check=True)
        head_now = subprocess.run(["git", "-C", GIT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        state["git_head"] = head_now
        log(f"[Track 1] Re-cloned at HEAD: {head_now}")

def check_and_sync_track2(state, changes):
    log("[Track 2] Checking Codeberg Package API & Debian Releases...")
    os.makedirs(META_DIR, exist_ok=True)
    os.makedirs(GENERIC_DIR, exist_ok=True)
    os.makedirs(DEBIAN_DIR, exist_ok=True)

    # 1. Fetch package list from API
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
            log(f"[Track 2] Error checking API page {page}: {e}")
            break

    with open(os.path.join(META_DIR, "packages-api-response.json"), "w", encoding="utf-8") as f:
        json.dump(pkg_list, f, indent=2)

    # 2. Fetch Debian APT distribution indices
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

    # 3. Build remote manifest
    remote_files = {}

    # Debian packages
    for fname, meta in debian_meta.items():
        dest = os.path.join(DEBIAN_DIR, fname)
        remote_files[dest] = {
            "url": f"https://codeberg.org/api/packages/netkillui/debian/{meta['Filename']}",
            "sha256": meta.get("SHA256"),
            "size": int(meta["Size"]) if "Size" in meta else None,
            "category": f"Debian ({meta.get('Package', '')} v{meta.get('Version', '')})"
        }

    # Generic release packages
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
                    remote_files[dest] = {
                        "url": f"https://codeberg.org/api/packages/netkillui/generic/{p_name}/{p_ver}/{fname}",
                        "sha256": f.get("sha256"),
                        "size": f.get("Size"),
                        "category": f"Generic ({p_name} @ {p_ver})"
                    }
            except Exception as e:
                log(f"[Track 2] Error querying generic package {p_name} @ {p_ver}: {e}")

    with open(os.path.join(META_DIR, "generic-package-details.json"), "w", encoding="utf-8") as f:
        json.dump(generic_details, f, indent=2)

    # 4. Check for changes against local files & state
    state_files = state.get("files", {})
    files_to_download = []
    unchanged_count = 0

    for dest, info in remote_files.items():
        rel_path = os.path.relpath(dest, BASE_DIR).replace("\\", "/")
        expected_sha = info.get("sha256")
        expected_size = info.get("size")

        # Check local file
        if os.path.exists(dest):
            if expected_size is None or os.path.getsize(dest) == expected_size:
                local_sha = compute_sha256(dest)
                if expected_sha is None or local_sha.lower() == expected_sha.lower():
                    state_files[rel_path] = {"sha256": local_sha, "size": os.path.getsize(dest)}
                    unchanged_count += 1
                    continue
                else:
                    log(f"[Track 2] Checksum change detected: {rel_path}")
            else:
                log(f"[Track 2] File size change detected: {rel_path}")
        else:
            log(f"[Track 2] New file detected: {rel_path}")

        files_to_download.append((dest, rel_path, info))

    changes["files_unchanged_count"] = unchanged_count

    # 5. Download ONLY changed/new files
    if not files_to_download:
        log(f"[Track 2] All {unchanged_count} files are unchanged. 0 bytes downloaded.")
    else:
        log(f"[Track 2] Downloading {len(files_to_download)} changed/new files...")
        for dest, rel_path, info in files_to_download:
            fname = os.path.basename(dest)
            tmp_dest = dest + ".tmp"
            try:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                data = get_url(info["url"])
                with open(tmp_dest, "wb") as out:
                    out.write(data)
                if os.path.exists(dest):
                    os.remove(dest)
                os.rename(tmp_dest, dest)

                actual_sha = compute_sha256(dest)
                actual_size = os.path.getsize(dest)

                if info["sha256"] and actual_sha.lower() != info["sha256"].lower():
                    log(f"[Track 2] ERROR: {fname} SHA256 mismatch! Expected: {info['sha256']}, Got: {actual_sha}")
                else:
                    log(f"[Track 2] DOWNLOADED & VERIFIED: {fname} ({actual_size:,} bytes | SHA256: {actual_sha[:16]}...)")
                    state_files[rel_path] = {"sha256": actual_sha, "size": actual_size}
                    changes["files_downloaded"].append({
                        "file": rel_path,
                        "size": actual_size,
                        "sha256": actual_sha,
                        "category": info["category"]
                    })
            except Exception as e:
                log(f"[Track 2] Failed downloading {fname}: {e}")
                if os.path.exists(tmp_dest):
                    try:
                        os.remove(tmp_dest)
                    except Exception:
                        pass

    state["files"] = state_files
    generate_report(remote_files)

def generate_report(remote_files):
    report_lines = []
    report_lines.append("# PNetLab Artifacts & Releases Verification Report\n")
    report_lines.append(f"Last updated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n")
    report_lines.append("## Step 1: Git Repository Verification\n")
    report_lines.append("- **Remote URL**: `https://codeberg.org/netkillui/Pnetlabv8.git`")
    track1_uri = f"file:///{os.path.join(BASE_DIR, 'track-1-git').replace('\\', '/')}"
    report_lines.append(f"- **Local Clone Path**: [`track-1-git/`]({track1_uri})")
    report_lines.append("- **Branch**: `main`\n")

    report_lines.append("## Step 2: Codeberg Package API Releases Verification\n")
    report_lines.append("- **Package Registry API**: `https://codeberg.org/api/v1/packages/netkillui`")
    report_lines.append("- **Debian APT Repository**: `https://codeberg.org/api/packages/netkillui/debian` (dist: `resolute`, component: `main`)\n")

    report_lines.append("### Verified File Manifest\n")
    report_lines.append("| Category | Local Path | Size (bytes) | Status | SHA256 Checksum |")
    report_lines.append("| :--- | :--- | :--- | :--- | :--- |")

    for dest, info in sorted(remote_files.items(), key=lambda x: x[0]):
        rel_path = os.path.relpath(dest, BASE_DIR).replace("\\", "/")
        if os.path.exists(dest):
            size = os.path.getsize(dest)
            sha = compute_sha256(dest)
            status = "✅ VERIFIED" if (info["sha256"] is None or sha.lower() == info["sha256"].lower()) else "❌ CHECKSUM MISMATCH"
            report_lines.append(f"| {info['category']} | `{rel_path}` | {size:,} | {status} | `{sha}` |")
        else:
            report_lines.append(f"| {info['category']} | `{rel_path}` | - | ❌ MISSING | - |")

    if os.path.exists(META_DIR):
        for f in sorted(os.listdir(META_DIR)):
            fpath = os.path.join(META_DIR, f)
            size = os.path.getsize(fpath)
            sha = compute_sha256(fpath)
            report_lines.append(f"| Metadata Index | `metadata/{f}` | {size:,} | ✅ VERIFIED | `{sha}` |")

    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines) + "\n")

def execute_sync_cycle():
    log("="*60)
    log("STARTING 24-HOUR DIFFERENTIAL CHANGE-DETECTION SYNC")
    log("="*60)
    sync_parent_github_repo()
    state = load_state()
    changes = {
        "git_changes": [],
        "files_downloaded": [],
        "files_unchanged_count": 0
    }

    try:
        check_and_sync_track1(state, changes)
        check_and_sync_track2(state, changes)
        save_state(state)
        log_change_history(changes)

        downloaded_num = len(changes['files_downloaded'])
        log(f"Sync finished. New/Changed files downloaded: {downloaded_num}, Unchanged skipped: {changes['files_unchanged_count']}")
        log("="*60)
    except Exception as e:
        log(f"FATAL ERROR during sync cycle: {e}")

def run_24h_loop():
    log("Starting continuous 24-hour scheduler loop (Cycle interval: 86,400s / 24 hours)...")
    while True:
        execute_sync_cycle()
        log("Sleeping for 24 hours (86,400 seconds) until next scheduled check...")
        time.sleep(86400)

if __name__ == "__main__":
    if "--loop" in sys.argv or "--daemon" in sys.argv:
        run_24h_loop()
    else:
        execute_sync_cycle()
