from netmiko import ConnectHandler

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


all_devices = [ACCESS_SW1, ACCESS_SW2, ACCESS_SW3]

for devices in all_devices:
    net_connect = ConnectHandler(**devices)
    for n in range (2,21):
       print("Creating VLAN " + str(n))
       config_commands = ['vlan ' + str(n), 'name Netmiko_VLAN_' + str(n)]
       output = net_connect.send_config_set(config_commands)
       print(output)