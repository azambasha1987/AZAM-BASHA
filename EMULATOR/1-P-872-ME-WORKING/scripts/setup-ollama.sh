#!/usr/bin/env bash
# ==============================================================================
# PNETLab AI Lab Builder & Local Ollama VM Provisioning Script
# Configures PNETLab v8.72+ to communicate with an external/host Ollama LLM engine
#
# Supports piped execution & non-root diagnostic checks.
# ==============================================================================
set -euo pipefail

# Support non-root diagnostic/check mode
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [HOST_IP] [MODEL] | [--check | --status]"
    exit 0
fi

if [[ "${1:-}" =~ ^(--check|--status)$ ]]; then
    echo "=== PNETLab AI & MCP Daemon Diagnostic Check ==="
    echo -n "[*] MCP Daemon Service Status: "
    systemctl is-active pnetlab-mcp 2>/dev/null || echo "INACTIVE / NOT INSTALLED"

    echo -n "[*] AI Config File (/opt/unetlab/data/ai/config.json): "
    if [ -f /opt/unetlab/data/ai/config.json ]; then
        echo "PRESENT"
    else
        echo "MISSING"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this script as root (sudo bash $0)" >&2
    exit 1
fi

echo "=== PNETLab AI Lab Builder & Ollama Setup ==="

HOST_IP="${1:-}"
if [[ -z "$HOST_IP" ]]; then
    DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -n1 || true)
    if [ -e /dev/tty ]; then
        read -rp "Windows Host IP [Default: ${DEFAULT_GW}]: " INPUT_IP < /dev/tty || true
        HOST_IP="${INPUT_IP:-$DEFAULT_GW}"
    else
        HOST_IP="$DEFAULT_GW"
    fi
fi

OLLAMA_MODEL="${2:-qwen2.5:14b-instruct}"

echo "[*] Windows/Host IP: ${HOST_IP}"
echo "[*] Ollama Model:   ${OLLAMA_MODEL}"

# 1. System Account & Permissions
echo "[1/5] Setting up system account and permissions..."
if ! id -u pnetlab-mcp &>/dev/null; then
    useradd --system --no-create-home --user-group --shell /usr/sbin/nologin pnetlab-mcp
fi
usermod -aG pnetlab-mcp www-data || true

# 2. Install Required Python Dependencies
echo "[2/5] Installing required Python dependencies..."
python3 -m pip install --break-system-packages --ignore-installed "mcp==1.29.1" "openai>=1.12.0" "httpx" || \
python3 -m pip install "mcp==1.29.1" "openai>=1.12.0" "httpx"

# 3. Directory Trees & Permissions
echo "[3/5] Creating directory trees and setting permissions..."
mkdir -p /opt/unetlab/data/ai/progress
chmod 751 /opt/unetlab/data/ai
chown root:www-data /opt/unetlab/data/ai || true
chmod 750 /opt/unetlab/data/ai/progress
chown root:www-data /opt/unetlab/data/ai/progress || true

# 4. Configure config.json & bridge.secret
echo "[4/5] Configuring AI configuration & bridge secrets..."
python3 - <<PYEOF
import json, os, secrets, hashlib, time

ai_dir = "/opt/unetlab/data/ai"
cfg_path = os.path.join(ai_dir, "config.json")
secret_path = os.path.join(ai_dir, "bridge.secret")

cfg = {}
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, "r") as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}

cfg.setdefault("mcp", {})
cfg.setdefault("provider", {})
cfg.setdefault("limits", {})

cfg["mcp"]["enabled"] = True
cfg["mcp"]["bind"] = "127.0.0.1"
cfg["mcp"]["port"] = 5701

if not cfg["mcp"].get("bridge_secret"):
    cfg["mcp"]["bridge_secret"] = secrets.token_hex(32)

with open(secret_path, "w") as f:
    f.write(cfg["mcp"]["bridge_secret"])

cfg["provider"]["provider"] = "local"
cfg["provider"]["base_url"] = "http://${HOST_IP}:11434/v1"
cfg["provider"]["model"] = "${OLLAMA_MODEL}"
cfg["provider"]["api_key"] = "ollama"

tok_hash = hashlib.sha256("pnetlab_secret_token".encode()).hexdigest()
if not cfg["mcp"].get("tokens"):
    cfg["mcp"]["tokens"] = [{"name": "default_agent", "hash": tok_hash, "pod": 0, "tenant": 0, "role": "admin"}]

cfg["limits"]["per_user_daily_tokens"] = 0
cfg["limits"]["ai_allowed_roles"] = []

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF

chmod 640 /opt/unetlab/data/ai/config.json
chown root:pnetlab-mcp /opt/unetlab/data/ai/config.json || true
chmod 640 /opt/unetlab/data/ai/bridge.secret
chown root:www-data /opt/unetlab/data/ai/bridge.secret || true

# 5. Enable and Restart Services
echo "[5/5] Enabling and restarting PNETLab MCP and Apache services..."
SERVICE_SRC="/opt/unetlab/scripts/mcp/pnetlab-mcp.service"
SERVICE_DEST="/etc/systemd/system/pnetlab-mcp.service"

if [ -f "$SERVICE_SRC" ]; then
    cp -f "$SERVICE_SRC" "$SERVICE_DEST"
elif [ ! -f "$SERVICE_DEST" ]; then
    cat << 'EOF' > "$SERVICE_DEST"
[Unit]
Description=PNETLab Model Context Protocol (MCP) Daemon
After=network.target

[Service]
Type=simple
User=pnetlab-mcp
Group=pnetlab-mcp
WorkingDirectory=/opt/unetlab/data/ai
ExecStart=/usr/bin/python3 -m mcp run /opt/unetlab/data/ai
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

if [ -f "$SERVICE_DEST" ]; then
    chmod 644 "$SERVICE_DEST"
    systemctl daemon-reload || true
    systemctl enable pnetlab-mcp || true
    systemctl restart pnetlab-mcp || true
fi
systemctl restart apache2 || service apache2 restart || true

echo "=== [SUCCESS] PNETLab Ollama Integration Configured Successfully! ==="
echo "Verify connectivity with: curl -m 3 http://${HOST_IP}:11434/v1/models"
