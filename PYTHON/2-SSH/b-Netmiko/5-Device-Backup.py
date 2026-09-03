from simplecrypt import encrypt, decrypt
from pprint import pprint
from netmiko import ConnectHandler
import json
from time import time

import threading

#--------------------------------------------------------------------------------------------------------------
def read_devices( devices_filename ):
    
    devices = {}  #create our dictionary for storing devices and their info
    
    with open( devices_filename ) as devices_file:
        
        for device_line in devices_file:
            
            device_info = device_line.strip().split(',') #extract device info from line
            
            device = {'ipaddr': device_info[0],
                      'type':   device_info[1],
                      'name':   device_info[2]}  # create dictionary of device objects
            
            devices[device['ipaddr']] = device   # store our device in the devices dictionary
                                                 # note the key for devices dictionary entries
    
    print('\n------ devices ------------------------------')
    pprint( devices )
    
    return devices

#------------------------------------------------------------------------------------------------------------
def read_device_creds( device_creds_filename, key ):
    
    print('\n... getting credentials ...\n')
    with open( device_creds_filename, 'rb') as device_creds_file:
        device_creds_json = decrypt( key, device_creds_file.read() )
    
    device_creds_list = json.loads( device_creds_json )
    pprint( device_creds_list )
    
    print('\n-------------- device_creds -------------------------')
    
    # convert to dictionary of lists using dictionary comprehension
    device_creds = { dev[0]:dev for dev in device_creds_list }
    pprint( device_creds )
    
    return device_creds

#-------------------------------------------------------------------------------------------------------
def config_worker( device, creds ):
    
    #---- Connect to the device -------
    if   device['type'] == 'junos-srx': device_type = 'juniper'
    elif device['type'] == 'cisco-ios': device_type = 'cisco_ios'
    elif device['type'] == 'cisco-xe':  device_type = 'cisco_xe'
    elif device['type'] == 'cisco-xr':  device_type = 'cisco_xr'
    else:                               device_type = 'cisco_ios' # attempt IOS as default
    # lines 59 and 60 cut off while onscreen. Made best guess.    
    print('----- Connecting to device {0}, username={1}, password={2}'.format( device['ipaddr'],
                                                                                creds[1], creds[2] ))

    #---- Connect to the device
    session = ConnectHandler( device_type=device_type, ip=device['ipaddr'],
                                                       username=creds[1], password=creds[2] )
    #session = ConnectHandler( device_type=device_type, ip='172.16.0.1',  #Faking out IP addr
    #                                                   username=creds[1], password=creds[2] )
    
    if device_type == 'juniper':
        #----- Use CLI comand to get config data from device
        print('--- Getting configuration from device')
        session.send_command('configure terminal')
        config_data = session.send_command('show configuration')
    
    if device_type == 'cisco_ios':
        #--- Use CLI command to get config from device
        print('--- Getting configuration from device')
        config_data = session.send_command('show run')
    
    if device_type == 'cisco_xr':
        #--- Use CLI command to get config from device
        print('--- Getting configuration from device')
        config_data = session.send_command('show configuration running-config')
    
    
    #----- Write out config information to file
    config_filename = 'config-' + device['ipaddr']
    
    print('--- Writing configuration: ', config_filename)
    with open( config_filename, 'w' ) as config_out: config_out.write( config_data )
    
    session.disconnect()
    
    return


#==================================================================================
#----- Main: Get configuration
#==================================================================================

import os

# Resolve paths relative to the script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
devices_path = os.path.join(script_dir, 'devices-file')
creds_path = os.path.join(script_dir, 'encrypted-device-creds')

devices = read_devices( devices_path )
creds   = read_device_creds( creds_path, 'cisco' )

starting_time = time()

config_threads_list = []
for ipaddr,device in devices.items():

#====line 110 cut off while onscreen. Made best guess  --------    
    print('Creating thread for: ', device)
    config_threads_list.append( threading.Thread( target=config_worker, args=(device, creds[ipaddr]) ) )

print('\n---- Begin get config threading ----\n')
for config_thread in config_threads_list:
    config_thread.start()
    
for config_thread in config_threads_list:
    config_thread.join()

print('\n---- End get config threading, elapsed time=', time() - starting_time)

# explanation:
#
# imports:
# - simplecrypt.encrypt, decrypt: Used for encrypting and decrypting data using AES encryption with a password key.
# - pprint.pprint: Used to print Python data structures (like dictionaries and lists) in a well-formatted, readable way.
# - netmiko.ConnectHandler: Establishes SSH sessions and interacts with network devices across multiple platforms (Cisco IOS/XR, Juniper, etc.).
# - json: Encodes and decodes data in JSON format (used here to deserialize credential structures).
# - time.time: Measures execution times to track how long parallel network connections take.
# - threading: Enables running multiple tasks in parallel using system threads, speeding up config collection for multiple devices.
#
# Functions:
# 1. read_devices(devices_filename):
#    - Opens a text file where each line defines a device in 'ipaddr,type,name' format.
#    - Parses and constructs a dictionary mapping IP addresses to device details.
# 2. read_device_creds(device_creds_filename, key):
#    - Opens a binary file containing encrypted JSON credentials.
#    - Decrypts the contents using the provided password/key.
#    - Loads the decrypted string as a JSON list, and uses a dictionary comprehension to convert it to a dictionary keyed by IP address.
# 3. config_worker(device, creds):
#    - Designed to be run in a separate thread for each device.
#    - Maps device types to appropriate Netmiko driver names (e.g. cisco_ios, cisco_xr, juniper).
#    - Connects to the network device via Netmiko.
#    - Fetches the running configuration using the correct OS command (e.g. 'show run', 'show configuration').
#    - Saves the configurations to local text files named `config-<IP>` and terminates the session.
#
# Script Flow:
# 1. Calls `read_devices` to parse the device list.
# 2. Calls `read_device_creds` to decrypt and parse credentials.
# 3. Records the start time.
# 4. Loops through each device in the parsed list and creates a thread pointing to `config_worker`.
# 5. Starts all threads in the list (`config_thread.start()`) to connect to the switches concurrently.
# 6. Waits for all threads to finish execution (`config_thread.join()`).
# 7. Prints the total execution time (concurrency significantly reduces elapsed time compared to sequential execution).