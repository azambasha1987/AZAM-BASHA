import paramiko
import sys
import time
import os
from PIL import Image

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CLEAN_LOGO_LOCAL = r"C:\Users\azamb\.gemini\antigravity-ide\brain\ad475abf-4846-4fb3-bb0b-f12c4f938431\scratch\logo_clean.png"
LOCAL_GIT_ASSETS = r"e:\Git\EMULATOR\Azam-Pnet\assets"

def deploy_new_logo():
    # 1. Update local repository assets
    os.makedirs(LOCAL_GIT_ASSETS, exist_ok=True)
    img = Image.open(CLEAN_LOGO_LOCAL)
    img.save(os.path.join(LOCAL_GIT_ASSETS, "logo.png"), "PNG")
    
    # Save icon (64x64)
    img_icon = img.resize((64, 64), Image.Resampling.LANCZOS)
    img_icon.save(os.path.join(LOCAL_GIT_ASSETS, "logo-icon.png"), "PNG")
    
    # Save favicon.ico (multi-size)
    favicon_local = os.path.join(LOCAL_GIT_ASSETS, "favicon.ico")
    img.save(favicon_local, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    print("[+] Updated local Git repository assets in e:\\Git\\EMULATOR\\Azam-Pnet\\assets")

    # 2. Connect to Remote VM
    print("[*] Connecting to 192.168.1.29 via SFTP...")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect('192.168.1.29', port=22, username='root', password='azam', look_for_keys=False, allow_agent=False)
    sftp = client.open_sftp()

    remote_logo_paths = [
        "/opt/unetlab/data/branding/logo.png",
        "/opt/unetlab/html/images/logo.png",
        "/opt/unetlab/html/themes/default/images/logo.png",
        "/opt/unetlab/html/assets-common/img/logo.png",
        "/opt/azambasha/assets/logo.png",
        "/opt/azambasha/assets/logo-icon.png"
    ]

    for rpath in remote_logo_paths:
        rdir = os.path.dirname(rpath)
        client.exec_command(f"mkdir -p '{rdir}'")
        print(f"[*] Uploading logo to {rpath}...")
        sftp.put(CLEAN_LOGO_LOCAL, rpath)
        client.exec_command(f"chmod 644 '{rpath}'")

    remote_favicon_paths = [
        "/opt/unetlab/html/images/favicon.png",
        "/opt/unetlab/html/themes/default/images/favicon.ico",
        "/opt/unetlab/html/favicon.ico",
        "/opt/unetlab/html/favicon/favicon.ico"
    ]

    for fpath in remote_favicon_paths:
        rdir = os.path.dirname(fpath)
        client.exec_command(f"mkdir -p '{rdir}'")
        print(f"[*] Uploading favicon to {fpath}...")
        sftp.put(favicon_local, fpath)
        client.exec_command(f"chmod 644 '{fpath}'")

    # Update branding config.json to cache bust
    now_ts = int(time.time())
    cfg_json = f'{{\n    "name": "Azam Basha",\n    "login_header": "Azam Basha Network Emulation Platform",\n    "hide_default_creds": false,\n    "updated_at": {now_ts}\n}}'
    print("[*] Updating /opt/unetlab/data/branding/config.json...")
    with sftp.open('/opt/unetlab/data/branding/config.json', 'w') as f:
        f.write(cfg_json.encode('utf-8'))
        
    client.exec_command("chmod -R 777 /opt/unetlab/data/branding && chown -R www-data:www-data /opt/unetlab/data/branding")

    sftp.close()
    client.close()
    print("[+] Successfully replaced the logo everywhere across the entire platform!")

if __name__ == "__main__":
    deploy_new_logo()
