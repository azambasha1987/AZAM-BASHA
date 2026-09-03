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
| Desktop Install Bundle | Installs PNetLab v8 on Ubuntu Desktop workstation environment on bare metal. Tested on Ubuntu 26.04 Desktop and Xubuntu 26.04 Desktop — Xubuntu is recommended for its lighter resource footprint. Dual boot alongside Widows or external SSD setup works. | [download](https://mega.nz/file/rRZzXSRa#fsAL-CGdLPf0gCjBVoeIeMuo-A1Fsdm3nCx2Ea3u_a4) |

## Requirements

- 64-bit host, hardware virtualization support (Intel VT-x / AMD-V)
- Minimum 4 vCPU / 8 GB RAM / 40 GB disk for light use; scale up for larger labs
- Ubuntu 26.04 LTS ("27H1 Resolute") for the network install method

## Installation

### Option 1 — Network install (recommended)

Run the network install script on a fresh Ubuntu 26.04 server:

```bash
curl -fsSL https://codeberg.org/api/packages/netkillui/generic/pnetlab-core-assets/0.channel/pnetlab-network-install-latest.sh | sudo bash -s -- --yes --release latest
```

The script partitions storage, installs dependencies, and pulls the latest
PNetLab v8 package automatically.

### Option 2 — OVA (autoinstaller)

1. Download the OVA from the table above.
2. Import it into VMware Workstation/ESXi or VirtualBox.
3. Power on the VM. It boots into an unattended autoinstaller that partitions
  the disk and installs Ubuntu 26.04 + PNetLab v8 with no manual input beyond
  DHCP/static IP choice.
4. Once the install finishes and the VM reboots, log in to the web UI at
  `https://<host-ip>/`.

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

This repository includes automated maintenance scripts, optimization tools, dataplane accelerators, and disaster recovery utilities in [`scripts/`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts):

| Script | Purpose | Quick Run |
| :--- | :--- | :--- |
| [`scripts/pnetlab-apply-all-fixes.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-apply-all-fixes.sh) | **Master Runner**: Interactive menu to launch any utility or apply all essential fixes. | `sudo bash scripts/pnetlab-apply-all-fixes.sh` |
| [`scripts/pnetlab-dataplane-engine.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-dataplane-engine.sh) | **Dataplane Accelerator**: Fast-path kernel bridge bypass (~2× throughput, 1/3 CPU, 10k queues). | `sudo bash scripts/pnetlab-dataplane-engine.sh` |
| [`scripts/pnetlab-link-impairment.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-link-impairment.sh) | **Link Quality & Impairment**: Injects latency, jitter, loss, rate limits, and corruption on any link. | `sudo bash scripts/pnetlab-link-impairment.sh` |
| [`scripts/pnetlab-capture-stream.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-capture-stream.sh) | **Packet Capture & Streamer**: Low-overhead packet recording and live Wireshark streaming. | `sudo bash scripts/pnetlab-capture-stream.sh` |
| [`scripts/pnetlab-dataplane-stats.py`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-dataplane-stats.py) | **Real-Time Telemetry**: Per-interface live PPS/BPS top monitor, JSON export, and Prometheus API. | `python3 scripts/pnetlab-dataplane-stats.py` |
| [`scripts/pnetlab-health-check.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-health-check.sh) | **Health Dashboard**: Visual audit of CPU virtualization, RAM, disk, services, and image counts. | `bash scripts/pnetlab-health-check.sh` |
| [`scripts/pnetlab-speed-optimizer.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-speed-optimizer.sh) | **Speed Optimizer**: KSM memory deduplication (30-50% RAM savings), OPcache 256MB, Apache Gzip, & sysctl. | `sudo bash scripts/pnetlab-speed-optimizer.sh` |
| [`scripts/pnetlab-disable-logout.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-disable-logout.sh) | **Permanent Session Fix**: Sets 10-year session across PHP, MySQL, cookies, and keepalive heartbeat. | `sudo bash scripts/pnetlab-disable-logout.sh` |
| [`scripts/pnetlab-fix-permissions.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-fix-permissions.sh) | **Permission & Node Recovery**: Repairs `/opt/unetlab` ownership, `/dev/kvm`, locks, and IOL licenses. | `sudo bash scripts/pnetlab-fix-permissions.sh` |
| [`scripts/pnetlab-fix-export-and-apt.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-fix-export-and-apt.sh) | **Export & APT Fix**: Cleans duplicate repos, installs zip/unzip, and enables recursive nested lab export. | `sudo bash scripts/pnetlab-fix-export-and-apt.sh` |
| [`scripts/pnetlab-backup-restore.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/pnetlab-backup-restore.sh) | **Backup & Restore**: One-command snapshot and restore of database, labs, and configurations. | `sudo bash scripts/pnetlab-backup-restore.sh backup` |
| [`scripts/setup-ollama.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/setup-ollama.sh) | **AI Lab Builder VM Setup**: Configures PNETLab v8.72+ MCP service and connects to local Ollama LLM. | `sudo bash scripts/setup-ollama.sh <HOST_IP>` |
| [`scripts/setup-ollama-host.ps1`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/setup-ollama-host.ps1) | **Windows Host Setup**: Binds Ollama to `0.0.0.0`, opens firewall port 11434, and pulls `qwen2.5:14b-instruct`. | `.\scripts\setup-ollama-host.ps1` |

---

## Technical Documentation & Guides

Detailed administrator documentation is available in [`docs/`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs):

- **High-Performance Dataplane Guide**: [`docs/PNETLAB_HIGH_PERFORMANCE_DATAPLANE_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/PNETLAB_HIGH_PERFORMANCE_DATAPLANE_GUIDE.md) — Fast-path forwarding, link impairment recipes, live capture, and telemetry.
- **Master Administration Toolkit**: [`docs/PNETLAB_ADMIN_TOOLKIT_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/PNETLAB_ADMIN_TOOLKIT_GUIDE.md) — Comprehensive operations manual for all tools.
- **Speed & Resource Optimizer**: [`docs/PNETLAB_SPEED_OPTIMIZER_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/PNETLAB_SPEED_OPTIMIZER_GUIDE.md) — KSM RAM deduplication, OPcache bytecode acceleration, Apache compression, and network stack tuning.
- **AI Lab Builder & Ollama**: [`docs/AI_LAB_BUILDER_OLLAMA_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/AI_LAB_BUILDER_OLLAMA_GUIDE.md) — Architecture diagram, 4-stage execution flow, troubleshooting matrix, and sample prompts.
- **Permanent Session Guide**: [`docs/PNETLAB_PERMANENT_SESSION_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/PNETLAB_PERMANENT_SESSION_GUIDE.md) & [HTML Version](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/pnetlab-never-logout-guide.html) — Full root-cause analysis and multi-layer session fix.
- **Lab Export & APT Fix**: [`docs/PNETLAB_EXPORT_AND_APT_FIX_GUIDE.md`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/docs/PNETLAB_EXPORT_AND_APT_FIX_GUIDE.md) — Step-by-step resolution for export errors and nested labs.

---

## Support / Issues

Open an issue in this repository's issue tracker.

## License

See the license terms distributed with the PNetLab v8 package.