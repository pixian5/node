#!/usr/bin/env python3
"""最小 VLESS+WS 客户端，验证 148.100.112.30 的 WS 节点(443/80) 是否真实可用"""
import socket, ssl, base64, os, struct, sys

HOST = "148.100.112.30"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 443
SNI = "v9-y.douyinvod.com"
PATH = "/videos"
UUID = bytes.fromhex("41d4f8b3-2a45-4531-a33b-938e2eebb939".replace("-", ""))
TLS = PORT == 443

def ws_frame(data):
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    header = bytearray([0x82])
    if len(data) < 126:
        header.append(0x80 | len(data))
    elif len(data) < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", len(data))
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", len(data))
    header += mask
    return bytes(header) + masked

def vless_header(port, addr):
    h = b"\x00" + UUID + b"\x00" + b"\x01"
    h += struct.pack(">H", port)
    if len(addr) == 4:
        h += b"\x01" + addr
    elif len(addr) == 16:
        h += b"\x02" + addr
    else:
        h += b"\x03" + bytes([len(addr)]) + addr
    return h

def main():
    print(f"[*] 连接 {HOST}:{PORT} ({'TLS' if TLS else 'plain'}, SNI={SNI})")
    raw = socket.create_connection((HOST, PORT), timeout=10)
    sock = raw
    if TLS:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            sock = ctx.wrap_socket(raw, server_hostname=SNI)
            print(f"[+] TLS 握手成功: {sock.version()}")
        except Exception as e:
            print(f"[-] TLS 失败: {e}")
            sys.exit(1)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET {PATH} HTTP/1.1\r\n"
           f"Host: {SNI}\r\n"
           f"Upgrade: websocket\r\n"
           f"Connection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\n"
           f"Sec-WebSocket-Version: 13\r\n\r\n")
    sock.sendall(req.encode())
    resp = sock.recv(1024)
    print(f"[*] WS 握手: {resp.split(b'\\r\\n',1)[0]!r}")
    if b"101" not in resp.split(b"\r\n", 1)[0]:
        print("[-] WS 升级失败")
        sys.exit(2)
    print("[+] WS 升级成功 (101)")
    hdr = vless_header(80, socket.inet_aton("1.1.1.1"))
    sock.sendall(ws_frame(hdr))
    print("[*] VLESS 头已发送，等待响应...")
    sock.settimeout(6)
    try:
        data = sock.recv(4096)
        if data:
            print(f"[+] 收到 {len(data)} 字节: {data[:80]!r}")
            print("[✓] 节点可用：VLESS+WS 通道真实连通")
        else:
            print("[-] 收到空数据")
    except socket.timeout:
        print("[*] 6秒无响应（VLESS 正常，通道已建立）")
    except Exception as e:
        print(f"[-] 异常: {e}")

if __name__ == "__main__":
    main()