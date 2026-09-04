# PNetLab v8

PNetLab is a self-hosted network emulation platform for building and running
virtual labs (routers, switches, firewalls, servers, and more) in your browser.

This repository is a landing page for **PNetLab v8** downloads and upgrade
instructions. It does not host the application source.

## Downloads

| Artifact | Description | Link |
| --- | --- | --- |
| Network Install Script | Hands-off installer for a fresh Ubuntu 26.04 (27H1 "Resolute") host — pulls and installs the latest PNetLab v8 release over the network. | [download](https://codeberg.org/api/packages/netkillui/generic/pnetlab-core-assets/0.channel/pnetlab-network-install-latest.sh) |
| OVA (autoinstaller) | Minimal Ubuntu 26.04 image with an unattended autoinstaller — boots and installs PNetLab v8 itself. | [download](https://mega.nz/file/uNAz3JDb#CQA93KkaU3XrCs6EIosChOjYonn1W4ELgnLm7NcZ2Wg) |
| Desktop Install Bundle | Installs PNetLab v8 on Ubuntu Desktop workstation environment on bare metal. Tested on Ubuntu 26.04 Desktop and Xubuntu 26.04 Desktop — Xubuntu is recommended for its lighter resource footprint. Dual boot alongside Windows or external SSD setup works. | [download](https://mega.nz/file/rRZzXSRa#fsAL-CGdLPf0gCjBVoeIeMuo-A1Fsdm3nCx2Ea3u_a4) |

## Requirements

- 64-bit host, hardware virtualization support (Intel VT-x / AMD-V)
- Minimum 4 vCPU / 8 GB RAM / 40 GB disk for light use; scale up for larger labs
- Ubuntu 26.04 LTS ("27H1 Resolute") for the network install method

## Installation Options

### Option 1 — Single-Line Installation via Uploaded Folder / Zip
If you uploaded and extracted the package directory on your Ubuntu 26 server:

```bash
cd /opt/pnetlab && sudo bash install.sh
```

---

### Option 2 — Single-Line Installation via GitHub Directly (Recommended)
On a fresh or existing Ubuntu 26.04 server, run this single line in your terminal:

```bash
sudo git clone https://github.com/azambasha1987/AZAM-BASHA.git /opt/pnetlab && cd /opt/pnetlab && sudo bash install.sh
```

*(If `/opt/pnetlab` already exists, update and run: `cd /opt/pnetlab && sudo git pull && sudo bash install.sh`)*

---

### Option 3 — Cluster Satellite (Worker Node) Installation
To provision a dedicated headless worker VM to scale out compute capacity for your Master PNETLab server:

```bash
cd /opt/pnetlab && sudo bash install-satellite.sh
```

Join the worker to your master server:
```bash
sudo pnet-satellite-join --master <MASTER_IP> --id 1 --name "Satellite-1" --psk <GENERATED_PSK>
```

---

### Web Dashboard & Login (Master Node):
* **URL**: `https://<YOUR_UBUNTU_IP>/`
* **Username**: `admin`
* **Password**: `pnet`
* **Console**: `Native` *(or HTML5)*

## Updating

PNetLab v8 ships update packages through its built-in update mechanism.

```bash
sudo pnetlab-update
```

This checks the configured release channel, downloads the newest package, and
applies it in place. Review the changelog before updating a production lab
host.

### Manual upgrade (if `pnetlab-update` is unavailable)

1. Back up `/opt/unetlab` (or your configured lab data path) and any custom
  node images.
2. Download the target release package (placeholder link above).
3. Install it:
  
  ```bash
  sudo dpkg -i pnetlab_<version>_amd64.deb
  sudo apt-get -f install
  ```
  
4. Reboot and verify the web UI and running labs come back up correctly.

## Administration Scripts & Fixes

This repository includes automated maintenance scripts, optimization tools, dataplane accelerators, and disaster recovery utilities in [`scripts/`](scripts/):

| Script | Purpose | Quick Run |
| :--- | :--- | :--- |
| [`scripts/pnetlab-apply-all-fixes.sh`](scripts/pnetlab-apply-all-fixes.sh) | **Master Runner**: Interactive menu to launch any utility or apply all essential fixes. | `sudo bash scripts/pnetlab-apply-all-fixes.sh` |
| [`scripts/pnetlab-dataplane-engine.sh`](scripts/pnetlab-dataplane-engine.sh) | **Dataplane Accelerator**: Fast-path kernel bridge bypass (~2× throughput, 1/3 CPU, 10k queues). | `sudo bash scripts/pnetlab-dataplane-engine.sh` |
| [`scripts/pnetlab-link-impairment.sh`](scripts/pnetlab-link-impairment.sh) | **Link Quality & Impairment**: Injects latency, jitter, loss, rate limits, and corruption on any link. | `sudo bash scripts/pnetlab-link-impairment.sh` |
| [`scripts/pnetlab-capture-stream.sh`](scripts/pnetlab-capture-stream.sh) | **Packet Capture & Streamer**: Low-overhead packet recording and live Wireshark streaming. | `sudo bash scripts/pnetlab-capture-stream.sh` |
| [`scripts/pnetlab-dataplane-stats.py`](scripts/pnetlab-dataplane-stats.py) | **Real-Time Telemetry**: Per-interface live PPS/BPS top monitor, JSON export, and Prometheus API. | `python3 scripts/pnetlab-dataplane-stats.py` |
| [`scripts/pnetlab-health-check.sh`](scripts/pnetlab-health-check.sh) | **Health Dashboard**: Visual audit of CPU virtualization, RAM, disk, services, and image counts. | `bash scripts/pnetlab-health-check.sh` |
| [`scripts/pnetlab-speed-optimizer.sh`](scripts/pnetlab-speed-optimizer.sh) | **Speed Optimizer**: KSM memory deduplication (30-50% RAM savings), OPcache 256MB, Apache Gzip, & sysctl. | `sudo bash scripts/pnetlab-speed-optimizer.sh` |
| [`scripts/pnetlab-disable-logout.sh`](scripts/pnetlab-disable-logout.sh) | **Permanent Session Fix**: Sets 10-year session across PHP, MySQL, cookies, and keepalive heartbeat. | `sudo bash scripts/pnetlab-disable-logout.sh` |
| [`scripts/pnetlab-fix-permissions.sh`](scripts/pnetlab-fix-permissions.sh) | **Permission & Node Recovery**: Repairs `/opt/unetlab` ownership, `/dev/kvm`, locks, and IOL licenses. | `sudo bash scripts/pnetlab-fix-permissions.sh` |
| [`scripts/pnetlab-fix-export-and-apt.sh`](scripts/pnetlab-fix-export-and-apt.sh) | **Export & APT Fix**: Cleans duplicate repos, installs zip/unzip, and enables recursive nested lab export. | `sudo bash scripts/pnetlab-fix-export-and-apt.sh` |
| [`scripts/pnetlab-backup-restore.sh`](scripts/pnetlab-backup-restore.sh) | **Backup & Restore**: One-command snapshot and restore of database, labs, and configurations. | `sudo bash scripts/pnetlab-backup-restore.sh backup` |
| [`scripts/pnetlab-upload-and-docker-fix.sh`](scripts/pnetlab-upload-and-docker-fix.sh) | **512MB Upload & Docker Fix**: Boosts upload limits to 512MB and enables kernel IP forwarding. | `sudo bash scripts/pnetlab-upload-and-docker-fix.sh` |
| [`scripts/pnetlab-system-and-console-fix.sh`](scripts/pnetlab-system-and-console-fix.sh) | **SSL & HTML5 Console Fix**: 10-year IP-SAN SSL cert, guacd auto-recovery, and Cloud bridge promiscuous mode. | `sudo bash scripts/pnetlab-system-and-console-fix.sh` |
| [`scripts/pnetlab-database-and-system-deep-fix.sh`](scripts/pnetlab-database-and-system-deep-fix.sh) | **Database & Limits Deep-Fix**: Disables strict SQL mode, scales nofile to 1M, logrotate, and THP tuning. | `sudo bash scripts/pnetlab-database-and-system-deep-fix.sh` |
| [`scripts/pnetlab-image-doctor.sh`](scripts/pnetlab-image-doctor.sh) | **Image Doctor**: Audits image folder naming, template mappings, and QCOW2 disk integrity. | `sudo bash scripts/pnetlab-image-doctor.sh --check` |
| [`connect_pnetlab.bat`](connect_pnetlab.bat) | **Windows Host Connector**: Auto-discovers VM, opens Web UI, and scans node console ports (30001+). | Double-click `connect_pnetlab.bat` |
| [`scripts/pnetlab-block-updates.sh`](scripts/pnetlab-block-updates.sh) | **Version Freeze & Update Blocker**: Locks APT packages, sets Pin-Priority -1, masks updaters, and enforces offline mode. | `sudo bash scripts/pnetlab-block-updates.sh` |
| [`scripts/setup-ollama.sh`](scripts/setup-ollama.sh) | **AI Lab Builder VM Setup**: Configures PNETLab v8.72+ MCP service and connects to local Ollama LLM. | `sudo bash scripts/setup-ollama.sh <HOST_IP>` |
| [`scripts/setup-ollama-host.ps1`](scripts/setup-ollama-host.ps1) | **Windows Host Setup**: Binds Ollama to `0.0.0.0`, opens firewall port 11434, and pulls `qwen2.5:14b-instruct`. | `.\scripts\setup-ollama-host.ps1` |

---

## Technical Documentation & Guides

Detailed administrator documentation is available in [`docs/`](docs/):

- **High-Performance Dataplane Guide**: [`docs/PNETLAB_HIGH_PERFORMANCE_DATAPLANE_GUIDE.md`](docs/PNETLAB_HIGH_PERFORMANCE_DATAPLANE_GUIDE.md) — Fast-path forwarding, link impairment recipes, live capture, and telemetry.
- **Master Administration Toolkit**: [`docs/PNETLAB_ADMIN_TOOLKIT_GUIDE.md`](docs/PNETLAB_ADMIN_TOOLKIT_GUIDE.md) — Comprehensive operations manual for all tools.
- **Speed & Resource Optimizer**: [`docs/PNETLAB_SPEED_OPTIMIZER_GUIDE.md`](docs/PNETLAB_SPEED_OPTIMIZER_GUIDE.md) — KSM RAM deduplication, OPcache bytecode acceleration, Apache compression, and network stack tuning.
- **AI Lab Builder & Ollama**: [`docs/AI_LAB_BUILDER_OLLAMA_GUIDE.md`](docs/AI_LAB_BUILDER_OLLAMA_GUIDE.md) — Architecture diagram, 4-stage execution flow, troubleshooting matrix, and sample prompts.
- **Permanent Session Guide**: [`docs/PNETLAB_PERMANENT_SESSION_GUIDE.md`](docs/PNETLAB_PERMANENT_SESSION_GUIDE.md) & [HTML Version](docs/pnetlab-never-logout-guide.html) — Full root-cause analysis and multi-layer session fix.
- **Lab Export & APT Fix**: [`docs/PNETLAB_EXPORT_AND_APT_FIX_GUIDE.md`](docs/PNETLAB_EXPORT_AND_APT_FIX_GUIDE.md) — Step-by-step resolution for export errors and nested labs.

---

## Support / Issues

Open an issue in this repository's issue tracker.

## License

See the license terms distributed with the PNetLab v8 package.
