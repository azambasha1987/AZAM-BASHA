# Azam Basha Lab Export & APT Sources Fix Guide

**Troubleshooting & Resolution Guide for Azam Basha Appliance Administration**

---

## 1. Overview & Issues Addressed

This guide addresses two common administrative and functional issues in PNETLab deployments:
1. **APT Repository Conflicts / Duplicate Lists:**
   - Error messages during `apt update` caused by stale or duplicate installer repository configurations in `/etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list`.
2. **Lab Export Failures & Subfolder Support:**
   - Exporting labs fails when `zip` / `unzip` utilities are missing.
   - `/opt/unetlab/html/Exports` symlink or permission issues prevent downloading exported archive files.
   - The original `/opt/unetlab/scripts/remove_uuid.sh` script does not recursively process nested subfolders or sub-labs inside zip archives.

---

## 2. Automated Fix Deployment

Run [`scripts/pnetlab-fix-export-and-apt.sh`](../scripts/pnetlab-fix-export-and-apt.sh) on your PNETLab VM as root:

```bash
chmod +x pnetlab-fix-export-and-apt.sh
sudo ./pnetlab-fix-export-and-apt.sh
```

---

## 3. Step-by-Step Fix Breakdown

### Step 1: Remove Duplicate APT Source Entry
Removes the conflicting installer list:
```bash
rm -f /etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list
```

### Step 2: Install Required Utilities (`zip` and `unzip`)
Updates package lists and installs missing archive utilities needed for exporting and importing `.unl` files:
```bash
apt-get update && apt-get install -y zip unzip
```

### Step 3: Configure Exports Directory & Symlink
Ensures `/opt/unetlab/data/Exports` is created and correctly linked into Apache DocumentRoot with `www-data` ownership:
```bash
mkdir -p /opt/unetlab/data/Exports
ln -sfn /opt/unetlab/data/Exports /opt/unetlab/html/Exports
chown -R www-data:www-data /opt/unetlab/data/Exports /opt/unetlab/html/Exports
chmod -R 775 /opt/unetlab/data/Exports
```

### Step 4: Patch `remove_uuid.sh` for Recursive Subfolder Support
Replaces `/opt/unetlab/scripts/remove_uuid.sh` to properly extract archives, recursively strip UUIDs across all nested `.unl` topology files in subdirectories, and update the zip archive:
```bash
cat << "EOF" > /opt/unetlab/scripts/remove_uuid.sh
#!/bin/bash
if [ $# -ne 1 ]; then
    echo "ERROR: wrong options given."
    exit 15
fi

if [ ! -f "$1" ]; then
    echo "ERROR: file does not exist."
    exit 15
fi

TEMP=$(mktemp -d --suffix=_unetlab)
unzip -q -o -d "$TEMP" "$1"
if [ $? -ne 0 ]; then
    rm -rf "$TEMP"
    echo "ERROR: cannot unzip file."
    exit 15
fi

find "$TEMP" -name "*.unl" -exec sed -i "s/ id=\"[0-9a-f-]\{36\}\"//g" "{}" \;

(cd "$TEMP" && zip -q -r -u "$1" .)
rm -rf "$TEMP"
exit 0
EOF
chmod +x /opt/unetlab/scripts/remove_uuid.sh
```

### Step 5: Restart Apache
```bash
systemctl restart apache2
```

---

## 4. Verification

1. **Test APT Update:**
   ```bash
   apt-get update
   ```
   *Expected result: Clean update without warnings or duplicate target errors.*

2. **Test Lab Export in PNETLab Web UI:**
   - Open PNETLab Web Interface.
   - Navigate to any lab (including nested folders).
   - Click **Export** &rarr; Verify the `.zip` archive downloads successfully without errors.
