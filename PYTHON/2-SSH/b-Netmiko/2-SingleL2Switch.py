#!/usr/bin/env python

from netmiko import ConnectHandler

ios_xe_l2 = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.105',
    'username': 'azam',
    'password': 'cisco',
    'secret': 'cisco',
}


net_connect = ConnectHandler(**ios_xe_l2)
net_connect.enable()
#net_connect.find_prompt()
output = net_connect.send_command('show ip int brief')
print(output)

config_commands = ['int loop 0', 'ip address 1.1.1.1 255.255.255.0']
output = net_connect.send_config_set(config_commands)
print(output)

for n in range (2,20):
    print("Creating VLAN " + str(n))
    config_commands = ['vlan ' + str(n), 'name Netmiko_VLAN_' + str(n)]
    output = net_connect.send_config_set(config_commands)
    print(output)

net_connect.disconnect()

# explanation:
#
# imports:
# - netmiko.ConnectHandler: Used to establish SSH connections and execute commands/configuration on network devices.
#
# variables:
# - ios_xe_l2: A dictionary containing connection parameters for the target L2 switch.
#   - 'device_type': Specifies the OS type of the device ('cisco_xe').
#   - 'ip': The management IP address of the target L2 switch ('192.168.1.105').
#   - 'username': Username for SSH login ('azam').
#   - 'password': Password for SSH login ('cisco').
#   - 'secret': Enable password for entering privilege EXEC mode ('cisco').
#
# script flow:
# 1. net_connect = ConnectHandler(**ios_xe_l2): Connects to the switch using parameters unpacked from the dictionary.
# 2. net_connect.enable(): Enters enable/privilege EXEC mode on the switch using the configured 'secret'.
# 3. #net_connect.find_prompt(): (Commented out) Retrieves the current command prompt.
# 4. output = net_connect.send_command('show ip int brief'): Executes the non-interactive show command on the switch and saves output.
# 5. print(output): Prints the command output to the local terminal screen.
# 6. config_commands = [...]: Defines a list of configuration commands to create and assign IP to Loopback 0.
# 7. output = net_connect.send_config_set(config_commands): Enters config mode (conf t), executes the configuration command list, and exits config mode (end).
# 8. print(output): Prints the configuration session output.
# 9. for n in range (2,20): Iterates through VLAN IDs from 2 to 19 (inclusive).
# 10. print("Creating VLAN " + str(n)): Prints progress to the terminal.
# 11. config_commands = [...]: Generates config commands to create the VLAN and assign it a name (e.g. 'vlan 2' and 'name Netmiko_VLAN_2').
# 12. output = net_connect.send_config_set(config_commands): Applies the VLAN commands on the switch.
# 13. print(output): Prints the VLAN configuration response.
# 14. net_connect.disconnect(): Closes the SSH session cleanly and releases connections.