#!/usr/bin/env python3
"""节点性能实测 v2：TCP connect + TLS 握手计时（TUN 已关，直连）"""
import socket, ssl, time, json

IP = "148.100.112.30"
NODES = [
    ("80-WS直连",      IP, 80,   None),
    ("443-WS-TLS",     IP, 443,  "l.sbbz.tech"),
    ("443-XHTTP",      IP, 443,  "l.sbbz.tech"),
    ("8443-Reality",   IP, 8443, "itunes.apple.com"),
    ("2053-XHTTP-Real",IP, 2053, "itunes.apple.com"),
    ("2083-XHTTP-CDN", IP, 2083, "lvx2083.sbbz.tech"),
]

def time_tcp(host, port):
    t0 = time.perf_counter()
    with socket.create_connection((host, port), timeout=8):
        return (time.perf_counter() - t0) * 1000

def time_tls(host, port, sni):
    t0 = time.perf_counter()
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    raw = socket.create_connection((host, port), timeout=8)
    t_conn = (time.perf_counter() - t0) * 1000
    t0b = time.perf_counter()
    with ctx.wrap_socket(raw, server_hostname=sni):
        t_tls = (time.perf_counter() - t0b) * 1000
    return t_conn, t_tls

results = []
for name, host, port, sni in NODES:
    r = {"node": name}
    try:
        if sni is None:
            times = [time_tcp(host, port) for _ in range(3)]
            r.update(ok=True, tcp_ms=round(min(times), 2))
        else:
            data = [time_tls(host, port, sni) for _ in range(3)]
            r.update(ok=True,
                     tcp_ms=round(min(t[0] for t in data), 2),
                     tls_ms=round(min(t[1] for t in data), 2),
                     total_ms=round(min(t[0]+t[1] for t in data), 2))
    except Exception as e:
        r.update(ok=False, err=str(e)[:60])
    results.append(r)
    print(json.dumps(r, ensure_ascii=False))