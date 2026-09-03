import getpass
from netmiko import ConnectHandler

HOST = "192.168.1.104"
user = input("Enter your SSH username: ")
password = getpass.getpass()

device = {
    "device_type": "cisco_ios",
    "host": HOST,
    "username": user,
    "password": password,
    "secret": "cisco",  # Enable password
}

net_connect = ConnectHandler(**device)
net_connect.enable()

config_commands = [
    "int loop 0",
    "ip address 1.1.1.1 255.255.255.255",
    "int loop 1",
    "ip address 2.2.2.2 255.255.255.255",
    "router ospf 1",
    "network 0.0.0.0 255.255.255.255 area 0",
]

output = net_connect.send_config_set(config_commands)
print(output)
net_connect.disconnect()

#lets break down the code:
