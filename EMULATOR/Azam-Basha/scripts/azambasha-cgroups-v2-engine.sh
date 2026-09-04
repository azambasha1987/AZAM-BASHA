#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Cgroups v2 & Virtualization Resource Throttling Engine
# Configures unified Cgroups v2 slice hierarchy, KSM memory deduplication,
# and systemd resource delegation for QEMU, IOL, and Docker lab nodes.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    [1/3] Configuring Cgroups v2 & Resource Engine...       "
echo "============================================================"

# 1. Create Azam Basha Dedicated Systemd Resource Slices
cat > /etc/systemd/system/azambasha.slice << 'EOF'
[Unit]
Description=Azam Basha Lab Node Slices & Resource Controllers
Before=slices.target

[Slice]
CPUAccounting=yes
MemoryAccounting=yes
IOAccounting=yes
TasksAccounting=yes
EOF

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
echo "      -> Configured Cgroups v2 /etc/systemd/system/azambasha.slice"

# 2. Configure Kernel Samepage Merging (KSM) for QEMU Memory Deduplication
echo "============================================================"
echo "    [2/3] Configuring Proactive KSM Deduplication Engine... "
echo "============================================================"
cat > /etc/systemd/system/azambasha-ksm-tune.service << 'EOF'
[Unit]
Description=Azam Basha High Performance KSM Memory Deduplication
After=sys-kernel-mm-ksm.mount systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c ' \
    [ -f /sys/kernel/mm/ksm/run ] && echo 1 > /sys/kernel/mm/ksm/run; \
    [ -f /sys/kernel/mm/ksm/pages_to_scan ] && echo 1000 > /sys/kernel/mm/ksm/pages_to_scan; \
    [ -f /sys/kernel/mm/ksm/sleep_millisecs ] && echo 20 > /sys/kernel/mm/ksm/sleep_millisecs; \
    [ -f /sys/kernel/mm/ksm/use_zero_pages ] && echo 1 > /sys/kernel/mm/ksm/use_zero_pages; \
    [ -f /sys/kernel/mm/ksm/merge_across_nodes ] && echo 1 > /sys/kernel/mm/ksm/merge_across_nodes; \
    exit 0'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable --now azambasha-ksm-tune.service 2>/dev/null || true

# Apply KSM immediately
if [ -f /sys/kernel/mm/ksm/run ]; then
    echo 1 > /sys/kernel/mm/ksm/run 2>/dev/null || true
    echo 1000 > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null || true
    echo 20 > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null || true
    echo 1 > /sys/kernel/mm/ksm/use_zero_pages 2>/dev/null || true
    echo "      -> Enabled high-throughput KSM memory deduplication (1000 pages / 20ms)"
fi

echo "============================================================"
echo "    [3/3] Setting User & Task Process Limits (1024 Nodes)..."
echo "============================================================"
cat > /etc/security/limits.d/99-azambasha.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 524288
* hard nproc 524288
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 524288
root hard nproc 524288
www-data soft nofile 1048576
www-data hard nofile 1048576
www-data soft nproc 524288
www-data hard nproc 524288
EOF
echo "      -> Configured security limits (1M file descriptors, 512K processes)"

echo "============================================================"
echo "    [SUCCESS] Cgroups v2 & Virtualization Engine Active!    "
echo "============================================================"
