import getpass
import telnetlib

HOST = "192.168.1.104"
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
tn.write(b"int loop 0\n")
tn.write(b"ip address 1.1.1.1 255.255.255.255\n")
tn.write(b"int loop 1\n")
tn.write(b"ip address 2.2.2.2 255.255.255.255\n")
tn.write(b"router ospf 1\n")
tn.write(b"network 0.0.0.0 255.255.255.255 area 0\n")
tn.write(b"end\n")
tn.write(b"exit\n")

print(tn.read_all().decode())

#explanation:
#
# imports:
# - getpass: Standard library module used to securely prompt the user for passwords
#            without echoing their input on the terminal.
# - telnetlib: Module used to establish Telnet connections to remote hosts.
#              (Note: Removed in Python 3.13+, but restored via telnetlib-313-and-up package).
#
# script flow:
# 1. Prompts the user for a Telnet username (input) and password (getpass.getpass).
# 2. Connects to the target router IP (192.168.1.104) via Telnet.
# 3. Reads buffer until "Username: " and writes the username.
# 4. Reads buffer until "Password: " and writes the password.
# 5. Enters enable mode ("enable" -> enable password "cisco").
# 6. Enters global configuration mode ("conf t").
# 7. Configures Loopback 0 (1.1.1.1) and Loopback 1 (2.2.2.2).
# 8. Starts OSPF process 1 and advertises all subnets in area 0.
# 9. Ends configuration, exits, and prints the full output from the router session.
