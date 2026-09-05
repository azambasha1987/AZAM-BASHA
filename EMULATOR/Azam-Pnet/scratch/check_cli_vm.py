import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.29', username='root', password='azam', timeout=5)

cmd = """python3 -c "
with open('/opt/unetlab/html/includes/cli.php', 'r') as f:
    lines = f.readlines()
for i in range(710, min(745, len(lines))):
    print(f'{i+1}: {lines[i].rstrip()}')
" """

stdin, stdout, stderr = ssh.exec_command(cmd)
print(stdout.read().decode('utf-8', errors='replace').encode('ascii', errors='replace').decode('ascii'))
print(stderr.read().decode('utf-8', errors='replace').encode('ascii', errors='replace').decode('ascii'))
ssh.close()
