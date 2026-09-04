#!/usr/bin/env bash
# ==============================================================================
# PNETLab 1-Click Standalone Offline Bundle Packager
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-${SCRIPT_DIR}/pnetlab-v8-standalone-offline.tar.gz}"

echo "============================================================"
echo "    PNETLab v8 Standalone Offline Bundle Packager           "
echo "============================================================"
echo "Packaging directory: $SCRIPT_DIR"
echo "Target output file : $OUTPUT_FILE"

# Clean temporary logs and scratch files
rm -rf "${SCRIPT_DIR}"/scratch/*.log "${SCRIPT_DIR}"/sync.log 2>/dev/null || true

tar --exclude='.git' \
    --exclude='.tempmediaStorage' \
    --exclude='*.tar.gz' \
    --exclude='*.ova' \
    --exclude='__pycache__' \
    -czf "$OUTPUT_FILE" \
    -C "$(dirname "$SCRIPT_DIR")" \
    "$(basename "$SCRIPT_DIR")"

echo ""
echo "============================================================"
echo "  [SUCCESS] Standalone Offline Archive Created!"
echo "  File: $OUTPUT_FILE"
echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "============================================================"
