# Azam Basha Appliance Master Administration Toolkit

**Complete Reference & Operational Manual for Azam Basha Virtual Appliances**

---

## 1. Toolkit Overview

The Azam Basha Administration Toolkit provides automated, enterprise-grade maintenance and optimization utilities located in [`scripts/`](../scripts/):

| Utility Script | Purpose | Quick Command |
| :--- | :--- | :--- |
| [`scripts/azambasha-apply-all-fixes.sh`](../scripts/azambasha-apply-all-fixes.sh) | **Master Runner**: Interactive menu to launch any utility or apply all essential fixes. | `sudo bash scripts/azambasha-apply-all-fixes.sh` |
| [`scripts/azambasha-health-check.sh`](../scripts/azambasha-health-check.sh) | **System Health Dashboard**: Visual audit of CPU virtualization, RAM, disk, services, and images. | `bash scripts/azambasha-health-check.sh` |
| [`scripts/azambasha-speed-optimizer.sh`](../scripts/azambasha-speed-optimizer.sh) | **Performance Suite**: KSM memory deduplication (30-50% RAM savings), OPcache, Gzip, & sysctl. | `sudo bash scripts/azambasha-speed-optimizer.sh` |
| [`scripts/azambasha-disable-logout.sh`](../scripts/azambasha-disable-logout.sh) | **Permanent Session Fix**: 10-year session across PHP, MySQL, sliding cookie, & keepalive. | `sudo bash scripts/azambasha-disable-logout.sh` |
| [`scripts/azambasha-fix-permissions.sh`](../scripts/azambasha-fix-permissions.sh) | **Permission & Node Recovery**: Fixes `/opt/unetlab` ownership, `/dev/kvm`, locks, and IOL license. | `sudo bash scripts/azambasha-fix-permissions.sh` |
| [`scripts/azambasha-fix-export-and-apt.sh`](../scripts/azambasha-fix-export-and-apt.sh) | **Export & APT Fix**: Solves repository conflicts, installs zip/unzip, and enables nested lab exports. | `sudo bash scripts/azambasha-fix-export-and-apt.sh` |
| [`scripts/azambasha-backup-restore.sh`](../scripts/azambasha-backup-restore.sh) | **Automated Backup/Restore**: Full snapshot archive of labs, users, database, and configurations. | `sudo bash scripts/azambasha-backup-restore.sh backup` |
| [`scripts/setup-ollama.sh`](../scripts/setup-ollama.sh) | **AI Lab Builder VM Setup**: Connects PNETLab MCP service to local Ollama LLM on host. | `sudo bash scripts/setup-ollama.sh <HOST_IP>` |
| [`scripts/setup-ollama-host.ps1`](../scripts/setup-ollama-host.ps1) | **Windows Host Setup**: Binds Ollama to `0.0.0.0`, configures firewall, and pulls `qwen2.5:14b-instruct`. | `.\scripts\setup-ollama-host.ps1` |

---

## 2. Common Operational Tasks

### Running System Health Diagnostics
```bash
bash scripts/azambasha-health-check.sh
```
*Displays CPU KVM virtualization status, RAM & KSM savings, storage usage, web services status, and an inventory of installed QEMU/IOL/Docker images.*

### Creating an Immediate Backup
```bash
sudo bash scripts/azambasha-backup-restore.sh backup
```
*Generates a timestamped `.tar.gz` archive in `/opt/unetlab/data/Backups/` containing MySQL database dumps, lab files, user accounts, and templates.*

### Restoring from Backup
```bash
sudo bash scripts/azambasha-backup-restore.sh restore /opt/unetlab/data/Backups/pnetlab_backup_YYYYMMDD_HHMMSS.tar.gz
```

### Fixing Node Startup Failures & Stale Locks
When lab nodes fail to boot or stay stuck in stopped state:
```bash
sudo bash scripts/azambasha-fix-permissions.sh
```

---

## 3. Piped Web Execution Support
All scripts support direct execution via curl or wget:
```bash
curl -fsSL https://.../scripts/azambasha-apply-all-fixes.sh | sudo bash
```
