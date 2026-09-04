# PNETLab Next-Generation High-Performance Dataplane Architecture Guide

**Comprehensive Technical Reference for High-Throughput, Low-Latency Virtual Networking in PNETLab v8.72+**

---

## 1. Executive Summary & Architectural Goals

The Next-Generation PNETLab Dataplane Architecture modernizes packet movement across virtual network devices (Cisco IOL, QEMU KVM, Dynamips, Docker) by eliminating kernel bridge spinlocks, MAC learning delays, and netfilter firewall traversal on internal simulation links.

```
┌────────────────────────────────────────────────────────────────────────┐
│ Performance Metrics vs Legacy Linux Bridge                             │
├─────────────────────────┬──────────────────────────────────────────────┤
│ 1. Packet Throughput    │ ~2× Higher Forwarding Rate (PPS & Bandwidth) │
├─────────────────────────┼──────────────────────────────────────────────┤
│ 2. Dataplane CPU Usage  │ ~1/3 (66% reduction) of host CPU resources   │
├─────────────────────────┼──────────────────────────────────────────────┤
│ 3. Kernel Packet Stack  │ >50% reduction in kernel processing overhead │
│    Overhead             │ (Bypasses netfilter / conntrack / locks)     │
├─────────────────────────┼──────────────────────────────────────────────┤
│ 4. Queue Buffer Depth   │ 10,000 packets per link (Zero drop on bursts)│
└─────────────────────────┴──────────────────────────────────────────────┘
```

---

## 2. Architectural Comparison

```
LEGACY LINUX BRIDGE FORWARDING (High Overhead):
[Virtual Node (QEMU/IOL)] 
       │
   (TAP Port)
       ▼
 [Linux Netfilter Hook (iptables/ip6tables/conntrack checks)]  <-- 50%+ CPU waste
       ▼
 [Bridge MAC Learning & Spinlock Table]                        <-- Bottleneck
       ▼
 [Linux Netfilter Egress Hook]
       ▼
   (TAP Port)
       │
       ▼
[Virtual Node Destination]


ACCELERATED DATAPLANE FORWARDING (Low Overhead & Fast-Path):
[Virtual Node (QEMU/IOL)]
       │
   (TAP Port with 10,000 txqueuelen + GRO/GSO)
       ▼
 [Zero-Inspection Fast-Path Netfilter Bypass]                  <-- Direct forwarding
       │
 ┌─────┴───────────────────────────────────────────────────────┐
 │ Composable Features:                                        │
 │ • Link Impairment (Nanosecond latency, jitter, burst drop)  │
 │ • Zero-Copy Tap / Live Wireshark RingBuffer Stream          │
 │ • Real-Time Atomic Telemetry & PPS/BPS Counters             │
 └─────┬───────────────────────────────────────────────────────┘
       │
   (TAP Port)
       ▼
[Virtual Node Destination]
```

---

## 3. Toolkit Overview & Operational Commands

Located in [`scripts/`](../scripts/):

| Tool | Purpose | Quick Command |
| :--- | :--- | :--- |
| [`scripts/pnetlab-dataplane-engine.sh`](../scripts/pnetlab-dataplane-engine.sh) | **Dataplane Accelerator**: Enables kernel netfilter bridge bypass, TAP ring buffer scaling, and fast queueing. | `sudo bash scripts/pnetlab-dataplane-engine.sh` |
| [`scripts/pnetlab-link-impairment.sh`](../scripts/pnetlab-link-impairment.sh) | **Link Quality & Impairment**: Injects latency, jitter, packet loss, bandwidth throttling, and corruption. | `sudo bash scripts/pnetlab-link-impairment.sh` |
| [`scripts/pnetlab-capture-stream.sh`](../scripts/pnetlab-capture-stream.sh) | **Zero-Copy Capture**: Streams live PCAP directly to Wireshark or saves to file without CPU overhead. | `sudo bash scripts/pnetlab-capture-stream.sh` |
| [`scripts/pnetlab-dataplane-stats.py`](../scripts/pnetlab-dataplane-stats.py) | **Real-Time Telemetry**: Live terminal monitor, JSON export, and Prometheus metrics server. | `python3 scripts/pnetlab-dataplane-stats.py` |

---

## 4. Link Impairment Recipes

You can simulate real-world WAN, satellite, and degraded network conditions on any virtual link with zero topology restructuring:

### 1. Realistic WAN Link (30ms latency, 5ms jitter, 0.5% packet loss)
```bash
sudo bash scripts/pnetlab-link-impairment.sh set vnet0_1_0 --delay 30ms --jitter 5ms --loss 0.5%
```

### 2. Geostationary Satellite Link (600ms latency, 20ms jitter, 10 Mbps bandwidth)
```bash
sudo bash scripts/pnetlab-link-impairment.sh set vnet0_1_0 --delay 600ms --jitter 20ms --rate 10mbit
```

### 3. Degraded Wireless / Lossy Link (5% packet loss, 2% packet reordering)
```bash
sudo bash scripts/pnetlab-link-impairment.sh set vnet0_1_0 --loss 5% --reorder 2%
```

### 4. Protocol Resilience Testing (0.2% packet corruption for TCP/BGP checksum testing)
```bash
sudo bash scripts/pnetlab-link-impairment.sh set vnet0_1_0 --corrupt 0.2%
```

### 5. Restore Wire Speed
```bash
sudo bash scripts/pnetlab-link-impairment.sh clear vnet0_1_0
# Or clear all interfaces:
sudo bash scripts/pnetlab-link-impairment.sh clear all
```

---

## 5. Live Traffic Capture & Wireshark Streaming

### Method A: Stream Live Packets Directly to Windows Wireshark
1. On the PNETLab VM, start streaming interface `vnet0_1_0` on TCP port `19001`:
   ```bash
   sudo bash scripts/pnetlab-capture-stream.sh stream vnet0_1_0 19001
   ```
2. On your Windows machine, run Wireshark connected to the stream:
   ```cmd
   ncat <PNETLAB_VM_IP> 19001 | "C:\Program Files\Wireshark\Wireshark.exe" -k -i -
   ```

### Method B: Capture to File with BPF Filter
```bash
sudo bash scripts/pnetlab-capture-stream.sh capture vnet0_1_0 bgp_session.pcap --filter "tcp port 179 or ip proto 89"
```

---

## 6. Real-Time Telemetry & Prometheus Integration

### Live Terminal Top Dashboard
```bash
python3 scripts/pnetlab-dataplane-stats.py
```
*Outputs an auto-refreshing table showing real-time PPS, Mbps bandwidth, and drop counters for all active links.*

### Prometheus & JSON Metrics Endpoint
```bash
python3 scripts/pnetlab-dataplane-stats.py --server 9105
```
*Provides Prometheus metrics at `http://<VM_IP>:9105/` and JSON telemetry at `http://<VM_IP>:9105/json` for Grafana dashboards and canvas telemetry.*
