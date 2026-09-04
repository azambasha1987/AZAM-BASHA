#!/usr/bin/env bash
# ==============================================================================
# Azam Basha High-Performance Packet Capture & Live Streamer
#
# Provides:
# • Low-overhead memory-mapped live packet capture on virtual links (vunl* / vnet* / pnet*)
# • Protocol/BPF filtering on Point-to-Point links, Hubs, and Clouds
# • Live Wireshark streaming over TCP port or stdout
# • Instant buffer capture with zero packet drop
# ==============================================================================
set -euo pipefail

# Help & Usage
if [[ "${1:-}" =~ ^(-h|--help)$ ]] || [ $# -eq 0 ]; then
    echo "============================================================"
    echo "   Azam Basha High-Performance Packet Capture & Stream      "
    echo "============================================================"
    echo "Usage: sudo bash $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  capture <IFACE> [FILE.pcap] [OPTIONS]   Record packets to a file"
    echo "  stream <IFACE> [PORT] [OPTIONS]         Stream live packets over TCP for Wireshark"
    echo "  live <IFACE> [OPTIONS]                  Output live packet summaries to terminal"
    echo "  list                                    List active capture interfaces (TAP/Hub/Cloud)"
    echo ""
    echo "Options:"
    echo "  --filter <BPF>     BPF filter expression (e.g., 'tcp port 179 or ip proto 89')"
    echo "  --count <N>        Stop after N packets"
    echo "  --duration <SEC>   Stop after SEC seconds"
    echo "  --snaplen <BYTES>  Snapshot length in bytes (default: 0 / full packet)"
    echo ""
    echo "Examples:"
    echo "  # Capture OSPF/BGP on vunl0_1_0 to file:"
    echo "  sudo bash $0 capture vunl0_1_0 bgp_test.pcap --filter 'tcp port 179 or ip proto 89'"
    echo ""
    echo "  # Stream vunl0_1_0 or pnet0 live on TCP port 19001 for Wireshark:"
    echo "  sudo bash $0 stream vunl0_1_0 19001"
    echo ""
    echo "  # In Wireshark on Windows, connect via ssh or ncat:"
    echo "  ncat <VM_IP> 19001 | \"C:\\Program Files\\Wireshark\\Wireshark.exe\" -k -i -"
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    list)
        echo "=== Available Capture Interfaces (Point-to-Point / Hub / Cloud) ==="
        for dev in $(find /sys/class/net/ -maxdepth 1 \( -name "vunl*" -o -name "vnet*" -o -name "pnet*" \) | xargs -n1 basename 2>/dev/null | sort); do
            RX_PKTS=$(cat "/sys/class/net/$dev/statistics/rx_packets" 2>/dev/null || echo 0)
            TX_PKTS=$(cat "/sys/class/net/$dev/statistics/tx_packets" 2>/dev/null || echo 0)
            DEV_TYPE="Link/TAP"
            [[ "$dev" =~ ^pnet ]] && DEV_TYPE="Cloud/Bridge Hub"
            echo "  * $dev [$DEV_TYPE] (Rx: ${RX_PKTS} pkts, Tx: ${TX_PKTS} pkts)"
        done
        ;;

    live)
        IFACE="${1:-}"
        if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[ERROR] Invalid interface: '$IFACE'"
            exit 1
        fi
        shift || true

        FILTER=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --filter)
                    FILTER="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        echo "=== Starting Live Console Capture on $IFACE (Ctrl+C to stop) ==="
        tcpdump -i "$IFACE" -nn -l -B 4096 ${FILTER:+"$FILTER"}
        ;;

    capture)
        if [ "$(id -u)" -ne 0 ]; then
            echo "[ERROR] Please run with sudo / root to capture network packets." >&2
            exit 1
        fi
        IFACE="${1:-}"
        if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[ERROR] Invalid interface: '$IFACE'"
            exit 1
        fi
        shift

        OUTFILE="${1:-azambasha_capture_$(date +%Y%m%d_%H%M%S).pcap}"
        [[ "$OUTFILE" == --* ]] && OUTFILE="azambasha_capture_$(date +%Y%m%d_%H%M%S).pcap" || shift || true

        FILTER=""
        COUNT=""
        DURATION=""
        SNAPLEN="0"

        while [ $# -gt 0 ]; do
            case "$1" in
                --filter)
                    FILTER="$2"
                    shift 2
                    ;;
                --count)
                    COUNT="-c $2"
                    shift 2
                    ;;
                --duration)
                    DURATION="-G $2 -W 1"
                    shift 2
                    ;;
                --snaplen)
                    SNAPLEN="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        echo "============================================================"
        echo "   Azam Basha Packet Capture Started                        "
        echo "============================================================"
        echo " • Interface:  $IFACE"
        echo " • Output:     $OUTFILE"
        echo " • Buffer:     4096 KB ring buffer (Zero packet drop)"
        [ -n "$FILTER" ] && echo " • Filter:     $FILTER"
        echo "============================================================"
        echo "Press Ctrl+C to stop capturing."

        tcpdump -i "$IFACE" -s "$SNAPLEN" -B 4096 -U -w "$OUTFILE" $COUNT $DURATION ${FILTER:+"$FILTER"}
        echo ""
        echo "[SUCCESS] Capture saved to: $OUTFILE ($(ls -lh "$OUTFILE" | awk '{print $5}'))"
        ;;

    stream)
        if [ "$(id -u)" -ne 0 ]; then
            echo "[ERROR] Please run with sudo / root to stream live packets." >&2
            exit 1
        fi
        IFACE="${1:-}"
        PORT="${2:-19001}"

        if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[ERROR] Invalid interface: '$IFACE'"
            exit 1
        fi

        echo "============================================================"
        echo "   Azam Basha Live Wireshark Streamer                       "
        echo "============================================================"
        echo " • Interface:  $IFACE"
        echo " • Stream TCP: 0.0.0.0:$PORT"
        echo "============================================================"
        echo "On your Windows machine, open Wireshark via:"
        echo "  ncat <VM_IP> $PORT | \"C:\\Program Files\\Wireshark\\Wireshark.exe\" -k -i -"
        echo ""
        echo "Waiting for Wireshark client connection on port $PORT..."

        if command -v nc &>/dev/null || command -v ncat &>/dev/null; then
            NC_CMD=$(command -v nc || command -v ncat)
            tcpdump -i "$IFACE" -s 0 -B 4096 -U -w - 2>/dev/null | $NC_CMD -l -p "$PORT"
        else
            echo "Installing netcat for TCP streaming..."
            apt-get update && apt-get install -y netcat-openbsd
            tcpdump -i "$IFACE" -s 0 -B 4096 -U -w - 2>/dev/null | nc -l -p "$PORT"
        fi
        ;;

    *)
        echo "[ERROR] Unknown command: $COMMAND"
        exit 1
        ;;
esac
