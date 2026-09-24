#!/usr/bin/env python3
"""
从 sub.yaml 自动同步 dy_worker.js 并部署到 Cloudflare Worker。

流程：
  读 sub.yaml -> 按规则挑出自有服务器节点 -> 生成 vless/hysteria2 通用链接
  -> 替换 dy_worker.js 里的链接块 -> 部署（PUT + PATCH settings）-> 拉线上源码校验

凭证可以放环境变量，也可以在脚本同目录建 .env 文件（**已在 .gitignore 里，别提交**），
脚本会自动读取 .env，且不会覆盖已存在的环境变量。

环境变量
  必填（部署阶段；DRY_RUN=1 时不需要）：
    CF_API_EMAIL        Cloudflare 账号邮箱，如 xwn4@outlook.com
    CF_API_KEY          Global API Key（也可改用 CF_API_TOKEN，二选一）
    CF_API_TOKEN        API Token（优先于 EMAIL/KEY，需 Workers 写权限）
    CF_ACCOUNT_ID       账户 ID

  可选：
    SUB_YAML            订阅源路径，默认 ./pages/c_deploy/sub.yaml
    DY_WORKER_JS        worker 源文件路径，默认 ./dy_worker.js
    CF_WORKER_NAME      worker 名，默认 dy
    CF_COMPAT_DATE      compatibility_date，默认读取线上现有值（拿不到则 2026-09-07）
    DY_DOMAINS          自有服务器域名白名单，逗号分隔，默认 aws.sbbz.tech,awsvx2083.sbbz.tech
                        节点的 server / servername / sni / host 任一精确等于其中一项即入选
    DY_NODES           显式节点名白名单，逗号分隔；设了就忽略 DY_DOMAINS
    DY_DEFAULT_FP      节点没写 client-fingerprint 时的默认值，默认 chrome
    DRY_RUN            设为 1 只生成并打印，不写文件也不部署

用法：
    export CF_API_EMAIL=xwn4@outlook.com CF_API_KEY=xxx CF_ACCOUNT_ID=xxx
    python3 sync_dy_worker.py              # 生成 + 写文件 + 部署 + 校验
    DRY_RUN=1 python3 sync_dy_worker.py    # 只看看会生成什么
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("缺少 pyyaml，请先安装：pip install pyyaml")

ROOT = Path(__file__).resolve().parent
API = "https://api.cloudflare.com/client/v4"


def load_dotenv():
    """读取脚本同目录的 .env（KEY=VALUE，# 开头为注释），不覆盖已有环境变量"""
    f = ROOT / ".env"
    if not f.exists():
        return
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip("'\"")
        if k and k not in os.environ:
            os.environ[k] = v


def env(name, default=""):
    v = os.environ.get(name, "")
    return v.strip() if v.strip() else default


load_dotenv()


CFG = {
    "sub_yaml": Path(env("SUB_YAML", str(ROOT / "pages" / "c_deploy" / "sub.yaml"))),
    "worker_js": Path(env("DY_WORKER_JS", str(ROOT / "dy_worker.js"))),
    "worker_name": env("CF_WORKER_NAME", "dy"),
    "account_id": env("CF_ACCOUNT_ID"),
    "email": env("CF_API_EMAIL"),
    "api_key": env("CF_API_KEY"),
    "api_token": env("CF_API_TOKEN"),
    "compat_date": env("CF_COMPAT_DATE"),
    "domains": [d.strip() for d in env("DY_DOMAINS", "aws.sbbz.tech,awsvx2083.sbbz.tech").split(",") if d.strip()],
    "nodes": [n.strip() for n in env("DY_NODES").split(",") if n.strip()],
    "default_fp": env("DY_DEFAULT_FP", "chrome"),
    "dry_run": env("DRY_RUN") == "1",
}

LINK_RE = re.compile(r"^(vless|hysteria2|trojan|vmess|tuic|anytls)://\S+")


def log(msg):
    print(msg, flush=True)


def die(msg):
    print(f"[失败] {msg}", flush=True)
    sys.exit(1)


# ---------- 1. 挑节点 ----------

def node_domains(p):
    """取出一个节点所有相关域名"""
    out = {p.get("server"), p.get("servername"), p.get("sni")}
    for key in ("ws-opts", "xhttp-opts", "http-opts", "grpc-opts", "h2-opts"):
        opts = p.get(key) or {}
        out.add(opts.get("host"))
        headers = opts.get("headers") or {}
        out.add(headers.get("Host"))
    return {d for d in out if isinstance(d, str)}


def pick_nodes(proxies):
    if CFG["nodes"]:
        wanted = set(CFG["nodes"])
        picked = [p for p in proxies if p.get("name") in wanted]
        missing = wanted - {p.get("name") for p in picked}
        if missing:
            die(f"DY_NODES 里这些节点在 sub.yaml 中不存在: {sorted(missing)}")
        return picked

    domains = set(CFG["domains"])
    picked = []
    for p in proxies:
        if node_domains(p) & domains:
            picked.append(p)
    if not picked:
        die(f"没有节点命中 DY_DOMAINS={sorted(domains)}，请检查白名单")
    return picked


# ---------- 2. 生成链接 ----------

def frag(name):
    """URL 片段（#后面的节点名）：正常情况保持明文便于阅读，含不安全字符才编码"""
    if re.search(r"[ \t&#%?]", name):
        return urllib.parse.quote(name, safe="")
    return name


def vless_url(p):
    uuid = p.get("uuid")
    server, port = p.get("server"), p.get("port")
    if not (uuid and server and port):
        return None

    q = {"encryption": "none"}
    reality = p.get("reality-opts") or {}
    tls = p.get("tls") is True
    network = p.get("network") or "tcp"

    if reality:
        q["security"] = "reality"
        q["pbk"] = reality.get("public-key")
        q["sid"] = reality.get("short-id")
    elif tls:
        q["security"] = "tls"
    else:
        q["security"] = "none"

    if tls or reality:
        sni = p.get("servername") or p.get("sni")
        if sni:
            q["sni"] = sni
        fp = p.get("client-fingerprint") or CFG["default_fp"]
        if fp:
            q["fp"] = fp
        if p.get("skip-cert-verify") is True:
            q["allowInsecure"] = "1"

    q["type"] = network
    if network == "ws":
        opts = p.get("ws-opts") or {}
        if opts.get("path"):
            q["path"] = opts["path"]
        host = (opts.get("headers") or {}).get("Host") or opts.get("host")
        if host:
            q["host"] = host
    elif network == "xhttp":
        opts = p.get("xhttp-opts") or {}
        if opts.get("path"):
            q["path"] = opts["path"]
        if opts.get("host"):
            q["host"] = opts["host"]
        if opts.get("mode"):
            q["mode"] = opts["mode"]
    elif network == "grpc":
        opts = p.get("grpc-opts") or {}
        if opts.get("grpc-service-name"):
            q["serviceName"] = opts["grpc-service-name"]

    if p.get("flow"):
        q["flow"] = p["flow"]

    query = "&".join(f"{k}={v}" for k, v in q.items() if v not in (None, ""))
    return f"vless://{uuid}@{server}:{port}?{query}#{frag(p.get('name', ''))}"


def hysteria2_url(p):
    password, server, port = p.get("password"), p.get("server"), p.get("port")
    if not (password and server and port):
        return None

    q = {}
    if p.get("obfs"):
        q["obfs"] = p["obfs"]
    if p.get("obfs-password"):
        q["obfs-password"] = p["obfs-password"]
    sni = p.get("sni") or p.get("servername")
    if sni:
        q["sni"] = sni
    if p.get("alpn"):
        q["alpn"] = ",".join(p["alpn"]) if isinstance(p["alpn"], list) else p["alpn"]
    if p.get("up"):
        q["up"] = p["up"]
    if p.get("down"):
        q["down"] = p["down"]
    if p.get("skip-cert-verify") is True:
        q["insecure"] = "1"

    query = "&".join(f"{k}={v}" for k, v in q.items() if v not in (None, ""))
    tail = f"/?{query}" if query else "/"
    return f"hysteria2://{password}@{server}:{port}{tail}#{frag(p.get('name', ''))}"


BUILDERS = {"vless": vless_url, "hysteria2": hysteria2_url}


def build_links(nodes):
    links, skipped = [], []
    for p in nodes:
        ptype = p.get("type")
        builder = BUILDERS.get(ptype)
        if not builder:
            skipped.append(f"{p.get('name')}（不支持的类型 {ptype}）")
            continue
        url = builder(p)
        if url:
            links.append(url)
        else:
            skipped.append(f"{p.get('name')}（缺必要字段）")
    return links, skipped


# ---------- 3. 写回 dy_worker.js ----------

TEMPLATE = """addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const subConfig = `<!DOCTYPE html>
<html>
  <head>
  <meta charset="utf-8" name="viewport" content="width=device-width, initial-scale=1">
  <title>dy</title>
  <style>
  button {
    all: unset;
    cursor: pointer;
    color: #007aff;
    word-break: break-word;
    display: block;
  }
  button:hover {
    color: #005ec4;
  }
  </style>
  </head>
    <body style="font-family: sans-serif; white-space: pre-line;">
<button onclick="copyText(this)">

__LINKS__

</button>

    <script>
      function copyText(el) {
        navigator.clipboard.writeText(el.textContent).catch(() => {});
      }
    </script>
  </body>
</html>`

return new Response(subConfig, {
  headers: {
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Disposition": "attachment; filename=\\"超究极死神订阅.txt\\"",
    "Subscription-Userinfo": "upload=102400; download=204800; total=10737418240; expire=1893456000",
    "Profile-Update-Interval": "6",
  }
})
}
"""

BTN_RE = re.compile(r'(<button onclick="copyText\(this\)">)(.*?)(</button>)', re.DOTALL)


def render_worker(links):
    block = "\n" + "\n".join(links) + "\n"
    if CFG["worker_js"].exists():
        src = CFG["worker_js"].read_text(encoding="utf-8")
        if not BTN_RE.search(src):
            die(f"{CFG['worker_js']} 里找不到 copyText 按钮块，不敢自动改，请手工确认结构")
        return BTN_RE.sub(lambda m: m.group(1) + block + m.group(3), src, count=1)
    log(f"[提示] {CFG['worker_js']} 不存在，用内置模板新建")
    return TEMPLATE.replace("__LINKS__", "\n".join(links))


# ---------- 4. 部署 ----------

def auth_headers(extra=None):
    h = dict(extra or {})
    if CFG["api_token"]:
        h["Authorization"] = f"Bearer {CFG['api_token']}"
    elif CFG["email"] and CFG["api_key"]:
        h["X-Auth-Email"] = CFG["email"]
        h["X-Auth-Key"] = CFG["api_key"]
    else:
        die("缺少凭证：请设置 CF_API_TOKEN，或同时设置 CF_API_EMAIL + CF_API_KEY")
    return h


def cf(method, path, body=None, headers=None, raw=False, timeout=90):
    url = f"{API}{path}"
    req = urllib.request.Request(url, data=body, headers=auth_headers(headers), method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
            return data.decode("utf-8", "replace") if raw else json.loads(data)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:600]
        die(f"{method} {path} -> HTTP {e.code}: {detail}")
    except urllib.error.URLError as e:
        die(f"{method} {path} -> 网络错误: {e.reason}")


def script_path():
    return f"/accounts/{CFG['account_id']}/workers/scripts/{CFG['worker_name']}"


def get_compat_date():
    if CFG["compat_date"]:
        return CFG["compat_date"]
    r = cf("GET", f"{script_path()}/settings")
    return ((r.get("result") or {}).get("compatibility_date")) or "2026-09-07"


def deploy(source, compat_date):
    log("== 上传脚本 ==")
    cf("PUT", script_path(), body=source.encode("utf-8"),
       headers={"Content-Type": "application/javascript"})
    log("  脚本已上传")

    # PUT 会清空 compatibility_date，必须补回；该接口只收 multipart/form-data
    log("== 恢复 compatibility_date ==")
    settings = json.dumps({
        "compatibility_date": compat_date,
        "compatibility_flags": [],
        "usage_model": "standard",
        "bindings": [],
    }).encode()
    boundary = "----dysync" + os.urandom(8).hex()
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="settings"\r\n'
        "Content-Type: application/json\r\n\r\n"
    ).encode() + settings + f"\r\n--{boundary}--\r\n".encode()
    cf("PATCH", f"{script_path()}/settings", body=body,
       headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    log(f"  compatibility_date = {compat_date}")


def verify(links):
    log("== 校验线上 ==")
    online = cf("GET", script_path(), raw=True)
    online_links = [m.group(0) for m in (LINK_RE.match(l) for l in online.splitlines()) if m]
    if set(online_links) == set(links):
        log(f"  线上 {len(links)} 条链接与本地一致")
        return
    die(f"线上与本地不一致\n  本地 {len(links)} 条\n  线上 {len(online_links)} 条\n"
        f"  线上多出: {sorted(set(online_links) - set(links))}\n"
        f"  线上缺失: {sorted(set(links) - set(online_links))}")


# ---------- main ----------

def main():
    if not CFG["sub_yaml"].exists():
        die(f"订阅源不存在: {CFG['sub_yaml']}（可用 SUB_YAML 指定）")

    cfg = yaml.safe_load(CFG["sub_yaml"].read_text(encoding="utf-8"))
    proxies = [p for p in (cfg.get("proxies") or []) if isinstance(p, dict)]
    log(f"读取 {CFG['sub_yaml'].name}：共 {len(proxies)} 个节点")

    nodes = pick_nodes(proxies)
    log(f"命中自有服务器节点 {len(nodes)} 个：{', '.join(p.get('name','') for p in nodes)}")

    links, skipped = build_links(nodes)
    for s in skipped:
        log(f"  [跳过] {s}")
    if not links:
        die("没有生成任何链接")

    log("\n生成的链接：")
    for l in links:
        log("  " + l)

    source = render_worker(links)

    if CFG["dry_run"]:
        log("\nDRY_RUN=1，不写文件也不部署。上面即为将写入的内容。")
        return

    CFG["worker_js"].write_text(source, encoding="utf-8")
    log(f"\n已写入 {CFG['worker_js']}")

    if not CFG["account_id"]:
        die("缺少 CF_ACCOUNT_ID，无法部署")

    deploy(source, get_compat_date())
    verify(links)
    log("\n完成。dy.sbbz.tech 已更新。")


if __name__ == "__main__":
    main()
