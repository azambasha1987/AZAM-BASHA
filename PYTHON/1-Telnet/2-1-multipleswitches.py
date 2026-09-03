import getpass
import telnetlib
import os
import socket

user = input("Enter your telnet username: ")
password = getpass.getpass()

# Get the directory of the current script to find the 'switches' file reliably
script_dir = os.path.dirname(os.path.abspath(__file__))
switches_path = os.path.join(script_dir, "switches")

try:
    with open(switches_path) as f:
        for IP in f:
            IP = IP.strip()
            if not IP or IP.startswith("#"):
                continue
            
            print("\n" + "=" * 40)
            print(f"Configuring Switch: {IP}")
            print("=" * 40)
            
            try:
                # Use a timeout of 5 seconds to prevent hanging on unresponsive hosts
                tn = telnetlib.Telnet(IP, timeout=5)
                
                # Read until username prompt (with 5-second timeout)
                tn.read_until(b"Username: ", timeout=5)
                tn.write((user + "\n").encode('ascii'))
                
                if password:
                    tn.read_until(b"Password: ", timeout=5)
                    tn.write((password + "\n").encode('ascii'))
                    
                tn.write(b"enable\n")
                tn.write(b"cisco\n")
                tn.write(b"conf t\n")
                
                # Configure VLANs 2 to 10 on each switch
                for n in range(2, 11):
                    tn.write(f"vlan {n}\n".encode('ascii'))
                    tn.write(f"name Python_VLAN_{n}\n".encode('ascii'))
                    
                tn.write(b"end\n")
                tn.write(b"exit\n")
                
                # Print the switch output
                print(tn.read_all().decode('ascii'))
                print(f"Successfully configured switch: {IP}")
                
            except (socket.timeout, TimeoutError):
                print(f"Error: Connection timed out for switch {IP}.")
            except ConnectionRefusedError:
                print(f"Error: Connection refused by switch {IP}.")
            except EOFError:
                print(f"Error: Connection closed unexpectedly by switch {IP}.")
            except Exception as e:
                print(f"Error configuring switch {IP}: {e}")
                
except FileNotFoundError:
    print(f"Error: The file '{switches_path}' was not found.")
    print("Please ensure the 'switches' file exists in the same directory as the script.")