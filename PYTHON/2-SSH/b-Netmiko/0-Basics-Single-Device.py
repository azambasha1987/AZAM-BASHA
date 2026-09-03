#!/usr/bin/env python

from netmiko import ConnectHandler

Access_SW1 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.108',
    'username': 'azam',
    'password': 'cisco',
}

net_connect = ConnectHandler(**Access_SW1)
output = net_connect.send_command('show ip int brief')
print(output)


