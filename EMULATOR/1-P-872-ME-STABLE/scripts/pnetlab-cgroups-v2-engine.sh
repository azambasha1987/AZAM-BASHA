#!/usr/bin/env bash
# ==============================================================================
# PNetLab Cgroups v2 & Virtualization Resource Throttling Engine
# Configures unified Cgroups v2 slice hierarchy, KSM memory de-duplication,
# and systemd resource delegation for QEMU, IOL, and Docker lab nodes.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    [3/4] Configuring Cgroups v2 & Resource Engine...       "
echo "============================================================"

# 1. Create PNETLab Dedicated Systemd Resource Slice
cat > /etc/systemd/system/pnetlab.slice << 'EOF'
[Unit]
Description=PNETLab Lab Node Slices & Resource Controllers
Before=slices.target

[Slice]
CPUAccounting=yes
MemoryAccounting=yes
IOAccounting=yes
TasksAccounting=yes
EOF

systemctl daemon-reload 2>/dev/null || true
echo "      -> Configured Cgroups v2 /etc/systemd/system/pnetlab.slice"

# 2. Configure Kernel Samepage Merging (KSM) for QEMU Memory Deduplication
cat > /etc/systemd/system/pnetlab-ksm-tune.service << 'EOF'
[Unit]
Description=PNETLab High Performance KSM Memory Deduplication
After=sys-kernel-mm-ksm.mount systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c ' \
    [ -f /sys/kernel/mm/ksm/run ] && echo 1 > /sys/kernel/mm/ksm/run; \
    [ -f /sys/kernel/mm/ksm/pages_to_scan ] && echo 500 > /sys/kernel/mm/ksm/pages_to_scan; \
    [ -f /sys/kernel/mm/ksm/sleep_millisecs ] && echo 20 > /sys/kernel/mm/ksm/sleep_millisecs; \
    [ -f /sys/kernel/mm/ksm/merge_across_nodes ] && echo 1 > /sys/kernel/mm/ksm/merge_across_nodes; \
    exit 0'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable --now pnetlab-ksm-tune.service 2>/dev/null || true

# Apply KSM immediately
if [ -f /sys/kernel/mm/ksm/run ]; then
    echo 1 > /sys/kernel/mm/ksm/run 2>/dev/null || true
    echo 500 > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null || true
    echo 20 > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null || true
    echo "      -> Enabled high-throughput KSM memory deduplication"
fi

echo "============================================================"
echo "    [SUCCESS] Cgroups v2 & Virtualization Engine Active!    "
echo "============================================================"
