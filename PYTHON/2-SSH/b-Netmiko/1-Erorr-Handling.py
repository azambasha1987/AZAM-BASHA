#!/usr/bin/env python

import os
from getpass import getpass
from netmiko import ConnectHandler
from netmiko.exceptions import NetMikoTimeoutException, AuthenticationException
from paramiko.ssh_exception import SSHException

username = input('Enter your SSH username: ')
password = getpass()

script_dir = os.path.dirname(os.path.abspath(__file__))
commands_file_path = os.path.join(script_dir, 'commands_file')
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
    ip_address_of_device = devices.split(',')[0].strip()
    print('Connecting to device: ' + ip_address_of_device)
    ios_device = {
        'device_type': 'cisco_ios',
        'ip': ip_address_of_device,
        'username': username,
        'password': password
    }
    
    try:
        net_connect = ConnectHandler(**ios_device)
    except AuthenticationException:
        print('Authentication failure: ' + ip_address_of_device)
        continue
    except NetMikoTimeoutException:
        print('Timeout to device: ' + ip_address_of_device)
        continue
    except EOFError:
        print("End of file while attempting device " + ip_address_of_device)
        continue
    except SSHException:
        print('SSH issue. Are you sure SSH is enabled? ' + ip_address_of_device)
        continue
    except Exception as unknown_error:
        print('Some other error: ' + str(unknown_error))
        continue
    
    output = net_connect.send_config_set(commands_list)
    print(output)