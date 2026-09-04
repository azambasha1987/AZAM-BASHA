#!/usr/bin/env python3
"""
Automated Deployment & Live PNetLab Fix Applicator for Remote VM
Uploads updated install.sh and scripts to the target PNetLab appliance and applies them.
"""

import os
import sys
import getpass
import paramiko

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def deploy(host, user="root", password=None):
    if not password:
        password = getpass.getpass(f"Enter SSH password for {user}@{host}: ")
    
    print(f"\n[*] Connecting to {user}@{host}:22...")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        client.connect(host, port=22, username=user, password=password, timeout=10)
        print(f"[+] Successfully authenticated as {user}@{host}!")
    except Exception as e:
        print(f"[-] SSH Authentication failed: {e}")
        return False

    sftp = client.open_sftp()
    remote_tmp = "/tmp/pnetlab_deploy"
    
    print(f"[*] Creating remote directory: {remote_tmp}...")
    try:
        sftp.mkdir(remote_tmp)
    except Exception:
        pass

    # 1. Upload install.sh
    local_install = os.path.join(BASE_DIR, "install.sh")
    remote_install = f"{remote_tmp}/install.sh"
    print(f"[*] Uploading install.sh -> {remote_install}...")
    sftp.put(local_install, remote_install)

    # 2. Upload scripts folder
    local_scripts = os.path.join(BASE_DIR, "scripts")
    remote_scripts = f"{remote_tmp}/scripts"
    try:
        sftp.mkdir(remote_scripts)
    except Exception:
        pass
    
    for f in os.listdir(local_scripts):
        if f.endswith((".sh", ".py", ".ps1")):
            src = os.path.join(local_scripts, f)
            dst = f"{remote_scripts}/{f}"
            print(f"    -> Uploading {f}...")
            sftp.put(src, dst)

    sftp.close()

    # 3. Execute remote updates
    print("\n[*] Applying 2-Tier Enterprise Root CA & Multi-IP SAN Certificate on VM...")
    cmd = f"""
    chmod +x {remote_tmp}/install.sh {remote_scripts}/*.sh 2>/dev/null || true
    
    CA_CERT="/etc/ssl/certs/pnetlab-ca.crt"
    CA_KEY="/etc/ssl/private/pnetlab-ca.key"
    SSL_CERT="/etc/ssl/certs/pnetlab-selfsigned.crt"
    SSL_KEY="/etc/ssl/private/pnetlab-selfsigned.key"
    mkdir -p /etc/ssl/certs /etc/ssl/private

    # 1. Generate PNETLab Internal Root CA (20-Year Validity)
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        openssl req -x509 -new -nodes -newkey rsa:2048 -days 7300 \\
            -keyout "$CA_KEY" \\
            -out "$CA_CERT" \\
            -subj '/CN=PNETLab Enterprise Root CA/O=PNETLab Virtual Appliance/OU=Security' \\
            -addext 'basicConstraints=critical,CA:TRUE' \\
            -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null || true
        chmod 0600 "$CA_KEY"
        chmod 0644 "$CA_CERT"
    fi

    # 2. Collect all active IP addresses
    IP_SAN="IP:127.0.0.1"
    for ip in $(hostname -I 2>/dev/null || ip -4 addr show | awk '/inet /{{print $2}}' | cut -d/ -f1); do
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
            IP_SAN="${{IP_SAN}},IP:${{ip}}"
        fi
    done

    CSR_FILE="/tmp/pnetlab_server.csr"
    EXT_FILE="/tmp/pnetlab_san.ext"

    cat << EOF > "$EXT_FILE"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:pnetlab,DNS:pnetlab.local,DNS:localhost,${{IP_SAN}}
EOF

    openssl req -new -nodes -newkey rsa:2048 \\
        -keyout "$SSL_KEY" \\
        -out "$CSR_FILE" \\
        -subj '/CN=pnetlab.local/O=PNETLab Virtual Appliance/OU=Web Engine' 2>/dev/null || true

    openssl x509 -req -in "$CSR_FILE" \\
        -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \\
        -out "$SSL_CERT" \\
        -days 3650 \\
        -extfile "$EXT_FILE" 2>/dev/null || true

    rm -f "$CSR_FILE" "$EXT_FILE" 2>/dev/null || true
    chmod 0600 "$SSL_KEY"
    chmod 0644 "$SSL_CERT"

    # 3. Publish Root CA to web download endpoints for 1-click client trust
    mkdir -p /opt/unetlab/html
    cp -f "$CA_CERT" /opt/unetlab/html/pnetlab-ca.crt 2>/dev/null || true
    cp -f "$CA_CERT" /opt/unetlab/html/ca.crt 2>/dev/null || true
    chmod 0644 /opt/unetlab/html/pnetlab-ca.crt /opt/unetlab/html/ca.crt 2>/dev/null || true

    cp -f "$SSL_CERT" /etc/ssl/certs/apache-selfsigned.crt 2>/dev/null || true
    cp -f "$SSL_KEY" /etc/ssl/private/apache-selfsigned.key 2>/dev/null || true

    systemctl reload apache2
    echo "SUCCESS: 2-Tier Root CA active and Apache reloaded! Active SAN IPs: ${{IP_SAN}}"
    """

    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode()
    err = stderr.read().decode()
    
    if out:
        print(f"\n[Remote Output]\n{out.strip()}")
    if err:
        print(f"\n[Remote Notices]\n{err.strip()}")
        
    client.close()
    print(f"\n[+] Deployment to {host} completed successfully!")
    return True

if __name__ == "__main__":
    target_ip = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.23"
    deploy(target_ip)
