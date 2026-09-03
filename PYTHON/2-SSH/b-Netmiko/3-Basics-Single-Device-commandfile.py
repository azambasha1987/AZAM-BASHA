import os
from netmiko import ConnectHandler

# Resolve path to commands_file relative to the script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
commands_file_path = os.path.join(script_dir, 'commands_file')

with open(commands_file_path) as f:
    commands_to_send = f.read().splitlines()

ios_xe_devices = {
    'device_type': 'cisco_xe',
    'ip': '192.168.1.108',
    'username': 'azam',
    'password': 'cisco',
    'secret': 'cisco',
}

all_devices = [ios_xe_devices]

for devices in all_devices:
    net_connect = ConnectHandler(**devices)
    net_connect.enable()
    output = net_connect.send_config_set(commands_to_send)
    print(output)

# explanation:
#
# imports:
# - os: Standard Python library used for interacting with the operating system (e.g. constructing file paths).
# - netmiko.ConnectHandler: Used to establish SSH connections and execute commands/configurations on network devices.
#
# Path Resolution:
# - script_dir = os.path.dirname(os.path.abspath(__file__)): Gets the absolute path of the directory containing this script.
# - commands_file_path = os.path.join(script_dir, 'commands_file'): Constructs the absolute path to 'commands_file' relative to the script.
#   This allows the script to be run from any working directory without raising FileNotFoundError.
#
# Reading commands:
# - with open(commands_file_path) as f: Opens the commands file.
# - commands_to_send = f.read().splitlines(): Reads the file and splits it into a list of individual command strings (removing newline characters).
#
# variables:
# - ios_xe_devices: A dictionary containing connection parameters for the target IOS-XE device.
#   - 'device_type': Specifies the Netmiko driver for the target device ('cisco_xe').
#   - 'ip': The management IP address of the device ('192.168.1.108').
#   - 'username': The username used for SSH authentication ('azam').
#   - 'password': The password used for SSH authentication ('cisco').
#   - 'secret': The enable secret required to elevate to Privileged EXEC mode ('cisco').
# - all_devices: A list containing dictionaries of devices to configure.
#
# Script Flow:
# 1. Open and read configuration commands from 'commands_file' into the 'commands_to_send' list.
# 2. Iterate through each device configuration dictionary in the 'all_devices' list.
# 3. Establish an SSH connection to the device using `ConnectHandler(**devices)`.
# 4. Elevate the session privileges to Privileged EXEC mode using `net_connect.enable()` (required for entering configuration mode).
# 5. Apply the commands from the list using `net_connect.send_config_set(commands_to_send)`.
# 6. Print the configuration session output to the screen.