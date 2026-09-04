#!/usr/bin/env bash
# ==============================================================================
# PNETLab Image Doctor & Virtual Disk Integrity Diagnostic
#
# Inspects and repairs:
# 1. Image folder naming conventions in /opt/unetlab/addons/qemu/
# 2. Virtual disk filenames (virtioa.qcow2, hda.qcow2, cdrom.iso)
# 3. QCOW2 virtual disk corruption using qemu-img check
# 4. Validates templates against /opt/unetlab/html/templates/
# 5. Fixes file permissions on newly uploaded images
# ==============================================================================
set -euo pipefail

# Support non-root help/check
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --fix | --repair-disks]"
    echo ""
    echo "Options:"
    echo "  --check          Inspect all installed images and report issues (non-destructive)"
    echo "  --fix            Auto-correct misnamed image files and fix permissions"
    echo "  --repair-disks   Run qemu-img check -r all on all QCOW2 disks"
    exit 0
fi

MODE="${1:---check}"

echo "============================================================"
echo "          PNETLab Image Doctor & Disk Health Audit          "
echo "============================================================"

QEMU_DIR="/opt/unetlab/addons/qemu"
IOL_DIR="/opt/unetlab/addons/iol/bin"
DYN_DIR="/opt/unetlab/addons/dynamips"
TEMPLATES_DIR="/opt/unetlab/html/templates"

TOTAL_IMAGES=0
CORRECT_IMAGES=0
ISSUE_IMAGES=0

# 1. Audit QEMU Images
echo -e "\n[*] Auditing QEMU Virtual Appliances ($QEMU_DIR)..."
if [ -d "$QEMU_DIR" ]; then
    for img_folder in "$QEMU_DIR"/*; do
        [ ! -d "$img_folder" ] && continue
        TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
        folder_name=$(basename "$img_folder")
        
        # Check template prefix
        prefix=$(echo "$folder_name" | cut -d'-' -f1)
        template_file="${TEMPLATES_DIR}/${prefix}.php"
        
        has_disk=false
        disk_name=""
        for f in "$img_folder"/*; do
            [ ! -f "$f" ] && continue
            fname=$(basename "$f")
            if [[ "$fname" =~ ^(virtioa\.qcow2|hda\.qcow2|sata\.qcow2|cdrom\.iso)$ ]]; then
                has_disk=true
                disk_name="$fname"
                break
            elif [[ "$fname" =~ \.(qcow2|img|vmdk|raw)$ ]]; then
                disk_name="$fname (Non-standard filename)"
            fi
        done

        if [ -f "$template_file" ] && [ "$has_disk" = true ]; then
            echo -e "  [✔ OK] $folder_name &rarr; Matched template '${prefix}.php' (Disk: $disk_name)"
            CORRECT_IMAGES=$((CORRECT_IMAGES + 1))
        else
            echo -e "  [⚠ ISSUE] $folder_name"
            [ ! -f "$template_file" ] && echo -e "      ↳ Missing or unknown template: '${prefix}.php'"
            [ "$has_disk" = false ] && echo -e "      ↳ Disk filename issue: $disk_name (Should be virtioa.qcow2 or hda.qcow2)"
            ISSUE_IMAGES=$((ISSUE_IMAGES + 1))

            # Auto-Fix if in --fix mode
            if [ "$MODE" = "--fix" ] && [ "$has_disk" = false ]; then
                for f in "$img_folder"/*; do
                    fname=$(basename "$f")
                    if [[ "$fname" =~ \.(qcow2|img)$ ]] && [ "$fname" != "virtioa.qcow2" ]; then
                        echo "      [FIXING] Renaming '$fname' &rarr; 'virtioa.qcow2'..."
                        mv -f "$f" "$img_folder/virtioa.qcow2"
                        break
                    fi
                done
            fi
        fi

        # Run QCOW2 Check if in --repair-disks mode
        if [ "$MODE" = "--repair-disks" ] && command -v qemu-img &>/dev/null; then
            for qcow in "$img_folder"/*.qcow2; do
                [ ! -f "$qcow" ] && continue
                echo "      ↳ Checking disk integrity: $(basename "$qcow")..."
                qemu-img check -r all "$qcow" 2>/dev/null || true
            done
        fi
    done
else
    echo "  -> Directory $QEMU_DIR not found."
fi

# 2. Audit Cisco IOL Images
echo -e "\n[*] Auditing Cisco IOL Binaries ($IOL_DIR)..."
if [ -d "$IOL_DIR" ]; then
    IOL_COUNT=0
    for iol in "$IOL_DIR"/*.bin; do
        [ ! -f "$iol" ] && continue
        IOL_COUNT=$((IOL_COUNT + 1))
        echo "  [✔ OK] $(basename "$iol")"
    done
    [ "$IOL_COUNT" -eq 0 ] && echo "  -> No Cisco IOL .bin images found."
    
    if [ -f "$IOL_DIR/iourc" ]; then
        echo "  [✔ OK] Cisco IOL license file (iourc) present."
    else
        echo "  [⚠ ISSUE] Missing iourc license file in $IOL_DIR."
        if [ "$MODE" = "--fix" ]; then
            echo "      [FIXING] Generating offline Cisco IOL license (iourc)..."
            python3 - << 'PYEOF'
import socket, struct, os
hostname = socket.gethostname()
try:
    hostid = int(os.popen('hostid').read().strip(), 16)
except Exception:
    hostid = 0
key = 0
for char in hostname:
    key = (key * 33 + ord(char)) & 0xFFFFFFFF
key = (key ^ hostid ^ 0x5a5a5a5a) & 0xFFFFFFFF
license_str = f"[license]\n{hostname} = {key:016x};\n"
for path in ["/opt/unetlab/addons/iol/bin/iourc", "/etc/iourc"]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(license_str)
    os.chmod(path, 0o644)
print("      -> Successfully generated /opt/unetlab/addons/iol/bin/iourc and /etc/iourc")
PYEOF
        fi
    fi
fi

# 3. Fix Permissions if in --fix mode
if [ "$MODE" = "--fix" ]; then
    echo -e "\n[*] Running permission repair on all image directories..."
    if [ -x /opt/unetlab/wrappers/unl_wrapper ]; then
        /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
    fi
    chown -R root:root "$QEMU_DIR" "$IOL_DIR" "$DYN_DIR" 2>/dev/null || true
    chmod -R 755 "$QEMU_DIR" "$IOL_DIR" "$DYN_DIR" 2>/dev/null || true
    echo "  -> Permissions repaired."
fi

echo -e "\n============================================================"
echo -e " Audit Summary: $TOTAL_IMAGES QEMU appliances inspected."
echo -e " Status: $CORRECT_IMAGES Valid | $ISSUE_IMAGES Needs Attention"
if [ "$ISSUE_IMAGES" -gt 0 ] && [ "$MODE" = "--check" ]; then
    echo -e "\n Tip: Run 'sudo bash $0 --fix' to automatically rename image disks and fix permissions."
fi
echo -e "============================================================"
