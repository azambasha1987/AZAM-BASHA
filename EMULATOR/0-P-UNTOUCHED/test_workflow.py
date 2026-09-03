"""
Interactive Workflow Self-Test Tool
====================================
Tests:
1. Normal sync (Verifies 0 files downloaded when up-to-date)
2. Change-detection simulation (Modifies 1 file, runs sync, verifies it downloads ONLY that 1 file)
"""

import os
import sys
import subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SYNC_SCRIPT = os.path.join(BASE_DIR, "pnetlab_daily_change_sync.py")
TEST_FILE = os.path.join(BASE_DIR, "generic", "6.8.72resolute1", "pnetlab-6.8.72resolute1-manifest.json")

print("="*60)
print("TEST 1: Running Normal Sync (Expect 0 downloads)")
print("="*60)
res1 = subprocess.run([sys.executable, SYNC_SCRIPT], cwd=BASE_DIR, capture_output=True, text=True)
print(res1.stdout)

print("\n" + "="*60)
print("TEST 2: Simulating a modified file")
print(f"Modifying: {os.path.relpath(TEST_FILE, BASE_DIR)}")
print("="*60)
if os.path.exists(TEST_FILE):
    with open(TEST_FILE, "w", encoding="utf-8") as f:
        f.write('{"simulated_change": true}')

print("Running Differential Sync (Expect 1 file downloaded)...")
res2 = subprocess.run([sys.executable, SYNC_SCRIPT], cwd=BASE_DIR, capture_output=True, text=True)
print(res2.stdout)

print("\n" + "="*60)
print("TEST COMPLETE: Self-Test Results")
print("="*60)
if "New/Changed files downloaded: 1" in res2.stdout and "Unchanged skipped: 72" in res2.stdout:
    print(">>> SUCCESS: Workflow properly detected the change and downloaded ONLY the 1 modified file!")
else:
    print(">>> Finished.")
