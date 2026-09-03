#!/usr/bin/env python

from netmiko import ConnectHandler
import os

ACCESS_SW1 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.108',
    'username': 'azam',
    'password': 'cisco',
}

ACCESS_SW2 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.109',
    'username': 'azam',
    'password': 'cisco',
}

ACCESS_SW3 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.110',
    'username': 'azam',
    'password': 'cisco',
}

DIS_SW1 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.106',
    'username': 'azam',
    'password': 'cisco',
}

DIS_SW2 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.105',
    'username': 'azam',
    'password': 'cisco',
}


script_dir = os.path.dirname(os.path.abspath(__file__))
access_config_path = os.path.join(script_dir, 'ACCESS_SWITCHES')

with open(access_config_path) as f:
    lines = f.read().splitlines()
print(lines)


all_devices = [ACCESS_SW1, ACCESS_SW2, ACCESS_SW3]

#ACCESS = [ACCESS_SW1, ACCESS_SW2, ACCESS_SW3]
#DISTRUBTION 

for devices in all_devices:
    net_connect = ConnectHandler(**devices)
    output = net_connect.send_config_set(lines)
    print(output)


core_config_path = os.path.join(script_dir, 'DISTRIBUTION_SWITCHES')

with open(core_config_path) as f:
    lines = f.read().splitlines()
print(lines)


all_devices = [DIS_SW2, DIS_SW1]

for devices in all_devices:
    net_connect = ConnectHandler(**devices)
    output = net_connect.send_config_set(lines)
    print(output)

