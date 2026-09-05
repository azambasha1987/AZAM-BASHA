import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.29', username='root', password='azam', timeout=5)

cmd = """python3 -c "
import os, glob

# Check CPU & RAM
print('=== CPU Info ===')
with open('/proc/cpuinfo') as f:
    cores = [l for l in f if 'model name' in l]
    print(f'Total Cores: {len(cores)}, Model: {cores[0].split(\x27:\x27)[1].strip() if cores else \x27N/A\x27}')

print('=== RAM Info ===')
with open('/proc/meminfo') as f:
    for l in f:
        if any(k in l for k in ['MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree']):
            print(l.strip())

print('=== KSM Status ===')
if os.path.exists('/sys/kernel/mm/ksm/run'):
    with open('/sys/kernel/mm/ksm/run') as f: print(f'KSM Run: {f.read().strip()}')
    with open('/sys/kernel/mm/ksm/pages_sharing') as f: print(f'Pages Sharing: {f.read().strip()}')

print('=== Template vios / viosl2 settings ===')
for t in ['/opt/unetlab/html/templates/intel/vios.yml', '/opt/unetlab/html/templates/intel/viosl2.yml']:
    if os.path.exists(t):
        print(f'--- {t} ---')
        with open(t) as f:
            for l in f:
                if any(k in l for k in ['ram:', 'cpu:', 'qemu_options:', 'qemu_version:', 'qemu_arch:']):
                    print(l.strip())
" """

stdin, stdout, stderr = ssh.exec_command(cmd)
print(stdout.read().decode('utf-8', errors='replace').encode('ascii', errors='replace').decode('ascii'))
print(stderr.read().decode('utf-8', errors='replace').encode('ascii', errors='replace').decode('ascii'))
ssh.close()
