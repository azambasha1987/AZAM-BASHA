#!/usr/bin/env python3
"""
PNETLab Real-Time Per-Link Telemetry & Dataplane Stats Exporter
==============================================================
Monitors per-interface and per-link metrics across virtual networks:
- Packets Per Second (PPS Rx / Tx)
- Bits Per Second (BPS / Mbps Rx / Tx)
- Total Packets & Bytes (Rx / Tx)
- Dropped & Error Packets
- Link State & MTU

Modes:
- Default: Live interactive terminal dashboard (top-like refresh)
- --json: Outputs structured JSON metrics snapshot
- --server [PORT]: Starts a lightweight HTTP metrics server (Prometheus / JSON) on port 9105
"""

import os
import sys
import time
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

def read_interface_stats():
    stats = {}
    net_dev = "/proc/net/dev"
    if not os.path.exists(net_dev):
        return stats

    with open(net_dev, "r") as f:
        lines = f.readlines()[2:] # Skip headers

    for line in lines:
        parts = line.strip().split()
        if not parts:
            continue
        iface = parts[0].rstrip(":")
        if not iface.startswith(("vnet", "vunl", "pnet", "eth", "ens", "enp", "eno", "br")):
            continue

        try:
            rx_bytes = int(parts[1])
            rx_packets = int(parts[2])
            rx_errs = int(parts[3])
            rx_drop = int(parts[4])
            tx_bytes = int(parts[9])
            tx_packets = int(parts[10])
            tx_errs = int(parts[11])
            tx_drop = int(parts[12])

            # Read link state & MTU if available in sysfs
            sys_path = f"/sys/class/net/{iface}"
            operstate = "unknown"
            mtu = 1500
            if os.path.exists(f"{sys_path}/operstate"):
                try:
                    with open(f"{sys_path}/operstate", "r") as sf:
                        operstate = sf.read().strip()
                except Exception:
                    pass
            if os.path.exists(f"{sys_path}/mtu"):
                try:
                    with open(f"{sys_path}/mtu", "r") as sf:
                        mtu = int(sf.read().strip())
                except Exception:
                    pass

            stats[iface] = {
                "rx_bytes": rx_bytes,
                "rx_packets": rx_packets,
                "rx_errors": rx_errs,
                "rx_drops": rx_drop,
                "tx_bytes": tx_bytes,
                "tx_packets": tx_packets,
                "tx_errors": tx_errs,
                "tx_drops": tx_drop,
                "state": operstate,
                "mtu": mtu,
                "timestamp": time.time()
            }
        except (IndexError, ValueError):
            continue

    return stats

def compute_rates(prev_stats, curr_stats):
    rates = {}
    for iface, curr in curr_stats.items():
        if iface in prev_stats:
            prev = prev_stats[iface]
            dt = curr["timestamp"] - prev["timestamp"]
            if dt > 0:
                rx_pps = max(0, int((curr["rx_packets"] - prev["rx_packets"]) / dt))
                tx_pps = max(0, int((curr["tx_packets"] - prev["tx_packets"]) / dt))
                rx_bps = max(0, int(((curr["rx_bytes"] - prev["rx_bytes"]) * 8) / dt))
                tx_bps = max(0, int(((curr["tx_bytes"] - prev["tx_bytes"]) * 8) / dt))
            else:
                rx_pps, tx_pps, rx_bps, tx_bps = 0, 0, 0, 0
        else:
            rx_pps, tx_pps, rx_bps, tx_bps = 0, 0, 0, 0

        rates[iface] = {
            **curr,
            "rx_pps": rx_pps,
            "tx_pps": tx_pps,
            "rx_bps": rx_bps,
            "tx_bps": tx_bps,
            "rx_mbps": round(rx_bps / 1_000_000, 2),
            "tx_mbps": round(tx_bps / 1_000_000, 2)
        }
    return rates

def format_bytes(n):
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.2f} GB"
    elif n >= 1_000_000:
        return f"{n / 1_000_000:.2f} MB"
    elif n >= 1_000:
        return f"{n / 1_000:.2f} KB"
    return f"{n} B"

def run_live_dashboard():
    prev = read_interface_stats()
    time.sleep(1)
    try:
        while True:
            curr = read_interface_stats()
            rates = compute_rates(prev, curr)
            prev = curr

            # Clear terminal
            os.system('cls' if os.name == 'nt' else 'clear')

            print("="*80)
            print("         PNETLab Real-Time Dataplane & Link Telemetry Monitor")
            print("="*80)
            print(f"{'Interface':<14} {'State':<7} {'Rx PPS':<9} {'Tx PPS':<9} {'Rx Bandwidth':<14} {'Tx Bandwidth':<14} {'Drops':<6}")
            print("-" * 80)

            for iface in sorted(rates.keys()):
                r = rates[iface]
                total_drops = r["rx_drops"] + r["tx_drops"]
                rx_rate = f"{r['rx_mbps']} Mbps" if r['rx_mbps'] > 0.05 else f"{r['rx_bps']:,} bps"
                tx_rate = f"{r['tx_mbps']} Mbps" if r['tx_mbps'] > 0.05 else f"{r['tx_bps']:,} bps"
                state_str = r['state'].upper() if r['state'] != "unknown" else "UP"

                print(f"{iface:<14} {state_str:<7} {r['rx_pps']:<9,}{r['tx_pps']:<9,} {rx_rate:<14} {tx_rate:<14} {total_drops:<6}")

            print("="*80)
            print("Press Ctrl+C to exit dashboard.")
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nExiting telemetry monitor.")

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        curr = read_interface_stats()
        if self.path == "/json" or self.path == "/api/stats":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(curr, indent=2).encode("utf-8"))
        else:
            # Prometheus plain text metrics
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            lines = ["# PNETLab Dataplane Prometheus Metrics\n"]
            for iface, data in curr.items():
                lines.append(f'pnetlab_rx_packets_total{{interface="{iface}"}} {data["rx_packets"]}')
                lines.append(f'pnetlab_tx_packets_total{{interface="{iface}"}} {data["tx_packets"]}')
                lines.append(f'pnetlab_rx_bytes_total{{interface="{iface}"}} {data["rx_bytes"]}')
                lines.append(f'pnetlab_tx_bytes_total{{interface="{iface}"}} {data["tx_bytes"]}')
                lines.append(f'pnetlab_rx_drops_total{{interface="{iface}"}} {data["rx_drops"]}')
                lines.append(f'pnetlab_tx_drops_total{{interface="{iface}"}} {data["tx_drops"]}')
                lines.append(f'pnetlab_rx_errors_total{{interface="{iface}"}} {data["rx_errors"]}')
                lines.append(f'pnetlab_tx_errors_total{{interface="{iface}"}} {data["tx_errors"]}')
            self.wfile.write("\n".join(lines).encode("utf-8") + b"\n")

    def log_message(self, format, *args):
        pass

def run_metrics_server(port=9105):
    server = HTTPServer(("0.0.0.0", port), MetricsHandler)
    print(f"PNETLab Dataplane Telemetry Exporter running on http://0.0.0.0:{port}/ (JSON: /json)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping metrics server.")

if __name__ == "__main__":
    if "--json" in sys.argv:
        curr = read_interface_stats()
        print(json.dumps(curr, indent=2))
    elif "--server" in sys.argv:
        port = 9105
        if len(sys.argv) > 2 and sys.argv[2].isdigit():
            port = int(sys.argv[2])
        run_metrics_server(port)
    else:
        run_live_dashboard()
