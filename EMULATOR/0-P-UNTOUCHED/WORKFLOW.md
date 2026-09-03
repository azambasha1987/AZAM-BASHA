# 24-Hour Differential Change Detection & Sync Workflow

This workflow checks for upstream updates every 24 hours across **Track 1** (Git commits) and **Track 2** (Codeberg Package API releases), and **downloads only the files that have changed or are newly added**.

---

## Differential Change Detection Architecture

```mermaid
graph TD
    A[Start 24-Hour Cycle] --> B[Track 1: Git Remote Check]
    B --> C{Remote Git HEAD != Local?}
    C -- Yes --> D[Pull Git updates & log changed files]
    C -- No --> E[Track 1 Unchanged - 0 bytes]
    
    D --> F[Track 2: Package API & APT Index Check]
    E --> F
    
    F --> G[Query API & Fetch Distribution Packages Metadata]
    G --> H[Iterate over all Remote Artifacts]
    H --> I{File exists locally AND SHA256 matches?}
    I -- Yes: Unchanged --> J[Skip download - 0 bytes network traffic]
    I -- No: Missing / Changed --> K[Download ONLY this changed/new file]
    K --> L[Verify SHA256 cryptographic checksum]
    
    J --> M[Save state.json & append changes_history.json]
    L --> M
    M --> N[Update VERIFICATION_REPORT.md & sync.log]
    N --> O[Wait 24 hours for next scheduled run]
```

---

## Core Components

| File | Purpose |
| :--- | :--- |
| [`pnetlab_daily_change_sync.py`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/pnetlab_daily_change_sync.py) | **Differential Engine**: Queries remote API, verifies SHA256 hashes, downloads ONLY new/changed files, maintains `state.json` and `changes_history.json`. |
| [`setup_windows_scheduler.ps1`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/setup_windows_scheduler.ps1) | **Scheduler Setup**: Registers a native Windows Scheduled Task (`PNetLab-24h-Sync`) to run daily at 03:00 AM automatically in the background. |
| [`run_sync.bat`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/run_sync.bat) | **Manual Runner**: One-click launcher to check and sync changes on demand. |
| [`state.json`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/state.json) | Tracks current state, timestamps, and SHA256 hashes of all verified files. |
| [`changes_history.json`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/changes_history.json) | Append-only changelog documenting what was downloaded on each 24-hour cycle. |
| [`sync.log`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/sync.log) | Human-readable timestamped execution logs. |
| [`VERIFICATION_REPORT.md`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/VERIFICATION_REPORT.md) | Cryptographic verification manifest updated automatically. |

---

## How to Set Up & Run

### Method 1: Windows Task Scheduler (Recommended for 24-Hour Automation)
Open PowerShell and run:
```powershell
powershell -ExecutionPolicy Bypass -File "e:\Git\EMULATOR\0-P-UNTOUCHED\setup_windows_scheduler.ps1"
```
- Automatically executes every 24 hours at 03:00 AM.
- Runs silently in the background without needing the IDE or console open.
- To test the scheduled task immediately:
  ```powershell
  Start-ScheduledTask -TaskName "PNetLab-24h-Sync"
  ```

### Method 2: Python 24-Hour Daemon Loop
Run the sync script in loop mode:
```bash
python e:\Git\EMULATOR\0-P-UNTOUCHED\pnetlab_daily_change_sync.py --loop
```
- Executes one check immediately, then sleeps for 86,400 seconds (24 hours) between cycles.

### Method 3: Manual On-Demand Check
Double-click [`run_sync.bat`](file:///e:/Git/EMULATOR/0-P-UNTOUCHED/run_sync.bat) or run:
```bash
python e:\Git\EMULATOR\0-P-UNTOUCHED\pnetlab_daily_change_sync.py
```
