#!/usr/bin/env bash
# ==============================================================================
# PNetLab PHP 8.4 / 8.5 Runtime & API Modernizer for Ubuntu 26+ (Resolute)
# Injects #[AllowDynamicProperties] into core UNetLab and Slim framework classes,
# tunes PHP-FPM OPcache/memory limits, and stabilizes HTTP/HTTPS session cookies.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "    [2/4] Modernizing PHP 8.4/8.5 Engine & Configurations..."
echo "============================================================"

# 1. Detect Installed PHP Version
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.5")"
echo "      -> Detected PHP Runtime: PHP ${PHP_VER}"

# 2. Inject #[AllowDynamicProperties] into Core UNetLab & Slim Classes
echo "      -> Patching PHP classes with #[AllowDynamicProperties]..."
python3 - << 'PYEOF'
import os, re

target_dirs = ["/opt/unetlab/html/includes", "/opt/unetlab/html/includes/Slim", "/opt/unetlab/html/includes/models"]

class_regex = re.compile(r'^(class\s+[A-Za-z0-9_]+)', re.MULTILINE)

for target_dir in target_dirs:
    if not os.path.exists(target_dir):
        continue
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            if file.endswith('.php'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                    
                    if '#[AllowDynamicProperties]' in content:
                        continue
                    
                    # Inject attribute before class declaration
                    modified = False
                    def repl(match):
                        nonlocal modified
                        modified = True
                        return "#[\\AllowDynamicProperties]\n" + match.group(1)
                    
                    new_content = class_regex.sub(repl, content, count=1)
                    if modified:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(new_content)
                except Exception as e:
                    pass
PYEOF

# 3. Ensure Session Cookie Compatibility in api.php
API_PHP="/opt/unetlab/html/api.php"
if [ -f "$API_PHP" ]; then
    sed -i 's/"secure" *=> *true/"secure" => (!empty($_SERVER["HTTPS"]) \&\& $_SERVER["HTTPS"] !== "off")/g' "$API_PHP" 2>/dev/null || true
    sed -i 's/"samesite" *=> *"Strict"/"samesite" => "Lax"/g' "$API_PHP" 2>/dev/null || true
    echo "      -> Modernized session cookie attributes in api.php"
fi

# 4. Tune PHP-FPM and PHP CLI Configurations
for conf in /etc/php/${PHP_VER}/fpm/php.ini /etc/php/${PHP_VER}/cli/php.ini /etc/php/*/*/php.ini; do
    if [ -f "$conf" ]; then
        sed -i 's/^memory_limit = .*/memory_limit = 2048M/' "$conf" 2>/dev/null || true
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100G/' "$conf" 2>/dev/null || true
        sed -i 's/^post_max_size = .*/post_max_size = 100G/' "$conf" 2>/dev/null || true
        sed -i 's/^max_execution_time = .*/max_execution_time = 3600/' "$conf" 2>/dev/null || true
        sed -i 's/^max_input_time = .*/max_input_time = 3600/' "$conf" 2>/dev/null || true
        sed -i 's/^;max_input_vars = .*/max_input_vars = 100000/' "$conf" 2>/dev/null || true
        sed -i 's/^max_input_vars = .*/max_input_vars = 100000/' "$conf" 2>/dev/null || true
        sed -i 's/^error_reporting = .*/error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_NOTICE \& ~E_USER_DEPRECATED/' "$conf" 2>/dev/null || true
        
        # OPcache Settings
        sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$conf" 2>/dev/null || true
        sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=512/' "$conf" 2>/dev/null || true
        sed -i 's/^;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=64/' "$conf" 2>/dev/null || true
        sed -i 's/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=50000/' "$conf" 2>/dev/null || true
        sed -i 's/^;opcache.revalidate_freq=.*/opcache.revalidate_freq=2/' "$conf" 2>/dev/null || true
    fi
done
echo "      -> Applied high-performance OPcache, 2GB memory, and 100GB upload limits"

# 5. Restart PHP-FPM Service
systemctl restart "php${PHP_VER}-fpm" 2>/dev/null || systemctl restart php*-fpm 2>/dev/null || true

echo "============================================================"
echo "    [SUCCESS] PHP 8.4/8.5 Engine & Runtime Modernized!      "
echo "============================================================"
