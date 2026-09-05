import paramiko
import os

def check_xml():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('192.168.1.29', username='root', password='azam', timeout=5)

    cmd = """python3 -c "
import glob, xml.etree.ElementTree as ET

files = glob.glob('/opt/unetlab/labs/**/*.unl', recursive=True)
errors = []
for p in files:
    try:
        ET.parse(p)
    except Exception as e:
        errors.append((p, str(e)))

print(f'Total XML files checked on VM: {len(files)}')
print(f'Errors found: {len(errors)}')
for p, err in errors:
    print(f'  {p}: {err}')
" """

    stdin, stdout, stderr = ssh.exec_command(cmd)
    print(stdout.read().decode())
    print(stderr.read().decode())
    ssh.close()

if __name__ == '__main__':
    check_xml()
