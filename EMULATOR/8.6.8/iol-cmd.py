#!/usr/bin/env python3
"""iol-cmd.py <port> <cmd1;cmd2;...>  — drive an IOL console over telnet."""
import socket, sys, time

port = int(sys.argv[1])
cmds = sys.argv[2].split(";")

s = socket.create_connection(("127.0.0.1", port), timeout=10)
s.settimeout(0.5)

def drain():
    out = b""
    while True:
        try:
            b = s.recv(65535)
            if not b:
                break
            out += b
        except socket.timeout:
            break
    return out

def send(line, wait=1.0):
    s.sendall(line.encode() + b"\r\n")
    time.sleep(wait)
    return drain()

# wake the console
s.sendall(b"\r\n"); time.sleep(1.5); drain()
s.sendall(b"\r\n"); time.sleep(1.0); drain()
out = b""
for c in cmds:
    c = c.strip()
    wait = 2.5 if c.startswith(("show", "ping")) else 0.8
    out += send(c, wait)
    # pump space for --More-- pagination
    for _ in range(6):
        if b"--More--" in out:
            s.sendall(b" "); time.sleep(0.8); out += drain()
print(out.decode(errors="replace"))
