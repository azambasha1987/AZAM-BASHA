import getpass
import os
import socket
import telnetlib

# Get Username and Password
user = input("Enter your username: ")
password = getpass.getpass()

# Get the directory of the current script to find the 'switches' file reliably
script_dir = os.path.dirname(os.path.abspath(__file__))
switches_path = os.path.join(script_dir, "switches")
backup_dir = os.path.join(script_dir, "backup")
os.makedirs(backup_dir, exist_ok=True)

try:
    with open(switches_path) as f:
        for line in f:
            HOST = line.strip()
            if not HOST or HOST.startswith("#"):
                continue

            print("\n" + "=" * 40)
            print(f"Getting running-config for switch: {HOST}")
            print("=" * 40)

            try:
                tn = telnetlib.Telnet(HOST, timeout=5)

                tn.read_until(b"Username: ", timeout=5)
                tn.write((user + "\n").encode('ascii'))
                if password:
                    tn.read_until(b"Password: ", timeout=5)
                    tn.write((password + "\n").encode('ascii'))

                tn.write(b"enable\n")
                tn.read_until(b"Password: ", timeout=5)
                tn.write((password + "\n").encode('ascii'))
                tn.write(b"terminal length 0\n")
                tn.write(b"show run\n")
                tn.write(b"exit\n")

                readoutput = tn.read_all().decode('ascii', errors='ignore')

                output_filename = os.path.join(backup_dir, "switch_" + HOST)
                with open(output_filename, "w") as saveoutput:
                    saveoutput.write(readoutput)
                    saveoutput.write("\n")

                print(readoutput)
                print(f"Successfully saved backup for switch {HOST} to {output_filename}")

            except (socket.timeout, TimeoutError):
                print(f"Error: Connection timed out for switch {HOST}.")
            except ConnectionRefusedError:
                print(f"Error: Connection refused by switch {HOST}.")
            except EOFError:
                print(f"Error: Connection closed unexpectedly by switch {HOST}.")
            except Exception as e:
                print(f"Error connecting to switch {HOST}: {e}")

except FileNotFoundError:
    print(f"Error: The file '{switches_path}' was not found.")
    print("Please ensure the 'switches' file exists in the same directory as the script.")
