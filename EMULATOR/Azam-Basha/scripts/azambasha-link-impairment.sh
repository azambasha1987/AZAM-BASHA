#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Composable Link Impairment & Quality Controller
#
# Programmatically configures and controls real-world link conditions on Azam Basha
# virtual links, TAP interfaces, and bridge hubs:
# • Latency & Jitter (e.g., 20ms delay with 5ms normal distribution jitter)
# • Packet Loss & Burst Loss (e.g., 1.5% random or burst loss)
# • Bandwidth Throttling (e.g., 10Mbit, 100Mbit, 1Gbit token bucket)
# • Packet Corruption & Duplication (for protocol resilience testing)
# • Reordering (simulate out-of-order IP delivery)
# ==============================================================================
set -euo pipefail

# Help & Usage
if [[ "${1:-}" =~ ^(-h|--help)$ ]] || [ $# -eq 0 ]; then
    echo "============================================================"
    echo "       Azam Basha Composable Link Impairment Controller     "
    echo "============================================================"
    echo "Usage: sudo bash $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  set <IFACE> [OPTIONS]     Apply impairment parameters to an interface"
    echo "  show [<IFACE>]            Display active impairments on interface(s)"
    echo "  clear <IFACE | all>       Remove impairments and restore wire-speed"
    echo "  list                      List all active virtual interfaces (TAP/Hub)"
    echo ""
    echo "Set Options:"
    echo "  --delay <MS>              Artificial latency (e.g. 25ms)"
    echo "  --jitter <MS>             Latency variation / jitter (e.g. 5ms)"
    echo "  --loss <PCT>              Packet loss percentage (e.g. 2.5%)"
    echo "  --burst <PCT>             Burst packet loss probability"
    echo "  --rate <RATE>             Bandwidth limit (e.g. 10mbit, 50mbit, 100mbit, 1gbit)"
    echo "  --corrupt <PCT>           Packet corruption percentage (e.g. 0.5%)"
    echo "  --duplicate <PCT>         Packet duplication percentage (e.g. 1%)"
    echo "  --reorder <PCT>           Packet reordering percentage (e.g. 5%)"
    echo ""
    echo "Examples:"
    echo "  # Simulate a 30ms WAN link with 5ms jitter and 1% packet loss on vunl0_1_0:"
    echo "  sudo bash $0 set vunl0_1_0 --delay 30ms --jitter 5ms --loss 1%"
    echo ""
    echo "  # Throttle link to 10 Mbps with 50ms latency:"
    echo "  sudo bash $0 set vunl0_1_0 --rate 10mbit --delay 50ms"
    echo ""
    echo "  # Clear impairment on vunl0_1_0 or all interfaces:"
    echo "  sudo bash $0 clear vunl0_1_0"
    echo "  sudo bash $0 clear all"
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    list)
        echo "=== Active Virtual Interfaces (Point-to-Point / Hub) ==="
        find /sys/class/net/ -maxdepth 1 \( -name "vunl*" -o -name "vnet*" -o -name "pnet*" \) | xargs -n1 basename 2>/dev/null || echo "No virtual interfaces found."
        ;;

    show)
        IFACE="${1:-}"
        if [ -n "$IFACE" ]; then
            echo "=== Active Impairment on $IFACE ==="
            tc qdisc show dev "$IFACE"
        else
            echo "=== Active Impairments across all Virtual Interfaces ==="
            for dev in $(find /sys/class/net/ -maxdepth 1 \( -name "vunl*" -o -name "vnet*" -o -name "pnet*" \) | xargs -n1 basename 2>/dev/null); do
                QDISC_INFO=$(tc qdisc show dev "$dev" 2>/dev/null | grep -E "netem|tbf" || true)
                if [ -n "$QDISC_INFO" ]; then
                    echo -e "\n[*] Interface: $dev"
                    echo "    $QDISC_INFO"
                fi
            done
        fi
        ;;

    clear)
        if [ "$(id -u)" -ne 0 ]; then
            echo "[ERROR] Please run with sudo / root to modify qdiscs." >&2
            exit 1
        fi
        TARGET="${1:-all}"
        if [ "$TARGET" = "all" ]; then
            echo "[*] Clearing all link impairments on all virtual interfaces..."
            for dev in $(find /sys/class/net/ -maxdepth 1 \( -name "vunl*" -o -name "vnet*" -o -name "pnet*" \) | xargs -n1 basename 2>/dev/null); do
                tc qdisc del dev "$dev" root 2>/dev/null || true
            done
            echo "[SUCCESS] All link impairments cleared. Full wire speed restored."
        else
            if [ ! -d "/sys/class/net/$TARGET" ]; then
                echo "[ERROR] Interface $TARGET does not exist."
                exit 1
            fi
            tc qdisc del dev "$TARGET" root 2>/dev/null || true
            echo "[SUCCESS] Impairment cleared on $TARGET. Wire speed restored."
        fi
        ;;

    set)
        if [ "$(id -u)" -ne 0 ]; then
            echo "[ERROR] Please run with sudo / root to configure link impairments." >&2
            exit 1
        fi
        if [ $# -lt 1 ]; then
            echo "[ERROR] Missing target interface. Run with --help for usage."
            exit 1
        fi

        IFACE="$1"
        shift

        if [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[ERROR] Interface '$IFACE' does not exist in /sys/class/net/."
            exit 1
        fi

        # Parse parameters
        DELAY=""
        JITTER=""
        LOSS=""
        BURST=""
        RATE=""
        CORRUPT=""
        DUPLICATE=""
        REORDER=""

        while [ $# -gt 0 ]; do
            case "$1" in
                --delay)
                    DELAY="$2"
                    shift 2
                    ;;
                --jitter)
                    JITTER="$2"
                    shift 2
                    ;;
                --loss)
                    LOSS="$2"
                    shift 2
                    ;;
                --burst)
                    BURST="$2"
                    shift 2
                    ;;
                --rate)
                    RATE="$2"
                    shift 2
                    ;;
                --corrupt)
                    CORRUPT="$2"
                    shift 2
                    ;;
                --duplicate)
                    DUPLICATE="$2"
                    shift 2
                    ;;
                --reorder)
                    REORDER="$2"
                    shift 2
                    ;;
                *)
                    echo "[ERROR] Unknown option: $1"
                    exit 1
                    ;;
            esac
        done

        # Build netem command
        NETEM_PARAMS=""
        if [ -n "$DELAY" ]; then
            NETEM_PARAMS="$NETEM_PARAMS delay $DELAY"
            if [ -n "$JITTER" ]; then
                NETEM_PARAMS="$NETEM_PARAMS $JITTER distribution normal"
            fi
        fi

        if [ -n "$LOSS" ]; then
            NETEM_PARAMS="$NETEM_PARAMS loss $LOSS"
            if [ -n "$BURST" ]; then
                NETEM_PARAMS="$NETEM_PARAMS $BURST"
            fi
        fi

        if [ -n "$CORRUPT" ]; then
            NETEM_PARAMS="$NETEM_PARAMS corrupt $CORRUPT"
        fi

        if [ -n "$DUPLICATE" ]; then
            NETEM_PARAMS="$NETEM_PARAMS duplicate $DUPLICATE"
        fi

        if [ -n "$REORDER" ]; then
            NETEM_PARAMS="$NETEM_PARAMS reorder $REORDER"
        fi

        if [ -n "$RATE" ]; then
            NETEM_PARAMS="$NETEM_PARAMS rate $RATE"
        fi

        if [ -z "$NETEM_PARAMS" ]; then
            echo "[ERROR] No impairment parameters specified. Use --delay, --loss, --rate, etc."
            exit 1
        fi

        # Clear existing qdisc
        tc qdisc del dev "$IFACE" root 2>/dev/null || true

        # Apply netem
        tc qdisc add dev "$IFACE" root netem $NETEM_PARAMS

        echo "============================================================"
        echo " [SUCCESS] Impairment Applied to $IFACE:"
        echo " Parameters: $NETEM_PARAMS"
        echo "============================================================"
        tc qdisc show dev "$IFACE"
        ;;

    *)
        echo "[ERROR] Unknown command: $COMMAND"
        echo "Run with --help to view available commands."
        exit 1
        ;;
esac
