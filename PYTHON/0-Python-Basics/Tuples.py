# A tuple is an ordered, immutable collection of elements
device_info = ("router1", "192.168.1.1", "Cisco IOS")

print("Device Name:", device_info[0])
print("IP Address:", device_info[1])
print("OS Version:", device_info[2])

# You can also unpack a tuple:
name, ip, os = device_info
print(f"Unpacked: {name} is at {ip} running {os}")
