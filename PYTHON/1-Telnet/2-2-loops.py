import getpass
import telnetlib

HOST = "192.168.1.105"
user = input("Enter your telnet username: ")
password = getpass.getpass()

tn = telnetlib.Telnet(HOST)

tn.read_until(b"Username: ")
tn.write((user + "\n").encode('ascii'))
if password:
    tn.read_until(b"Password: ")
    tn.write(password.encode() + b"\n")

tn.write(b"enable\n")
tn.write(b"cisco\n")
tn.write(b"conf t\n")

# Create VLANs 2 to 100 using a loop to avoid repetitive commands
for n in range(2, 101):
    tn.write(f"vlan {n}\n".encode('ascii'))
    tn.write(f"name Python_VLAN_{n}\n".encode('ascii'))

# Exit configuration mode and Telnet session
tn.write(b"end\n")
tn.write(b"exit\n")

# Read and print the output from the switch
print(tn.read_all().decode('ascii'))
