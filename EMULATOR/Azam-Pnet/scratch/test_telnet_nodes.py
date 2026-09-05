import telnetlib
import time

def test_telnet(host, port, node_name):
    print(f"Connecting to {node_name} on {host}:{port}...")
    try:
        tn = telnetlib.Telnet(host, port, timeout=5)
        time.sleep(1)
        tn.write(b"\r\n")
        time.sleep(1)
        tn.write(b"\r\n")
        time.sleep(1)
        output = tn.read_very_eager().decode('utf-8', errors='ignore')
        print(f"--- Output from {node_name} ---")
        print(output)
        print("-------------------------------")
        tn.close()
        return True
    except Exception as e:
        print(f"Failed to connect to {node_name} ({host}:{port}): {e}")
        return False

if __name__ == '__main__':
    host = '192.168.1.29'
    test_telnet(host, 30001, 'SITE-1-WAN-R1 (IOSv Router)')
    test_telnet(host, 30003, 'SW-1 (IOSv-L2 Switch)')
