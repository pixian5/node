#!/usr/bin/env python3
"""将 Clash 配置部署到 Cloudflare Pages (c 项目) — 4步直接上传协议"""
import base64, os, sys, json, urllib.request, urllib.parse, uuid, time
from pathlib import Path
import blake3

ACC = os.environ.get("CF_ACCOUNT_ID", "e16771787e0f6f85e8976ba3befb0c1b")
PRJ = "c"
EMAIL = os.environ.get("CF_EMAIL", "xwn4@outlook.com")
KEY = os.environ.get("CF_API_KEY", "")
DIR = os.environ.get("PAGES_SRC_DIR", "/tmp/c_page")


def cf_hash(data: bytes, rel_path: str) -> str:
    """wrangler 的 hashFile: blake3(base64(bytes)+ext).hex()[:32]"""
    ext = os.path.splitext(rel_path)[1][1:]
    b64 = base64.b64encode(data)
    return blake3.blake3(b64 + ext.encode("ascii")).hexdigest()[:32]


def req(method, url, headers, body=None, binary=None, timeout=90, json_body=False):
    data = None
    if json_body:
        data = body.encode() if isinstance(body, str) else body
    elif body is not None:
        data = body
    elif binary is not None:
        data = binary
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        err = e.read()
        try:
            return e.code, json.loads(err)
        except Exception:
            return e.code, {"raw": err[:800]}


def main():
    # 1. upload-token
    print("== Step 1: upload-token ==")
    s, tok = req("GET",
                 f"https://api.cloudflare.com/client/v4/accounts/{ACC}/pages/projects/{PRJ}/upload-token",
                 {"X-Auth-Email": EMAIL, "X-Auth-Key": KEY})
    jwt = (tok.get("result") or {}).get("jwt")
    if not jwt:
        print("  FAIL", s, tok)
        return
    print("  JWT ok")

    # 读取普通文件 & 计算哈希 (_headers/_redirects 走 deployment 专用字段, 不用 assets)
    names = ["sub.yaml"]
    files = {}
    for n in names:
        data = (Path(DIR) / n).read_bytes()
        files[n] = {"data": data, "hash": cf_hash(data, n), "contentType": "text/yaml" if n.endswith("yaml") else "text/plain"}
        print(f"  {n}: hash={files[n]['hash'][:12]}... ::{files[n]['hash']}")
        os.write(1, b"")

    # 2. assets/upload: body 是 JSON array
    print("== Step 2: assets/upload ==")
    payload = [{
        "key": f["hash"],
        "value": base64.b64encode(f["data"]).decode(),
        "metadata": {"contentType": f["contentType"]},
        "base64": True,
    } for f in files.values()]
    s, up = req("POST", "https://api.cloudflare.com/client/v4/pages/assets/upload",
                {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
                body=json.dumps(payload), json_body=True)
    print("  status:", s, "resp:", json.dumps(up)[:300])
    if s >= 300:
        print("  FAIL"); return

    # 3. upsert-hashes
    print("== Step 3: upsert-hashes ==")
    s, uh = req("POST", "https://api.cloudflare.com/client/v4/pages/assets/upsert-hashes",
                {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
                body=json.dumps({"hashes": [f["hash"] for f in files.values()]}), json_body=True)
    print("  status:", s, "resp:", json.dumps(uh)[:300])

    # 4. 创建 deployment (multipart form-data: manifest + 专用 _headers/_redirects 文件字段)
    print("== Step 4: create deployment ==")
    boundary = "----page" + uuid.uuid4().hex
    manifest = {f"/{n}": f["hash"] for n, f in files.items()}
    parts = []
    def add_text_field(name, value):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    def add_file_field(name, data):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{name}\"\r\nContent-Type: text/plain\r\n\r\n".encode() + data + b"\r\n")
    add_text_field("manifest", json.dumps(manifest))
    add_text_field("branch", "main")
    commit_msg = f"Deploy {time.strftime('%Y-%m-%d %H:%M:%S')}"
    add_text_field("commit_message", commit_msg)
    add_text_field("commit_hash", uuid.uuid4().hex[:40])
    add_text_field("commit_dirty", "false")
    # _headers 和 _redirects 作为 deployment 专用字段
    add_file_field("_headers", (Path(DIR) / "_headers").read_bytes())
    add_file_field("_redirects", (Path(DIR) / "_redirects").read_bytes())
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    s, dep = req("POST",
                 f"https://api.cloudflare.com/client/v4/accounts/{ACC}/pages/projects/{PRJ}/deployments",
                 {"X-Auth-Email": EMAIL, "X-Auth-Key": KEY,
                  "Content-Type": f"multipart/form-data; boundary={boundary}"},
                 binary=body)
    print("  status:", s)
    r = dep.get("result") or {}
    print("  success:", dep.get("success"), "errors:", dep.get("errors"))
    print("  deployment id:", r.get("id"))
    print("  url:", r.get("url"))
    print("  files:", json.dumps(r.get("files", {}))[:300])


if __name__ == "__main__":
    main()