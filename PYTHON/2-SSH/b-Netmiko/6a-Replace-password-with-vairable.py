#1/usr/bin/env python

from getpass import getpass
from netmiko import ConnectHandler

import os

username = input('Enter your SSH username: ')
password = getpass()

# Resolve paths relative to the script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
commands_file_path = os.path.join(script_dir, 'commands_file')

# Try devices-file first, fallback to devices_file
devices_file_path = os.path.join(script_dir, 'devices-file')
if not os.path.exists(devices_file_path):
    devices_file_path = os.path.join(script_dir, 'devices_file')

with open(commands_file_path) as f:
    commands_list = f.read().splitlines()

with open(devices_file_path) as f:
    devices_list = f.read().splitlines()

for devices in devices_list:
    if not devices.strip():
        continue
    # Extract IP address (handles both comma-separated and IP-only format)
    ip_address_of_device = devices.split(',')[0].strip()
    print('Connecting to device: ' + ip_address_of_device)
    ios_device = {
        'device_type': 'cisco_ios',
        'ip': ip_address_of_device,
        'username': username,
        'password': password
    }
    
    
    net_connect = ConnectHandler(**ios_device)
    output = net_connect.send_config_set(commands_list)
    print(output)

