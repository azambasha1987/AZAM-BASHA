import paramiko
import time

ip_address = "192.168.1.105"
username = "azam"
password = "cisco"

ssh_client = paramiko.SSHClient()
ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh_client.connect(hostname=ip_address, username=username, password=password)

print(f"Successful connection {ip_address}")

remote_connection = ssh_client.invoke_shell()
time.sleep(1)

remote_connection.send(b"enable\n")
time.sleep(1)
remote_connection.send(b"cisco\n")
time.sleep(1)

remote_connection.send(b"configure terminal\n")
remote_connection.send(b"int loop 0\n")
remote_connection.send(b"ip address 1.1.1.1 255.255.255.255\n")
remote_connection.send(b"int loop 1\n")
remote_connection.send(b"ip address 2.2.2.2 255.255.255.255\n")
remote_connection.send(b"router ospf 1\n")
remote_connection.send(b"network 0.0.0.0 255.255.255.255 area 0\n")

for n in range(2, 21):
    print(f"Creating VLAN {n}")
    remote_connection.send(f"vlan {n}\n".encode())
    remote_connection.send(f"name Paramiko_VLAN_{n}\n".encode())
    time.sleep(0.5)

remote_connection.send(b"end\n")

# delay so that ssh input is taken
time.sleep(1)
output = remote_connection.recv(65535)
print(output.decode('utf-8', errors='ignore'))

ssh_client.close()