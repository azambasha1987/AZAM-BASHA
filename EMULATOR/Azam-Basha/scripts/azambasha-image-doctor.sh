#!/usr/bin/env bash
# ==============================================================================
# Azam Basha Image Doctor & Virtual Disk Integrity Diagnostic
# Fully compliant with EVE-NG / UNetLab QEMU Image Naming Standards:
#
# 1. Folder structure: /opt/unetlab/addons/qemu/<template>-<version>
# 2. Supported disk formats:
#    - VirtIO:   virtioa.qcow2, virtiob.qcow2, ...
#    - IDE:      hda.qcow2, hdb.qcow2, ...
#    - SATA:     sataa.qcow2, satab.qcow2, ...
#    - SCSI:     scsia.qcow2, scsib.qcow2, ...
#    - VirtIDE:  virtidea.qcow2, ...
#    - LSI:      lsia.qcow2, ...
#    - MegaSAS:  megasasa.qcow, megasasa.qcow2, ...
#    - Media:    cdrom.iso, kernel.img, BaseSystem.img
# 3. Validates against all 107 templates in /opt/unetlab/html/templates/
# 4. Auto-corrects non-standard filenames and repairs permissions
# ==============================================================================
set -euo pipefail

# Support non-root help/check
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: sudo bash $0 [--check | --fix | --repair-disks]"
    echo ""
    echo "Options:"
    echo "  --check          Inspect all installed images and report compliance (non-destructive)"
    echo "  --fix            Auto-correct misnamed image files and fix permissions"
    echo "  --repair-disks   Run qemu-img check -r all on all QCOW2 disks"
    exit 0
fi

MODE="${1:---check}"

echo "============================================================"
echo "      Azam Basha Image Doctor & Disk Health Audit Engine    "
echo "============================================================"

QEMU_DIR="/opt/unetlab/addons/qemu"
IOL_DIR="/opt/unetlab/addons/iol/bin"
DYN_DIR="/opt/unetlab/addons/dynamips"
TEMPLATES_DIR="/opt/unetlab/html/templates"

TOTAL_IMAGES=0
CORRECT_IMAGES=0
ISSUE_IMAGES=0

# Valid standard disk regex from EVE-NG specification
VALID_DISK_REGEX='^(virtio[a-z]+|hd[a-z]+|sata[a-z]+|scsi[a-z]+|virtide[a-z]+|lsi[a-z]+|megasas[a-z]+)\.qcow2?$|^(cdrom\.iso|kernel\.img|BaseSystem\.img)$'

# 1. Audit QEMU Images
echo -e "\n[*] Auditing QEMU Virtual Appliances ($QEMU_DIR)..."
if [ -d "$QEMU_DIR" ]; then
    for img_folder in "$QEMU_DIR"/*; do
        [ ! -d "$img_folder" ] && continue
        TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
        folder_name=$(basename "$img_folder")
        
        # Check template prefix (everything before the first hyphen)
        prefix=$(echo "$folder_name" | cut -d'-' -f1)
        
        # Check template file in templates root or subfolders
        template_found=false
        if [ -f "${TEMPLATES_DIR}/${prefix}.yml" ] || \
           [ -f "${TEMPLATES_DIR}/intel/${prefix}.yml" ] || \
           [ -f "${TEMPLATES_DIR}/amd/${prefix}.yml" ]; then
            template_found=true
        fi
        
        has_valid_disk=false
        disk_names=()
        non_standard_disks=()
        
        for f in "$img_folder"/*; do
            [ ! -f "$f" ] && continue
            fname=$(basename "$f")
            if [[ "$fname" =~ $VALID_DISK_REGEX ]]; then
                has_valid_disk=true
                disk_names+=("$fname")
            elif [[ "$fname" =~ \.(qcow2|qcow|img|vmdk|raw)$ ]]; then
                non_standard_disks+=("$fname")
            fi
        done

        if [ "$template_found" = true ] && [ "$has_valid_disk" = true ]; then
            echo -e "  [✔ OK] $folder_name &rarr; Template: '${prefix}.yml' | Disks: ${disk_names[*]}"
            CORRECT_IMAGES=$((CORRECT_IMAGES + 1))
        else
            echo -e "  [⚠ ISSUE] $folder_name"
            [ "$template_found" = false ] && echo -e "      ↳ Missing or unknown template: '${prefix}.yml'"
            [ "$has_valid_disk" = false ] && echo -e "      ↳ No standard HDD image found. Detected: ${non_standard_disks[*]:-none} (Should be virtioa.qcow2, hda.qcow2, sataa.qcow2, etc.)"
            ISSUE_IMAGES=$((ISSUE_IMAGES + 1))

            # Auto-Fix if in --fix mode
            if [ "$MODE" = "--fix" ] && [ "$has_valid_disk" = false ] && [ ${#non_standard_disks[@]} -gt 0 ]; then
                target_disk="virtioa.qcow2"
                # Determine default disk type from prefix
                case "$prefix" in
                    a10|acs|asa|barracuda|cda|cips|clearpass|aruba|cpsg|extremevoss|esxi|fpfw|fpsmc|hpvsr|huaweiusg6kv|ise|mikrotik|nsx|olive|ostinato|osx|silveredge|silverorch|stealth|timos|veos|vmx|vnam|vqfxpfe|vqfxre|xrv)
                        target_disk="hda.qcow2"
                        ;;
                    extremexos|firepower6|kerio|nxosv9k|sonicwall|vcenter)
                        target_disk="sataa.qcow2"
                        ;;
                    firepower|sourcefire)
                        target_disk="scsia.qcow2"
                        ;;
                    timoscpm|timosiom)
                        target_disk="virtidea.qcow2"
                        ;;
                    vwlc)
                        target_disk="megasasa.qcow"
                        ;;
                    *)
                        target_disk="virtioa.qcow2"
                        ;;
                esac
                first_disk="${non_standard_disks[0]}"
                echo "      [FIXING] Renaming '$first_disk' &rarr; '$target_disk'..."
                mv -f "$img_folder/$first_disk" "$img_folder/$target_disk"
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
    
    if [ -f "$IOL_DIR/iourc" ] || [ -f "/etc/iourc" ]; then
        echo "  [✔ OK] Cisco IOL license file (iourc) present."
    else
        echo "  [⚠ ISSUE] Missing iourc license file."
        if [ "$MODE" = "--fix" ]; then
            echo "      [FIXING] Generating offline Cisco IOL license (iourc)..."
            python3 - << 'PYEOF'
import hashlib, os, struct, socket
hostname = socket.gethostname()
try:
    hostid = int(os.popen('hostid').read().strip(), 16) & 0xFFFFFFFF
except Exception:
    hostid = 0
pad1 = b'\x4b\x58\x21\x81\x56\x7b\x0d\x91\xdf\x24\x08\xf8\x5c\x9b\x74\xf2'
pad2 = b'\x80' + b'\x00'*39
m = hashlib.md5()
m.update(struct.pack('!I', hostid))
m.update(pad1)
m.update(pad2)
key = m.hexdigest()[:16]
content = f"[license]\n{hostname} = {key};\n"
for path in ["/opt/unetlab/addons/iol/bin/iourc", "/etc/iourc", "/opt/unetlab/data/iourc"]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, 0o644)
print(f"      -> Successfully generated iourc for '{hostname}' (key: {key})")
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
