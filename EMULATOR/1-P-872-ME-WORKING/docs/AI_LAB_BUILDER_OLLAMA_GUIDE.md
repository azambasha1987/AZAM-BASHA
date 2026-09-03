# PNETLab AI Lab Builder & Local Ollama Integration

**Technical Reference & Deployment Guide | PNETLab v8.72+**

This guide details the architecture, host preparation, automated virtual machine provisioning, troubleshooting matrix, and diagnostic procedures required to integrate **PNETLab (v8.72+)** with a local **Ollama LLM engine**.

---

## 1. System Architecture & Theory of Operation

```
┌────────────────────────────────────────────────────────────────────────┐
│ Windows / Host Machine (LLM Engine)                                    │
│ ┌──────────────────────────────────────────────────────────────────┐   │
│ │ Ollama Server (Port 11434)                                       │   │
│ │ Model: qwen2.5:14b-instruct (Native Tool-Calling Engine)         │   │
│ └────────────────────────────────▲─────────────────────────────────┘   │
└──────────────────────────────────┼─────────────────────────────────────┘
                                   │ OpenAI-Compatible API (HTTP /v1)
┌──────────────────────────────────┼─────────────────────────────────────┐
│ PNETLab VM (Linux Backend)       ▼                                     │
│ ┌──────────────────────────────────────────────────────────────────┐   │
│ │ AI Lab Agent Client (ai_lab_agent.py / Python Async Engine)      │   │
│ └────────────────────────────────▲─────────────────────────────────┘   │
│                                  │ Model Context Protocol (MCP)        │
│                                  │ Streamable-HTTP / SSE Transport     │
│ ┌────────────────────────────────▼─────────────────────────────────┐   │
│ │ PNETLab MCP Server (pnetlab-mcp.service on 127.0.0.1:5701)       │   │
│ │ Tools: add_node, connect_nodes, start_node, provide_config, etc. │   │
│ └────────────────────────────────▲─────────────────────────────────┘   │
│                                  │ Internal Unix Sockets / Bridge      │
│ ┌────────────────────────────────▼─────────────────────────────────┐   │
│ │ PNETLab Web Server (Apache / PHP) & Canvas UI (AI Side-Panel)    │   │
│ └──────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

### The 4-Stage Execution Flow
1. **User Prompt**: Natural language lab topology request entered via the web interface.
2. **Context Assembly**: `ai_lab_agent.py` queries the local MCP server (`127.0.0.1:5701`) for installed device templates and tool definitions.
3. **Inference & Function Calling**: The agent submits the system prompt, tool definitions, and user prompt to Ollama's OpenAI-compatible endpoint (`http://<HOST_IP>:11434/v1`). Ollama outputs structured JSON tool calls.
4. **Topology Provisioning**: The agent executes calls back against the MCP daemon, which writes the network topology directly into the active `.unl` canvas file.

---

## 2. Host Machine Setup (Windows & Ollama)

You can use the automated script [`scripts/setup-ollama-host.ps1`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/setup-ollama-host.ps1) or follow the manual steps below:

### Step 1: Bind Ollama to External Interfaces
Open PowerShell as Administrator:
```powershell
# 1. Configure OLLAMA_HOST environment variable
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', '0.0.0.0:11434', 'Machine')
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', '0.0.0.0:11434', 'User')

# 2. Allow inbound traffic on TCP Port 11434 through Windows Defender Firewall
New-NetFirewallRule -DisplayName "Ollama Port 11434" -Direction Inbound -LocalPort 11434 -Protocol TCP -Action Allow -Profile Any

# 3. Restart the Ollama background process
Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue
Start-Process "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
```

### Step 2: Pull the Recommended Tool-Calling Model
> [!IMPORTANT]
> **Model Selection Requirement**: Reasoning-only models (like DeepSeek-R1) or basic completion models fail JSON function-calling schema validation. Always use instruction-tuned models with proven OpenAI tool-calling capabilities (e.g. `qwen2.5:14b-instruct` or `llama3.1:8b`).

```bash
ollama pull qwen2.5:14b-instruct
```

### Step 3: Identify Your Windows Host IP Address
```powershell
ipconfig | Select-String "IPv4 Address"
# Example output: 192.168.1.19
```

---

## 3. PNETLab VM Automated Deployment Script

Copy [`scripts/setup-ollama.sh`](file:///e:/Git/EMULATOR/1-P-872-ME-WORKING/scripts/setup-ollama.sh) to the VM or execute:

```bash
sudo bash setup-ollama.sh <YOUR_WINDOWS_HOST_IP> [OLLAMA_MODEL]
```

*Example:*
```bash
sudo bash setup-ollama.sh 192.168.1.19 qwen2.5:14b-instruct
```

This script will:
1. Create the system user `pnetlab-mcp` and grant group access to `www-data`.
2. Install python dependencies: `mcp==1.29.1`, `openai>=1.12.0`, `httpx`.
3. Create `/opt/unetlab/data/ai/progress` with correct permissions (`751`/`750`).
4. Generate `/opt/unetlab/data/ai/config.json` and `bridge.secret`.
5. Enable and start `pnetlab-mcp.service` and restart Apache.

---

## 4. Comprehensive Troubleshooting Matrix

| Error / Symptom | Root Cause | Resolution |
| :--- | :--- | :--- |
| `AttributeError: FastMCP object has no attribute 'streamable_http_app'` | Incompatible MCP library installed (e.g. `mcp <= 1.2.0` or `mcp >= 2.0.0`). | Run: `python3 -m pip install "mcp==1.29.1" --break-system-packages --ignore-installed` |
| Connection refused / Timed out on port 11434 | 1. Ollama listening only on 127.0.0.1.<br>2. Windows Firewall blocking port 11434.<br>3. Wrong Host IP. | 1. Set `OLLAMA_HOST=0.0.0.0:11434` and restart Ollama.<br>2. Run `New-NetFirewallRule` on Windows.<br>3. Verify IP with `ipconfig`. |
| 401 Unauthorized on MCP calls | Missing or mismatched SHA-256 Bearer token hash in `config.json`. | Re-run `/root/setup-ollama.sh <HOST_IP>` to refresh token hashes and restart `pnetlab-mcp`. |
| Agent failure: unhandled errors in TaskGroup | 1. File permission denied on `config.json` for `pnetlab-mcp`.<br>2. Malformed Base URL (e.g., trailing slashes or Markdown brackets). | 1. `chmod 640 /opt/unetlab/data/ai/config.json`<br>2. `chown root:pnetlab-mcp /opt/unetlab/data/ai/config.json`<br>3. Clean URL to: `http://<HOST_IP>:11434/v1` |
| Agent loops infinitely or fails schema validation | Configured LLM lacks structured OpenAI tool-calling capabilities. | Switch model in PNETLab AI settings to verified tool-calling model: `qwen2.5:14b-instruct` or `llama3.1:8b`. |

---

## 5. Verification & Diagnostic Commands

| Test Layer | Command (PNETLab CLI) | Expected Result |
| :--- | :--- | :--- |
| **Ollama Reachability** | `curl -m 3 http://<HOST_IP>:11434/v1/models` | HTTP 200 with model JSON list |
| **MCP Daemon State** | `systemctl status pnetlab-mcp` | `active (running)` |
| **Live Agent Logs** | `journalctl -u pnetlab-mcp -f` | Real-time tool invocations |
| **Broker API Calls** | `journalctl -e --no-pager -n 50 \| grep -i "verb="` | `verb_ai_lab_build` events |

---

## 6. Sample Lab Builder Prompts

- **Point-to-Point Router Link:**
  > *Create 2 Cisco IOL routers named R1 and R2, connect them via e0/0, assign 10.1.1.0/24 subnet, and start both nodes.*

- **Multi-Node OSPF Topology:**
  > *Create a 3-router linear topology with Cisco IOL nodes named R1, R2, and R3. Connect R1 e0/0 to R2 e0/0 using subnet 10.1.12.0/24. Connect R2 e0/1 to R3 e0/0 using subnet 10.1.23.0/24. Assign loopback 0 addresses matching router numbers (1.1.1.1/32, 2.2.2.2/32, 3.3.3.3/32). Start all nodes.*
