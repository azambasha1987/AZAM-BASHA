#!/usr/bin/env bash
# Wrapper for root azambasha-bootstrap-and-install.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "/opt/azambasha")"
if [ -f "${SCRIPT_DIR}/azambasha-bootstrap-and-install.sh" ]; then
    exec bash "${SCRIPT_DIR}/azambasha-bootstrap-and-install.sh" "$@"
else
    exec bash "/opt/azambasha/azambasha-bootstrap-and-install.sh" "$@"
fi
